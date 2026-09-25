# Structural breaks and regime alternatives (referee M7, M1) --------------------
# Uses the five JSS packages: strucchange, changepoint, ecp, MSGARCH, tvgarch.

#' Non-overlapping 5-trading-day returns. Bai-Perron and E-divisive are
#' O(n^2); on ~1,250 weekly returns they run in seconds instead of minutes.
weekly_returns <- function(returns) {
  w <- floor((seq_len(nrow(returns)) - 1) / 5)
  wk <- data.frame(date = as.Date(tapply(returns$date, w, max), origin = "1970-01-01"),
                   r = as.numeric(tapply(returns$r, w, sum)))
  wk[tapply(returns$r, w, length) == 5, ]
}

#' Bai-Perron breaks in the mean return and in volatility (|r|), strucchange,
#' on weekly returns; h is the minimal segment as a fraction of the sample.
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

#' PELT variance and mean-variance changepoints (changepoint), the modern
#' counterpart of ICSS.
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

#' Nonparametric E-divisive changes in distribution (ecp) on weekly
#' (5-trading-day) returns, which keeps the O(n^2) permutation test tractable.
ecp_breaks <- function(returns, R = 199, min.size = 26, sig.lvl = 0.05, seed = 1) {
  set.seed(seed)
  wk <- weekly_returns(returns)
  e <- ecp::e.divisive(matrix(wk$r), sig.lvl = sig.lvl, R = R, min.size = min.size)
  inner <- e$estimates[-c(1, length(e$estimates))]
  list(dates = wk$date[inner - 1], p_values = e$p.values, n_weeks = nrow(wk))
}

#' Single- vs two-regime GJR-GARCH with Student-t errors (MSGARCH), on
#' percentage returns. A stochastic regime-switching alternative to chaos.
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

#' TV-GARCH (Amado-Terasvirta multiplicative time-varying variance) via
#' tvgarch: tests constancy of the unconditional variance, fits the TV
#' component and returns standardized residuals for BDS. The mean is
#' AR(p)-filtered first, because tvgarch models the variance only.
tv_garch <- function(r, ar = 2) {
  y <- ar_filter(r, ar)$residuals
  test <- tvgarch::tvgarchTest(y)
  order_g <- as.integer(test$order.g[1])
  fit <- tvgarch::tvgarch(y, order.g = max(1L, order_g), turbo = TRUE)
  z <- as.numeric(stats::residuals(fit))
  list(test_order_g = order_g, fit = fit, std_resid = z[is.finite(z)])
}

#' Named subsamples: the paper window (clipped to the data), the post-float
#' period, and the volatility regimes found by PELT.
subsamples <- function(returns, var_breaks = NULL) {
  s <- list(
    `paper window (2000-2015)` = c("2000-01-01", "2015-12-31"),
    `pre-float (2000-Oct 2016)` = c("2000-01-01", "2016-11-02"),
    `post-float (Nov 2016-2025)` = c("2016-11-03", "2025-12-31"),
    `full sample` = c("1900-01-01", "2100-01-01")
  )
  lapply(s, function(w) returns[returns$date >= as.Date(w[1]) & returns$date <= as.Date(w[2]), ])
}
