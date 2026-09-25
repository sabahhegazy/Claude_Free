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
