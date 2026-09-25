# Chaos-specific diagnostics (referee M1) ---------------------------------------

#' Delay embedding: rows are (x_t, x_{t-lag}, ..., x_{t-(m-1)lag}).
embed_delay <- function(x, m, lag = 1) {
  n <- length(x) - (m - 1) * lag
  vapply(seq_len(m), function(j) x[(m - j) * lag + seq_len(n)], numeric(n))
}

#' Delay and embedding dimension. AMI (first minimum and 1/e decay) is
#' reported as the referee asked, but the embedding uses `tau_use` (default 1):
#' on the validation panel AMI picks tau = 3-7 for the logistic map, whose
#' correct delay is 1, because AMI is designed for sampled flows, not maps or
#' daily returns. Dimension by Cao's (1997) method at `tau_use`; NA means no
#' saturation up to `max_m`, which is what stochastic data should produce.
choose_embedding <- function(x, lag_max = 20, max_m = 10, tau_use = 1) {
  ami <- function(sel) tryCatch(
    nonlinearTseries::timeLag(x, technique = "ami", selection.method = sel,
                              lag.max = lag_max, do.plot = FALSE),
    error = function(e) NA_real_)
  m <- tryCatch(nonlinearTseries::estimateEmbeddingDim(x, time.lag = tau_use,
                                                       max.embedding.dim = max_m,
                                                       do.plot = FALSE),
                error = function(e) NA_integer_)
  if (is.null(m) || length(m) != 1 || is.na(m) || m < 1) m <- NA_integer_
  c(tau_ami_min = ami("first.minimum"), tau_ami_edecay = ami("first.e.decay"),
    tau = tau_use, m = m)
}

#' Grassberger-Procaccia correlation dimension D2 for m = 1..max_m on the
#' standardized series, Theiler window `theiler`, scaling region where the
#' correlation sum lies in [c_lo, c_hi]. Deterministic low-dimensional data
#' saturate; noise gives D2 close to m.
corr_dimension <- function(x, max_m = 8, lag = 1, theiler = 10, n_max = 2000,
                           c_lo = 0.001, c_hi = 0.05) {
  x <- (x - mean(x)) / stats::sd(x)
  x <- x[seq_len(min(length(x), n_max + (max_m - 1) * lag))]
  do.call(rbind, lapply(seq_len(max_m), function(m) {
    E <- embed_delay(x, m, lag)
    d <- as.matrix(stats::dist(E, method = "maximum"))
    idx <- which(upper.tri(d), arr.ind = TRUE)
    keep <- abs(idx[, 1] - idx[, 2]) > theiler
    dv <- sort(d[upper.tri(d)][keep])
    dv <- dv[dv > 1e-10]
    if (length(dv) < 100) return(data.frame(m = m, D2 = 0))
    eps <- exp(seq(log(stats::quantile(dv, c_lo)), log(stats::quantile(dv, c_hi)),
                   length.out = 12))
    C <- findInterval(eps, dv) / length(dv)
    ok <- C > 0
    slope <- unname(stats::coef(stats::lm(log(C[ok]) ~ log(eps[ok])))[2])
    data.frame(m = m, D2 = slope)
  }))
}

#' Gottwald-Melbourne 0-1 test for chaos, correlation method with the
#' oscillatory-term correction (Gottwald & Melbourne 2009). K ~ 1 for chaotic,
#' K ~ 0 for regular dynamics. Note that K ~ 1 also for stochastic noise, so the
#' test only separates regular from irregular dynamics.
zero_one_test <- function(x, n_c = 100, seed = 1) {
  set.seed(seed)
  N <- length(x)
  ncut <- floor(N / 10)
  cs <- stats::runif(n_c, pi / 5, 4 * pi / 5)
  j <- seq_len(N)
  ns <- seq_len(ncut)
  Kc <- vapply(cs, function(c) {
    p <- cumsum(x * cos(j * c))
    q <- cumsum(x * sin(j * c))
    M <- vapply(ns, function(n) {
      i <- seq_len(N - n)
      mean((p[i + n] - p[i])^2 + (q[i + n] - q[i])^2)
    }, numeric(1))
    D <- M - mean(x)^2 * (1 - cos(ns * c)) / (1 - cos(c))
    stats::cor(ns, D)
  }, numeric(1))
  c(K = stats::median(Kc), K_iqr = stats::IQR(Kc))
}

#' Same test via the chaos01 package, as an independent implementation.
zero_one_chaos01 <- function(x, n_c = 100) {
  chaos01::testChaos01(x, c.rep = n_c, alpha = 0, approach = "cor")
}

#' Neural-network (Shintani-Linton) estimate of the largest Lyapunov exponent
#' with DChaos. Uses the QR-decomposition spectrum (lyapmethod = "SLE") with
#' bootstrap blocking: the Norm-2 method ("LLE") underflows on strongly
#' contracting noise and fails on GARCH/IID series in the validation panel.
#' Returns the largest exponent's bootstrap median, its standard error, z and
#' DChaos's one-sided p-value for H0: lambda >= 0; a small p-value rejects chaos.
#' The series is standardized first (lambda is scale-free).
dchaos_lle <- function(x, m = 1:4, lag = 1, h = 2:10, B = 200, seed = 56666459) {
  x <- (x - mean(x)) / stats::sd(x)
  res <- DChaos::lyapunov(x, m = m, lag = lag, timelapse = "FIXED", h = h,
                          w0maxit = 100, wtsmaxit = 1e6, pre.white = TRUE,
                          lyapmethod = "SLE", blocking = "BOOT", B = B,
                          trace = 0, seed.t = TRUE, seed = seed, doplot = FALSE)
  e <- res$exponent.median
  data.frame(lle = e[1, 1], se = e[1, 2], z = e[1, 3], p_H0_chaos = e[1, 4],
             m_selected = nrow(e))
}

#' Out-of-sample k-nearest-neighbour (analogue) forecast versus the naive
#' benchmark of the training mean (for returns this is the random walk).
#' Neighbours are searched only among past embedded vectors. Returns the MSE
#' ratio (< 1 means the nonlinear predictor wins) and a Diebold-Mariano test
#' with Newey-West variance.
nn_forecast <- function(x, m = 3, lag = 1, k = 10, test_frac = 0.3) {
  E <- embed_delay(x, m, lag)
  y <- x[(m - 1) * lag + seq_len(nrow(E)) + 1]
  E <- E[-nrow(E), , drop = FALSE]
  y <- y[!is.na(y)]
  E <- E[seq_along(y), , drop = FALSE]
  n <- nrow(E)
  start <- floor(n * (1 - test_frac))
  f_nn <- f_rw <- numeric(n - start)
  for (i in seq_len(n - start)) {
    t <- start + i
    past <- seq_len(t - 1)
    d <- sqrt(colSums((t(E[past, , drop = FALSE]) - E[t, ])^2))
    nb <- past[order(d)[seq_len(k)]]
    f_nn[i] <- mean(y[nb])
    f_rw[i] <- mean(y[seq_len(start)])
  }
  obs <- y[start + seq_len(n - start)]
  e_nn <- obs - f_nn
  e_rw <- obs - f_rw
  dl <- e_nn^2 - e_rw^2
  L <- floor(length(dl)^(1 / 3))
  g <- stats::acf(dl, lag.max = L, type = "covariance", plot = FALSE)$acf[, 1, 1]
  v <- g[1] + 2 * sum((1 - seq_len(L) / (L + 1)) * g[-1])
  dm <- mean(dl) / sqrt(v / length(dl))
  data.frame(m = m, k = k, n_test = length(dl),
             mse_ratio = mean(e_nn^2) / mean(e_rw^2),
             dm_stat = dm, p_nn_better = stats::pnorm(dm))
}

#' All chaos diagnostics for one series.
chaos_battery <- function(x, dchaos = TRUE, dchaos_B = 200, dchaos_m = 1:4) {
  emb <- choose_embedding(x)
  tau <- unname(emb["tau"])
  cd <- corr_dimension(x, lag = tau)
  z1 <- zero_one_test(x)
  nn <- nn_forecast(x, m = if (is.na(emb["m"])) 3 else unname(emb["m"]), lag = tau)
  lle <- if (dchaos) dchaos_lle(x, m = dchaos_m, B = dchaos_B) else NULL
  list(embedding = emb, corr_dim = cd, zero_one = z1, nn = nn, lle = lle)
}
