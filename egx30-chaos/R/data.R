# EGX30 input handling ---------------------------------------------------------

MONTHS <- c(jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
            jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12)

#' Replace English month abbreviations with numbers before parsing, so "%b" is
#' never used. R matches "%b" against the machine's locale, and under French or
#' Arabic locales it parses nothing (see docs/data_quality_report.md, 6.1).
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
    stop("Data file not found: ", path, "\nCheck the egx_file target in _targets.R.",
         call. = FALSE)
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

#' Log returns r_t = log(P_t) - log(P_{t-1}), with trading-calendar gaps flagged.
make_returns <- function(prices, from = NULL, to = NULL) {
  if (!is.null(from)) prices <- prices[prices$date >= as.Date(from), ]
  if (!is.null(to)) prices <- prices[prices$date <= as.Date(to), ]
  r <- diff(log(prices$close))
  gap <- as.numeric(diff(prices$date))
  data.frame(date = prices$date[-1], r = r, gap_days = gap)
}

#' Calendar gaps longer than `min_days` (e.g. the Jan-Mar 2011 closure).
calendar_gaps <- function(returns, min_days = 7) {
  g <- returns[returns$gap_days >= min_days, c("date", "gap_days", "r")]
  rownames(g) <- NULL
  g
}

#' Returns with the closure-spanning return removed (sensitivity for the
#' 27 Jan - 23 Mar 2011 closure, whose single return spans 55 calendar days).
drop_long_gaps <- function(returns, max_gap = 30) returns[returns$gap_days <= max_gap, ]

#' Descriptive statistics laid out as in the paper's Table 1.
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

#' Values reported in Morad, Rady & Amin (2019), Table 1 (1998-2015).
paper_table1 <- function() {
  data.frame(N = 4393, median = 0.000645, mean = 0.000443, sd = 0.017319,
             skewness = -0.350851, kurtosis = 11.75502, iqr = 0.01764,
             jarque_bera = 14120.34, jb_p = 0, min = NA, max = NA)
}

#' Data audit: coverage, calendar, gaps, stale prices, extreme moves.
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
