"""Builds the zip to upload to CurseForge: only the MMT_* module folders, exactly as
committed (git archive, so nothing that isn't committed and none of tests/, media/,
CLAUDE.md, ...), plus a changelog to paste with it. Run from anywhere in the repo:

    python tools/make_release.py                     # the current commit
    python tools/make_release.py main                # another branch / tag / commit
    python tools/make_release.py main --since "2026-10-29 19:40"
                                                     # changelog from a date (no release tag yet)
    python tools/make_release.py main --tag          # also tag it release-<name> and push the tag

A branch name packs GITHUB's copy of it (fetched first; a local branch can be behind), and a commit
that already has a release tag is refused (--force to build it anyway).

Each upload gets a release name from its commit's date, YYYY.MM.DD (a second release
that day .2, .3, ...): use it as CurseForge's "Display Name" / version. It sorts the
right way everywhere, unlike "29/10/2026 19:40". The changelog lists every module's
version and the commits since the last release tag (release-*), so --tag after an
upload makes the next changelog start there.

Everything lands in dist/ (not tracked: the repo ignores everything it doesn't list).
New modules are picked up by themselves (every MMT_* folder in that commit).
"""
import os, re, subprocess, sys, zipfile


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout.strip()


args = sys.argv[1:]
tag_it = "--tag" in args
since = None
if "--since" in args:
    i = args.index("--since")
    since = args[i + 1]
    del args[i:i + 2]
args = [a for a in args if a != "--tag"]

force = "--force" in args
args = [a for a in args if a != "--force"]

root = git("rev-parse", "--show-toplevel")
os.chdir(root)
ref = args[0] if args else "HEAD"
# a branch name means GitHub's copy of it: a local branch can be behind (2026-10-30 a stale
# local main gave an empty second release)
subprocess.run(["git", "fetch", "-q", "--tags", "origin"], check=False)
if subprocess.run(["git", "rev-parse", "--verify", "-q", "refs/remotes/origin/" + ref],
                  capture_output=True).returncode == 0:
    ref = "origin/" + ref
print("packing %s (%s)" % (ref, git("log", "-1", "--format=%h %s", ref)[:90]))
modules = [d for d in git("ls-tree", "-d", "--name-only", ref).splitlines() if d.startswith("MMT_")]
if not modules:
    sys.exit("no MMT_* folders in " + ref)

# release name: the commit's date, .2 / .3 for more releases that day
tags = set(git("tag", "--list", "release-*").split())
# nothing new since a release that's already tagged: no second, empty release
same = [t for t in tags if git("rev-parse", t + "^{commit}") == git("rev-parse", ref + "^{commit}")]
if same and not force:
    sys.exit("%s is already released as %s - nothing new to release (push your changes to the branch "
             "first, or add --force)." % (ref, ", ".join(sorted(same))))
day = git("log", "-1", "--format=%cd", "--date=format:%Y.%m.%d", ref)
name, n = day, 1
while "release-" + name in tags:
    n += 1
    name = "%s.%d" % (day, n)

os.makedirs("dist", exist_ok=True)
out = os.path.join("dist", "QMMTModules-%s.zip" % name)
subprocess.run(["git", "archive", "--format=zip", "-o", out, ref, *modules], check=True)

# what's in it: one line per module with its version
versions = []
with zipfile.ZipFile(out) as z:
    names = z.namelist()
    for m in modules:
        toc = "%s/%s.toc" % (m, m)
        title, version = m, "?"
        if toc in names:
            for line in z.read(toc).decode("utf-8", "replace").splitlines():
                if line.startswith("## Version:"):
                    version = line.split(":", 1)[1].strip()
                elif line.startswith("## X-MMT-Title:"):
                    title = line.split(":", 1)[1].strip()
        versions.append((title, m, version))
    stray = [n for n in names if not n.split("/")[0].startswith("MMT_")]
    if stray:
        sys.exit("unexpected files in the zip: %s" % ", ".join(stray[:5]))

# changes: commits since the last release tag that's an ancestor of ref (or --since)
last = None
for t in sorted(tags, reverse=True):
    if subprocess.run(["git", "merge-base", "--is-ancestor", t, ref], capture_output=True).returncode == 0:
        last = t
        break
if since:
    log = git("log", "--no-merges", "--format=%s", "--since=" + since, ref)
    origin = "since " + since
elif last:
    log = git("log", "--no-merges", "--format=%s", "%s..%s" % (last, ref))
    origin = "since " + last[len("release-"):]
else:
    log = ""
    origin = None
changes = [l for l in log.splitlines() if l.strip()]

lines = ["# QMMT Modules %s" % name, "", "## Modules", ""]
for title, m, version in versions:
    lines.append("- %s (%s): %s" % (title, m, version))
if origin:
    lines += ["", "## Changes %s" % origin, ""]
    lines += ["- " + c for c in changes] if changes else ["- (no changes)"]
changelog = os.path.join("dist", "CHANGELOG-%s.md" % name)
with open(changelog, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

for title, m, version in versions:
    print("  %-22s %s" % (m, version))
print("%s (%d files)" % (out, len(names)))
print("%s (%d changes)" % (changelog, len(changes)))
print("Display name: QMMT Modules %s" % name)

if tag_it:
    t = "release-" + name
    subprocess.run(["git", "tag", "-a", t, git("rev-parse", ref), "-m", "QMMT Modules " + name], check=True)
    subprocess.run(["git", "push", "-q", "origin", t], check=True)
    print("tagged and pushed " + t)
