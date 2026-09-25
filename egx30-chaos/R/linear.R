# Linear diagnostics: unit roots, ACF/PACF, AR filter, variance ratios ---------

#' ADF and Phillips-Perron tests (urca), with lag selection reported.
unit_root_tests <- function(r, max_lags = 20) {
  adf <- urca::ur.df(r, type = "drift", lags = max_lags, selectlags = "BIC")
  pp <- urca::ur.pp(r, type = "Z-tau", model = "constant", lags = "short")
  data.frame(
    test = c("ADF (drift, BIC lags)", "Phillips-Perron (Z-tau, constant, short)"),
    statistic = c(adf@teststat[1, "tau2"], pp@teststat),
    lags = c(sum(grepl("z.diff.lag", rownames(adf@testreg$coefficients))), pp@lag),
    cv_1pct = c(adf@cval["tau2", "1pct"], pp@cval[1, "1pct"]),
    cv_5pct = c(adf@cval["tau2", "5pct"], pp@cval[1, "5pct"]),
    cv_10pct = c(adf@cval["tau2", "10pct"], pp@cval[1, "10pct"])
  )
}

#' ACF and PACF to lag 15 with 1% bands, as in the paper's Figs 2-3.
acf_table <- function(r, lag.max = 15) {
  a <- stats::acf(r, lag.max = lag.max, plot = FALSE)$acf[-1]
  p <- stats::pacf(r, lag.max = lag.max, plot = FALSE)$acf
  data.frame(lag = seq_len(lag.max), acf = a, pacf = p,
             band_1pct = stats::qnorm(0.995) / sqrt(length(r)))
}

#' AR order by AIC and BIC (paper uses PACF only; referee minor 5).
ar_order_selection <- function(r, max_p = 10) {
  ic <- t(vapply(0:max_p, function(p) {
    f <- stats::arima(r, order = c(p, 0, 0), method = "ML")
    c(p = p, aic = stats::AIC(f), bic = stats::BIC(f))
  }, numeric(3)))
  ic <- as.data.frame(ic)
  attr(ic, "best") <- c(aic = ic$p[which.min(ic$aic)], bic = ic$p[which.min(ic$bic)])
  ic
}

#' AR(p) filter; residuals are the paper's "filtered data".
ar_filter <- function(r, p = 2) {
  f <- stats::arima(r, order = c(p, 0, 0), method = "ML")
  res <- as.numeric(stats::residuals(f))
  lb <- vapply(c(10, 15, 20), function(l)
    stats::Box.test(res, lag = l, type = "Ljung-Box", fitdf = p)$p.value, numeric(1))
  list(fit = f, residuals = res,
       ljung_box = data.frame(lag = c(10, 15, 20), p_value = lb))
}

#' Lo-MacKinlay variance ratios computed directly (overlapping, bias-corrected)
#' with homoskedastic z1 and heteroskedasticity-robust z2.
variance_ratio <- function(r, qs = c(2, 4, 8, 16)) {
  T <- length(r)
  mu <- mean(r)
  s1 <- sum((r - mu)^2) / (T - 1)
  do.call(rbind, lapply(qs, function(q) {
    rq <- stats::filter(r, rep(1, q), sides = 1)[q:T]
    m <- q * (T - q + 1) * (1 - q / T)
    sq <- sum((rq - q * mu)^2) / m
    vr <- sq / s1
    z1 <- (vr - 1) / sqrt(2 * (2 * q - 1) * (q - 1) / (3 * q * T))
    e2 <- (r - mu)^2
    delta <- vapply(seq_len(q - 1), function(j)
      T * sum(e2[(j + 1):T] * e2[1:(T - j)]) / sum(e2)^2, numeric(1))
    theta <- sum((2 * (q - seq_len(q - 1)) / q)^2 * delta)
    z2 <- sqrt(T) * (vr - 1) / sqrt(theta)
    data.frame(q = q, VR = vr, z1 = z1, z2 = z2,
               p_z2 = 2 * stats::pnorm(-abs(z2)))
  }))
}

#' Variance-ratio battery: robust z2, Chow-Denning joint test, wild bootstrap.
vr_battery <- function(r, qs = c(2, 4, 8, 16), nboot = 999, seed = 1) {
  set.seed(seed)
  cd <- vrtest::Chow.Denning(r, qs)
  bt <- vrtest::Boot.test(r, qs, nboot = nboot, wild = "Normal")
  list(
    lo_mackinlay = variance_ratio(r, qs),
    chow_denning = data.frame(CD1 = cd$CD1, CD2 = cd$CD2,
                              cv_5pct = unname(cd$Critical.Values_10_5_1_percent[2])),
    wild_bootstrap_p = data.frame(
      test = c(paste0("Lo-MacKinlay q=", qs), "Chow-Denning joint"),
      p = c(bt$LM.pval, bt$CD.pval))
  )
}

#' Referee M3: VRs of the *differenced* return series reproduce the
#' implausibly small values in the paper's Table 3.
vr_misapplied <- function(r, qs = c(2, 4, 8, 16)) {
  out <- variance_ratio(diff(r), qs)[, c("q", "VR")]
  out$paper_VR <- c(0.608228, 0.303588, 0.157507, 0.076868)[seq_along(qs)]
  out$VR_times_q <- out$VR * out$q
  out
}

#' Smoothed log spectrum for the paper's Fig. 4 and the referee's M4.
spectrum_table <- function(r, spans = c(7, 7)) {
  s <- stats::spec.pgram(r, spans = spans, plot = FALSE, taper = 0.1, detrend = FALSE)
  data.frame(freq = s$freq, spec = s$spec)
}
