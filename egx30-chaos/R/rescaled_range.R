# Rescaled-range (R/S), V-statistic, Lo's modified R/S, DFA, GPH, local Whittle

#: Sub-period grid used in Morad, Rady & Amin (2019), Table 5. Every n divides
#: 7,000 but none divides the paper's N = 4,393 (referee comment M5.3).
PAPER_RS_GRID <- c(10, 14, 20, 25, 28, 35, 40, 50, 56, 70, 100, 125, 140, 175,
                   200, 250, 280, 350, 500, 700, 875, 1000, 1240)

#' Log-spaced sub-period grid keeping at least `min_blocks` blocks.
rs_grid <- function(N, n_min = 10, min_blocks = 4, k = 25) {
  unique(round(exp(seq(log(n_min), log(N / min_blocks), length.out = k))))
}

#' Classical R/S (Hurst 1951; Peters 1994). Each n uses p = floor(N/n)
#' contiguous blocks from the start of the sample; the N - p*n leftover
#' observations are reported, never silently dropped.
rs_table <- function(x, ns = rs_grid(length(x))) {
  N <- length(x)
  ns <- ns[ns >= 3 & ns <= N / 2]
  rows <- lapply(ns, function(n) {
    p <- N %/% n
    blocks <- matrix(x[seq_len(p * n)], nrow = n)
    rs <- apply(blocks, 2, function(b) {
      z <- cumsum(b - mean(b))
      s <- sqrt(mean((b - mean(b))^2))
      (max(z) - min(z)) / s
    })
    data.frame(n = n, blocks = p, leftover = N - p * n, rs = mean(rs))
  })
  out <- do.call(rbind, rows)
  out$log_n <- log10(out$n)
  out$log_rs <- log10(out$rs)
  out$v_stat <- out$rs / sqrt(out$n)
  out$e_rs <- expected_rs(out$n)
  out$v_expected <- out$e_rs / sqrt(out$n)
  out
}

#' Anis-Lloyd (1976) expected R/S for IID Gaussian noise with the Peters (1994)
#' small-sample factor (n - 1/2)/n.
expected_rs <- function(n) {
  vapply(n, function(k) {
    i <- seq_len(k - 1)
    g <- if (k <= 340) exp(lgamma((k - 1) / 2) - lgamma(k / 2)) / sqrt(pi)
         else 1 / sqrt(k * pi / 2)
    ((k - 0.5) / k) * g * sum(sqrt((k - i) / i))
  }, numeric(1))
}

#' Hurst exponent from an R/S table over n in [n_lo, n_hi].
#' `H` is the classical OLS slope; `H_AL` is the Anis-Lloyd-Peters corrected
#' estimate 0.5 + slope(log R/S - log E[R/S]).
hurst_fit <- function(tab, n_lo = min(tab$n), n_hi = max(tab$n)) {
  s <- tab[tab$n >= n_lo & tab$n <= n_hi, ]
  if (nrow(s) < 3) return(c(H = NA_real_, H_AL = NA_real_, k = nrow(s)))
  H <- unname(stats::coef(stats::lm(log_rs ~ log_n, data = s))[2])
  H_AL <- 0.5 + unname(stats::coef(stats::lm(I(log_rs - log10(e_rs)) ~ log_n, data = s))[2])
  c(H = H, H_AL = H_AL, k = nrow(s))
}

#' Hurst exponents over a list of n-ranges (named list of c(lo, hi)).
hurst_ranges <- function(x, ranges, ns = PAPER_RS_GRID) {
  tab <- rs_table(x, ns)
  t(vapply(ranges, function(r) hurst_fit(tab, r[1], r[2]), numeric(3)))
}

#' Shuffle / Gaussian bootstrap of H under an IID null (paper Table 6, Part B).
#' Returns the null draws plus one-sided (H > H_obs) and two-sided p-values.
hurst_bootstrap <- function(x, ranges, ns = PAPER_RS_GRID, B = 1000,
                            null = c("shuffle", "gaussian"), seed = 1) {
  null <- match.arg(null)
  set.seed(seed)
  obs <- hurst_ranges(x, ranges, ns)
  draws <- replicate(B, {
    xb <- if (null == "shuffle") sample(x) else stats::rnorm(length(x), mean(x), stats::sd(x))
    hurst_ranges(xb, ranges, ns)[, c("H", "H_AL")]
  }, simplify = "array")
  summ <- lapply(seq_along(ranges), function(i) {
    hb <- draws[i, "H", ]
    hal <- draws[i, "H_AL", ]
    data.frame(
      range = names(ranges)[i], null = null,
      H_obs = obs[i, "H"], H_null_mean = mean(hb),
      p_upper = (1 + sum(hb >= obs[i, "H"])) / (B + 1),
      p_two_sided = min(1, 2 * min((1 + sum(hb >= obs[i, "H"])) / (B + 1),
                                   (1 + sum(hb <= obs[i, "H"])) / (B + 1))),
      H_AL_obs = obs[i, "H_AL"], H_AL_null_mean = mean(hal),
      p_AL_upper = (1 + sum(hal >= obs[i, "H_AL"])) / (B + 1)
    )
  })
  list(summary = do.call(rbind, summ), draws = draws)
}

#' Lo (1991) modified R/S statistic V_q = Q_q / sqrt(N).
lo_modified_rs <- function(x, q) {
  N <- length(x)
  y <- x - mean(x)
  z <- cumsum(y)
  g <- stats::acf(y, lag.max = max(q, 1), type = "covariance", plot = FALSE,
                  demean = FALSE)$acf[, 1, 1]
  s2 <- g[1]
  if (q > 0) {
    j <- seq_len(q)
    s2 <- s2 + 2 * sum((1 - j / (q + 1)) * g[j + 1])
  }
  (max(z) - min(z)) / sqrt(s2) / sqrt(N)
}

#' Andrews (1991) data-dependent bandwidth used by Lo (1991).
andrews_q <- function(x) {
  N <- length(x)
  rho <- stats::acf(x, lag.max = 1, plot = FALSE)$acf[2]
  floor((1.5 * N)^(1 / 3) * (2 * abs(rho) / (1 - rho^2))^(2 / 3))
}

#' Lo's test over several q. Critical values from Lo (1991), Table II:
#' two-sided 95% acceptance region [0.809, 1.862]; 99% region [0.721, 2.098].
lo_test_table <- function(x, qs = NULL) {
  N <- length(x)
  if (is.null(qs)) {
    qs <- c(`Andrews` = andrews_q(x), `N^(1/4)` = round(N^0.25),
            `N^(1/3)` = round(N^(1 / 3)), `N^(1/2)` = round(sqrt(N)),
            `100` = 100, `150` = 150)
  }
  v <- vapply(qs, function(q) lo_modified_rs(x, q), numeric(1))
  data.frame(q_rule = names(qs), q = unname(qs), V = unname(v),
             reject_95 = v < 0.809 | v > 1.862,
             reject_99 = v < 0.721 | v > 2.098)
}

#' Detrended fluctuation analysis (Peng et al. 1994), linear detrending.
dfa_alpha <- function(x, scales = NULL) {
  N <- length(x)
  if (is.null(scales)) scales <- unique(round(exp(seq(log(10), log(N / 4), length.out = 20))))
  y <- cumsum(x - mean(x))
  Fs <- vapply(scales, function(s) {
    p <- N %/% s
    Y <- matrix(y[seq_len(p * s)], nrow = s)
    tt <- seq_len(s)
    X <- cbind(1, tt)
    H <- X %*% solve(crossprod(X), t(X))
    res <- Y - H %*% Y
    sqrt(mean(res^2))
  }, numeric(1))
  fit <- stats::lm(log(Fs) ~ log(scales))
  list(alpha = unname(stats::coef(fit)[2]),
       table = data.frame(scale = scales, F = Fs))
}

#' Geweke-Porter-Hudak log-periodogram estimate of d with m = N^bw.
gph_d <- function(x, bw = 0.5) {
  N <- length(x)
  m <- floor(N^bw)
  I <- periodogram(x)[seq_len(m)]
  lam <- 2 * pi * seq_len(m) / N
  reg <- -log(4 * sin(lam / 2)^2)
  fit <- stats::lm(log(I) ~ reg)
  c(d = unname(stats::coef(fit)[2]),
    se = pi / sqrt(24 * sum((reg - mean(reg))^2)), m = m)
}

#' Robinson (1995) local Whittle estimate of d with m = N^bw; se = 1/(2 sqrt(m)).
local_whittle_d <- function(x, bw = 0.65) {
  N <- length(x)
  m <- floor(N^bw)
  I <- periodogram(x)[seq_len(m)]
  lam <- 2 * pi * seq_len(m) / N
  R <- function(d) log(mean(lam^(2 * d) * I)) - 2 * d * mean(log(lam))
  d <- stats::optimize(R, c(-0.49, 0.99))$minimum
  c(d = d, se = 1 / (2 * sqrt(m)), m = m)
}

periodogram <- function(x) {
  N <- length(x)
  f <- stats::fft(x - mean(x))
  (Mod(f)^2 / (2 * pi * N))[-1]
}

#' Long-memory summary for one series.
long_memory_summary <- function(x) {
  tab <- rs_table(x)
  h <- hurst_fit(tab)
  g <- gph_d(x)
  lw <- local_whittle_d(x)
  data.frame(
    H_rs = h[["H"]], H_rs_AL = h[["H_AL"]],
    dfa_alpha = dfa_alpha(x)$alpha,
    gph_d = g[["d"]], gph_se = g[["se"]],
    lw_d = lw[["d"]], lw_se = lw[["se"]],
    lo_V_andrews = lo_modified_rs(x, andrews_q(x))
  )
}
