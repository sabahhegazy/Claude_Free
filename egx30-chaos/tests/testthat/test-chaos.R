test_that("0-1 test separates chaotic and periodic logistic maps", {
  expect_gt(zero_one_test(sim_logistic(2000, r = 4))[["K"]], 0.9)
  expect_lt(abs(zero_one_test(sim_logistic(2000, r = 3.5))[["K"]]), 0.1)
})

test_that("correlation dimension of the logistic map saturates near 1", {
  d <- corr_dimension(sim_logistic(2000, r = 4), max_m = 5)$D2
  expect_true(all(abs(d[2:5] - 1) < 0.25))
  set.seed(5)
  expect_gt(corr_dimension(stats::rnorm(2000), max_m = 5)$D2[5], 3.5)
})

test_that("nearest-neighbour forecasts beat the mean only for deterministic data", {
  expect_lt(nn_forecast(sim_logistic(2000, r = 4), m = 2)$mse_ratio, 0.1)
  set.seed(6)
  expect_gt(nn_forecast(sim_garch(2000), m = 2)$mse_ratio, 0.95)
})

test_that("DChaos recovers ln 2 on the logistic map and rejects chaos for GARCH", {
  skip_on_cran()
  l <- dchaos_lle(sim_logistic(1500, r = 4), m = 1:2, B = 50)
  expect_equal(l$lle, log(2), tolerance = 0.12)
  expect_gt(l$p_H0_chaos, 0.05)
  set.seed(8)
  g <- dchaos_lle(sim_garch(1500), m = 1:2, B = 50)
  expect_lt(g$lle, 0)
  expect_lt(g$p_H0_chaos, 0.05)
})
