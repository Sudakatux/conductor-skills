"""Offline tests for ensure-cli.sh --add-to-path, using a fake CLI and a temporary HOME."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest


SCRIPT = Path(__file__).with_name("ensure-cli.sh")
MARK = "# Added by conductor-skills: conductor CLI on PATH"


@pytest.fixture
def home(tmp_path: Path) -> Path:
    bin_dir = tmp_path / ".local" / "bin"
    bin_dir.mkdir(parents=True)
    cli = bin_dir / "conductor"
    cli.write_text("#!/bin/sh\nexit 0\n")  # answers every --help, so it counts as new enough
    cli.chmod(0o755)
    return tmp_path


def run(home: Path, shell: str, *args: str, path: str = "/usr/bin:/bin") -> subprocess.CompletedProcess[str]:
    env = {"HOME": str(home), "SHELL": shell, "PATH": path}
    return subprocess.run(["sh", str(SCRIPT), *args], env=env, capture_output=True, text=True, check=True)


def test_without_flag_suggests_and_changes_nothing(home: Path) -> None:
    out = run(home, "/bin/zsh")
    assert out.stdout == f"CONDUCTOR_BIN={home}/.local/bin/conductor\n"
    assert "--add-to-path" in out.stderr and ".zshrc" in out.stderr
    assert not (home / ".zshrc").exists()


def test_zsh_adds_one_line_once(home: Path) -> None:
    out = run(home, "/bin/zsh", "--add-to-path")
    assert out.stdout == f"CONDUCTOR_BIN={home}/.local/bin/conductor\n"
    rc = (home / ".zshrc").read_text()
    assert rc == f'\n{MARK}\nexport PATH="$HOME/.local/bin:$PATH"\n'

    run(home, "/bin/zsh", "--add-to-path")
    assert (home / ".zshrc").read_text() == rc


def test_existing_line_is_respected(home: Path) -> None:
    (home / ".zshrc").write_text('export PATH="$HOME/.local/bin:$PATH"\n')
    assert "--add-to-path" not in run(home, "/bin/zsh").stderr
    run(home, "/bin/zsh", "--add-to-path")
    assert MARK not in (home / ".zshrc").read_text()


def test_bash_uses_platform_startup_file(home: Path) -> None:
    run(home, "/bin/bash", "--add-to-path")
    uname = subprocess.run(["uname", "-s"], capture_output=True, text=True).stdout.strip()
    rc = home / (".bash_profile" if uname == "Darwin" else ".bashrc")
    assert MARK in rc.read_text()


def test_fish_writes_conf_d(home: Path) -> None:
    run(home, "/usr/local/bin/fish", "--add-to-path")
    conf = home / ".config" / "fish" / "conf.d" / "conductor-cli.fish"
    assert 'fish_add_path "$HOME/.local/bin"' in conf.read_text()


def test_unknown_shell_prints_line_and_writes_nothing(home: Path) -> None:
    out = run(home, "/bin/tcsh", "--add-to-path")
    assert "PATH not changed" in out.stderr
    assert sorted(p.name for p in home.iterdir()) == [".local"]


def test_already_on_path_is_noop(home: Path) -> None:
    out = run(home, "/bin/zsh", "--add-to-path", path=f"{home}/.local/bin:/usr/bin:/bin")
    assert "nothing to change" in out.stderr
    assert not (home / ".zshrc").exists()
