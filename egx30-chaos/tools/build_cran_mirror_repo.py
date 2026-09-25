#!/usr/bin/env python3
"""Build a local CRAN-like source repository from the GitHub CRAN mirror.

Use this only where CRAN itself is unreachable but github.com is (e.g. a
locked-down CI or cloud sandbox). It clones github.com/cran/<pkg> for every
requested package plus its recursive Depends/Imports/LinkingTo, tars each
checkout as <pkg>_<version>.tar.gz and writes PACKAGES with R's
tools::write_PACKAGES. Point R at it with

    options(repos = c(CRAN = "file:///abs/path/to/repo"))

and install.packages()/renv::install() resolve dependencies as usual. The
DESCRIPTION files keep "Repository: CRAN", so renv.lock records CRAN as the
source and renv::restore() works unchanged on a normal machine.

Usage: build_cran_mirror_repo.py OUTDIR pkg1 pkg2 ...
"""
import os
import re
import subprocess
import sys
import tarfile
from concurrent.futures import ThreadPoolExecutor

BASE = set("""base compiler datasets graphics grDevices grid methods parallel
splines stats stats4 tcltk tools utils R translations""".split())


def parse_description(path):
    fields, key = {}, None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line[:1] in (" ", "\t") and key:
                fields[key] += " " + line.strip()
            elif ":" in line:
                key, val = line.split(":", 1)
                fields[key] = val.strip()
    return fields


def deps(fields):
    out = set()
    for f in ("Depends", "Imports", "LinkingTo"):
        for item in fields.get(f, "").split(","):
            name = re.sub(r"\(.*?\)", "", item).strip()
            if name and name not in BASE:
                out.add(name)
    return out


def clone(pkg, src):
    dest = os.path.join(src, pkg)
    if not os.path.isdir(dest):
        subprocess.run(["git", "clone", "-q", "--depth", "1",
                        f"https://github.com/cran/{pkg}", dest], check=True)
    return pkg


def main():
    outdir = os.path.abspath(sys.argv[1])
    wanted = set(sys.argv[2:])
    src = os.path.join(outdir, "_git")
    contrib = os.path.join(outdir, "src", "contrib")
    os.makedirs(src, exist_ok=True)
    os.makedirs(contrib, exist_ok=True)
    done, frontier = set(), set(wanted)
    with ThreadPoolExecutor(8) as pool:
        while frontier:
            batch = sorted(frontier - done)
            frontier = set()
            for pkg in pool.map(lambda p: clone(p, src), batch):
                done.add(pkg)
                frontier |= deps(parse_description(os.path.join(src, pkg, "DESCRIPTION")))
            frontier -= done
            print(f"resolved {len(done)} packages", flush=True)
    for pkg in sorted(done):
        ver = parse_description(os.path.join(src, pkg, "DESCRIPTION"))["Version"]
        tgz = os.path.join(contrib, f"{pkg}_{ver}.tar.gz")
        if not os.path.exists(tgz):
            with tarfile.open(tgz, "w:gz") as tar:
                tar.add(os.path.join(src, pkg), arcname=pkg,
                        filter=lambda t: None if "/.git" in t.name or t.name.endswith(".git") else t)
    subprocess.run(["Rscript", "-e",
                    f"tools::write_PACKAGES('{contrib}', type = 'source')"], check=True)
    print(f"wrote {len(done)} packages to {contrib}")


if __name__ == "__main__":
    main()
