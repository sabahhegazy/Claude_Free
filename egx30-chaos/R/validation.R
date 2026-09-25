# Validation of the toolkit on series with known dynamics ----------------------

safe <- function(expr, default = NA_real_) tryCatch(expr, error = function(e) default)

#' Full diagnostic row for one validation series.
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

#' Monte Carlo operating characteristics: how often each diagnostic points to
#' chaos / nonlinearity for data with known dynamics. The BDS rows are
#' rejection rates at 5%; "chaos" for the LLE means lambda_hat > 0 and H0 not
#' rejected at 5%; "chaos" for the 0-1 test means K > 0.8.
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

#' Size and power of the R/S bootstrap and Lo's test on IID noise and fGn.
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
