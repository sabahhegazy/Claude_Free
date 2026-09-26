test_that("EGX30 dd-Mon-yy dates and thousands separators parse", {
  f <- tempfile(fileext = ".csv")
  writeLines(c('Date,Close', '02-Jan-00,"1,185.99"', '03-Jan-00,"1,211.81"',
               '15-Jun-05,4513.73', '16-Jun-05,4617.95', '18-Jun-05,4617.95'), f)
  p <- read_egx30(f)
  expect_equal(p$date[1], as.Date("2000-01-02"))
  expect_equal(p$close[1], 1185.99)
  cl <- clean_egx30(p)
  expect_equal(nrow(cl), 4)
  expect_equal(attr(cl, "dropped")$date, as.Date("2005-06-18"))
})

test_that("supplied EGX30 file audits cleanly", {
  skip_if_not(file.exists(egx_path))
  p <- clean_egx30(read_egx30(egx_path))
  expect_false(any(as.POSIXlt(p$date)$wday %in% c(5, 6)))
  expect_false(is.unsorted(p$date))
  r <- make_returns(p, to = "2015-12-31")
  expect_equal(nrow(r), 3894)
})

with_time_locale <- function(loc, code) {
  old <- Sys.getlocale("LC_TIME")
  on.exit(Sys.setlocale("LC_TIME", old))
  if (identical(suppressWarnings(Sys.setlocale("LC_TIME", loc)), "")) skip(paste("locale not installed:", loc))
  force(code)
}

test_that("month names parse identically under non-English locales", {
  skip_if_not(file.exists(egx_path))
  for (loc in c("fr_FR.UTF-8", "ar_EG.UTF-8")) with_time_locale(loc, {
    p <- suppressMessages(read_egx30(egx_path))
    expect_equal(nrow(p), 6283)
    expect_equal(range(p$date), as.Date(c("2000-01-02", "2025-10-30")))
  })
})

test_that("all supported date formats parse to the same dates", {
  want <- as.Date(c("2000-01-02", "2005-06-18"))
  for (x in list(c("02-Jan-00", "18-Jun-05"), c("2000-01-02", "2005-06-18"),
                 c("02/01/2000", "18/06/2005"), c("Jan 02, 2000", "Jun 18, 2005"),
                 c("02.01.2000", "18.06.2005"), c("02-01-2000", "18-06-2005"),
                 c("02-January-2000", "18-June-2005"))) {
    expect_equal(parse_dates(x), want, label = x[1])
  }
})

test_that("the reader stops on unparseable rows instead of dropping them silently", {
  f <- tempfile(fileext = ".csv")
  writeLines(c("Date,Close", '02-Jan-00,"1,185.99"', "bad-date,1200", "04-Jan-00,abc", "05-Jan-00,1195.91"), f)
  expect_error(read_egx30(f), "unparseable")
  expect_error(read_egx30(tempfile()), "not found")
})

test_that("a weekend row with a new price is kept and reported", {
  p <- data.frame(date = as.Date(c("2005-06-16", "2005-06-17", "2005-06-18", "2005-06-19")),
                  close = c(4617.95, 4700, 4700, 4782.16))
  expect_warning(cl <- suppressMessages(clean_egx30(p)), "Weekend rows with a new price")
  expect_equal(cl$date, as.Date(c("2005-06-16", "2005-06-17", "2005-06-19")))
  expect_equal(attr(cl, "dropped")$date, as.Date("2005-06-18"))
})
