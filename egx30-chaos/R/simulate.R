# Data-generating processes for validating the chaos toolkit -------------------

#' Logistic map x_{t+1} = r x_t (1 - x_t) with optional additive measurement
#' noise. For r = 4 the largest Lyapunov exponent is log(2) = 0.693.
sim_logistic <- function(n, r = 4, x0 = 0.1234, burn = 500, noise_sd = 0) {
  x <- numeric(n + burn)
  x[1] <- x0
  for (t in seq_len(n + burn - 1)) x[t + 1] <- r * x[t] * (1 - x[t])
  x <- x[-seq_len(burn)]
  x + stats::rnorm(n, sd = noise_sd)
}

#' AR(1)-GJR-GARCH(1,1) with standardised Student-t innovations. With
#' `gamma = 0` and `phi = 0` this is plain GARCH(1,1) noise: stochastic, non-IID,
#' fat-tailed, with volatility clustering, and not chaotic.
sim_garch <- function(n, omega = 1e-5, alpha = 0.08, beta = 0.88, gamma = 0,
                      phi = 0, mu = 0, df = 6, burn = 1000) {
  N <- n + burn
  z <- if (is.finite(df)) stats::rt(N, df) * sqrt((df - 2) / df) else stats::rnorm(N)
  h <- numeric(N)
  e <- numeric(N)
  y <- numeric(N)
  h[1] <- omega / (1 - alpha - beta - gamma / 2)
  e[1] <- sqrt(h[1]) * z[1]
  y[1] <- mu + e[1]
  for (t in 2:N) {
    h[t] <- omega + (alpha + gamma * (e[t - 1] < 0)) * e[t - 1]^2 + beta * h[t - 1]
    e[t] <- sqrt(h[t]) * z[t]
    y[t] <- mu + phi * (y[t - 1] - mu) + e[t]
  }
  y[-seq_len(burn)]
}

#' Fractional Gaussian noise via Davies-Harte circulant embedding.
sim_fgn <- function(n, H) {
  k <- 0:n
  acv <- 0.5 * (abs(k + 1)^(2 * H) - 2 * abs(k)^(2 * H) + abs(k - 1)^(2 * H))
  lam <- Re(stats::fft(c(acv, rev(acv[2:n]))))
  if (any(lam < 0)) lam[lam < 0] <- 0
  m <- 2 * n
  w <- complex(real = stats::rnorm(m), imaginary = stats::rnorm(m))
  x <- stats::fft(sqrt(lam / m) * w)
  Re(x)[seq_len(n)]
}

#' Iterative amplitude-adjusted Fourier-transform surrogate (Schreiber &
#' Schmitz 1996): keeps the marginal distribution and (approximately) the
#' periodogram, destroys any nonlinear structure.
iaaft <- function(x, iter = 100) {
  n <- length(x)
  sorted <- sort(x)
  amp <- Mod(stats::fft(x))
  s <- sample(x)
  for (i in seq_len(iter)) {
    f <- stats::fft(s)
    s <- Re(stats::fft(amp * exp(1i * Arg(f)), inverse = TRUE)) / n
    s_new <- sorted[rank(s, ties.method = "first")]
    if (identical(s_new, s)) break
    s <- s_new
  }
  s
}

#' The validation panel: known chaotic, periodic, and stochastic series.
validation_series <- function(n = 3000, seed = 20191209) {
  set.seed(seed)
  list(
    logistic_r4        = sim_logistic(n, r = 4),
    logistic_r4_noisy  = sim_logistic(n, r = 4, noise_sd = 0.05),
    logistic_r3.5      = sim_logistic(n, r = 3.5),
    garch_t            = sim_garch(n),
    ar_gjr_garch_t     = sim_garch(n, alpha = 0.05, gamma = 0.08, phi = 0.18),
    iid_gaussian       = stats::rnorm(n),
    fgn_h0.7           = sim_fgn(n, H = 0.7)
  )
}

#' Ground truth for the validation panel.
validation_truth <- function() {
  data.frame(
    series = c("logistic_r4", "logistic_r4_noisy", "logistic_r3.5", "garch_t",
               "ar_gjr_garch_t", "iid_gaussian", "fgn_h0.7"),
    chaotic = c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE),
    iid = c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE),
    long_memory = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE),
    true_lle = c(log(2), log(2), NA, NA, NA, NA, NA),
    true_H = c(NA, NA, NA, 0.5, 0.5, 0.5, 0.7)
  )
}
