# EGX30 chaos analysis: replication and revision

This project replicates **Morad, Rady & Amin (2019), "Chaotic Analysis of Egyptian
Stock Market with the Application to EGX 30 Price Index"** (54th Annual Conference
on Statistics, Computer Science and OR, Cairo University, pp. 45–62) in R. It
then carries out the revisions requested in the referee report: GARCH-filtered BDS
with bootstrap inference, corrected variance-ratio tests, bias-corrected R/S, Lo's
test against the right critical values, chaos-specific diagnostics, structural
breaks, and an extended sample through October 2025.

Every chaos diagnostic is first **validated on series with known dynamics**
(logistic map, noisy logistic map, periodic map, GARCH noise, IID noise,
fractional Gaussian noise) before it is applied to EGX30.

## Layout

| Path | Contents |
|---|---|
| `_targets.R` | the pipeline: validation → data → replication → revisions → breaks → report |
| `R/data.R` | reading, cleaning, auditing the EGX30 file |
| `R/simulate.R` | validation DGPs (logistic, GARCH, fGn) and IAAFT surrogates |
| `R/linear.R` | unit roots, ACF/PACF, AR filter, Lo–MacKinlay/Chow–Denning/wild-bootstrap VR |
| `R/nonlinear.R` | BDS, GARCH/GJR/EGARCH filters, ARCH-LM, parametric-bootstrap BDS |
| `R/rescaled_range.R` | classical R/S, V-statistic, Anis–Lloyd–Peters correction, Hurst bootstrap, Lo's modified R/S, DFA, GPH, local Whittle |
| `R/chaos.R` | AMI/Cao embedding, Grassberger–Procaccia D2, 0–1 test, DChaos Lyapunov exponent, nearest-neighbour forecasts with Diebold–Mariano |
| `R/breaks.R` | strucchange (Bai–Perron), changepoint (PELT), ecp (E-divisive), MSGARCH, tvgarch |
| `R/validation.R` | validation table, Monte Carlo operating characteristics, R/S size/power |
| `report.qmd` | Quarto report, rendered by the pipeline to `report.html` |
| `docs/data_quality_report.md` | date/price error audit of the EGX30 file (corrupted row, impact, fixes) |
| `tests/testthat/` | unit tests against known values (run `testthat::test_dir("tests/testthat")`) |
| `references/` | JSS/R Journal material; `MANIFEST.csv` records the source of each file |
| `scripts/download_references.R` | fetches the JSS replication archives and the DChaos article |
| `tools/build_cran_mirror_repo.py` | builds a local CRAN-like repo from github.com/cran for networks without CRAN |

## Running

```r
renv::restore()          # R >= 4.3; packages pinned in renv.lock
targets::tar_make()      # about 1 hour on 4 cores; knobs at the top of _targets.R
targets::tar_read(rep_table1)
```

Quarto ≥ 1.4 must be on the PATH for the report target.

On a machine where CRAN is blocked but github.com is reachable:

```sh
python3 tools/build_cran_mirror_repo.py /tmp/cranrepo $(Rscript -e 'cat(names(jsonlite::read_json("renv.lock")$Packages))')
RENV_CONFIG_REPOS_OVERRIDE=file:///tmp/cranrepo Rscript -e 'renv::restore()'
```

## References

`Rscript scripts/download_references.R` downloads the replication archives for
strucchange (JSS 7(2)), changepoint (JSS 58(3)), ecp (JSS 62(7)), MSGARCH (JSS 91(4))
and tvgarch (JSS 108(9)), plus the DChaos article (R Journal 13(1), RJ-2021-036).
It gets them from jstatsoft.org and journal.r-project.org when those are reachable.
Otherwise it falls back to GitHub. `references/MANIFEST.csv` states which source
was used.

In the session that built this project, jstatsoft.org was blocked. The checked-in
`references/` therefore holds:

- the DChaos article PDF and its replication script
- the MSGARCH authors' JSS replication script (`v91i04.R`)
- the strucchange and ecp JSS papers as package vignettes

The official JSS archives still need to be fetched by rerunning the script.
