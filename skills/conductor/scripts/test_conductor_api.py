"""Offline tests for remote URL normalization, Orkes authentication and worker-env."""

from __future__ import annotations

import importlib.util
import shutil
import stat
import subprocess
import sys
from pathlib import Path

import pytest


SCRIPT = Path(__file__).with_name("conductor_api.py")
SPEC = importlib.util.spec_from_file_location("conductor_api_fallback", SCRIPT)
assert SPEC and SPEC.loader
conductor_api = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(conductor_api)


@pytest.mark.parametrize(
    ("provided", "expected"),
    [
        ("https://developer.orkescloud.com/", "https://developer.orkescloud.com/api"),
        ("https://pg-qa.orkesconductor.com", "https://pg-qa.orkesconductor.com/api"),
        ("https://example.com/api/", "https://example.com/api"),
        ("https://example.com/custom/conductor/", "https://example.com/custom/conductor"),
    ],
)
def test_normalize_server_url(provided: str, expected: str) -> None:
    assert conductor_api.normalize_server_url(provided) == expected


def test_key_secret_are_exchanged_without_being_returned(monkeypatch) -> None:
    monkeypatch.setenv("CONDUCTOR_SERVER_URL", "https://developer.orkescloud.com/")
    monkeypatch.setenv("CONDUCTOR_AUTH_KEY", "test-key")
    monkeypatch.setenv("CONDUCTOR_AUTH_SECRET", "test-secret")
    monkeypatch.delenv("CONDUCTOR_AUTH_TOKEN", raising=False)
    seen = {}

    def fake_request(url, token, method="GET", body=None, expect_json=True):
        seen.update(url=url, token=token, method=method, body=body)
        return {"token": "exchanged-jwt"}

    monkeypatch.setattr(conductor_api, "request_json", fake_request)
    base, token = conductor_api.get_config()

    assert base == "https://developer.orkescloud.com/api"
    assert token == "exchanged-jwt"
    assert seen == {
        "url": "https://developer.orkescloud.com/api/token",
        "token": "",
        "method": "POST",
        "body": {"keyId": "test-key", "keySecret": "test-secret"},
    }


def test_explicit_token_takes_precedence(monkeypatch) -> None:
    monkeypatch.setenv("CONDUCTOR_SERVER_URL", "https://example.com/api")
    monkeypatch.setenv("CONDUCTOR_AUTH_TOKEN", "existing-token")
    monkeypatch.setenv("CONDUCTOR_AUTH_KEY", "test-key")
    monkeypatch.setenv("CONDUCTOR_AUTH_SECRET", "test-secret")

    def fail_exchange(*_args):
        raise AssertionError("key/secret exchange must not run when a token is set")

    monkeypatch.setattr(conductor_api, "exchange_auth_token", fail_exchange)
    assert conductor_api.get_config() == (
        "https://example.com/api",
        "existing-token",
    )


def test_partial_key_pair_fails(monkeypatch) -> None:
    monkeypatch.setenv("CONDUCTOR_SERVER_URL", "https://example.com/api")
    monkeypatch.setenv("CONDUCTOR_AUTH_KEY", "test-key")
    monkeypatch.delenv("CONDUCTOR_AUTH_SECRET", raising=False)
    monkeypatch.delenv("CONDUCTOR_AUTH_TOKEN", raising=False)

    with pytest.raises(SystemExit):
        conductor_api.get_config()


def _fake_fetch(responses):
    def fetch(url, token):
        for suffix, answer in responses.items():
            if url.endswith(suffix):
                return answer
        return 404, None
    return fetch


def test_usable_integration_needs_type_and_enabled_model() -> None:
    base = "https://acme.example/api"
    fetch = _fake_fetch({
        "/integrations/provider": (200, [
            {"name": "openai-prod", "type": "openai", "enabled": True},
            {"name": "claude-off", "type": "anthropic", "enabled": False},
            {"name": "claude", "type": "anthropic", "enabled": True},
        ]),
        "/integrations/provider/claude/integration": (200, [
            {"api": "claude-old", "enabled": True},
            {"api": "claude-new", "enabled": False},
        ]),
    })
    status, found, names = conductor_api.usable_integration(base, "t", "anthropic", "claude-old", fetch)
    assert (status, found, names) == (200, {"llmProvider": "claude", "model": "claude-old"}, ["claude"])
    # a disabled model doesn't count
    assert conductor_api.usable_integration(base, "t", "anthropic", "claude-new", fetch)[1] is None
    # no model asked: the integration alone is enough
    assert conductor_api.usable_integration(base, "t", "anthropic", None, fetch)[1] == {"llmProvider": "claude"}


def test_usable_integration_reports_forbidden() -> None:
    fetch = _fake_fetch({"/integrations/provider": (403, None)})
    assert conductor_api.usable_integration("https://a/api", "t", "anthropic", "m", fetch) == (403, None, [])


# ---------------------------------------------------------------------------
# worker-env: profile credentials -> .env, never printed
# ---------------------------------------------------------------------------


KEY = "kid-7f3a9c"
SECRET = "sec-Zq8!xY2#long"
SERVER = "https://developer.orkescloud.com"


def _profile(home: Path, name: str = "developer", **values: str) -> None:
    cfg = home / ".conductor-cli"
    cfg.mkdir(parents=True, exist_ok=True)
    body = values or {"server": f"{SERVER}/api", "server-type": "Enterprise",
                      "auth-key": KEY, "auth-secret": SECRET}
    (cfg / f"config-{name}.yaml").write_text("".join(f"{k}: {v}\n" for k, v in body.items()))


def _run(monkeypatch, *argv: str) -> None:
    monkeypatch.delenv("CONDUCTOR_PROFILE", raising=False)
    monkeypatch.setattr(sys, "argv", ["conductor_api.py", *argv])
    conductor_api.main()


def _assert_no_secrets(capsys) -> str:
    out, err = capsys.readouterr()
    for value in (KEY, SECRET):
        assert value not in out and value not in err
    return out + err


@pytest.fixture
def home(tmp_path, monkeypatch):
    h = tmp_path / "home"
    h.mkdir()
    monkeypatch.setenv("HOME", str(h))
    return h


def test_worker_env_writes_0600_and_prints_only_names(home, tmp_path, monkeypatch, capsys) -> None:
    _profile(home)
    work = tmp_path / "worker"
    work.mkdir()
    _run(monkeypatch, "--profile", "developer", "worker-env", "--out", str(work / ".env"))
    printed = _assert_no_secrets(capsys)
    for name in conductor_api.WORKER_ENV_KEYS:
        assert name in printed
    env = work / ".env"
    assert stat.S_IMODE(env.stat().st_mode) == 0o600
    text = env.read_text()
    assert f"CONDUCTOR_AUTH_KEY='{KEY}'" in text
    assert f"CONDUCTOR_AUTH_SECRET='{SECRET}'" in text
    assert f"CONDUCTOR_SERVER_URL='{SERVER}/api'" in text


def test_worker_env_merges_and_refuses_without_overwrite(home, tmp_path, monkeypatch, capsys) -> None:
    _profile(home)
    env = tmp_path / ".env"
    env.write_text("FOO=1\n# keep me\nexport CONDUCTOR_AUTH_KEY=old-key\n")
    with pytest.raises(SystemExit):
        _run(monkeypatch, "worker-env", "--profile", "developer", "--out", str(env))
    printed = _assert_no_secrets(capsys)
    assert "CONDUCTOR_AUTH_KEY" in printed and "--overwrite" in printed
    assert env.read_text() == "FOO=1\n# keep me\nexport CONDUCTOR_AUTH_KEY=old-key\n"

    _run(monkeypatch, "worker-env", "--profile", "developer", "--out", str(env), "--overwrite")
    _assert_no_secrets(capsys)
    lines = env.read_text().splitlines()
    assert lines[:2] == ["FOO=1", "# keep me"]
    assert sum(line.startswith("CONDUCTOR_AUTH_KEY=") for line in lines) == 1
    assert "old-key" not in env.read_text()
    assert stat.S_IMODE(env.stat().st_mode) == 0o600


def test_worker_env_keeps_unrelated_lines_when_new(home, tmp_path, monkeypatch, capsys) -> None:
    _profile(home)
    env = tmp_path / ".env"
    env.write_text("OPENAI_MODEL=gpt-4o-mini\n")
    _run(monkeypatch, "--profile=developer", "worker-env", "--out", str(tmp_path))  # a folder -> <folder>/.env
    _assert_no_secrets(capsys)
    text = env.read_text()
    assert text.startswith("OPENAI_MODEL=gpt-4o-mini\n")
    assert all(f"{name}=" in text for name in conductor_api.WORKER_ENV_KEYS)


@pytest.mark.parametrize("values", [
    {"server": f"{SERVER}/api", "server-type": "Enterprise", "auth-token": "tok-123"},
    {"server": "http://localhost:8080/api", "server-type": "OSS"},
])
def test_worker_env_refuses_profiles_without_key_and_secret(home, tmp_path, monkeypatch, capsys, values) -> None:
    _profile(home, "other", **values)
    with pytest.raises(SystemExit):
        _run(monkeypatch, "worker-env", "--profile", "other", "--out", str(tmp_path / ".env"))
    out, err = capsys.readouterr()
    assert "no auth key and secret" in err and "tok-123" not in out + err
    assert not (tmp_path / ".env").exists()


def test_worker_env_needs_a_profile(home, tmp_path, monkeypatch, capsys) -> None:
    with pytest.raises(SystemExit):
        _run(monkeypatch, "worker-env", "--out", str(tmp_path / ".env"))
    assert "--profile" in capsys.readouterr().err
    assert not (tmp_path / ".env").exists()


@pytest.mark.skipif(shutil.which("git") is None, reason="git not installed")
def test_worker_env_adds_env_to_gitignore_once(home, tmp_path, monkeypatch, capsys) -> None:
    _profile(home)
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    _run(monkeypatch, "--profile", "developer", "worker-env", "--out", str(repo / ".env"))
    printed = _assert_no_secrets(capsys)
    assert ".gitignore" in printed
    assert (repo / ".gitignore").read_text().splitlines().count(".env") == 1
    _run(monkeypatch, "--profile", "developer", "worker-env", "--out", str(repo / ".env"), "--overwrite")
    printed = _assert_no_secrets(capsys)
    assert ".gitignore" not in printed
    assert (repo / ".gitignore").read_text().splitlines().count(".env") == 1


def test_worker_env_outside_git_leaves_no_gitignore(home, tmp_path, monkeypatch, capsys) -> None:
    _profile(home)
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))
    work = tmp_path / "plain"
    work.mkdir()
    _run(monkeypatch, "--profile", "developer", "worker-env", "--out", str(work / ".env"))
    _assert_no_secrets(capsys)
    assert not (work / ".gitignore").exists()
