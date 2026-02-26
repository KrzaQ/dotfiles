# /// script
# requires-python = ">=3.10"
# ///
"""Dotfiles installer — symlinks config files into place."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from enum import Enum, auto
from pathlib import Path

DOTFILES_DIR = Path(__file__).resolve().parent.parent
HOME = Path.home()
MANIFEST_NAME = "manifest.json"


# ── Module definitions ──────────────────────────────────────────────


@dataclass
class FileLink:
    source: str  # relative to DOTFILES_DIR
    target: str  # relative to HOME


@dataclass
class DirLink:
    source: str
    target: str


@dataclass
class DirCreate:
    target: str
    mode: int = 0o755


@dataclass
class Module:
    name: str
    files: list[FileLink] = field(default_factory=list)
    dirs: list[DirLink] = field(default_factory=list)
    creates: list[DirCreate] = field(default_factory=list)


MODULES: list[Module] = [
    Module(
        name="zsh",
        files=[
            FileLink("zsh/.zshrc", ".zshrc"),
            FileLink("zsh/.zprofile", ".zprofile"),
            FileLink("zsh/.zshenv", ".zshenv"),
        ],
    ),
    Module(
        name="vim",
        files=[
            FileLink("vim/.vimrc", ".vimrc"),
        ],
        creates=[
            DirCreate(".vim/backup"),
            DirCreate(".vim/undo"),
        ],
    ),
    Module(
        name="git",
        files=[
            FileLink("git/config", ".config/git/config"),
        ],
    ),
    Module(
        name="ssh",
        files=[
            FileLink("ssh/config", ".ssh/config"),
            FileLink("ssh/authorized_keys", ".ssh/authorized_keys"),
        ],
        dirs=[
            DirLink("ssh/hosts", ".ssh/hosts"),
        ],
        creates=[
            DirCreate(".ssh/local", 0o700),
        ],
    ),
    Module(
        name="gh",
        files=[
            FileLink("config/gh/config.yml", ".config/gh/config.yml"),
        ],
    ),
]

MODULES_BY_NAME = {m.name: m for m in MODULES}


# ── Action types ────────────────────────────────────────────────────


class ActionKind(Enum):
    OK = auto()
    SKIP = auto()
    LINK = auto()
    BACKUP_AND_LINK = auto()
    FORCE_LINK = auto()
    MKDIR = auto()
    RM = auto()
    RESTORE = auto()
    KEEP = auto()
    RMDIR = auto()


@dataclass
class Action:
    kind: ActionKind
    target: Path
    source: Path | None = None
    backup_path: Path | None = None
    mode: int = 0
    message: str = ""


# ── Planning (read-only) ───────────────────────────────────────────


def resolve_target(target: str) -> Path:
    return HOME / target


def resolve_source(source: str) -> Path:
    return DOTFILES_DIR / source


def plan_link(source: Path, target: Path, backup_dir: Path, *, force: bool, is_dir: bool = False) -> Action:
    suffix = "/" if is_dir else ""
    if not source.exists():
        return Action(ActionKind.SKIP, target, message=f"source {source} not found")

    if target.is_symlink():
        current = target.resolve()
        if current == source.resolve():
            return Action(ActionKind.OK, target)
        if force:
            return Action(ActionKind.FORCE_LINK, target, source=source,
                          message=f"was -> {current}")
        return Action(ActionKind.SKIP, target,
                      message=f"symlink -> {current}, use --force to override")

    if target.exists():
        backup_path = backup_dir / target.name
        return Action(ActionKind.BACKUP_AND_LINK, target, source=source,
                      backup_path=backup_path)

    return Action(ActionKind.LINK, target, source=source)


def plan_mkdir(target: Path, mode: int) -> Action:
    if target.exists():
        return Action(ActionKind.OK, target)
    return Action(ActionKind.MKDIR, target, mode=mode)


def plan_uninstall_link(source: Path, target: Path, manifest: dict) -> Action | None:
    if not target.is_symlink():
        return None
    if target.resolve() != source.resolve():
        return None

    backup_str = manifest.get("backups", {}).get(str(target))
    if backup_str:
        backup_path = Path(backup_str)
        if backup_path.exists():
            return Action(ActionKind.RESTORE, target, backup_path=backup_path)

    return Action(ActionKind.RM, target)


def plan_uninstall_dir(target: Path) -> Action | None:
    if not target.is_dir() or target.is_symlink():
        return None
    if any(target.iterdir()):
        return Action(ActionKind.KEEP, target, message="not empty")
    return Action(ActionKind.RMDIR, target)


def plan_install(modules: list[Module], backup_dir: Path, *, force: bool) -> list[tuple[str, list[Action]]]:
    plan = []
    for module in modules:
        actions = []
        for f in module.files:
            actions.append(plan_link(resolve_source(f.source), resolve_target(f.target),
                                     backup_dir, force=force))
        for d in module.dirs:
            actions.append(plan_link(resolve_source(d.source), resolve_target(d.target),
                                     backup_dir, force=force, is_dir=True))
        for c in module.creates:
            actions.append(plan_mkdir(resolve_target(c.target), c.mode))
        plan.append((module.name, actions))
    return plan


def plan_uninstall(modules: list[Module], manifest: dict) -> list[tuple[str, list[Action]]]:
    plan = []
    for module in modules:
        actions = []
        for f in module.files:
            a = plan_uninstall_link(resolve_source(f.source), resolve_target(f.target), manifest)
            if a:
                actions.append(a)
        for d in module.dirs:
            a = plan_uninstall_link(resolve_source(d.source), resolve_target(d.target), manifest)
            if a:
                actions.append(a)
        for c in module.creates:
            a = plan_uninstall_dir(resolve_target(c.target))
            if a:
                actions.append(a)
        plan.append((module.name, actions))
    return plan


# ── Display ─────────────────────────────────────────────────────────


def print_plan(plan: list[tuple[str, list[Action]]]) -> None:
    for module_name, actions in plan:
        print(f"\n[{module_name}]")
        for a in actions:
            match a.kind:
                case ActionKind.OK:
                    print(f"  OK      {a.target}")
                case ActionKind.SKIP:
                    print(f"  SKIP    {a.target} ({a.message})")
                case ActionKind.LINK:
                    print(f"  LINK    {a.target} -> {a.source}")
                case ActionKind.BACKUP_AND_LINK:
                    print(f"  BACK    {a.target} -> {a.backup_path}")
                    print(f"  LINK    {a.target} -> {a.source}")
                case ActionKind.FORCE_LINK:
                    print(f"  FORCE   {a.target} -> {a.source} ({a.message})")
                case ActionKind.MKDIR:
                    print(f"  MKDIR   {a.target}/ (mode {oct(a.mode)})")
                case ActionKind.RM:
                    print(f"  RM      {a.target}")
                case ActionKind.RESTORE:
                    print(f"  RESTORE {a.target} <- {a.backup_path}")
                case ActionKind.KEEP:
                    print(f"  KEEP    {a.target}/ ({a.message})")
                case ActionKind.RMDIR:
                    print(f"  RMDIR   {a.target}/")


# ── Execution ───────────────────────────────────────────────────────


def execute_plan(plan: list[tuple[str, list[Action]]], *, backup_dir: Path, manifest: dict) -> None:
    for _, actions in plan:
        for a in actions:
            match a.kind:
                case ActionKind.OK | ActionKind.SKIP | ActionKind.KEEP:
                    pass
                case ActionKind.LINK:
                    a.target.parent.mkdir(parents=True, exist_ok=True)
                    a.target.symlink_to(a.source)
                case ActionKind.BACKUP_AND_LINK:
                    backup_dir.mkdir(parents=True, exist_ok=True)
                    a.target.rename(a.backup_path)
                    manifest["backups"][str(a.target)] = str(a.backup_path)
                    a.target.symlink_to(a.source)
                case ActionKind.FORCE_LINK:
                    a.target.unlink()
                    a.target.symlink_to(a.source)
                case ActionKind.MKDIR:
                    a.target.mkdir(parents=True, exist_ok=True)
                    a.target.chmod(a.mode)
                    manifest["created_dirs"].append(str(a.target))
                case ActionKind.RM:
                    a.target.unlink()
                case ActionKind.RESTORE:
                    a.target.unlink()
                    a.backup_path.rename(a.target)
                case ActionKind.RMDIR:
                    a.target.rmdir()


# ── Manifest ────────────────────────────────────────────────────────


def load_manifest(backup_dir: Path) -> dict:
    manifest_path = backup_dir / MANIFEST_NAME
    if manifest_path.exists():
        return json.loads(manifest_path.read_text())
    return {"backups": {}, "created_dirs": []}


def save_manifest(backup_dir: Path, manifest: dict) -> None:
    backup_dir.mkdir(parents=True, exist_ok=True)
    (backup_dir / MANIFEST_NAME).write_text(json.dumps(manifest, indent=2) + "\n")


# ── Validation ──────────────────────────────────────────────────────


def needs_backup(plan: list[tuple[str, list[Action]]]) -> bool:
    return any(a.kind == ActionKind.BACKUP_AND_LINK
               for _, actions in plan for a in actions)


def backup_dir_nonempty(backup_dir: Path) -> bool:
    if not backup_dir.exists():
        return False
    return any(backup_dir.iterdir())


# ── Main ────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(description="Dotfiles installer")
    parser.add_argument("-m", "--module", action="append", dest="modules",
                        help="Install specific module(s), can be repeated")
    parser.add_argument("-f", "--force", action="store_true",
                        help="Override existing symlinks pointing elsewhere")
    parser.add_argument("-n", "--dry-run", action="store_true",
                        help="Show what would be done without making changes")
    parser.add_argument("--backup-dir", default=str(HOME / ".dotfiles-backup"),
                        help="Directory for backing up existing files (default: ~/.dotfiles-backup)")
    parser.add_argument("--uninstall", action="store_true",
                        help="Remove symlinks managed by this installer")
    parser.add_argument("--list", action="store_true",
                        help="List available modules")

    args = parser.parse_args()

    if args.list:
        print("Available modules:")
        for m in MODULES:
            links = len(m.files) + len(m.dirs)
            print(f"  {m.name:12s} ({links} link(s))")
        return

    # Resolve which modules to operate on
    if args.modules:
        selected = []
        for name in args.modules:
            if name not in MODULES_BY_NAME:
                print(f"Error: unknown module '{name}'", file=sys.stderr)
                print(f"Available: {', '.join(MODULES_BY_NAME)}", file=sys.stderr)
                sys.exit(1)
            selected.append(MODULES_BY_NAME[name])
    else:
        selected = MODULES

    backup_dir = Path(args.backup_dir).expanduser()
    manifest = load_manifest(backup_dir)

    # Phase 1: plan
    if args.uninstall:
        actions = plan_uninstall(selected, manifest)
    else:
        actions = plan_install(selected, backup_dir, force=args.force)

    # Phase 2: validate
    abort = False
    if not args.uninstall and needs_backup(actions) and backup_dir_nonempty(backup_dir):
        abort = True

    # Phase 3: display
    if args.dry_run:
        print("(dry run — no changes will be made)")
    print_plan(actions)

    if abort:
        print(f"\nError: backup directory {backup_dir} is not empty.", file=sys.stderr)
        print("Run 'make uninstall' first, or remove it manually.", file=sys.stderr)
        sys.exit(1)

    # Phase 4: execute
    if not args.dry_run:
        execute_plan(actions, backup_dir=backup_dir, manifest=manifest)
        save_manifest(backup_dir, manifest)

    print()


if __name__ == "__main__":
    main()
