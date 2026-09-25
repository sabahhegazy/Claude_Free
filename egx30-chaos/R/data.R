# EGX30 input handling ---------------------------------------------------------

#' Read a daily EGX30 price file.
#'
#' Accepts any CSV with a date column and a closing-price column (e.g. exports
#' from egx.com.eg, Investing.com, Refinitiv or Bloomberg). Column names are
#' matched case-insensitively; thousands separators are stripped.
read_egx30 <- function(path) {
  raw <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
  nms <- tolower(trimws(names(raw)))
  date_col <- which(nms %in% c("date", "trade date", "day"))[1]
  close_col <- which(nms %in% c("close", "closing", "price", "last", "adj close",
                                "close price", "egx30", "value"))[1]
  if (is.na(date_col) || is.na(close_col)) {
    stop("Could not find date/close columns in ", path, "; found: ",
         paste(names(raw), collapse = ", "))
  }
  date <- parse_dates(raw[[date_col]])
  close <- as.numeric(gsub(",", "", raw[[close_col]]))
  out <- data.frame(date = date, close = close)
  out <- out[!is.na(out$date) & is.finite(out$close) & out$close > 0, ]
  out <- out[!duplicated(out$date), ]
  out[order(out$date), ]
}

parse_dates <- function(x) {
  if (inherits(x, "Date")) return(x)
  fmts <- c("%d-%b-%y", "%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%d-%m-%Y", "%b %d, %Y", "%d.%m.%Y")
  best <- NULL
  for (f in fmts) {
    d <- as.Date(x, format = f)
    if (is.null(best) || sum(!is.na(d)) > sum(!is.na(best))) best <- d
  }
  best
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

#' Drop rows the EGX could not have traded on. The EGX week is Sunday-Thursday
#' throughout 2000-2025, so a Friday/Saturday row that repeats the previous
#' close is a stale carry-forward (e.g. 2005-06-18 in the supplied file).
clean_egx30 <- function(prices) {
  wd <- as.POSIXlt(prices$date)$wday # 0 = Sunday, 5 = Friday, 6 = Saturday
  stale <- wd %in% c(5, 6) & c(FALSE, diff(prices$close) == 0)
  out <- prices[!stale, ]
  attr(out, "dropped") <- prices[stale, ]
  out
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
