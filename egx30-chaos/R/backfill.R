# Backfill check: CASE 30 was launched on 2 Feb 2003 and retroactively
# calculated back to 1 Jan 1998 (CBE Annual Report 2002/2003, p. 87), so every
# value before the launch is a reconstruction from the 30 stocks that were most
# liquid in 2003. This compares the backfilled and live segments.

CASE30_LAUNCH <- as.Date("2003-02-02")

#' Segments around the launch date. `paper_end` caps the paper window.
backfill_segments <- function(returns, launch = CASE30_LAUNCH, paper_end = "2015-12-31") {
  list(
    `backfilled (2000 - Jan 2003)` = returns[returns$date < launch, ],
    `live, paper window (Feb 2003 - 2015)` = returns[returns$date >= launch & returns$date <= as.Date(paper_end), ],
    `live, full (Feb 2003 - 2025)` = returns[returns$date >= launch, ],
    `paper window (2000 - 2015)` = returns[returns$date <= as.Date(paper_end), ]
  )
}

#' The main diagnostics on one segment of returns.
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

#' Segment table plus formal tests of a change at the launch date.
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
