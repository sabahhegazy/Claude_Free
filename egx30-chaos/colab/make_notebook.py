#!/usr/bin/env python3
"""Build egx30_replication_colab.ipynb from egx30_replication_colab.R.

The .R script is the single source of truth. Its "# %% [n] Title" markers
become notebook cells, and the header comment block becomes the introductory
markdown cell. Re-run after editing the script:  python3 make_notebook.py
"""
import json, re, pathlib

here = pathlib.Path(__file__).parent
src = (here / "egx30_replication_colab.R").read_text()
first = src.index("# %% [1]")
header, body = src[:first], src[first:]

intro = [
    "# EGX30 chaos analysis: replication in Google Colab (R runtime)\n",
    "\n",
    "Replicates Morad, Rady & Amin (2019) and the referee-requested revisions. "
    "This notebook is generated from `egx30_replication_colab.R`, so the two are identical.\n",
    "\n",
    "**Before running**\n",
    "1. Check the runtime is R: *Runtime > Change runtime type > R*. "
    "This notebook requests it, but Colab can fall back to Python.\n",
    "2. Upload `egx30_2000_2025.csv`: folder icon in the left sidebar > upload. It lands in `/content/`.\n",
    "3. If the file has another name or location, edit `DATA_PATH` in the first code cell.\n",
    "4. *Runtime > Run all*. The first cell installs packages (2-4 min). "
    "`RUN_MODE = \"full\"` takes about 45-60 min; `\"quick\"` about 15-20 min.\n",
    "\n",
    "Every step caches to `/content/egx30_results/cache`. After a disconnect, *Run all* resumes. "
    "Results (CSV tables, PNG figures, `results.rds`, `egx30_results.zip`) are in `/content/egx30_results`.\n",
    "\n",
    "<details><summary>Full notes from the script header</summary>\n\n```\n",
] + [l + "\n" for l in header.rstrip().splitlines()] + ["```\n</details>\n"]

cells = [{"cell_type": "markdown", "metadata": {}, "source": intro}]
chunks = re.split(r"(?m)^(?=# %% \[\d+\])", body)
for ch in chunks:
    if not ch.strip():
        continue
    title = re.match(r"# %% \[\d+\] (.*?)\s*-*\s*$", ch.splitlines()[0]).group(1)
    code = "\n".join(ch.splitlines()[1:]).strip("\n") + "\n"
    cells.append({"cell_type": "markdown", "metadata": {}, "source": [f"## {title}\n"]})
    cells.append({"cell_type": "code", "execution_count": None, "metadata": {}, "outputs": [],
                  "source": [l + "\n" for l in code.rstrip("\n").splitlines()]})

nb = {
    "nbformat": 4, "nbformat_minor": 0,
    "metadata": {
        "colab": {"provenance": [], "toc_visible": True},
        "kernelspec": {"name": "ir", "display_name": "R", "language": "R"},
        "language_info": {"name": "R"},
    },
    "cells": cells,
}
(here / "egx30_replication_colab.ipynb").write_text(json.dumps(nb, indent=1, ensure_ascii=False) + "\n")
print(f"{sum(c['cell_type'] == 'code' for c in cells)} code cells written")
