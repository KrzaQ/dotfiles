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
BLOCK_BEGIN = "# >>> kq dotfiles >>>"
BLOCK_END = "# <<< kq dotfiles <<<"


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
class ManagedBlock:
    source: str  # relative to DOTFILES_DIR; content goes between markers
    target: str  # relative to HOME


@dataclass
class Module:
    name: str
    files: list[FileLink] = field(default_factory=list)
    dirs: list[DirLink] = field(default_factory=list)
    creates: list[DirCreate] = field(default_factory=list)
    blocks: list[ManagedBlock] = field(default_factory=list)
    default: bool = True


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
        blocks=[
            ManagedBlock("git/ignore", ".config/git/ignore"),
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
        name="ssh-agent",
        default=False,
        files=[
            FileLink("config/systemd/ssh-agent.service", ".config/systemd/user/ssh-agent.service"),
        ],
        blocks=[
            ManagedBlock("zsh/ssh-agent.zprofile", ".zprofile.local"),
        ],
    ),
    Module(
        name="gh",
        files=[
            FileLink("config/gh/config.yml", ".config/gh/config.yml"),
        ],
    ),
    Module(
        name="fastfetch",
        files=[
            FileLink("config/fastfetch/config.jsonc", ".config/fastfetch/config.jsonc"),
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
    BLOCK_CREATE = auto()
    BLOCK_APPEND = auto()
    BLOCK_UPDATE = auto()
    BLOCK_STRIP = auto()
    BLOCK_STRIP_AND_RM = auto()
    BLOCK_CORRUPT = auto()


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


def _read_block_content(source: Path) -> str:
    """Source file content that will live between the markers (no trailing newline)."""
    return source.read_text().rstrip("\n")


def _find_block(text: str) -> tuple[int, int] | None | str:
    """Locate the managed block in text.

    Returns (begin_idx, end_idx) inclusive line indices, None if no markers found,
    or the string "corrupt" if exactly one marker is present (or markers out of order).
    """
    lines = text.splitlines()
    begin = end = -1
    for i, line in enumerate(lines):
        if line == BLOCK_BEGIN:
            begin = i
        elif line == BLOCK_END:
            end = i
    if begin == -1 and end == -1:
        return None
    if begin == -1 or end == -1 or begin > end:
        return "corrupt"
    return (begin, end)


def _strip_block(text: str) -> str:
    """Return text with the managed block removed.

    Also removes a single preceding blank line if present, to avoid growing gaps
    on repeated install/uninstall cycles.
    """
    found = _find_block(text)
    if not isinstance(found, tuple):
        return text
    begin, end = found
    lines = text.splitlines(keepends=True)
    cut_start = begin
    if cut_start > 0 and lines[cut_start - 1].strip() == "":
        cut_start -= 1
    return "".join(lines[:cut_start] + lines[end + 1:])


def _format_block(content: str) -> str:
    """Wrap content with markers. No trailing newline."""
    return f"{BLOCK_BEGIN}\n{content}\n{BLOCK_END}"


def plan_managed_block(mb: ManagedBlock) -> Action:
    source = resolve_source(mb.source)
    target = resolve_target(mb.target)
    if not source.exists():
        return Action(ActionKind.SKIP, target, message=f"source {source} not found")
    if not target.exists():
        return Action(ActionKind.BLOCK_CREATE, target, source=source)
    existing = target.read_text()
    found = _find_block(existing)
    if found is None:
        return Action(ActionKind.BLOCK_APPEND, target, source=source)
    if found == "corrupt":
        return Action(ActionKind.BLOCK_CORRUPT, target,
                      message="exactly one marker found; refusing to edit")
    begin, end = found
    current_block = "\n".join(existing.splitlines()[begin:end + 1])
    expected_block = _format_block(_read_block_content(source))
    if current_block == expected_block:
        return Action(ActionKind.OK, target)
    return Action(ActionKind.BLOCK_UPDATE, target, source=source)


def plan_uninstall_managed_block(mb: ManagedBlock) -> Action | None:
    target = resolve_target(mb.target)
    if not target.exists():
        return None
    existing = target.read_text()
    found = _find_block(existing)
    if found is None:
        return None
    if found == "corrupt":
        return Action(ActionKind.BLOCK_CORRUPT, target,
                      message="exactly one marker found; refusing to edit")
    remaining = _strip_block(existing)
    if remaining.strip() == "":
        return Action(ActionKind.BLOCK_STRIP_AND_RM, target)
    return Action(ActionKind.BLOCK_STRIP, target)


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
        for b in module.blocks:
            actions.append(plan_managed_block(b))
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
        for b in module.blocks:
            a = plan_uninstall_managed_block(b)
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
                case ActionKind.BLOCK_CREATE:
                    print(f"  CREATE  {a.target} (managed block, new file)")
                case ActionKind.BLOCK_APPEND:
                    print(f"  APPEND  {a.target} (managed block)")
                case ActionKind.BLOCK_UPDATE:
                    print(f"  UPDATE  {a.target} (managed block)")
                case ActionKind.BLOCK_STRIP:
                    print(f"  STRIP   {a.target} (managed block)")
                case ActionKind.BLOCK_STRIP_AND_RM:
                    print(f"  STRIP   {a.target} (managed block) + RM (empty)")
                case ActionKind.BLOCK_CORRUPT:
                    print(f"  ERROR   {a.target} ({a.message})")


# ── Execution ───────────────────────────────────────────────────────


def _atomic_write(target: Path, content: str) -> None:
    """Write content to target via a temp file in the same directory, then rename."""
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".tmp")
    tmp.write_text(content)
    tmp.rename(target)


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
                    manifest["backups"].pop(str(a.target), None)
                case ActionKind.RMDIR:
                    a.target.rmdir()
                    created = manifest["created_dirs"]
                    if str(a.target) in created:
                        created.remove(str(a.target))
                case ActionKind.BLOCK_CREATE:
                    content = _read_block_content(a.source)
                    _atomic_write(a.target, _format_block(content) + "\n")
                case ActionKind.BLOCK_APPEND:
                    existing = a.target.read_text()
                    content = _read_block_content(a.source)
                    sep = "" if existing.endswith("\n") else "\n"
                    _atomic_write(a.target, existing + sep + "\n" + _format_block(content) + "\n")
                case ActionKind.BLOCK_UPDATE:
                    existing = a.target.read_text()
                    found = _find_block(existing)
                    assert isinstance(found, tuple)
                    begin, end = found
                    lines = existing.splitlines(keepends=True)
                    content = _read_block_content(a.source)
                    new_lines = (_format_block(content) + "\n").splitlines(keepends=True)
                    _atomic_write(a.target, "".join(lines[:begin] + new_lines + lines[end + 1:]))
                case ActionKind.BLOCK_STRIP:
                    _atomic_write(a.target, _strip_block(a.target.read_text()))
                case ActionKind.BLOCK_STRIP_AND_RM:
                    a.target.unlink()


# ── Manifest ────────────────────────────────────────────────────────


def load_manifest(backup_dir: Path) -> dict:
    manifest_path = backup_dir / MANIFEST_NAME
    if manifest_path.exists():
        return json.loads(manifest_path.read_text())
    return {"backups": {}, "created_dirs": []}


def manifest_is_empty(manifest: dict) -> bool:
    return not manifest["backups"] and not manifest["created_dirs"]


def save_manifest(backup_dir: Path, manifest: dict) -> None:
    if manifest_is_empty(manifest):
        manifest_path = backup_dir / MANIFEST_NAME
        if manifest_path.exists():
            manifest_path.unlink()
        if backup_dir.exists() and not any(backup_dir.iterdir()):
            backup_dir.rmdir()
            print(f"Removed empty backup directory {backup_dir}")
        return
    backup_dir.mkdir(parents=True, exist_ok=True)
    (backup_dir / MANIFEST_NAME).write_text(json.dumps(manifest, indent=2) + "\n")


# ── Validation ──────────────────────────────────────────────────────


def needs_backup(plan: list[tuple[str, list[Action]]]) -> bool:
    return any(a.kind == ActionKind.BACKUP_AND_LINK
               for _, actions in plan for a in actions)


def has_corruption(plan: list[tuple[str, list[Action]]]) -> bool:
    return any(a.kind == ActionKind.BLOCK_CORRUPT
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
            parts = [f"{links} link(s)"]
            if m.blocks:
                parts.append(f"{len(m.blocks)} block(s)")
            if not m.default:
                parts.append("opt-in")
            print(f"  {m.name:12s} ({', '.join(parts)})")
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
    elif args.uninstall:
        selected = MODULES
    else:
        selected = [m for m in MODULES if m.default]

    backup_dir = Path(args.backup_dir).expanduser()
    manifest = load_manifest(backup_dir)

    # Phase 1: plan
    if args.uninstall:
        actions = plan_uninstall(selected, manifest)
    else:
        actions = plan_install(selected, backup_dir, force=args.force)

    # Phase 2: validate
    errors: list[str] = []
    if not args.uninstall and needs_backup(actions) and backup_dir_nonempty(backup_dir):
        errors.append(
            f"backup directory {backup_dir} is not empty.\n"
            "  Run 'make uninstall' first, or remove it manually."
        )
    if has_corruption(actions):
        errors.append(
            "managed-block markers are corrupted in target file(s).\n"
            "  Inspect the file(s) marked ERROR above and fix manually before re-running."
        )

    # Phase 3: display
    if args.dry_run:
        print("(dry run — no changes will be made)")
    print_plan(actions)

    if errors:
        print(file=sys.stderr)
        for msg in errors:
            print(f"Error: {msg}", file=sys.stderr)
        sys.exit(1)

    # Phase 4: execute
    if not args.dry_run:
        execute_plan(actions, backup_dir=backup_dir, manifest=manifest)
        save_manifest(backup_dir, manifest)

    print()


if __name__ == "__main__":
    main()
