# Download the JSS replication archives and the DChaos R Journal article.
#
#   Rscript scripts/download_references.R
#
# For each JSS paper the script first scrapes the article page on
# jstatsoft.org and downloads every galley (paper PDF, replication code,
# replication zip). If jstatsoft.org is unreachable (e.g. a locked-down
# sandbox) it falls back to author/CRAN material on GitHub: the paper's
# vignette source and, where the authors publish it, the JSS replication
# script. references/MANIFEST.csv records which source was used for each file,
# so fallback material is never mistaken for the official archive.

jss <- data.frame(
  pkg = c("strucchange", "changepoint", "ecp", "MSGARCH", "tvgarch"),
  id = c("v007i02", "v058i03", "v062i07", "v091i04", "v108i09"),
  doi = c("10.18637/jss.v007.i02", "10.18637/jss.v058.i03", "10.18637/jss.v062.i07",
          "10.18637/jss.v091.i04", "10.18637/jss.v108.i09"),
  title = c(
    "strucchange: An R Package for Testing for Structural Change in Linear Regression Models",
    "changepoint: An R Package for Changepoint Analysis",
    "ecp: An R Package for Nonparametric Multiple Change Point Analysis of Multivariate Data",
    "Markov-Switching GARCH Models in R: The MSGARCH Package",
    "Modeling Nonstationary Financial Volatility with the R Package tvgarch"
  )
)

# GitHub fallbacks: (repo, path in repo, local file name)
fallback <- list(
  strucchange = list(c("cran/strucchange", "vignettes/strucchange-intro.Rnw", "strucchange-intro.Rnw (JSS paper source, vignette)"),
                     c("cran/strucchange", "inst/doc/strucchange-intro.R", "strucchange-intro.R (JSS paper code, vignette)"),
                     c("cran/strucchange", "inst/doc/strucchange-intro.pdf", "strucchange-intro.pdf (JSS paper, vignette build)")),
  changepoint = list(c("rkillick/changepoint", "tests", NA)),
  ecp = list(c("cran/ecp", "inst/doc/ecp.pdf", "ecp.pdf (JSS paper, vignette)")),
  MSGARCH = list(c("keblu/MSGARCH", "Examples/JSS/v91i04.R", "v91i04.R (authors' JSS replication script)"),
                 c("keblu/MSGARCH", "Examples/JSS/v91i04-timing.R", "v91i04-timing.R (authors' JSS timing script)")),
  tvgarch = list(c("cran/tvgarch", "tests", NA))
)

out_root <- "references"
dir.create(out_root, showWarnings = FALSE)
manifest <- list()
log_file <- function(pkg, file, source, status) {
  manifest[[length(manifest) + 1]] <<- data.frame(item = pkg, file = file, source = source, status = status)
}

fetch <- function(url, dest) {
  ok <- tryCatch({
    utils::download.file(url, dest, mode = "wb", quiet = TRUE)
    file.exists(dest) && file.size(dest) > 0
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (!ok && file.exists(dest)) unlink(dest)
  ok
}

jss_galleys <- function(id) {
  page <- tryCatch(readLines(sprintf("https://www.jstatsoft.org/article/view/%s", id), warn = FALSE),
                   error = function(e) NULL, warning = function(w) NULL)
  if (is.null(page)) return(NULL)
  html <- paste(page, collapse = "\n")
  m <- gregexpr(sprintf("https://www\\.jstatsoft\\.org/article/view/%s/[0-9]+", id), html)
  unique(regmatches(html, m)[[1]])
}

git_sparse_file <- function(repo, path, dest_dir) {
  tmp <- tempfile("gh")
  on.exit(unlink(tmp, recursive = TRUE))
  st <- system2("git", c("clone", "-q", "--depth", "1", "--filter=blob:none", "--sparse",
                         sprintf("https://github.com/%s", repo), tmp), stdout = FALSE, stderr = FALSE)
  if (st != 0) return(character(0))
  system2("git", c("-C", tmp, "sparse-checkout", "set", "--no-cone", path), stdout = FALSE, stderr = FALSE)
  src <- file.path(tmp, path)
  files <- if (dir.exists(src)) list.files(src, full.names = TRUE, recursive = TRUE) else src[file.exists(src)]
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(files, dest_dir, overwrite = TRUE)
  file.path(dest_dir, basename(files))
}

for (i in seq_len(nrow(jss))) {
  pkg <- jss$pkg[i]
  dest <- file.path(out_root, "jss", pkg)
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  galleys <- jss_galleys(jss$id[i])
  if (length(galleys)) {
    for (g in galleys) {
      f <- file.path(dest, paste0(jss$id[i], "-", basename(g)))
      ok <- fetch(g, f)
      # Name the file after its content type once we have it.
      if (ok) {
        ext <- switch(system2("file", c("-b", "--mime-type", f), stdout = TRUE),
                      "application/pdf" = ".pdf", "application/zip" = ".zip",
                      "text/plain" = ".R", "")
        file.rename(f, paste0(f, ext))
        f <- paste0(f, ext)
      }
      log_file(pkg, f, g, if (ok) "official JSS galley" else "failed")
    }
    next
  }
  message(pkg, ": jstatsoft.org unreachable, using GitHub fallback")
  for (fb in fallback[[pkg]]) {
    if (is.na(fb[3])) next
    got <- git_sparse_file(fb[1], fb[2], dest)
    log_file(pkg, if (length(got)) got else file.path(dest, basename(fb[2])),
             sprintf("github.com/%s/%s", fb[1], fb[2]),
             if (length(got)) paste("fallback:", fb[3]) else "failed")
  }
  log_file(pkg, NA, sprintf("https://doi.org/%s", jss$doi[i]),
           "official replication archive NOT downloaded (jstatsoft.org unreachable); rerun where it is reachable")
}

# DChaos (Sandubete & Escot 2021), The R Journal 13(1):232-252, RJ-2021-036
rj <- file.path(out_root, "rjournal", "RJ-2021-036")
dir.create(rj, recursive = TRUE, showWarnings = FALSE)
for (f in c("RJ-2021-036.pdf", "RJ-2021-036.zip")) {
  urls <- c(sprintf("https://journal.r-project.org/articles/RJ-2021-036/%s", f),
            sprintf("https://raw.githubusercontent.com/rjournal/rjournal.github.io/master/_articles/RJ-2021-036/%s", f))
  ok <- FALSE
  for (u in urls) if (!ok && (ok <- fetch(u, file.path(rj, f)))) log_file("DChaos", file.path(rj, f), u, "downloaded")
  if (!ok) log_file("DChaos", file.path(rj, f), urls[1], "failed")
}
if (file.exists(file.path(rj, "RJ-2021-036.zip"))) {
  utils::unzip(file.path(rj, "RJ-2021-036.zip"), exdir = rj)
  log_file("DChaos", file.path(rj, "sandubete-escot.R"), "RJ-2021-036.zip", "extracted replication script")
}

manifest <- do.call(rbind, manifest)
utils::write.csv(manifest, file.path(out_root, "MANIFEST.csv"), row.names = FALSE)
print(manifest)
