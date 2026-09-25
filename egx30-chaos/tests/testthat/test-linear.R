test_that("variance ratios match vrtest", {
  set.seed(4)
  x <- stats::arima.sim(list(ar = 0.2), 3000)
  ours <- variance_ratio(x, c(2, 4))
  ref <- vrtest::Lo.Mac(x, c(2, 4))$Stats
  expect_equal(ours$z2, unname(ref[, "M2"]), tolerance = 0.03)
})

test_that("VR on differenced returns reproduces the paper's Table 3", {
  skip_if_not(file.exists(egx_path))
  r <- make_returns(clean_egx30(read_egx30(egx_path)), to = "2015-12-31")$r
  v <- vr_misapplied(r)
  expect_equal(v$VR, v$paper_VR, tolerance = 0.02)
})
