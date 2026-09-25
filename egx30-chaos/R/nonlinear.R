# BDS tests, conditional-heteroskedasticity filters, ARCH-LM -------------------

#' BDS W statistics for m = 2..m_max and eps = eps_sd * sd(x) (paper Table 4).
bds_grid <- function(x, m_max = 5, eps_sd = c(0.5, 1, 1.5, 2)) {
  b <- tseries::bds.test(x, m = m_max, eps = eps_sd * stats::sd(x))
  out <- expand.grid(m = 2:m_max, eps_sd = eps_sd)
  out$W <- as.vector(b$statistic)
  out$p <- as.vector(b$p.value)
  out
}

#' Paper Table 4 layout: BDS on original, AR-filtered, shuffled filtered and
#' Gaussian data, where the Gaussian column averages `reps` replications
#' (referee minor 7) instead of one draw.
bds_paper_table <- function(r, ar_resid, reps = 100, seed = 1) {
  set.seed(seed)
  orig <- bds_grid(r)
  filt <- bds_grid(ar_resid)
  shuf <- bds_grid(sample(ar_resid))
  gauss <- Reduce(`+`, lapply(seq_len(reps), function(i)
    bds_grid(stats::rnorm(length(r)))$W)) / reps
  data.frame(eps_sd = orig$eps_sd, m = orig$m, original = orig$W,
             ar_filtered = filt$W, shuffled = shuf$W, gaussian_mean = gauss)
}

#' Univariate GARCH specification (rugarch).
garch_spec <- function(model = c("sGARCH", "gjrGARCH", "eGARCH"), ar = 2,
                       dist = "std") {
  model <- match.arg(model)
  rugarch::ugarchspec(
    variance.model = list(model = model, garchOrder = c(1, 1)),
    mean.model = list(armaOrder = c(ar, 0), include.mean = TRUE),
    distribution.model = dist
  )
}

fit_garch <- function(r, model = "gjrGARCH", ar = 2, dist = "std") {
  rugarch::ugarchfit(garch_spec(model, ar, dist), r, solver = "hybrid")
}

#' Fit AR-GARCH, AR-GJR and AR-EGARCH and collect standardized residuals.
garch_filters <- function(r, ar = 2) {
  fits <- lapply(c(GARCH = "sGARCH", GJR = "gjrGARCH", EGARCH = "eGARCH"),
                 function(m) fit_garch(r, m, ar))
  ic <- do.call(rbind, lapply(names(fits), function(n) {
    f <- fits[[n]]
    cf <- rugarch::coef(f)
    data.frame(model = n, loglik = rugarch::likelihood(f),
               aic = rugarch::infocriteria(f)[1], bic = rugarch::infocriteria(f)[2],
               persistence = rugarch::persistence(f),
               leverage = if ("gamma1" %in% names(cf)) cf[["gamma1"]] else NA,
               leverage_t = if ("gamma1" %in% names(cf))
                 f@fit$robust.matcoef["gamma1", 3] else NA)
  }))
  list(fits = fits, ic = ic,
       std_resid = lapply(fits, function(f) as.numeric(rugarch::residuals(f, standardize = TRUE))))
}

#' Engle ARCH-LM test at several lags.
arch_lm <- function(x, lags = c(5, 10)) {
  do.call(rbind, lapply(lags, function(l) {
    t <- FinTS::ArchTest(x, lags = l)
    data.frame(lags = l, LM = unname(t$statistic), p = t$p.value)
  }))
}

#' Parametric bootstrap of BDS on GARCH standardized residuals (Hsieh 1991;
#' BDS on estimated residuals is not nuisance-parameter free). Simulates from
#' the fitted model, refits, and recomputes BDS each time.
bds_garch_bootstrap <- function(fit, r, B = 199, m_max = 5,
                                eps_sd = c(0.5, 1, 1.5, 2), seed = 1) {
  spec <- rugarch::getspec(fit)
  model <- spec@model$modeldesc$vmodel
  ar <- spec@model$modelinc[["ar"]]
  obs <- bds_grid(as.numeric(rugarch::residuals(fit, standardize = TRUE)), m_max, eps_sd)
  sim <- rugarch::ugarchsim(fit, n.sim = length(r), m.sim = B, startMethod = "unconditional",
                            rseed = seed + seq_len(B))
  X <- rugarch::fitted(sim)
  draws <- vapply(seq_len(B), function(b) {
    f <- tryCatch(fit_garch(X[, b], model, ar), error = function(e) NULL)
    if (is.null(f) || f@fit$convergence != 0) return(rep(NA_real_, nrow(obs)))
    bds_grid(as.numeric(rugarch::residuals(f, standardize = TRUE)), m_max, eps_sd)$W
  }, numeric(nrow(obs)))
  ok <- colSums(is.na(draws)) == 0
  draws <- draws[, ok, drop = FALSE]
  obs$p_asymptotic <- obs$p
  obs$p_bootstrap <- vapply(seq_len(nrow(obs)), function(i)
    (1 + sum(abs(draws[i, ]) >= abs(obs$W[i]))) / (ncol(draws) + 1), numeric(1))
  obs$cv95_lo <- apply(draws, 1, stats::quantile, 0.025)
  obs$cv95_hi <- apply(draws, 1, stats::quantile, 0.975)
  obs$p <- NULL
  attr(obs, "B_used") <- ncol(draws)
  obs
}
