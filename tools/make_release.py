"""Builds the zip to upload to CurseForge: only the MMT_* module folders, exactly as
committed (git archive, so nothing that isn't committed and none of tests/, media/,
CLAUDE.md, ...). Run from anywhere in the repo:

    python tools/make_release.py          # the current commit
    python tools/make_release.py dev      # another branch / tag / commit

The zip lands in dist/ (not tracked: the repo ignores everything it doesn't list).
New modules are picked up by themselves (every MMT_* folder in that commit).
"""
import os, subprocess, sys, zipfile


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout.strip()


root = git("rev-parse", "--show-toplevel")
os.chdir(root)
ref = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
modules = [d for d in git("ls-tree", "-d", "--name-only", ref).splitlines() if d.startswith("MMT_")]
if not modules:
    sys.exit("no MMT_* folders in " + ref)

stamp = git("log", "-1", "--format=%cd-%h", "--date=format:%Y%m%d", ref)
os.makedirs("dist", exist_ok=True)
out = os.path.join("dist", "QMMTModules-%s.zip" % stamp)
subprocess.run(["git", "archive", "--format=zip", "-o", out, ref, *modules], check=True)

# what's in it: one line per module with its version
with zipfile.ZipFile(out) as z:
    names = z.namelist()
    for m in modules:
        toc = "%s/%s.toc" % (m, m)
        version = "?"
        if toc in names:
            for line in z.read(toc).decode("utf-8", "replace").splitlines():
                if line.startswith("## Version:"):
                    version = line.split(":", 1)[1].strip()
        print("  %-22s %s" % (m, version))
    stray = [n for n in names if not n.split("/")[0].startswith("MMT_")]
    if stray:
        sys.exit("unexpected files in the zip: %s" % ", ".join(stray[:5]))
print("%s (%d files)" % (out, len(names)))
