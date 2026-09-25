test_that("expected R/S follows the Anis-Lloyd asymptote", {
  n <- c(50, 500, 5000)
  expect_true(all(diff(expected_rs(n)) > 0))
  expect_equal(expected_rs(5000) / sqrt(pi * 5000 / 2), 1, tolerance = 0.02)
})

test_that("fGn has the right lag-1 autocorrelation and is recovered", {
  set.seed(1)
  x <- sim_fgn(2^13, 0.7)
  expect_equal(stats::acf(x, plot = FALSE)$acf[2], 2^(2 * 0.7 - 1) - 1, tolerance = 0.03)
  expect_equal(dfa_alpha(x)$alpha, 0.7, tolerance = 0.06)
  expect_equal(local_whittle_d(x)[["d"]], 0.2, tolerance = 0.08)
})

test_that("corrected Hurst exponent is ~0.5 on IID noise", {
  set.seed(2)
  h <- replicate(30, hurst_fit(rs_table(stats::rnorm(4000)))[["H_AL"]])
  expect_equal(mean(h), 0.5, tolerance = 0.03)
})

test_that("Lo's statistic stays in the 95% region for IID noise most of the time", {
  set.seed(3)
  rej <- replicate(200, { x <- stats::rnorm(2000); v <- lo_modified_rs(x, andrews_q(x)); v < 0.809 || v > 1.862 })
  expect_lt(mean(rej), 0.10)
})
