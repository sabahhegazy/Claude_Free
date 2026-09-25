# With/without comparison for the stale 2005-06-18 row.
# Rscript scripts/stale_row_impact.R   -- evidence for docs/data_quality_report.md
suppressMessages(for (f in list.files("R", full.names = TRUE)) source(f))
raw <- read_egx30("data/raw/egx30_2000_2025.csv"); cln <- clean_egx30(raw)
metrics <- function(p, to) {
  rt <- make_returns(p, to = to); r <- rt$r
  ds <- describe_returns(r); a2 <- ar_filter(r, 2); e <- a2$residuals
  g <- fit_garch(r, "gjrGARCH", 2); z <- as.numeric(rugarch::residuals(g, standardize = TRUE))
  bz <- bds_grid(z); br <- bds_grid(r)
  h <- hurst_fit(rs_table(e, PAPER_RS_GRID))
  c(N = ds$N, zero_returns = sum(r == 0), mean_x1e4 = ds$mean * 1e4, sd_x100 = ds$sd * 100,
    skewness = ds$skewness, kurtosis = ds$kurtosis, jarque_bera = ds$jarque_bera,
    acf1 = acf(r, plot = FALSE)$acf[2], ar1 = unname(coef(a2$fit)[1]), ar2 = unname(coef(a2$fit)[2]),
    ljung_box20_p = a2$ljung_box$p_value[3], VR2 = variance_ratio(r, 2)$VR, VR2_z2 = variance_ratio(r, 2)$z2,
    bds_raw_maxW = max(br$W), bds_gjr_max_absW = max(abs(bz$W)), bds_gjr_min_p = min(bz$p),
    gjr_persistence = unname(rugarch::persistence(g)), H_classical = h[["H"]], H_AL = h[["H_AL"]],
    lo_V_andrews = lo_modified_rs(e, andrews_q(e)), lw_d = local_whittle_d(e)[["d"]],
    K01 = zero_one_test(z)[["K"]])
}
out <- list()
for (w in c("2015-12-31", "2025-12-31")) {
  a <- metrics(raw, w); b <- metrics(cln, w)
  out[[w]] <- data.frame(window = ifelse(w == "2015-12-31", "2000-2015", "2000-2025"), metric = names(a),
                         with_row = a, cleaned = b, abs_diff = b - a, rel_diff_pct = 100 * (b - a) / abs(a))
}
res <- do.call(rbind, out); rownames(res) <- NULL
options(width = 200); print(res, digits = 5)
# Local effect: the returns around the row
k <- function(p) { r <- make_returns(p); r[r$date >= as.Date("2005-06-15") & r$date <= as.Date("2005-06-21"), ] }
cat("\nWith row:\n"); print(k(raw)); cat("\nCleaned:\n"); print(k(cln))
