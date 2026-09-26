# ==============================================================================
# EGX30 chaos analysis: self-contained replication script for Google Colab
# ==============================================================================
# Replicates Morad, Rady & Amin (2019), "Chaotic Analysis of Egyptian Stock
# Market with the Application to EGX 30 Price Index" (54th Annual Conference on
# Statistics, Computer Science and OR, Cairo University, pp. 45-62), and runs
# the revisions requested by the referee report:
#   * data audit and cleaning of the EGX30 file
#   * validation of every chaos tool on series with known dynamics
#   * the paper's Tables 1-7 (descriptives, unit roots, variance ratios, BDS,
#     rescaled range, Hurst bootstrap, Lo's modified R/S)
#   * GARCH-filtered BDS with parametric-bootstrap inference (referee M2)
#   * corrected variance ratios (M3), long memory (M4-M6)
#   * chaos diagnostics: Cao embedding, correlation dimension, 0-1 test,
#     DChaos neural-network Lyapunov exponent, nearest-neighbour forecasts (M1)
#   * structural breaks and regimes: strucchange, changepoint, ecp, MSGARCH,
#     tvgarch (M7), and subsamples around the 2016 float (M8)
#
# ------------------------------------------------------------------------------
# PREREQUISITES AND HOW TO RUN IN GOOGLE COLAB
# ------------------------------------------------------------------------------
# Option A (recommended): native R runtime
#   1. Open https://colab.research.google.com and create a new notebook.
#   2. Runtime > Change runtime type > Runtime type: "R" > Save.
#   3. Upload the data: click the folder icon in the left sidebar, then the
#      upload icon, and choose egx30_2000_2025.csv. It lands in /content/.
#   4. Paste this whole script into one cell (or upload this .R file to
#      /content/ and run: source("/content/egx30_replication_colab.R")).
#   5. Run the cell. The first run installs packages (about 2-4 minutes with
#      the binary repository used below).
#
# Option B: Python runtime with rpy2 (use this if you want Google Drive)
#   Cell 1 (Python):  from google.colab import drive; drive.mount('/content/drive')
#   Cell 2 (Python):  %load_ext rpy2.ipython
#   Cell 3:           %%R
#                     DATA_PATH <- "/content/drive/MyDrive/egx30_2000_2025.csv"
#                     source("/content/egx30_replication_colab.R")
#   Plots are written to OUT_DIR as PNG files in this mode.
#   Google Drive cannot be mounted from the R runtime, which is why Option A
#   uses the upload button instead.
#
# DATA FILE
#   Daily EGX30 closes as CSV with a date column and a close column, e.g.
#       Date,Close
#       02-Jan-00,"1,185.99"
#   Accepted date formats: dd-Mon-yy, yyyy-mm-dd, dd/mm/yyyy, mm/dd/yyyy,
#   dd-mm-yyyy, "Mon dd, yyyy", dd.mm.yyyy. Thousands separators are removed.
#   Month names are parsed in English independently of the machine's locale.
#
# RUN TIME (free Colab, 2 vCPUs)
#   RUN_MODE = "full"   about 45-60 minutes (report-grade bootstrap sizes;
#                       measured 30 min on a 4-core machine)
#   RUN_MODE = "quick"  about 15-20 minutes (smaller bootstraps, same outputs;
#                       measured 11 min on a 4-core machine)
#   Every step caches its result in OUT_DIR/cache. If Colab disconnects,
#   re-run the script and finished steps load from the cache. Delete
#   OUT_DIR/cache to force a fresh run; the cache is also reset automatically
#   when DATA_PATH or RUN_MODE change.
#
# OUTPUTS (in OUT_DIR, default /content/egx30_results)
#   tables/*.csv, figures/*.png, results.rds (every result object), and
#   egx30_results.zip for download (Files pane > right-click > Download).
# ==============================================================================

# %% [1] Settings: the only line you normally need to change is DATA_PATH ------

if (!exists("DATA_PATH")) DATA_PATH <- "/content/egx30_2000_2025.csv"
if (!exists("RUN_MODE")) RUN_MODE <- "full"         # "full" or "quick"
if (!exists("OUT_DIR")) OUT_DIR <- if (dir.exists("/content")) "/content/egx30_results" else "egx30_results"

# Bootstrap and replication sizes for each mode.
BUDGET <- list(
  full  = list(B_HURST = 2000, B_BDS_GARCH = 199, B_DCHAOS = 500, B_DCHAOS_SUB = 200,
               MC_REPS = 25, RS_REPS = 200, VAL_N = 3000, BDS_GAUSS_REPS = 100,
               VR_BOOT = 999, ECP_R = 199),
  quick = list(B_HURST = 300, B_BDS_GARCH = 39, B_DCHAOS = 100, B_DCHAOS_SUB = 50,
               MC_REPS = 5, RS_REPS = 40, VAL_N = 2000, BDS_GAUSS_REPS = 20,
               VR_BOOT = 199, ECP_R = 99)
)[[RUN_MODE]]
if (is.null(BUDGET)) stop('RUN_MODE must be "full" or "quick"')

SEED <- 20191209
PAPER_END <- "2015-12-31"   # the paper's sample ends in December 2015

# %% [2] Environment setup: packages and Colab compatibility -------------------
# Colab's R runtime installs CRAN packages from source by default, which takes
# 20+ minutes for rugarch, MSGARCH and RcppArmadillo. Posit Package Manager
# serves precompiled Linux binaries for the Ubuntu release Colab runs on, so
# we point R at it (falling back to CRAN source if that fails).

os_codename <- function() {
  if (!file.exists("/etc/os-release")) return(NA_character_)
  l <- readLines("/etc/os-release", warn = FALSE)
  v <- sub("^VERSION_CODENAME=", "", grep("^VERSION_CODENAME=", l, value = TRUE))
  if (length(v)) gsub('"', "", v) else NA_character_
}

setup_repos <- function() {
  code <- os_codename()
  cran <- "https://cloud.r-project.org"
  if (.Platform$OS.type == "unix" && Sys.info()[["sysname"]] == "Linux" && !is.na(code)) {
    # Posit Package Manager requires this user agent to serve binaries.
    options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(),
            paste(getRversion(), R.version$platform, R.version$arch, R.version$os)))
    options(repos = c(CRAN = sprintf("https://packagemanager.posit.co/cran/__linux__/%s/latest", code)))
  } else {
    options(repos = c(CRAN = cran))
  }
  options(Ncpus = max(1L, parallel::detectCores()))
  invisible(getOption("repos"))
}

PACKAGES <- c(
  "tseries",          # BDS test, Jarque-Bera
  "urca",             # ADF and Phillips-Perron unit-root tests
  "vrtest",           # Chow-Denning and wild-bootstrap variance-ratio tests
  "rugarch",          # GARCH / GJR / EGARCH filters and simulation
  "FinTS",            # ARCH-LM test
  "nonlinearTseries", # AMI delay and Cao embedding dimension
  "DChaos",           # neural-network Lyapunov exponent (R Journal 2021)
  "strucchange",      # Bai-Perron breakpoints (JSS 2002)
  "changepoint",      # PELT variance changepoints (JSS 2014)
  "ecp",              # E-divisive nonparametric change points (JSS 2014)
  "MSGARCH",          # Markov-switching GARCH (JSS 2019)
  "tvgarch"           # time-varying GARCH (JSS 2024)
)

install_missing <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (!length(missing)) return(invisible(character(0)))
  message("Installing: ", paste(missing, collapse = ", "))
  ok <- tryCatch({ install.packages(missing); TRUE }, error = function(e) FALSE)
  still <- missing[!vapply(missing, requireNamespace, logical(1), quietly = TRUE)]
  if (length(still)) {
    message("Retrying from CRAN source: ", paste(still, collapse = ", "))
    install.packages(still, repos = "https://cloud.r-project.org")
  }
  still <- missing[!vapply(missing, requireNamespace, logical(1), quietly = TRUE)]
  if (length(still)) stop("Could not install: ", paste(still, collapse = ", "),
                          ". Check the log above for the missing system library.")
  invisible(missing)
}

setup_repos()
install_missing(PACKAGES)
suppressPackageStartupMessages({
  library(tseries); library(urca); library(vrtest); library(rugarch)
  library(FinTS); library(nonlinearTseries); library(DChaos)
  library(strucchange); library(changepoint); library(ecp)
  library(MSGARCH); library(tvgarch)
})
set.seed(SEED)
options(width = 150, digits = 5, warn = 1)

# Graphics: inline in the R runtime; PNG files are always written as well.
IN_NOTEBOOK <- isTRUE(getOption("jupyter.in_kernel")) || "IRkernel" %in% loadedNamespaces()
if (IN_NOTEBOOK) options(repr.plot.width = 10, repr.plot.height = 5, repr.plot.res = 110)
PAL <- c("#2a78d6", "#eb6834", "#1baf7a", "#eda100")  # colour-blind-checked palette

dir.create(file.path(OUT_DIR, "tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUT_DIR, "figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUT_DIR, "cache"), recursive = TRUE, showWarnings = FALSE)

# Cache: each analysis step is stored as RDS so a re-run resumes after a
# disconnect. The cache key includes the data file's checksum and RUN_MODE.
cache_key <- function() {
  paste(RUN_MODE, if (file.exists(DATA_PATH)) unname(tools::md5sum(DATA_PATH)) else "nodata")
}
key_file <- file.path(OUT_DIR, "cache", "KEY")
if (!file.exists(key_file) || !identical(readLines(key_file), cache_key())) {
  unlink(list.files(file.path(OUT_DIR, "cache"), full.names = TRUE))
  writeLines(cache_key(), key_file)
}
cached <- function(name, expr) {
  f <- file.path(OUT_DIR, "cache", paste0(name, ".rds"))
  if (file.exists(f)) return(readRDS(f))
  t0 <- Sys.time()
  val <- expr
  saveRDS(val, f)
  message(sprintf("  [%s] done in %.1fs", name, as.numeric(Sys.time() - t0, units = "secs")))
  val
}
RESULTS <- list()
keep <- function(name, value) { RESULTS[[name]] <<- value; invisible(value) }
save_table <- function(x, name) {
  utils::write.csv(as.data.frame(x), file.path(OUT_DIR, "tables", paste0(name, ".csv")), row.names = FALSE)
  invisible(x)
}
show_tab <- function(title, x, digits = 4) {
  cat("\n", strrep("-", 78), "\n", title, "\n", strrep("-", 78), "\n", sep = "")
  if (is.data.frame(x)) print(x, digits = digits, row.names = FALSE) else print(x, digits = digits)
  invisible(x)
}
fig <- function(name, width = 10, height = 5, code) {
  png(file.path(OUT_DIR, "figures", paste0(name, ".png")), width = width, height = height, units = "in", res = 120)
  code(); dev.off()
  if (IN_NOTEBOOK) code()
}
section <- function(title) cat("\n\n", strrep("=", 78), "\n", title, "\n", strrep("=", 78), "\n", sep = "")

# %% [3] Function library -------------------------------------------------------
# Copied from the project's tested R/ modules (egx30-chaos/R/*.R), except the
# data reader above, which fixes the locale and silent-drop issues.

# ---- Data reading and cleaning (locale-independent; fails loudly) ------------

MONTHS <- c(jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
            jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12)

# Replace English month abbreviations with numbers before parsing, so "%b" is
# never used. R matches "%b" against the machine's locale, and under French or
# Arabic locales it parses nothing (see docs/data_quality_report.md, 6.1).
parse_dates <- function(x) {
  if (inherits(x, "Date")) return(x)
  x <- trimws(as.character(x))
  num <- x
  for (m in names(MONTHS)) {
    num <- gsub(paste0("(?i)\\b", m, "[a-z]*\\b"), sprintf("%02d", MONTHS[[m]]), num, perl = TRUE)
  }
  num <- gsub(",", "", num)
  # 4-digit-year formats come first: as.Date() ignores trailing characters, so
  # "%d-%m-%y" would read "02-01-2000" as 2020-01-02. On a tie in the number
  # of parsed dates the earlier format wins; a 4-digit format applied to a
  # 2-digit year yields a year < 1900, which the guard below rejects.
  fmts <- c("%d-%m-%Y", "%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%m %d %Y", "%d.%m.%Y", "%d-%m-%y")
  best <- NULL
  for (f in fmts) {
    d <- as.Date(num, format = f)
    # Guard against 2-digit years parsed by a 4-digit format (year < 1900).
    d[!is.na(d) & as.integer(format(d, "%Y")) < 1900] <- NA
    if (is.null(best) || sum(!is.na(d)) > sum(!is.na(best))) best <- d
  }
  best
}

# Read a daily EGX30 price file: any CSV with a date column and a close column.
# Every row removed at this stage is counted and reported; more than 1% of
# unparseable rows stops the script instead of silently shrinking the sample.
read_egx30 <- function(path) {
  if (!file.exists(path)) {
    stop("Data file not found: ", path, "\nUpload it with the Files pane (left sidebar) ",
         "or set DATA_PATH to its location, then re-run.", call. = FALSE)
  }
  raw <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE,
                         colClasses = "character", strip.white = TRUE)
  nms <- tolower(trimws(names(raw)))
  date_col <- which(nms %in% c("date", "trade date", "day"))[1]
  close_col <- which(nms %in% c("close", "closing", "price", "last", "adj close",
                                "close price", "egx30", "value"))[1]
  if (is.na(date_col) || is.na(close_col)) {
    stop("Could not find date/close columns in ", path, "; found: ",
         paste(names(raw), collapse = ", "), call. = FALSE)
  }
  date <- parse_dates(raw[[date_col]])
  close <- suppressWarnings(as.numeric(gsub("[, ]", "", raw[[close_col]])))
  out <- data.frame(date = date, close = close)
  bad_date <- is.na(out$date)
  bad_price <- !bad_date & !(is.finite(out$close) & out$close > 0)
  if (mean(bad_date | bad_price) > 0.01) {
    stop(sprintf("%d of %d rows have unparseable dates or prices. First bad rows:\n%s",
                 sum(bad_date | bad_price), nrow(raw),
                 paste(utils::capture.output(print(head(raw[bad_date | bad_price, c(date_col, close_col)]))), collapse = "\n")),
         call. = FALSE)
  }
  out <- out[!(bad_date | bad_price), ]
  dup <- duplicated(out$date)
  out <- out[!dup, ]
  out <- out[order(out$date), ]
  message(sprintf("read_egx30: %d rows read, %d bad dates, %d bad prices, %d duplicate dates removed",
                  nrow(raw), sum(bad_date), sum(bad_price), sum(dup)))
  attr(out, "n_raw") <- nrow(raw)
  out
}

# The EGX week is Sunday-Thursday throughout 2000-2025. A Friday/Saturday row
# that repeats the previous close is a stale carry-forward (2005-06-18 in the
# supplied file) and is dropped. A weekend row with a *different* close cannot
# be explained that way, so it is kept but reported for manual review.
clean_egx30 <- function(prices) {
  wd <- as.POSIXlt(prices$date)$wday # 0 = Sunday, 5 = Friday, 6 = Saturday
  weekend <- wd %in% c(5, 6)
  repeat_close <- c(FALSE, diff(prices$close) == 0)
  stale <- weekend & repeat_close
  if (any(weekend & !repeat_close)) {
    warning("Weekend rows with a new price (kept, please verify):\n",
            paste(utils::capture.output(print(prices[weekend & !repeat_close, ])), collapse = "\n"),
            call. = FALSE)
  }
  out <- prices[!stale, ]
  attr(out, "dropped") <- prices[stale, ]
  attr(out, "weekend_kept") <- prices[weekend & !repeat_close, ]
  message(sprintf("clean_egx30: %d stale weekend row(s) dropped: %s", sum(stale),
                  paste(format(prices$date[stale]), collapse = ", ")))
  out
}

# Log returns r_t = log(P_t) - log(P_{t-1}), with trading-calendar gaps flagged.
make_returns <- function(prices, from = NULL, to = NULL) {
  if (!is.null(from)) prices <- prices[prices$date >= as.Date(from), ]
  if (!is.null(to)) prices <- prices[prices$date <= as.Date(to), ]
  r <- diff(log(prices$close))
  gap <- as.numeric(diff(prices$date))
  data.frame(date = prices$date[-1], r = r, gap_days = gap)
}

# Calendar gaps longer than `min_days` (e.g. the Jan-Mar 2011 closure).
calendar_gaps <- function(returns, min_days = 7) {
  g <- returns[returns$gap_days >= min_days, c("date", "gap_days", "r")]
  rownames(g) <- NULL
  g
}

# Returns with the closure-spanning return removed (sensitivity for the
# 27 Jan - 23 Mar 2011 closure, whose single return spans 55 calendar days).
drop_long_gaps <- function(returns, max_gap = 30) returns[returns$gap_days <= max_gap, ]

# Descriptive statistics laid out as in the paper's Table 1.
describe_returns <- function(r) {
  m <- mean(r)
  cm <- r - m
  sk <- mean(cm^3) / mean(cm^2)^1.5
  ku <- mean(cm^4) / mean(cm^2)^2
  jb <- length(r) / 6 * (sk^2 + (ku - 3)^2 / 4)
  data.frame(N = length(r), median = stats::median(r), mean = m, sd = stats::sd(r),
             skewness = sk, kurtosis = ku, iqr = stats::IQR(r), jarque_bera = jb,
             jb_p = stats::pchisq(jb, 2, lower.tail = FALSE),
             min = min(r), max = max(r))
}

# Values reported in Morad, Rady & Amin (2019), Table 1 (1998-2015).
paper_table1 <- function() {
  data.frame(N = 4393, median = 0.000645, mean = 0.000443, sd = 0.017319,
             skewness = -0.350851, kurtosis = 11.75502, iqr = 0.01764,
             jarque_bera = 14120.34, jb_p = 0, min = NA, max = NA)
}

# Data audit: coverage, calendar, gaps, stale prices, extreme moves.
audit_egx30 <- function(raw_prices, prices) {
  r <- make_returns(prices)
  wd <- factor(weekdays(prices$date),
               levels = c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday",
                          "Friday", "Saturday"))
  yr <- table(format(prices$date, "%Y"))
  big <- r[order(-abs(r$r)), ][1:15, ]
  big$close <- prices$close[match(big$date, prices$date)]
  list(
    coverage = data.frame(
      rows_raw = nrow(raw_prices), rows_clean = nrow(prices),
      dropped = nrow(attr(prices, "dropped")),
      first = min(prices$date), last = max(prices$date),
      returns = nrow(r), zero_returns = sum(r$r == 0),
      max_identical_run = max(rle(prices$close)$lengths),
      obs_2000_2015 = sum(r$date <= as.Date("2015-12-31")),
      paper_N_1998_2015 = 4393
    ),
    dropped_rows = attr(prices, "dropped"),
    weekdays = as.data.frame(table(weekday = wd)),
    per_year = data.frame(year = names(yr), obs = as.integer(yr)),
    gaps = calendar_gaps(r, 7),
    largest_moves = big,
    events = r[r$date %in% as.Date(c("2003-01-29", "2003-01-30", "2003-02-02",
                                     "2008-10-07", "2011-01-27", "2011-03-23",
                                     "2016-11-03", "2016-11-06", "2020-03-15",
                                     "2024-03-06")), ]
  )
}

# Data-generating processes for validating the chaos toolkit -------------------

# Logistic map x_{t+1} = r x_t (1 - x_t) with optional additive measurement
# noise. For r = 4 the largest Lyapunov exponent is log(2) = 0.693.
sim_logistic <- function(n, r = 4, x0 = 0.1234, burn = 500, noise_sd = 0) {
  x <- numeric(n + burn)
  x[1] <- x0
  for (t in seq_len(n + burn - 1)) x[t + 1] <- r * x[t] * (1 - x[t])
  x <- x[-seq_len(burn)]
  x + stats::rnorm(n, sd = noise_sd)
}

# AR(1)-GJR-GARCH(1,1) with standardised Student-t innovations. With
# `gamma = 0` and `phi = 0` this is plain GARCH(1,1) noise: stochastic, non-IID,
# fat-tailed, with volatility clustering, and not chaotic.
sim_garch <- function(n, omega = 1e-5, alpha = 0.08, beta = 0.88, gamma = 0,
                      phi = 0, mu = 0, df = 6, burn = 1000) {
  N <- n + burn
  z <- if (is.finite(df)) stats::rt(N, df) * sqrt((df - 2) / df) else stats::rnorm(N)
  h <- numeric(N)
  e <- numeric(N)
  y <- numeric(N)
  h[1] <- omega / (1 - alpha - beta - gamma / 2)
  e[1] <- sqrt(h[1]) * z[1]
  y[1] <- mu + e[1]
  for (t in 2:N) {
    h[t] <- omega + (alpha + gamma * (e[t - 1] < 0)) * e[t - 1]^2 + beta * h[t - 1]
    e[t] <- sqrt(h[t]) * z[t]
    y[t] <- mu + phi * (y[t - 1] - mu) + e[t]
  }
  y[-seq_len(burn)]
}

# Fractional Gaussian noise via Davies-Harte circulant embedding.
sim_fgn <- function(n, H) {
  k <- 0:n
  acv <- 0.5 * (abs(k + 1)^(2 * H) - 2 * abs(k)^(2 * H) + abs(k - 1)^(2 * H))
  lam <- Re(stats::fft(c(acv, rev(acv[2:n]))))
  if (any(lam < 0)) lam[lam < 0] <- 0
  m <- 2 * n
  w <- complex(real = stats::rnorm(m), imaginary = stats::rnorm(m))
  x <- stats::fft(sqrt(lam / m) * w)
  Re(x)[seq_len(n)]
}

# Iterative amplitude-adjusted Fourier-transform surrogate (Schreiber &
# Schmitz 1996): keeps the marginal distribution and (approximately) the
# periodogram, destroys any nonlinear structure.
iaaft <- function(x, iter = 100) {
  n <- length(x)
  sorted <- sort(x)
  amp <- Mod(stats::fft(x))
  s <- sample(x)
  for (i in seq_len(iter)) {
    f <- stats::fft(s)
    s <- Re(stats::fft(amp * exp(1i * Arg(f)), inverse = TRUE)) / n
    s_new <- sorted[rank(s, ties.method = "first")]
    if (identical(s_new, s)) break
    s <- s_new
  }
  s
}

# The validation panel: known chaotic, periodic, and stochastic series.
validation_series <- function(n = 3000, seed = 20191209) {
  set.seed(seed)
  list(
    logistic_r4        = sim_logistic(n, r = 4),
    logistic_r4_noisy  = sim_logistic(n, r = 4, noise_sd = 0.05),
    logistic_r3.5      = sim_logistic(n, r = 3.5),
    garch_t            = sim_garch(n),
    ar_gjr_garch_t     = sim_garch(n, alpha = 0.05, gamma = 0.08, phi = 0.18),
    iid_gaussian       = stats::rnorm(n),
    fgn_h0.7           = sim_fgn(n, H = 0.7)
  )
}

# Ground truth for the validation panel.
validation_truth <- function() {
  data.frame(
    series = c("logistic_r4", "logistic_r4_noisy", "logistic_r3.5", "garch_t",
               "ar_gjr_garch_t", "iid_gaussian", "fgn_h0.7"),
    chaotic = c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE),
    iid = c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE),
    long_memory = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE),
    true_lle = c(log(2), log(2), NA, NA, NA, NA, NA),
    true_H = c(NA, NA, NA, 0.5, 0.5, 0.5, 0.7)
  )
}

# Rescaled-range (R/S), V-statistic, Lo's modified R/S, DFA, GPH, local Whittle

#: Sub-period grid used in Morad, Rady & Amin (2019), Table 5. Every n divides
#: 7,000 but none divides the paper's N = 4,393 (referee comment M5.3).
PAPER_RS_GRID <- c(10, 14, 20, 25, 28, 35, 40, 50, 56, 70, 100, 125, 140, 175,
                   200, 250, 280, 350, 500, 700, 875, 1000, 1240)

# Log-spaced sub-period grid keeping at least `min_blocks` blocks.
rs_grid <- function(N, n_min = 10, min_blocks = 4, k = 25) {
  unique(round(exp(seq(log(n_min), log(N / min_blocks), length.out = k))))
}

# Classical R/S (Hurst 1951; Peters 1994). Each n uses p = floor(N/n)
# contiguous blocks from the start of the sample; the N - p*n leftover
# observations are reported, never silently dropped.
rs_table <- function(x, ns = rs_grid(length(x))) {
  N <- length(x)
  ns <- ns[ns >= 3 & ns <= N / 2]
  rows <- lapply(ns, function(n) {
    p <- N %/% n
    blocks <- matrix(x[seq_len(p * n)], nrow = n)
    rs <- apply(blocks, 2, function(b) {
      z <- cumsum(b - mean(b))
      s <- sqrt(mean((b - mean(b))^2))
      (max(z) - min(z)) / s
    })
    data.frame(n = n, blocks = p, leftover = N - p * n, rs = mean(rs))
  })
  out <- do.call(rbind, rows)
  out$log_n <- log10(out$n)
  out$log_rs <- log10(out$rs)
  out$v_stat <- out$rs / sqrt(out$n)
  out$e_rs <- expected_rs(out$n)
  out$v_expected <- out$e_rs / sqrt(out$n)
  out
}

# Anis-Lloyd (1976) expected R/S for IID Gaussian noise with the Peters (1994)
# small-sample factor (n - 1/2)/n.
expected_rs <- function(n) {
  vapply(n, function(k) {
    i <- seq_len(k - 1)
    g <- if (k <= 340) exp(lgamma((k - 1) / 2) - lgamma(k / 2)) / sqrt(pi)
         else 1 / sqrt(k * pi / 2)
    ((k - 0.5) / k) * g * sum(sqrt((k - i) / i))
  }, numeric(1))
}

# Hurst exponent from an R/S table over n in [n_lo, n_hi].
# `H` is the classical OLS slope; `H_AL` is the Anis-Lloyd-Peters corrected
# estimate 0.5 + slope(log R/S - log E[R/S]).
hurst_fit <- function(tab, n_lo = min(tab$n), n_hi = max(tab$n)) {
  s <- tab[tab$n >= n_lo & tab$n <= n_hi, ]
  if (nrow(s) < 3) return(c(H = NA_real_, H_AL = NA_real_, k = nrow(s)))
  H <- unname(stats::coef(stats::lm(log_rs ~ log_n, data = s))[2])
  H_AL <- 0.5 + unname(stats::coef(stats::lm(I(log_rs - log10(e_rs)) ~ log_n, data = s))[2])
  c(H = H, H_AL = H_AL, k = nrow(s))
}

# Hurst exponents over a list of n-ranges (named list of c(lo, hi)).
hurst_ranges <- function(x, ranges, ns = PAPER_RS_GRID) {
  tab <- rs_table(x, ns)
  t(vapply(ranges, function(r) hurst_fit(tab, r[1], r[2]), numeric(3)))
}

# Shuffle / Gaussian bootstrap of H under an IID null (paper Table 6, Part B).
# Returns the null draws plus one-sided (H > H_obs) and two-sided p-values.
hurst_bootstrap <- function(x, ranges, ns = PAPER_RS_GRID, B = 1000,
                            null = c("shuffle", "gaussian"), seed = 1) {
  null <- match.arg(null)
  set.seed(seed)
  obs <- hurst_ranges(x, ranges, ns)
  draws <- replicate(B, {
    xb <- if (null == "shuffle") sample(x) else stats::rnorm(length(x), mean(x), stats::sd(x))
    hurst_ranges(xb, ranges, ns)[, c("H", "H_AL")]
  }, simplify = "array")
  summ <- lapply(seq_along(ranges), function(i) {
    hb <- draws[i, "H", ]
    hal <- draws[i, "H_AL", ]
    data.frame(
      range = names(ranges)[i], null = null,
      H_obs = obs[i, "H"], H_null_mean = mean(hb),
      p_upper = (1 + sum(hb >= obs[i, "H"])) / (B + 1),
      p_two_sided = min(1, 2 * min((1 + sum(hb >= obs[i, "H"])) / (B + 1),
                                   (1 + sum(hb <= obs[i, "H"])) / (B + 1))),
      H_AL_obs = obs[i, "H_AL"], H_AL_null_mean = mean(hal),
      p_AL_upper = (1 + sum(hal >= obs[i, "H_AL"])) / (B + 1)
    )
  })
  list(summary = do.call(rbind, summ), draws = draws)
}

# Lo (1991) modified R/S statistic V_q = Q_q / sqrt(N).
lo_modified_rs <- function(x, q) {
  N <- length(x)
  y <- x - mean(x)
  z <- cumsum(y)
  g <- stats::acf(y, lag.max = max(q, 1), type = "covariance", plot = FALSE,
                  demean = FALSE)$acf[, 1, 1]
  s2 <- g[1]
  if (q > 0) {
    j <- seq_len(q)
    s2 <- s2 + 2 * sum((1 - j / (q + 1)) * g[j + 1])
  }
  (max(z) - min(z)) / sqrt(s2) / sqrt(N)
}

# Andrews (1991) data-dependent bandwidth used by Lo (1991).
andrews_q <- function(x) {
  N <- length(x)
  rho <- stats::acf(x, lag.max = 1, plot = FALSE)$acf[2]
  floor((1.5 * N)^(1 / 3) * (2 * abs(rho) / (1 - rho^2))^(2 / 3))
}

# Lo's test over several q. Critical values from Lo (1991), Table II:
# two-sided 95% acceptance region [0.809, 1.862]; 99% region [0.721, 2.098].
lo_test_table <- function(x, qs = NULL) {
  N <- length(x)
  if (is.null(qs)) {
    qs <- c(`Andrews` = andrews_q(x), `N^(1/4)` = round(N^0.25),
            `N^(1/3)` = round(N^(1 / 3)), `N^(1/2)` = round(sqrt(N)),
            `100` = 100, `150` = 150)
  }
  v <- vapply(qs, function(q) lo_modified_rs(x, q), numeric(1))
  data.frame(q_rule = names(qs), q = unname(qs), V = unname(v),
             reject_95 = v < 0.809 | v > 1.862,
             reject_99 = v < 0.721 | v > 2.098)
}

# Detrended fluctuation analysis (Peng et al. 1994), linear detrending.
dfa_alpha <- function(x, scales = NULL) {
  N <- length(x)
  if (is.null(scales)) scales <- unique(round(exp(seq(log(10), log(N / 4), length.out = 20))))
  y <- cumsum(x - mean(x))
  Fs <- vapply(scales, function(s) {
    p <- N %/% s
    Y <- matrix(y[seq_len(p * s)], nrow = s)
    tt <- seq_len(s)
    X <- cbind(1, tt)
    H <- X %*% solve(crossprod(X), t(X))
    res <- Y - H %*% Y
    sqrt(mean(res^2))
  }, numeric(1))
  fit <- stats::lm(log(Fs) ~ log(scales))
  list(alpha = unname(stats::coef(fit)[2]),
       table = data.frame(scale = scales, F = Fs))
}

# Geweke-Porter-Hudak log-periodogram estimate of d with m = N^bw.
gph_d <- function(x, bw = 0.5) {
  N <- length(x)
  m <- floor(N^bw)
  I <- periodogram(x)[seq_len(m)]
  lam <- 2 * pi * seq_len(m) / N
  reg <- -log(4 * sin(lam / 2)^2)
  fit <- stats::lm(log(I) ~ reg)
  c(d = unname(stats::coef(fit)[2]),
    se = pi / sqrt(24 * sum((reg - mean(reg))^2)), m = m)
}

# Robinson (1995) local Whittle estimate of d with m = N^bw; se = 1/(2 sqrt(m)).
local_whittle_d <- function(x, bw = 0.65) {
  N <- length(x)
  m <- floor(N^bw)
  I <- periodogram(x)[seq_len(m)]
  lam <- 2 * pi * seq_len(m) / N
  R <- function(d) log(mean(lam^(2 * d) * I)) - 2 * d * mean(log(lam))
  d <- stats::optimize(R, c(-0.49, 0.99))$minimum
  c(d = d, se = 1 / (2 * sqrt(m)), m = m)
}

periodogram <- function(x) {
  N <- length(x)
  f <- stats::fft(x - mean(x))
  (Mod(f)^2 / (2 * pi * N))[-1]
}

# Long-memory summary for one series.
long_memory_summary <- function(x) {
  tab <- rs_table(x)
  h <- hurst_fit(tab)
  g <- gph_d(x)
  lw <- local_whittle_d(x)
  data.frame(
    H_rs = h[["H"]], H_rs_AL = h[["H_AL"]],
    dfa_alpha = dfa_alpha(x)$alpha,
    gph_d = g[["d"]], gph_se = g[["se"]],
    lw_d = lw[["d"]], lw_se = lw[["se"]],
    lo_V_andrews = lo_modified_rs(x, andrews_q(x))
  )
}

# Linear diagnostics: unit roots, ACF/PACF, AR filter, variance ratios ---------

# ADF and Phillips-Perron tests (urca), with lag selection reported.
unit_root_tests <- function(r, max_lags = 20) {
  adf <- urca::ur.df(r, type = "drift", lags = max_lags, selectlags = "BIC")
  pp <- urca::ur.pp(r, type = "Z-tau", model = "constant", lags = "short")
  data.frame(
    test = c("ADF (drift, BIC lags)", "Phillips-Perron (Z-tau, constant, short)"),
    statistic = c(adf@teststat[1, "tau2"], pp@teststat),
    lags = c(sum(grepl("z.diff.lag", rownames(adf@testreg$coefficients))), pp@lag),
    cv_1pct = c(adf@cval["tau2", "1pct"], pp@cval[1, "1pct"]),
    cv_5pct = c(adf@cval["tau2", "5pct"], pp@cval[1, "5pct"]),
    cv_10pct = c(adf@cval["tau2", "10pct"], pp@cval[1, "10pct"])
  )
}

# ACF and PACF to lag 15 with 1% bands, as in the paper's Figs 2-3.
acf_table <- function(r, lag.max = 15) {
  a <- stats::acf(r, lag.max = lag.max, plot = FALSE)$acf[-1]
  p <- stats::pacf(r, lag.max = lag.max, plot = FALSE)$acf
  data.frame(lag = seq_len(lag.max), acf = a, pacf = p,
             band_1pct = stats::qnorm(0.995) / sqrt(length(r)))
}

# AR order by AIC and BIC (paper uses PACF only; referee minor 5).
ar_order_selection <- function(r, max_p = 10) {
  ic <- t(vapply(0:max_p, function(p) {
    f <- stats::arima(r, order = c(p, 0, 0), method = "ML")
    c(p = p, aic = stats::AIC(f), bic = stats::BIC(f))
  }, numeric(3)))
  ic <- as.data.frame(ic)
  attr(ic, "best") <- c(aic = ic$p[which.min(ic$aic)], bic = ic$p[which.min(ic$bic)])
  ic
}

# AR(p) filter; residuals are the paper's "filtered data".
ar_filter <- function(r, p = 2) {
  f <- stats::arima(r, order = c(p, 0, 0), method = "ML")
  res <- as.numeric(stats::residuals(f))
  lb <- vapply(c(10, 15, 20), function(l)
    stats::Box.test(res, lag = l, type = "Ljung-Box", fitdf = p)$p.value, numeric(1))
  list(fit = f, residuals = res,
       ljung_box = data.frame(lag = c(10, 15, 20), p_value = lb))
}

# Lo-MacKinlay variance ratios computed directly (overlapping, bias-corrected)
# with homoskedastic z1 and heteroskedasticity-robust z2.
variance_ratio <- function(r, qs = c(2, 4, 8, 16)) {
  T <- length(r)
  mu <- mean(r)
  s1 <- sum((r - mu)^2) / (T - 1)
  do.call(rbind, lapply(qs, function(q) {
    rq <- stats::filter(r, rep(1, q), sides = 1)[q:T]
    m <- q * (T - q + 1) * (1 - q / T)
    sq <- sum((rq - q * mu)^2) / m
    vr <- sq / s1
    z1 <- (vr - 1) / sqrt(2 * (2 * q - 1) * (q - 1) / (3 * q * T))
    e2 <- (r - mu)^2
    delta <- vapply(seq_len(q - 1), function(j)
      T * sum(e2[(j + 1):T] * e2[1:(T - j)]) / sum(e2)^2, numeric(1))
    theta <- sum((2 * (q - seq_len(q - 1)) / q)^2 * delta)
    z2 <- sqrt(T) * (vr - 1) / sqrt(theta)
    data.frame(q = q, VR = vr, z1 = z1, z2 = z2,
               p_z2 = 2 * stats::pnorm(-abs(z2)))
  }))
}

# Variance-ratio battery: robust z2, Chow-Denning joint test, wild bootstrap.
vr_battery <- function(r, qs = c(2, 4, 8, 16), nboot = 999, seed = 1) {
  set.seed(seed)
  cd <- vrtest::Chow.Denning(r, qs)
  bt <- vrtest::Boot.test(r, qs, nboot = nboot, wild = "Normal")
  list(
    lo_mackinlay = variance_ratio(r, qs),
    chow_denning = data.frame(CD1 = cd$CD1, CD2 = cd$CD2,
                              cv_5pct = unname(cd$Critical.Values_10_5_1_percent[2])),
    wild_bootstrap_p = data.frame(
      test = c(paste0("Lo-MacKinlay q=", qs), "Chow-Denning joint"),
      p = c(bt$LM.pval, bt$CD.pval))
  )
}

# Referee M3: VRs of the *differenced* return series reproduce the
# implausibly small values in the paper's Table 3.
vr_misapplied <- function(r, qs = c(2, 4, 8, 16)) {
  out <- variance_ratio(diff(r), qs)[, c("q", "VR")]
  out$paper_VR <- c(0.608228, 0.303588, 0.157507, 0.076868)[seq_along(qs)]
  out$VR_times_q <- out$VR * out$q
  out
}

# Smoothed log spectrum for the paper's Fig. 4 and the referee's M4.
spectrum_table <- function(r, spans = c(7, 7)) {
  s <- stats::spec.pgram(r, spans = spans, plot = FALSE, taper = 0.1, detrend = FALSE)
  data.frame(freq = s$freq, spec = s$spec)
}

# BDS tests, conditional-heteroskedasticity filters, ARCH-LM -------------------

# BDS W statistics for m = 2..m_max and eps = eps_sd * sd(x) (paper Table 4).
bds_grid <- function(x, m_max = 5, eps_sd = c(0.5, 1, 1.5, 2)) {
  b <- tseries::bds.test(x, m = m_max, eps = eps_sd * stats::sd(x))
  out <- expand.grid(m = 2:m_max, eps_sd = eps_sd)
  out$W <- as.vector(b$statistic)
  out$p <- as.vector(b$p.value)
  out
}

# Paper Table 4 layout: BDS on original, AR-filtered, shuffled filtered and
# Gaussian data, where the Gaussian column averages `reps` replications
# (referee minor 7) instead of one draw.
bds_paper_table <- function(r, ar_resid, reps = 100, seed = 1) {
  set.seed(seed)
  orig <- bds_grid(r)
  filt <- bds_grid(ar_resid)
  shuf <- bds_grid(sample(ar_resid))
  gauss <- Reduce(`+`, lapply(seq_len(reps), function(i)
    bds_grid(stats::rnorm(length(r)))$W)) / reps
  data.frame(eps_sd = orig$eps_sd, m = orig$m, original = orig$W,
             ar_filtered = filt$W, shuffled = shuf$W, gaussian_mean = gauss)
}

# Univariate GARCH specification (rugarch).
garch_spec <- function(model = c("sGARCH", "gjrGARCH", "eGARCH"), ar = 2,
                       dist = "std") {
  model <- match.arg(model)
  rugarch::ugarchspec(
    variance.model = list(model = model, garchOrder = c(1, 1)),
    mean.model = list(armaOrder = c(ar, 0), include.mean = TRUE),
    distribution.model = dist
  )
}

fit_garch <- function(r, model = "gjrGARCH", ar = 2, dist = "std") {
  rugarch::ugarchfit(garch_spec(model, ar, dist), r, solver = "hybrid")
}

# Fit AR-GARCH, AR-GJR and AR-EGARCH and collect standardized residuals.
garch_filters <- function(r, ar = 2) {
  fits <- lapply(c(GARCH = "sGARCH", GJR = "gjrGARCH", EGARCH = "eGARCH"),
                 function(m) fit_garch(r, m, ar))
  ic <- do.call(rbind, lapply(names(fits), function(n) {
    f <- fits[[n]]
    cf <- rugarch::coef(f)
    data.frame(model = n, loglik = rugarch::likelihood(f),
               aic = rugarch::infocriteria(f)[1], bic = rugarch::infocriteria(f)[2],
               persistence = rugarch::persistence(f),
               leverage = if ("gamma1" %in% names(cf)) cf[["gamma1"]] else NA,
               leverage_t = if ("gamma1" %in% names(cf))
                 f@fit$robust.matcoef["gamma1", 3] else NA)
  }))
  list(fits = fits, ic = ic,
       std_resid = lapply(fits, function(f) as.numeric(rugarch::residuals(f, standardize = TRUE))))
}

# Engle ARCH-LM test at several lags.
arch_lm <- function(x, lags = c(5, 10)) {
  do.call(rbind, lapply(lags, function(l) {
    t <- FinTS::ArchTest(x, lags = l)
    data.frame(lags = l, LM = unname(t$statistic), p = t$p.value)
  }))
}

# Parametric bootstrap of BDS on GARCH standardized residuals (Hsieh 1991;
# BDS on estimated residuals is not nuisance-parameter free). Simulates from
# the fitted model, refits, and recomputes BDS each time.
bds_garch_bootstrap <- function(fit, r, B = 199, m_max = 5,
                                eps_sd = c(0.5, 1, 1.5, 2), seed = 1) {
  spec <- rugarch::getspec(fit)
  model <- spec@model$modeldesc$vmodel
  ar <- spec@model$modelinc[["ar"]]
  obs <- bds_grid(as.numeric(rugarch::residuals(fit, standardize = TRUE)), m_max, eps_sd)
  sim <- rugarch::ugarchsim(fit, n.sim = length(r), m.sim = B, startMethod = "unconditional",
                            rseed = seed + seq_len(B))
  X <- rugarch::fitted(sim)
  draws <- vapply(seq_len(B), function(b) {
    f <- tryCatch(fit_garch(X[, b], model, ar), error = function(e) NULL)
    if (is.null(f) || f@fit$convergence != 0) return(rep(NA_real_, nrow(obs)))
    bds_grid(as.numeric(rugarch::residuals(f, standardize = TRUE)), m_max, eps_sd)$W
  }, numeric(nrow(obs)))
  ok <- colSums(is.na(draws)) == 0
  draws <- draws[, ok, drop = FALSE]
  obs$p_asymptotic <- obs$p
  obs$p_bootstrap <- vapply(seq_len(nrow(obs)), function(i)
    (1 + sum(abs(draws[i, ]) >= abs(obs$W[i]))) / (ncol(draws) + 1), numeric(1))
  obs$cv95_lo <- apply(draws, 1, stats::quantile, 0.025)
  obs$cv95_hi <- apply(draws, 1, stats::quantile, 0.975)
  obs$p <- NULL
  attr(obs, "B_used") <- ncol(draws)
  obs
}

# Chaos-specific diagnostics (referee M1) ---------------------------------------

# Delay embedding: rows are (x_t, x_{t-lag}, ..., x_{t-(m-1)lag}).
embed_delay <- function(x, m, lag = 1) {
  n <- length(x) - (m - 1) * lag
  vapply(seq_len(m), function(j) x[(m - j) * lag + seq_len(n)], numeric(n))
}

# Delay and embedding dimension. AMI (first minimum and 1/e decay) is
# reported as the referee asked, but the embedding uses `tau_use` (default 1):
# on the validation panel AMI picks tau = 3-7 for the logistic map, whose
# correct delay is 1, because AMI is designed for sampled flows, not maps or
# daily returns. Dimension by Cao's (1997) method at `tau_use`; NA means no
# saturation up to `max_m`, which is what stochastic data should produce.
choose_embedding <- function(x, lag_max = 20, max_m = 10, tau_use = 1) {
  ami <- function(sel) tryCatch(
    nonlinearTseries::timeLag(x, technique = "ami", selection.method = sel,
                              lag.max = lag_max, do.plot = FALSE),
    error = function(e) NA_real_)
  m <- tryCatch(nonlinearTseries::estimateEmbeddingDim(x, time.lag = tau_use,
                                                       max.embedding.dim = max_m,
                                                       do.plot = FALSE),
                error = function(e) NA_integer_)
  if (is.null(m) || length(m) != 1 || is.na(m) || m < 1) m <- NA_integer_
  c(tau_ami_min = ami("first.minimum"), tau_ami_edecay = ami("first.e.decay"),
    tau = tau_use, m = m)
}

# Grassberger-Procaccia correlation dimension D2 for m = 1..max_m on the
# standardized series, Theiler window `theiler`, scaling region where the
# correlation sum lies in [c_lo, c_hi]. Deterministic low-dimensional data
# saturate; noise gives D2 close to m.
corr_dimension <- function(x, max_m = 8, lag = 1, theiler = 10, n_max = 2000,
                           c_lo = 0.001, c_hi = 0.05) {
  x <- (x - mean(x)) / stats::sd(x)
  x <- x[seq_len(min(length(x), n_max + (max_m - 1) * lag))]
  do.call(rbind, lapply(seq_len(max_m), function(m) {
    E <- embed_delay(x, m, lag)
    d <- as.matrix(stats::dist(E, method = "maximum"))
    idx <- which(upper.tri(d), arr.ind = TRUE)
    keep <- abs(idx[, 1] - idx[, 2]) > theiler
    dv <- sort(d[upper.tri(d)][keep])
    dv <- dv[dv > 1e-10]
    if (length(dv) < 100) return(data.frame(m = m, D2 = 0))
    eps <- exp(seq(log(stats::quantile(dv, c_lo)), log(stats::quantile(dv, c_hi)),
                   length.out = 12))
    C <- findInterval(eps, dv) / length(dv)
    ok <- C > 0 & is.finite(log(eps))
    # A periodic orbit has only a handful of distinct distances, so the
    # correlation sum has no scaling region and D2 is undefined (NA).
    slope <- if (sum(ok) < 3 || length(unique(C[ok])) < 3) NA_real_ else
      unname(stats::coef(stats::lm(log(C[ok]) ~ log(eps[ok])))[2])
    data.frame(m = m, D2 = slope)
  }))
}

# Gottwald-Melbourne 0-1 test for chaos, correlation method with the
# oscillatory-term correction (Gottwald & Melbourne 2009). K ~ 1 for chaotic,
# K ~ 0 for regular dynamics. Note that K ~ 1 also for stochastic noise, so the
# test only separates regular from irregular dynamics.
zero_one_test <- function(x, n_c = 100, seed = 1) {
  set.seed(seed)
  N <- length(x)
  ncut <- floor(N / 10)
  cs <- stats::runif(n_c, pi / 5, 4 * pi / 5)
  j <- seq_len(N)
  ns <- seq_len(ncut)
  Kc <- vapply(cs, function(c) {
    p <- cumsum(x * cos(j * c))
    q <- cumsum(x * sin(j * c))
    M <- vapply(ns, function(n) {
      i <- seq_len(N - n)
      mean((p[i + n] - p[i])^2 + (q[i + n] - q[i])^2)
    }, numeric(1))
    D <- M - mean(x)^2 * (1 - cos(ns * c)) / (1 - cos(c))
    stats::cor(ns, D)
  }, numeric(1))
  c(K = stats::median(Kc), K_iqr = stats::IQR(Kc))
}

# Same test via the chaos01 package, as an independent implementation.
zero_one_chaos01 <- function(x, n_c = 100) {
  chaos01::testChaos01(x, c.rep = n_c, alpha = 0, approach = "cor")
}

# Neural-network (Shintani-Linton) estimate of the largest Lyapunov exponent
# with DChaos. Uses the QR-decomposition spectrum (lyapmethod = "SLE") with
# bootstrap blocking: the Norm-2 method ("LLE") underflows on strongly
# contracting noise and fails on GARCH/IID series in the validation panel.
# Returns the largest exponent's bootstrap median, its standard error, z and
# DChaos's one-sided p-value for H0: lambda >= 0; a small p-value rejects chaos.
# The series is standardized first (lambda is scale-free).
# If the QR recursion overflows (seen for m up to 4 on GARCH-standardized
# EGX30 residuals) the upper bound of m is lowered by one and the fit retried;
# `m_max_used` records the range actually searched.
quiet_dchaos <- function(expr) {
  out <- NULL
  utils::capture.output(out <- expr)
  out
}

dchaos_lle <- function(x, m = 1:4, lag = 1, h = 2:10, B = 200, seed = 56666459) {
  x <- (x - mean(x)) / stats::sd(x)
  for (m_hi in rev(m)) {
    # capture.output() swallows DChaos's text progress bars, which would
    # otherwise print thousands of lines into the Colab cell.
    res <- tryCatch(
      quiet_dchaos(DChaos::lyapunov(x, m = min(m):m_hi, lag = lag, timelapse = "FIXED", h = h,
                       w0maxit = 100, wtsmaxit = 1e6, pre.white = TRUE,
                       lyapmethod = "SLE", blocking = "BOOT", B = B,
                       trace = 0, seed.t = TRUE, seed = seed, doplot = FALSE)),
      error = function(e) NULL)
    if (!is.null(res)) break
  }
  if (is.null(res)) stop("DChaos failed for every embedding range")
  e <- res$exponent.median
  data.frame(lle = e[1, 1], se = e[1, 2], z = e[1, 3], p_H0_chaos = e[1, 4],
             m_selected = nrow(e), m_max_used = m_hi)
}

# Out-of-sample k-nearest-neighbour (analogue) forecast versus the naive
# benchmark of the training mean (for returns this is the random walk).
# Neighbours are searched only among past embedded vectors. Returns the MSE
# ratio (< 1 means the nonlinear predictor wins) and a Diebold-Mariano test
# with Newey-West variance.
nn_forecast <- function(x, m = 3, lag = 1, k = 10, test_frac = 0.3) {
  E <- embed_delay(x, m, lag)
  y <- x[(m - 1) * lag + seq_len(nrow(E)) + 1]
  E <- E[-nrow(E), , drop = FALSE]
  y <- y[!is.na(y)]
  E <- E[seq_along(y), , drop = FALSE]
  n <- nrow(E)
  start <- floor(n * (1 - test_frac))
  f_nn <- f_rw <- numeric(n - start)
  for (i in seq_len(n - start)) {
    t <- start + i
    past <- seq_len(t - 1)
    d <- sqrt(colSums((t(E[past, , drop = FALSE]) - E[t, ])^2))
    nb <- past[order(d)[seq_len(k)]]
    f_nn[i] <- mean(y[nb])
    f_rw[i] <- mean(y[seq_len(start)])
  }
  obs <- y[start + seq_len(n - start)]
  e_nn <- obs - f_nn
  e_rw <- obs - f_rw
  dl <- e_nn^2 - e_rw^2
  L <- floor(length(dl)^(1 / 3))
  g <- stats::acf(dl, lag.max = L, type = "covariance", plot = FALSE)$acf[, 1, 1]
  v <- g[1] + 2 * sum((1 - seq_len(L) / (L + 1)) * g[-1])
  dm <- mean(dl) / sqrt(v / length(dl))
  data.frame(m = m, k = k, n_test = length(dl),
             mse_ratio = mean(e_nn^2) / mean(e_rw^2),
             dm_stat = dm, p_nn_better = stats::pnorm(dm))
}

# All chaos diagnostics for one series.
chaos_battery <- function(x, dchaos = TRUE, dchaos_B = 200, dchaos_m = 1:4) {
  emb <- choose_embedding(x)
  tau <- unname(emb["tau"])
  cd <- corr_dimension(x, lag = tau)
  z1 <- zero_one_test(x)
  nn <- nn_forecast(x, m = if (is.na(emb["m"])) 3 else unname(emb["m"]), lag = tau)
  lle <- if (dchaos) dchaos_lle(x, m = dchaos_m, B = dchaos_B) else NULL
  list(embedding = emb, corr_dim = cd, zero_one = z1, nn = nn, lle = lle)
}

# Structural breaks and regime alternatives (referee M7, M1) --------------------
# Uses the five JSS packages: strucchange, changepoint, ecp, MSGARCH, tvgarch.

# Non-overlapping 5-trading-day returns. Bai-Perron and E-divisive are
# O(n^2); on ~1,250 weekly returns they run in seconds instead of minutes.
weekly_returns <- function(returns) {
  w <- floor((seq_len(nrow(returns)) - 1) / 5)
  wk <- data.frame(date = as.Date(tapply(returns$date, w, max), origin = "1970-01-01"),
                   r = as.numeric(tapply(returns$r, w, sum)))
  wk[tapply(returns$r, w, length) == 5, ]
}

# Bai-Perron breaks in the mean return and in volatility (|r|), strucchange,
# on weekly returns; h is the minimal segment as a fraction of the sample.
bai_perron <- function(returns, h = 0.05) {
  returns <- weekly_returns(returns)
  d <- data.frame(r = returns$r, a = abs(returns$r))
  run <- function(f) {
    bp <- strucchange::breakpoints(f, data = d, h = h)
    k <- bp$breakpoints
    if (all(is.na(k))) k <- integer(0)
    list(n_breaks = length(k), dates = returns$date[k], bic = summary(bp)$RSS["BIC", ])
  }
  list(mean = run(r ~ 1), volatility = run(a ~ 1),
       supF_mean = strucchange::sctest(strucchange::Fstats(r ~ 1, data = d, from = h)))
}

# PELT variance and mean-variance changepoints (changepoint), the modern
# counterpart of ICSS.
pelt_breaks <- function(returns, minseglen = 60) {
  v <- changepoint::cpt.var(returns$r, method = "PELT", penalty = "MBIC",
                            test.stat = "Normal", minseglen = minseglen)
  mv <- changepoint::cpt.meanvar(returns$r, method = "PELT", penalty = "MBIC",
                                 test.stat = "Normal", minseglen = minseglen)
  list(var = returns$date[changepoint::cpts(v)],
       meanvar = returns$date[changepoint::cpts(mv)],
       var_segments = segment_table(returns, changepoint::cpts(v)))
}

segment_table <- function(returns, cps) {
  edges <- c(0, cps, nrow(returns))
  do.call(rbind, lapply(seq_len(length(edges) - 1), function(i) {
    idx <- (edges[i] + 1):edges[i + 1]
    data.frame(start = returns$date[min(idx)], end = returns$date[max(idx)],
               n = length(idx), mean = mean(returns$r[idx]),
               sd_annual = stats::sd(returns$r[idx]) * sqrt(245))
  }))
}

# Nonparametric E-divisive changes in distribution (ecp) on weekly
# (5-trading-day) returns, which keeps the O(n^2) permutation test tractable.
ecp_breaks <- function(returns, R = 199, min.size = 26, sig.lvl = 0.05, seed = 1) {
  set.seed(seed)
  wk <- weekly_returns(returns)
  e <- ecp::e.divisive(matrix(wk$r), sig.lvl = sig.lvl, R = R, min.size = min.size)
  inner <- e$estimates[-c(1, length(e$estimates))]
  list(dates = wk$date[inner - 1], p_values = e$p.values, n_weeks = nrow(wk))
}

# Single- vs two-regime GJR-GARCH with Student-t errors (MSGARCH), on
# percentage returns. A stochastic regime-switching alternative to chaos.
ms_garch <- function(r) {
  y <- 100 * (r - mean(r))
  s1 <- MSGARCH::CreateSpec(variance.spec = list(model = "gjrGARCH"),
                            distribution.spec = list(distribution = "std"))
  s2 <- MSGARCH::CreateSpec(variance.spec = list(model = c("gjrGARCH", "gjrGARCH")),
                            distribution.spec = list(distribution = c("std", "std")))
  f1 <- MSGARCH::FitML(s1, y)
  f2 <- MSGARCH::FitML(s2, y)
  probs <- MSGARCH::State(f2)$SmoothProb[-1, 1, , drop = TRUE]
  uv <- vapply(MSGARCH::ExtractStateFit(f2), MSGARCH::UncVol, numeric(1))
  hi <- which.max(uv)
  list(
    ic = data.frame(model = c("1-regime GJR-t", "2-regime MS-GJR-t"),
                    loglik = c(f1$loglik, f2$loglik),
                    aic = c(stats::AIC(f1), stats::AIC(f2)),
                    bic = c(stats::BIC(f1), stats::BIC(f2))),
    uncond_vol = uv,
    transition = MSGARCH::TransMat(f2),
    p_high = probs[, hi]
  )
}

# TV-GARCH (Amado-Terasvirta multiplicative time-varying variance) via
# tvgarch: tests constancy of the unconditional variance, fits the TV
# component and returns standardized residuals for BDS. The mean is
# AR(p)-filtered first, because tvgarch models the variance only.
tv_garch <- function(r, ar = 2) {
  y <- ar_filter(r, ar)$residuals
  test <- tvgarch::tvgarchTest(y)
  order_g <- as.integer(test$order.g[1])
  fit <- tvgarch::tvgarch(y, order.g = max(1L, order_g), turbo = TRUE)
  z <- as.numeric(stats::residuals(fit))
  list(test_order_g = order_g, fit = fit, std_resid = z[is.finite(z)])
}

# Named subsamples: the paper window (clipped to the data), the post-float
# period, and the volatility regimes found by PELT.
subsamples <- function(returns, var_breaks = NULL) {
  s <- list(
    `paper window (2000-2015)` = c("2000-01-01", "2015-12-31"),
    `pre-float (2000-Oct 2016)` = c("2000-01-01", "2016-11-02"),
    `post-float (Nov 2016-2025)` = c("2016-11-03", "2025-12-31"),
    `full sample` = c("1900-01-01", "2100-01-01")
  )
  lapply(s, function(w) returns[returns$date >= as.Date(w[1]) & returns$date <= as.Date(w[2]), ])
}

# Validation of the toolkit on series with known dynamics ----------------------

safe <- function(expr, default = NA_real_) tryCatch(expr, error = function(e) default)

# Full diagnostic row for one validation series.
validate_series <- function(x, name, dchaos_B = 200) {
  cb <- chaos_battery(x, dchaos_B = dchaos_B, dchaos_m = 1:3)
  g <- safe(fit_garch(x, "sGARCH", ar = 1), NULL)
  z <- if (is.null(g)) NULL else as.numeric(rugarch::residuals(g, standardize = TRUE))
  bds_at <- function(v) if (is.null(v)) NA_real_ else
    tseries::bds.test(v, m = 2, eps = stats::sd(v))$statistic[1]
  # Undefined for a periodic orbit (zero periodogram ordinates), hence NA.
  lm <- safe(long_memory_summary(x), data.frame(H_rs_AL = NA_real_, lw_d = NA_real_))
  d2 <- cb$corr_dim$D2
  data.frame(
    series = name,
    bds_raw_m2 = bds_at(x),
    bds_garch_m2 = bds_at(z),
    archlm_p = safe(FinTS::ArchTest(x, lags = 5)$p.value),
    H_AL = lm$H_rs_AL, lw_d = lm$lw_d,
    tau_ami = unname(cb$embedding["tau_ami_min"]),
    cao_m = unname(cb$embedding["m"]),
    D2_m2 = d2[2], D2_m4 = d2[4], D2_m8 = d2[8],
    K01 = unname(cb$zero_one["K"]),
    nn_mse_ratio = cb$nn$mse_ratio, nn_p = cb$nn$p_nn_better,
    lle = cb$lle$lle, lle_p_H0_chaos = cb$lle$p_H0_chaos
  )
}

# Monte Carlo operating characteristics: how often each diagnostic points to
# chaos / nonlinearity for data with known dynamics. The BDS rows are
# rejection rates at 5%; "chaos" for the LLE means lambda_hat > 0 and H0 not
# rejected at 5%; "chaos" for the 0-1 test means K > 0.8.
monte_carlo <- function(reps = 25, n = 2000, seed = 7, dchaos_B = 100) {
  dgps <- list(
    garch_t = function() sim_garch(n),
    logistic_noisy = function() sim_logistic(n, r = 4, x0 = stats::runif(1, 0.05, 0.95),
                                             noise_sd = 0.05),
    iid_gaussian = function() stats::rnorm(n)
  )
  set.seed(seed)
  rows <- list()
  for (d in names(dgps)) for (i in seq_len(reps)) {
    x <- dgps[[d]]()
    g <- safe(fit_garch(x, "sGARCH", ar = 1), NULL)
    zb <- if (is.null(g)) NA_real_ else {
      z <- as.numeric(rugarch::residuals(g, standardize = TRUE))
      tseries::bds.test(z, m = 2, eps = stats::sd(z))$p.value[1]
    }
    l <- safe(dchaos_lle(x, m = 1:3, B = dchaos_B), NULL)
    rows[[length(rows) + 1]] <- data.frame(
      dgp = d, rep = i,
      bds_raw_reject = tseries::bds.test(x, m = 2, eps = stats::sd(x))$p.value[1] < 0.05,
      bds_garch_reject = zb < 0.05,
      zero_one_chaos = zero_one_test(x, n_c = 50)[["K"]] > 0.8,
      lle_chaos = if (is.null(l)) NA else l$lle > 0 & l$p_H0_chaos > 0.05,
      nn_beats_mean = nn_forecast(x, m = 2)$p_nn_better < 0.05
    )
  }
  draws <- do.call(rbind, rows)
  stats::aggregate(cbind(bds_raw_reject, bds_garch_reject, zero_one_chaos, lle_chaos,
                         nn_beats_mean) ~ dgp, data = draws, FUN = mean, na.action = stats::na.pass)
}

# Size and power of the R/S bootstrap and Lo's test on IID noise and fGn.
rs_size_power <- function(reps = 200, n = 3000, seed = 11) {
  set.seed(seed)
  sim <- function(gen) t(replicate(reps, {
    x <- gen()
    c(H = hurst_fit(rs_table(x))[["H"]], H_AL = hurst_fit(rs_table(x))[["H_AL"]],
      lo_reject = lo_test_table(x, c(Andrews = andrews_q(x)))$reject_95,
      lw_d = local_whittle_d(x)[["d"]])
  }))
  out <- lapply(list(iid = function() stats::rnorm(n), fgn_0.6 = function() sim_fgn(n, 0.6),
                     fgn_0.7 = function() sim_fgn(n, 0.7), garch_t = function() sim_garch(n)),
                function(g) colMeans(sim(g)))
  data.frame(dgp = names(out), do.call(rbind, out), row.names = NULL)
}

# Backfill check: CASE 30 was launched on 2 Feb 2003 and retroactively
# calculated back to 1 Jan 1998 (CBE Annual Report 2002/2003, p. 87), so every
# value before the launch is a reconstruction from the 30 stocks that were most
# liquid in 2003. This compares the backfilled and live segments.

CASE30_LAUNCH <- as.Date("2003-02-02")

# Segments around the launch date. `paper_end` caps the paper window.
backfill_segments <- function(returns, launch = CASE30_LAUNCH, paper_end = "2015-12-31") {
  list(
    `backfilled (2000 - Jan 2003)` = returns[returns$date < launch, ],
    `live, paper window (Feb 2003 - 2015)` = returns[returns$date >= launch & returns$date <= as.Date(paper_end), ],
    `live, full (Feb 2003 - 2025)` = returns[returns$date >= launch, ],
    `paper window (2000 - 2015)` = returns[returns$date <= as.Date(paper_end), ]
  )
}

# The main diagnostics on one segment of returns.
segment_diagnostics <- function(r, dchaos_B = 200) {
  ds <- describe_returns(r)
  a2 <- ar_filter(r, 2)
  g <- fit_garch(r, "gjrGARCH", ar = 2)
  z <- as.numeric(rugarch::residuals(g, standardize = TRUE))
  bz <- bds_grid(z)
  lm <- long_memory_summary(a2$residuals)
  l <- dchaos_lle(z, B = dchaos_B)
  data.frame(
    N = ds$N, mean_ann_pct = 100 * 245 * ds$mean, sd_ann_pct = 100 * sqrt(245) * ds$sd,
    skewness = ds$skewness, kurtosis = ds$kurtosis,
    near_zero_pct = 100 * mean(abs(r) < 1e-4),          # |r| < 0.01%: thin-trading proxy
    acf1 = stats::acf(r, plot = FALSE)$acf[2],
    ljung_box20_p = a2$ljung_box$p_value[3],
    VR2 = variance_ratio(r, 2)$VR, VR2_z2 = variance_ratio(r, 2)$z2,
    bds_raw_maxW = max(bds_grid(r)$W),
    bds_gjr_max_absW = max(abs(bz$W)), bds_gjr_min_p = min(bz$p),
    gjr_persistence = unname(rugarch::persistence(g)),
    H_AL = lm$H_rs_AL, lw_d = lm$lw_d, lw_se = lm$lw_se, lo_V = lm$lo_V_andrews,
    lle = l$lle, lle_p_H0_chaos = l$p_H0_chaos
  )
}

# Segment table plus formal tests of a change at the launch date.
backfill_check <- function(returns, dchaos_B = 200) {
  seg <- backfill_segments(returns)
  tab <- do.call(rbind, lapply(names(seg), function(n)
    cbind(segment = n, segment_diagnostics(seg[[n]]$r, dchaos_B))))
  # Chow test for a change in the AR(1) regression r_t = a + b r_{t-1} at the
  # launch date, within the paper window.
  pw <- seg[["paper window (2000 - 2015)"]]
  d <- data.frame(r = pw$r[-1], r1 = pw$r[-nrow(pw)])
  k <- sum(pw$date[-1] < CASE30_LAUNCH)
  chow <- strucchange::sctest(r ~ r1, data = d, type = "Chow", point = k)
  # Difference in lag-1 autocorrelation (Fisher z) and in variance (F test).
  b <- seg[[1]]$r; l <- seg[[2]]$r
  rho <- c(stats::acf(b, plot = FALSE)$acf[2], stats::acf(l, plot = FALSE)$acf[2])
  zdiff <- (atanh(rho[1]) - atanh(rho[2])) / sqrt(1 / (length(b) - 3) + 1 / (length(l) - 3))
  vt <- stats::var.test(b, l)
  tests <- data.frame(
    test = c("Chow test, AR(1) coefficients at 2 Feb 2003 (paper window)",
             "Lag-1 autocorrelation equal (Fisher z), backfilled vs live 2003-2015",
             "Variance equal (F test), backfilled vs live 2003-2015"),
    statistic = c(unname(chow$statistic), zdiff, unname(vt$statistic)),
    p_value = c(chow$p.value, 2 * stats::pnorm(-abs(zdiff)), vt$p.value)
  )
  list(segments = tab, tests = tests)
}

# %% [4] Load, audit and clean the EGX30 data ---------------------------------
section("4. Data: load, audit, clean")

raw_prices <- read_egx30(DATA_PATH)             # parse dates and prices, report drops
prices <- clean_egx30(raw_prices)               # drop stale weekend carry-forwards
audit <- audit_egx30(raw_prices, prices)        # coverage, calendar, gaps, big moves
ret_full <- make_returns(prices)                # r_t = log(P_t) - log(P_{t-1})
ret_paper <- make_returns(prices, to = PAPER_END)
keep("audit", audit)

show_tab("Coverage", audit$coverage)
show_tab("Rows removed as stale weekend carry-forwards", audit$dropped_rows)
show_tab("Rows per weekday (EGX trades Sunday-Thursday)", audit$weekdays)
show_tab("Calendar gaps of 7+ days (the 2011 closure is the 55-day gap)", audit$gaps)
show_tab("Largest absolute returns", audit$largest_moves)
if (min(prices$date) > as.Date("1998-01-31")) {
  message(sprintf("Note: data start %s; the paper starts in January 1998, so the paper window here is %s to %s (N = %d, paper N = 4,393).",
                  format(min(prices$date)), format(min(ret_paper$date)), PAPER_END, nrow(ret_paper)))
}
save_table(audit$coverage, "audit_coverage"); save_table(audit$gaps, "audit_gaps")
save_table(audit$largest_moves, "audit_largest_moves")

fig("returns", 10, 3.5, function() {
  plot(ret_full$date, ret_full$r, type = "l", lwd = 0.5, col = PAL[1],
       xlab = "", ylab = "log return", main = "EGX30 daily log returns")
  abline(v = as.Date(c("2011-01-27", "2016-11-03")), lty = 2, col = "grey45")
})

# %% [5] Validate the toolkit on series with known dynamics -------------------
# Before touching EGX30, every diagnostic is run where the answer is known:
# chaotic, noisy-chaotic and periodic logistic maps, GARCH noise, IID noise,
# and fractional Gaussian noise. This shows which tools can tell chaos from
# stochastic volatility (DChaos, nearest-neighbour forecasts) and which cannot
# (raw BDS, the 0-1 test).
section("5. Validation of the chaos toolkit")

val_series <- validation_series(n = BUDGET$VAL_N)
val_table <- cached("val_table", do.call(rbind, lapply(names(val_series), function(nm)
  validate_series(val_series[[nm]], nm, dchaos_B = 200))))
val_corr_dim <- cached("val_corr_dim", do.call(rbind, lapply(names(val_series), function(nm)
  cbind(series = nm, corr_dimension(val_series[[nm]])))))
val_mc <- cached("val_mc", monte_carlo(reps = BUDGET$MC_REPS))
val_rs <- cached("val_rs", rs_size_power(reps = BUDGET$RS_REPS))
val_bds_boot <- cached("val_bds_boot", {
  x <- val_series$garch_t
  bds_garch_bootstrap(fit_garch(x, "sGARCH", ar = 1), x, B = min(99, BUDGET$B_BDS_GARCH))
})
keep("validation", list(table = val_table, corr_dim = val_corr_dim, mc = val_mc, rs = val_rs, bds_boot = val_bds_boot))

show_tab("Validation panel (truth: logistic_r4* chaotic with lambda = log 2 = 0.693; others not chaotic)",
     merge(validation_truth()[, c("series", "chaotic", "true_lle")], val_table, by = "series", sort = FALSE))
show_tab("Monte Carlo: share of replications flagging nonlinearity / chaos", val_mc)
show_tab("R/S, Lo and local-Whittle on IID, fGn and GARCH (means over replications)", val_rs)
save_table(val_table, "validation_table"); save_table(val_mc, "validation_monte_carlo")
save_table(val_rs, "validation_rs"); save_table(val_corr_dim, "validation_corr_dim")

fig("validation_corr_dim", 8, 4.5, function() {
  s <- c("logistic_r4", "logistic_r4_noisy", "garch_t", "iid_gaussian")
  plot(NA, xlim = c(1, 8), ylim = c(0, 8), xlab = "embedding dimension m", ylab = "D2",
       main = "Correlation dimension: chaos saturates, noise tracks the diagonal")
  abline(0, 1, col = "grey70")
  for (i in seq_along(s)) {
    d <- val_corr_dim[val_corr_dim$series == s[i], ]
    lines(d$m, d$D2, col = PAL[i], lty = i, lwd = 2); points(d$m, d$D2, col = PAL[i], pch = 15 + i)
  }
  legend("topleft", s, col = PAL, lty = 1:4, pch = 16:19, bty = "n")
})

# %% [6] Replication of the paper, 2000-2015 ----------------------------------
section("6. Replication of the paper (Tables 1-7)")
r15 <- ret_paper$r

# Table 1: descriptive statistics, compared with the paper's printed values.
t1 <- rbind(cbind(source = "paper (1998-2015)", paper_table1()),
            cbind(source = "replication", describe_returns(r15)),
            cbind(source = "full sample", describe_returns(ret_full$r)))
show_tab("Table 1: descriptive statistics", t1, 5); save_table(t1, "table1_descriptives")

# Table 2: ADF (BIC lag selection) and Phillips-Perron unit-root tests.
t2 <- unit_root_tests(r15); show_tab("Table 2: unit-root tests", t2); save_table(t2, "table2_unit_roots")

# Figs 2-3: ACF/PACF to lag 15; AR order by AIC/BIC; AR(2) filter as in the paper.
acf_t <- acf_table(r15); show_tab("ACF / PACF with 1% band", acf_t); save_table(acf_t, "acf_pacf")
ar_ic <- cached("ar_ic", ar_order_selection(r15))
show_tab("AR order selected by information criteria", attr(ar_ic, "best"))
ar2 <- ar_filter(r15, 2)
show_tab("Ljung-Box on AR(2) residuals", ar2$ljung_box)
fig("acf_pacf", 10, 3.5, function() {
  op <- par(mfrow = c(1, 2)); on.exit(par(op))
  acf(r15, lag.max = 15, main = "ACF (Fig. 3)", ci = 0.99)
  pacf(r15, lag.max = 15, main = "PACF (Fig. 2)", ci = 0.99)
})

# Fig. 4: smoothed log-log power spectrum. Long memory would make it rise
# toward zero frequency; a flat low end means short-range dependence.
spec_t <- spectrum_table(r15)
fig("spectrum", 8, 4, function() {
  plot(spec_t$freq, spec_t$spec, log = "xy", type = "l", col = PAL[1],
       xlab = "frequency (cycles/day)", ylab = "spectral density", main = "Power spectrum (Fig. 4)")
})

# Table 3: the paper's variance ratios are reproduced only when the
# Lo-MacKinlay statistic is (wrongly) computed on differenced returns.
t3 <- vr_misapplied(r15); show_tab("Table 3: VR of differenced returns vs paper", t3); save_table(t3, "table3_vr_misapplied")

# Table 4: BDS on original, AR(2)-filtered, shuffled residuals and Gaussian noise.
t4 <- cached("table4_bds", bds_paper_table(r15, ar2$residuals, reps = BUDGET$BDS_GAUSS_REPS))
show_tab("Table 4: BDS W statistics", t4); save_table(t4, "table4_bds")

# Tables 5-6: classical R/S and V statistic on the paper's sub-period grid;
# Hurst exponents by range (classical and Anis-Lloyd-Peters corrected);
# bootstrap against shuffled and Gaussian IID nulls.
PAPER_RANGES <- list(`1<n<125 (A-B)` = c(10, 125), `125<n<350 (B-C)` = c(125, 350),
                     `351<n<700 (C-D as printed)` = c(350, 700), `1<n<1240 (A-D)` = c(10, 1240))
set.seed(3)
rs_list <- list(original = rs_table(r15, PAPER_RS_GRID), filtered = rs_table(ar2$residuals, PAPER_RS_GRID),
                shuffled = rs_table(sample(ar2$residuals), PAPER_RS_GRID),
                gaussian = rs_table(rnorm(length(r15), mean(ar2$residuals), sd(ar2$residuals)), PAPER_RS_GRID))
show_tab("Table 5: R/S on AR(2) residuals (leftover = obs not in whole blocks)",
     rs_list$filtered[, c("n", "blocks", "leftover", "log_rs", "v_stat", "e_rs")])
save_table(do.call(rbind, lapply(names(rs_list), function(n) cbind(series = n, rs_list[[n]]))), "table5_rs")
t6a <- rbind(cbind(series = "original", as.data.frame(hurst_ranges(r15, PAPER_RANGES)), range = names(PAPER_RANGES)),
             cbind(series = "AR(2) filtered", as.data.frame(hurst_ranges(ar2$residuals, PAPER_RANGES)), range = names(PAPER_RANGES)))
show_tab("Table 6A: Hurst exponents by range", t6a); save_table(t6a, "table6a_hurst")
t6b <- cached("table6b_hurst_boot", rbind(
  hurst_bootstrap(ar2$residuals, PAPER_RANGES, B = BUDGET$B_HURST, null = "shuffle")$summary,
  hurst_bootstrap(ar2$residuals, PAPER_RANGES, B = BUDGET$B_HURST, null = "gaussian")$summary))
show_tab(sprintf("Table 6B: Hurst bootstrap (%d draws per null)", BUDGET$B_HURST), t6b); save_table(t6b, "table6b_hurst_bootstrap")
fig("rs_vstat", 10, 4.5, function() {
  op <- par(mfrow = c(1, 2)); on.exit(par(op))
  plot(NA, xlim = range(rs_list[[1]]$log_n), ylim = range(sapply(rs_list, `[[`, "log_rs")),
       xlab = "log10 n", ylab = "log10 R/S", main = "R/S (Fig. 5)")
  lines(rs_list[[1]]$log_n, log10(rs_list[[1]]$e_rs), lty = 3)
  for (i in 1:4) { lines(rs_list[[i]]$log_n, rs_list[[i]]$log_rs, col = PAL[i]); points(rs_list[[i]]$log_n, rs_list[[i]]$log_rs, col = PAL[i], pch = 15 + i) }
  legend("topleft", c(names(rs_list), "E[R/S] IID"), col = c(PAL, "black"), pch = c(16:19, NA), lty = c(1, 1, 1, 1, 3), bty = "n", cex = 0.8)
  plot(NA, xlim = range(rs_list[[1]]$log_n), ylim = range(sapply(rs_list, `[[`, "v_stat")),
       xlab = "log10 n", ylab = "V statistic", main = "V statistic (Fig. 6)")
  lines(rs_list[[1]]$log_n, rs_list[[1]]$v_expected, lty = 3)
  for (i in 1:4) { lines(rs_list[[i]]$log_n, rs_list[[i]]$v_stat, col = PAL[i]); points(rs_list[[i]]$log_n, rs_list[[i]]$v_stat, col = PAL[i], pch = 15 + i) }
})

# Table 7: Lo's modified R/S for several bandwidths q. Lo (1991): two-sided
# 95% acceptance region [0.809, 1.862]; 0.721 is the 0.5% fractile.
t7 <- rbind(cbind(series = "original", lo_test_table(r15)), cbind(series = "AR(2) filtered", lo_test_table(ar2$residuals)))
show_tab("Table 7: Lo's modified R/S", t7); save_table(t7, "table7_lo")
keep("replication", list(t1 = t1, t2 = t2, ar_ic = ar_ic, ar2_lb = ar2$ljung_box, t3 = t3, t4 = t4,
                         rs = rs_list, t6a = t6a, t6b = t6b, t7 = t7))

# %% [7] Referee revisions on the paper window and the full sample -------------
section("7. Referee revisions (2000-2015 and full sample)")

revisions <- function(r, tag) {
  cat("\n### Sample:", tag, sprintf("(N = %d)\n", length(r)))
  # M3: variance ratios on returns, robust z2, Chow-Denning, wild bootstrap.
  vr <- cached(paste0("vr_", tag), vr_battery(r, nboot = BUDGET$VR_BOOT))
  show_tab("M3: Lo-MacKinlay variance ratios (robust z2)", vr$lo_mackinlay)
  show_tab("M3: Chow-Denning joint test", vr$chow_denning)
  show_tab("M3: wild-bootstrap p-values", vr$wild_bootstrap_p)
  # M2: AR(2)-GARCH/GJR/EGARCH with Student-t errors, ARCH-LM before/after,
  # BDS on standardized residuals, and a parametric bootstrap for BDS.
  arf <- ar_filter(r, 2)
  garch <- cached(paste0("garch_", tag), garch_filters(r, ar = 2))
  show_tab("M2: GARCH filters (information criteria, leverage)", garch$ic)
  arch <- rbind(cbind(series = "AR(2) residuals", arch_lm(arf$residuals)),
                cbind(series = "AR(2)-GJR-t std. resid.", arch_lm(garch$std_resid$GJR)),
                cbind(series = "AR(2)-EGARCH-t std. resid.", arch_lm(garch$std_resid$EGARCH)))
  show_tab("M2: ARCH-LM before and after filtering", arch)
  bds_g <- rbind(cbind(filter = "AR(2)-GJR-t", bds_grid(garch$std_resid$GJR)),
                 cbind(filter = "AR(2)-EGARCH-t", bds_grid(garch$std_resid$EGARCH)))
  show_tab("M2: BDS on GARCH-standardized residuals (asymptotic p)", bds_g)
  bds_b <- cached(paste0("bds_boot_", tag), bds_garch_bootstrap(garch$fits$GJR, r, B = BUDGET$B_BDS_GARCH))
  show_tab(sprintf("M2: BDS on GJR residuals with parametric bootstrap (%d refits)", attr(bds_b, "B_used")), bds_b)
  # M4-M6: long memory by R/S (corrected), DFA, GPH, local Whittle, Lo.
  lm_t <- rbind(cbind(series = "AR(2) residuals", long_memory_summary(arf$residuals)),
                cbind(series = "|GJR std. resid.|", long_memory_summary(abs(garch$std_resid$GJR))))
  show_tab("M4-M6: long-memory estimates", lm_t)
  lo <- lo_test_table(arf$residuals); show_tab("M6: Lo's test on AR(2) residuals", lo)
  # M1: chaos diagnostics on AR(2) residuals and on GJR-standardized residuals.
  ch_ar <- cached(paste0("chaos_ar_", tag), chaos_battery(arf$residuals, dchaos_B = BUDGET$B_DCHAOS))
  ch_g <- cached(paste0("chaos_garch_", tag), chaos_battery(garch$std_resid$GJR, dchaos_B = BUDGET$B_DCHAOS))
  row <- function(cb, s) data.frame(series = s, tau_ami = cb$embedding[["tau_ami_min"]], cao_m = cb$embedding[["m"]],
    D2_m2 = cb$corr_dim$D2[2], D2_m4 = cb$corr_dim$D2[4], D2_m8 = cb$corr_dim$D2[8], K01 = cb$zero_one[["K"]],
    nn_mse_ratio = cb$nn$mse_ratio, nn_p = cb$nn$p_nn_better, lle = cb$lle$lle, lle_se = cb$lle$se,
    lle_p_H0_chaos = cb$lle$p_H0_chaos, lle_m_max = cb$lle$m_max_used)
  ch <- rbind(row(ch_ar, "AR(2) residuals"), row(ch_g, "GJR std. residuals"))
  show_tab("M1: chaos diagnostics (lle < 0 with small p rejects chaos; K01 ~ 1 is uninformative)", ch)
  for (nm in c("vr", "arch", "bds_g", "bds_b", "lm_t", "lo", "ch")) save_table(
    if (nm == "vr") get(nm)$lo_mackinlay else get(nm), paste0("revision_", nm, "_", tag))
  list(vr = vr, garch_ic = garch$ic, arch = arch, bds_garch = bds_g, bds_boot = bds_b,
       long_memory = lm_t, lo = lo, chaos = ch, corr_dim_ar = ch_ar$corr_dim, corr_dim_garch = ch_g$corr_dim)
}
rev_paper <- keep("revisions_paper", revisions(ret_paper$r, "paper"))
rev_full <- keep("revisions_full", revisions(ret_full$r, "full"))

fig("egx_corr_dim", 8, 4.5, function() {
  L <- list(`EGX30 AR(2) resid.` = rev_full$corr_dim_ar, `EGX30 GJR resid.` = rev_full$corr_dim_garch,
            `logistic r=4` = val_corr_dim[val_corr_dim$series == "logistic_r4", ],
            `IID Gaussian` = val_corr_dim[val_corr_dim$series == "iid_gaussian", ])
  plot(NA, xlim = c(1, 8), ylim = c(0, 8), xlab = "m", ylab = "D2", main = "EGX30 correlation dimension vs benchmarks")
  abline(0, 1, col = "grey70")
  for (i in seq_along(L)) { lines(L[[i]]$m, L[[i]]$D2, col = PAL[i], lty = i, lwd = 2); points(L[[i]]$m, L[[i]]$D2, col = PAL[i], pch = 15 + i) }
  legend("topleft", names(L), col = PAL, lty = 1:4, pch = 16:19, bty = "n")
})

# %% [8] Structural breaks and regime models (M7-M8) ---------------------------
section("8. Structural breaks and regimes")

bp <- cached("bai_perron", bai_perron(ret_full))              # strucchange, weekly returns
show_tab("Bai-Perron mean breaks", bp$mean$dates); show_tab("Bai-Perron volatility breaks", bp$volatility$dates)
show_tab("sup-F test for a mean break", bp$supF_mean)
pelt <- cached("pelt", pelt_breaks(ret_full))                 # changepoint, daily
show_tab("PELT variance regimes", pelt$var_segments); save_table(pelt$var_segments, "breaks_pelt_segments")
ecpb <- cached("ecp", ecp_breaks(ret_full, R = BUDGET$ECP_R))  # ecp, weekly returns
show_tab("E-divisive change points (weekly)", ecpb$dates)
ms <- cached("msgarch", ms_garch(ret_full$r))                 # MSGARCH
show_tab("MS-GARCH vs single-regime GJR-t", ms$ic); show_tab("Regime daily volatility (%)", ms$uncond_vol)
show_tab("Regime transition matrix", ms$transition); save_table(ms$ic, "breaks_msgarch_ic")
tv <- cached("tvgarch", tv_garch(ret_full$r))                 # tvgarch
tv_bds <- bds_grid(tv$std_resid)
show_tab(sprintf("TV-GARCH: %d transition location(s); BDS on its standardized residuals", tv$test_order_g), tv_bds)
save_table(tv_bds, "breaks_tvgarch_bds")
keep("breaks", list(bai_perron = bp[c("mean", "volatility")], pelt = pelt, ecp = ecpb,
                    msgarch = ms[c("ic", "uncond_vol", "transition", "p_high")], tvgarch_bds = tv_bds))

fig("msgarch_regimes", 10, 3.5, function() {
  plot(ret_full$date, ms$p_high, type = "l", col = PAL[1], ylim = c(0, 1), xlab = "",
       ylab = "P(high-vol regime)", main = "MS-GJR-t high-volatility regime, with PELT breaks")
  abline(v = pelt$var, lty = 2, col = "grey45")
})

# Subsamples: paper window, pre- and post-November 2016 float, full sample.
sub <- cached("subsamples", do.call(rbind, lapply(names(subsamples(ret_full)), function(nm) {
  x <- subsamples(ret_full)[[nm]]$r
  e <- ar_filter(x, 2)$residuals
  z <- as.numeric(rugarch::residuals(fit_garch(x, "gjrGARCH", ar = 2), standardize = TRUE))
  lmm <- long_memory_summary(e); l <- dchaos_lle(z, B = BUDGET$B_DCHAOS_SUB); b <- bds_grid(z)
  data.frame(subsample = nm, N = length(x), bds_raw_m2_1sd = bds_grid(x)$W[5],
             bds_gjr_max_abs_W = max(abs(b$W)), bds_gjr_min_p = min(b$p), H_AL = lmm$H_rs_AL,
             lw_d = lmm$lw_d, lo_V = lmm$lo_V_andrews, K01 = zero_one_test(z)[["K"]],
             lle = l$lle, lle_p_H0_chaos = l$p_H0_chaos)
})))
show_tab("Subsample diagnostics (GJR-t standardized residuals)", sub); save_table(sub, "subsamples")
nogap <- drop_long_gaps(ret_full)$r
bz <- bds_grid(as.numeric(rugarch::residuals(fit_garch(nogap, "gjrGARCH", 2), standardize = TRUE)))
show_tab("Sensitivity: 2011 closure return dropped", data.frame(N = length(nogap), max_abs_W = max(abs(bz$W)), min_p = min(bz$p)))
keep("subsamples", sub)

# Backfill check: CASE 30 launched on 2 Feb 2003 and was calculated backwards
# to 1998 (CBE Annual Report 2002/2003, p. 87). Compare backfilled and live
# segments and test for a change at the launch date.
bf <- cached("backfill", backfill_check(ret_full, dchaos_B = BUDGET$B_DCHAOS_SUB))
show_tab("Backfilled (pre-Feb 2003) vs live segments", bf$segments)
show_tab("Tests for a change at the 2 Feb 2003 launch", bf$tests)
save_table(bf$segments, "backfill_segments"); save_table(bf$tests, "backfill_tests")
keep("backfill", bf)

# %% [9] Summary and export ----------------------------------------------------
section("9. Summary")

lle_all <- c(rev_paper$chaos$lle, rev_full$chaos$lle)
p_all <- c(rev_paper$chaos$lle_p_H0_chaos, rev_full$chaos$lle_p_H0_chaos)
cat(sprintf(paste0(
  "* Table 3: VR of differenced returns = %s (paper: %s) -> the paper's VRs were computed on the wrong series.\n",
  "* Correct VR(2) on returns = %.3f, robust z2 = %.2f (positive autocorrelation).\n",
  "* BDS on raw returns: max W = %.1f; after AR(2)-GJR-t filtering: max |W| = %.2f (2000-2015), %.2f (full).\n",
  "* Hurst (Anis-Lloyd corrected, full range) = %.3f; local-Whittle d = %.3f (se %.3f).\n",
  "* DChaos largest Lyapunov exponent: %s; p-values for H0 (chaos): %s.\n",
  "* MS-GARCH BIC %.1f vs single-regime %.1f (lower is better).\n"),
  paste(sprintf("%.3f", t3$VR), collapse = "/"), paste(sprintf("%.3f", t3$paper_VR), collapse = "/"),
  rev_paper$vr$lo_mackinlay$VR[1], rev_paper$vr$lo_mackinlay$z2[1],
  max(t4$original), max(abs(rev_paper$bds_boot$W)), max(abs(rev_full$bds_boot$W)),
  t6b$H_AL_obs[4], rev_paper$long_memory$lw_d[1], rev_paper$long_memory$lw_se[1],
  paste(sprintf("%.3f", lle_all), collapse = ", "), paste(format.pval(p_all, digits = 2), collapse = ", "),
  ms$ic$bic[2], ms$ic$bic[1]))
cat(if (all(lle_all < 0 & p_all < 0.05))
  "=> Every Lyapunov estimate is negative and rejects chaos; the nonlinearity is volatility clustering and regime shifts.\n"
  else "=> At least one Lyapunov estimate does not reject chaos; inspect the M1 tables above.\n")

RESULTS$settings <- list(DATA_PATH = DATA_PATH, RUN_MODE = RUN_MODE, BUDGET = BUDGET, SEED = SEED,
                         R = R.version.string, packages = vapply(PACKAGES, function(p) as.character(packageVersion(p)), ""))
saveRDS(RESULTS, file.path(OUT_DIR, "results.rds"))
zip_path <- file.path(OUT_DIR, "egx30_results.zip")
old <- setwd(OUT_DIR)
zip_ok <- tryCatch({ utils::zip(basename(zip_path), c("tables", "figures", "results.rds"), flags = "-rq"); TRUE },
                   error = function(e) FALSE, warning = function(w) FALSE)
setwd(old)
cat("\nOutputs written to", normalizePath(OUT_DIR), "\n")
if (zip_ok) cat("Download:", zip_path, "(Files pane > right-click > Download)\n")
