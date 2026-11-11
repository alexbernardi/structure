"""Laboratories (ADR-0010, AGENT-WORKSHOP/PROTOCOLS/LABORATORY-PIPELINE.md).

A laboratory is a git branch `lab/<name>` checked out in its own worktree (a sibling folder by default), created from
an approved `main`, with a Godot project at LABS/<name>/ that installs pinned versions of approved package systems.
Main -> laboratory -> experiment -> validate -> promote -> main:

  lab create <name> --systems movement_core   worktree + branch from main, scaffold LABS/<name>, pin systems, commit
  lab sync                                     merge the latest main into the lab branch (never rebase / overwrite)
  lab validate                                 static checks, the lab's tests, system pins, a workbench's own suite
  lab promote <name> [--merge]                 merge into a fresh integration branch from main, validate it there,
                                               and (with --merge) fast-forward main to the validated merge commit

Nothing here pushes, force-pushes or rewrites history.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from . import buildinfo, packages, paths, toolchain

NAME_RE = re.compile(r"^[a-z][a-z0-9_]{1,31}$")
TEMPLATE = paths.LABS / "_TEMPLATE"
DEFAULT_GATES = ["check", "tools", "import", "unit", "rooms", "utility", "labs"]


class LabError(RuntimeError):
    pass


def _git(*args: str, cwd: Path = paths.REPO, check: bool = False) -> subprocess.CompletedProcess:
    proc = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise LabError(f"git {' '.join(args)} failed in {cwd}:\n{proc.stdout}{proc.stderr}")
    return proc


def _cli(worktree: Path, *args: str) -> int:
    """Runs another worktree's own CLI (its paths resolve to that worktree). The pinned Godot already installed here is
    shared through STRUCTURE_GODOT, so a fresh worktree does not download it again."""
    print(f"  [{worktree.name}] structure.py {' '.join(args)}", flush=True)
    env = dict(os.environ)
    if "STRUCTURE_GODOT" not in env and toolchain.godot_executable().is_file():
        env["STRUCTURE_GODOT"] = str(toolchain.godot_executable())
    return subprocess.run([sys.executable, str(worktree / "TOOLS" / "cli" / "structure.py"), *args], cwd=worktree, env=env).returncode


def branch(name: str) -> str:
    return f"lab/{name}"


def current_branch(cwd: Path = paths.REPO) -> str:
    return _git("rev-parse", "--abbrev-ref", "HEAD", cwd=cwd).stdout.strip()


def worktrees() -> dict[str, Path]:
    """branch -> worktree path for every worktree of this repository."""
    out, path = {}, None
    for line in _git("worktree", "list", "--porcelain").stdout.splitlines():
        if line.startswith("worktree "):
            path = Path(line[9:])
        elif line.startswith("branch refs/heads/") and path is not None:
            out[line[len("branch refs/heads/"):]] = path
    return out


def dirty(cwd: Path) -> list[str]:
    return [l for l in _git("status", "--porcelain", cwd=cwd).stdout.splitlines() if l.strip()]


def lab_folder(name: str, root: Path = paths.REPO) -> Path:
    return root / "LABS" / name


def load_lab(name: str, root: Path = paths.REPO) -> dict:
    path = lab_folder(name, root) / "lab.json"
    if not path.is_file():
        raise LabError(f"no laboratory '{name}' ({path} missing)")
    return json.loads(path.read_text(encoding="utf-8"))


def current_lab() -> str | None:
    b = current_branch()
    return b.split("/", 1)[1] if b.startswith("lab/") else None


# ---------------------------------------------------------------------------------------------- create

def create(name: str, systems: list[str], base: str = "main", path: Path | None = None) -> Path:
    if not NAME_RE.match(name):
        raise LabError(f"laboratory name must match {NAME_RE.pattern}")
    if _git("rev-parse", "-q", "--verify", f"refs/heads/{branch(name)}").returncode == 0:
        raise LabError(f"branch {branch(name)} already exists")
    for system in systems:
        packages.files_at(system.split("@")[0], None)   # the system exists here
    path = (path or paths.REPO.parent / f"{paths.REPO.name.split('-')[0]}-lab-{name}").resolve()
    if path.exists():
        raise LabError(f"{path} already exists")
    base_sha = _git("rev-parse", base, check=True).stdout.strip()
    _git("worktree", "add", "-b", branch(name), str(path), base, check=True)
    print(f"  worktree {path} on {branch(name)} from {base} {base_sha[:10]}")
    args = ["lab", "init", name, "--base", base_sha] + [a for s in systems for a in ("--systems", s)]
    if _cli(path, *args) != 0:
        raise LabError(f"scaffolding failed in {path}; the worktree is kept for inspection "
                       f"(`git worktree remove {path}` and `git branch -D {branch(name)}` to discard it)")
    return path


def scaffold(name: str, systems: list[str], folder: Path) -> dict:
    """Copies LABS/_TEMPLATE to `folder` and installs the systems ("room" or "room@version"); -> {system: version}."""
    if folder.exists():
        raise LabError(f"{folder} already exists")
    shutil.copytree(TEMPLATE, folder, ignore=shutil.ignore_patterns(".godot", "*.uid"))
    for f in folder.rglob("*"):
        if f.is_file() and f.suffix in {".md", ".json", ".godot", ".gd", ".tscn"}:
            text = f.read_text(encoding="utf-8")
            if "{{LAB_NAME}}" in text:
                f.write_text(text.replace("{{LAB_NAME}}", name), encoding="utf-8")
    pins = {}
    for spec in systems:
        system, _, version = spec.partition("@")
        record = packages.install(system, folder, version or None)
        pins[system] = record["version"]
        print(f"  installed {system} {record['version']} at {folder.name}/{packages.mount(system)}")
    return pins


def init(name: str, systems: list[str], base_sha: str) -> Path:
    """Inside the new lab worktree: scaffold LABS/<name>/ from LABS/_TEMPLATE, pin the systems, commit."""
    folder = lab_folder(name)
    pins = scaffold(name, systems, folder)
    lab = {"name": name, "branch": branch(name), "base": base_sha, "created": buildinfo.utc_now(), "systems": pins,
           "develops": [], "note": "Systems listed in `develops` have their workbench in this lab; the rest are pinned."}
    (folder / "lab.json").write_text(json.dumps(lab, indent=2) + "\n", encoding="utf-8")
    _git("add", str(folder), check=True)
    _git("commit", "-m", f"lab {name}: create from main {base_sha[:10]} with "
         + (", ".join(f"{k} {v}" for k, v in pins.items()) or "no systems"), check=True)
    return folder


# ---------------------------------------------------------------------------------------------- sync

def sync(update_systems: bool = False, base: str = "main") -> int:
    lab = current_lab()
    if lab is None:
        raise LabError(f"not on a laboratory branch (on {current_branch()}); run this in the lab's worktree")
    if dirty(paths.REPO):
        raise LabError("uncommitted changes in the lab: commit them (or `git stash push -u -m <tag>`) before syncing")
    before = _git("rev-parse", "HEAD").stdout.strip()
    proc = _git("merge", "--no-ff", "--no-edit", base)
    if proc.returncode != 0:
        conflicts = _git("diff", "--name-only", "--diff-filter=U").stdout.split()
        print(proc.stdout + proc.stderr)
        print("MERGE CONFLICT - nothing was overwritten. Resolve each file keeping both sides' intent, then "
              "`git add` + `git commit`; or `git merge --abort` to return to", before[:10])
        for f in conflicts:
            print("  conflict:", f)
        return 1
    print(f"  merged {base} into {branch(lab)}: {_git('rev-parse', '--short', 'HEAD').stdout.strip()}")
    return report_pins(lab, update_systems)


def report_pins(lab: str, update: bool = False) -> int:
    data = load_lab(lab)
    changed = False
    for system, pinned in data.get("systems", {}).items():
        current = packages._room(system)["version"]
        verdict = packages.compatibility(pinned, current)
        print(f"  {system}: pinned {pinned}, approved {current} ({verdict})")
        if update and verdict == "behind_compatible":
            packages.install(system, lab_folder(lab))
            data["systems"][system] = current
            changed = True
            print(f"    updated to {current}")
        elif verdict == "behind_breaking":
            print(f"    breaking update: read SYSTEM-ROOMS/{system}/README.md migration notes, then "
                  f"`room install {system} LABS/{lab}` and fix the lab")
    if changed:
        (lab_folder(lab) / "lab.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        _git("add", "-A", "LABS", check=True)
        _git("commit", "-m", f"lab {lab}: update pinned systems", check=True)
    return 0


# ---------------------------------------------------------------------------------------------- validate

def validate(name: str | None, run_suites) -> bool:
    """Static checks, this lab's tests, its pins; plus the full suite of any system it develops (workbench)."""
    name = name or current_lab()
    suites = ["check"]
    if name and lab_folder(name).is_dir():
        suites.append("labs")
        report_pins(name)
        for system in load_lab(name).get("develops", []):
            print(f"  {name} develops {system}: its workbench tests run too")
            suites.append("utility")
    else:
        suites += ["utility"]   # a branch without LABS/<name> (e.g. the movement workbench): its utility tests
    return run_suites(sorted(set(suites), key=suites.index))


# ---------------------------------------------------------------------------------------------- promote

def promote(name: str | None, source_branch: str | None, merge: bool, gates: list[str], base: str = "main") -> dict:
    source = source_branch or branch(name)
    trees = worktrees()
    if _git("rev-parse", "-q", "--verify", f"refs/heads/{source}").returncode != 0:
        raise LabError(f"no branch {source}")
    if source in trees and dirty(trees[source]):
        raise LabError(f"{trees[source]} ({source}) has uncommitted changes; commit them first")
    base_sha = _git("rev-parse", base, check=True).stdout.strip()
    source_sha = _git("rev-parse", source, check=True).stdout.strip()
    ahead = _git("rev-list", "--count", f"{base}..{source}").stdout.strip()
    behind = _git("rev-list", "--count", f"{source}..{base}").stdout.strip()
    stamp = buildinfo.utc_stamp()
    label = (name or source).replace("/", "-")
    integration = f"integrate/{label}-{stamp}"
    where = paths.RUNTIME / "worktrees" / f"integrate-{label}-{stamp}"
    where.parent.mkdir(parents=True, exist_ok=True)
    print(f"Promotion of {source} {source_sha[:10]} ({ahead} commits ahead of {base}, {behind} behind)")
    _git("worktree", "add", "-b", integration, str(where), base, check=True)
    print(f"  integration branch {integration} from {base} {base_sha[:10]} in {where.relative_to(paths.REPO)}")
    proc = _git("merge", "--no-ff", "--no-edit", "-m", f"integrate {source} into {base}", source, cwd=where)
    record = {"source": source, "source_sha": source_sha, "base": base, "base_sha": base_sha, "integration": integration,
              "worktree": str(where), "ahead": int(ahead), "behind": int(behind), "gates": gates, "at": buildinfo.utc_now()}
    if proc.returncode != 0:
        conflicts = _git("diff", "--name-only", "--diff-filter=U", cwd=where).stdout.split()
        record.update({"ok": False, "conflicts": conflicts})
        print("  MERGE CONFLICT in the integration worktree (main and the lab are untouched):")
        for f in conflicts:
            print("    ", f)
        print(f"  Resolve there ({where}), commit, and re-run the gates with "
              f"`structure.py test {' '.join(gates)}` inside it; or sync the lab first (`lab sync`).")
        return _save(record, label, stamp)
    merge_sha = _git("rev-parse", "HEAD", cwd=where).stdout.strip()
    record["merge_sha"] = merge_sha
    print(f"  merged cleanly: {merge_sha[:10]}; running the gates in the integration worktree")
    ok = _cli(where, "setup") == 0 if "import" in gates else True
    ok = ok and _cli(where, "test", *gates) == 0
    record["ok"] = ok
    if not ok:
        print(f"  GATES FAILED - main is untouched; fix on {source} (or in {where}) and promote again")
        return _save(record, label, stamp)
    print("  all gates passed")
    if merge:
        main_tree = trees.get(base)
        if main_tree is None:
            raise LabError(f"{base} is not checked out in any worktree; fast-forward it with "
                           f"`git branch -f {base} {merge_sha}` only if nobody else uses it")
        if dirty(main_tree):
            raise LabError(f"{main_tree} ({base}) has uncommitted changes; the validated merge is {integration}")
        if _git("rev-parse", base).stdout.strip() != base_sha:
            raise LabError(f"{base} moved during validation; promote again so the gates see the new {base}")
        _git("merge", "--ff-only", merge_sha, cwd=main_tree, check=True)
        record["promoted"] = merge_sha
        print(f"  {base} fast-forwarded to the validated merge {merge_sha[:10]} (not pushed)")
    else:
        print(f"  validated merge ready: `structure.py lab promote ... --merge`, or `git -C <{base} worktree> merge "
              f"--ff-only {merge_sha[:10]}`")
    return _save(record, label, stamp)


def _save(record: dict, label: str, stamp: str) -> dict:
    out = paths.RUNTIME / "promotions" / f"lab-{label}-{stamp}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"  record: {out.relative_to(paths.REPO)}")
    return record


def list_labs() -> list[dict]:
    out = []
    trees = worktrees()
    for line in _git("branch", "--list", "lab/*", "--format=%(refname:short) %(objectname:short)").stdout.splitlines():
        b, sha = line.split()
        behind = _git("rev-list", "--count", f"{b}..main").stdout.strip()
        ahead = _git("rev-list", "--count", f"main..{b}").stdout.strip()
        out.append({"branch": b, "commit": sha, "worktree": str(trees.get(b, "")), "ahead_of_main": int(ahead),
                    "behind_main": int(behind)})
    return out
