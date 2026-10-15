"""changelog from conventional commits

  python tools/changelog.py               # whole CHANGELOG.md to stdout
  python tools/changelog.py --tag v0.2.0  # notes for one release (what CI uses)
  python tools/changelog.py --write       # rewrite CHANGELOG.md
  python tools/changelog.py --write --next v0.2.0
                                          # same, but untagged commits go under v0.2.0

commits that aren't conventional, merges and "chore(release)" bumps are left out.
"""
import argparse
import re
import subprocess
import sys

REPO = "https://github.com/Nevatrix/myanimelist-autotrack.koplugin"

SECTIONS = [
    ("feat", "Features"),
    ("fix", "Fixes"),
    ("perf", "Performance"),
    ("refactor", "Refactoring"),
    ("docs", "Docs"),
    ("test", "Tests"),
    ("ci", "CI"),
    ("build", "Build"),
    ("chore", "Chores"),
]

HEADER = re.compile(r"^(?P<type>\w+)(?:\((?P<scope>[^)]+)\))?(?P<breaking>!)?: (?P<desc>.+)$")


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def tags():
    """version tags, oldest first"""
    out = git("tag", "--list", "v*", "--sort=v:refname").split()
    return out


def commits(rev_range):
    sep, end = "\x1f", "\x1e"
    out = git("log", "--no-merges", f"--format=%H{sep}%s{sep}%b{end}", rev_range)
    result = []
    for raw in out.split(end):
        raw = raw.strip()
        if not raw:
            continue
        sha, subject, body = (raw.split(sep) + ["", ""])[:3]
        m = HEADER.match(subject.strip())
        if not m:
            continue
        if m["type"] == "chore" and m["scope"] == "release":
            continue
        result.append({
            "sha": sha,
            "type": m["type"],
            "scope": m["scope"],
            "desc": m["desc"],
            "breaking": bool(m["breaking"]) or "BREAKING CHANGE" in body,
        })
    return result


def tag_date(tag):
    return git("log", "-1", "--format=%ad", "--date=short", tag).strip()


def render(title, items, prev=None, cur=None):
    lines = [title, ""]
    breaking = [c for c in items if c["breaking"]]
    if breaking:
        lines.append("### ⚠ Breaking changes")
        lines += [f"- {fmt(c)}" for c in breaking]
        lines.append("")
    known = {t for t, _ in SECTIONS}
    for key, name in SECTIONS:
        group = [c for c in items if c["type"] == key]
        if group:
            lines.append(f"### {name}")
            lines += [f"- {fmt(c)}" for c in group]
            lines.append("")
    other = [c for c in items if c["type"] not in known]
    if other:
        lines.append("### Other")
        lines += [f"- {fmt(c)}" for c in other]
        lines.append("")
    if not items:
        lines += ["Nothing user facing in this one.", ""]
    if prev and cur:
        lines.append(f"**Full diff:** [{prev}...{cur}]({REPO}/compare/{prev}...{cur})")
        lines.append("")
    return "\n".join(lines)


def fmt(c):
    scope = f"**{c['scope']}:** " if c["scope"] else ""
    return f"{scope}{c['desc']} ([{c['sha'][:7]}]({REPO}/commit/{c['sha']}))"


def release_notes(tag):
    all_tags = tags()
    prev = None
    if tag in all_tags:
        i = all_tags.index(tag)
        prev = all_tags[i - 1] if i > 0 else None
    elif all_tags:
        prev = all_tags[-1]
    rng = f"{prev}..{tag}" if prev else tag
    return render("## What's changed", commits(rng), prev, tag)


def full_changelog(next_tag=None):
    import datetime
    all_tags = tags()
    parts = ["# Changelog", "", "Generated from the commit history by `tools/changelog.py`.", ""]
    unreleased = commits(f"{all_tags[-1]}..HEAD" if all_tags else "HEAD")
    if unreleased:
        if next_tag:
            prev = all_tags[-1] if all_tags else None
            parts.append(render(f"## {next_tag} ({datetime.date.today().isoformat()})", unreleased, prev, next_tag))
        else:
            parts.append(render("## Unreleased", unreleased))
    for i in range(len(all_tags) - 1, -1, -1):
        tag = all_tags[i]
        prev = all_tags[i - 1] if i > 0 else None
        rng = f"{prev}..{tag}" if prev else tag
        parts.append(render(f"## {tag} ({tag_date(tag)})", commits(rng), prev, tag))
    return "\n".join(parts).rstrip() + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--next", help="name for the commits after the last tag")
    a = ap.parse_args()
    if a.tag:
        sys.stdout.write(release_notes(a.tag))
    elif a.write:
        with open("CHANGELOG.md", "w", encoding="utf-8", newline="\n") as f:
            f.write(full_changelog(a.next))
        print("CHANGELOG.md updated")
    else:
        sys.stdout.write(full_changelog(a.next))


if __name__ == "__main__":
    main()
