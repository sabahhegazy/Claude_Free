# EGX30 chaos replication pipeline. Run with targets::tar_make().
library(targets)
library(tarchetypes)

tar_option_set(
  packages = c("stats", "utils"),
  seed = 20191209,
  format = "rds"
)
tar_source("R")

# Budget knobs: raise for the final run, lower for quick iterations.
B_HURST <- 2000      # paper uses 5,000 bootstrap samples
B_BDS_GARCH <- 199   # parametric bootstrap refits for BDS on GARCH residuals
B_DCHAOS <- 500      # DChaos bootstrap blocks
MC_REPS <- 25        # Monte Carlo replications per DGP

PAPER_RANGES <- list(`1<n<125 (A-B)` = c(10, 125), `125<n<350 (B-C)` = c(125, 350),
                     `351<n<700 (C-D as printed)` = c(350, 700),
                     `1<n<1240 (A-D)` = c(10, 1240))

validation <- list(
  tar_target(val_series, validation_series(n = 3000)),
  tar_target(val_truth, validation_truth()),
  tar_target(val_names, names(val_series)),
  tar_target(val_table, validate_series(val_series[[val_names]], val_names, dchaos_B = 200),
             pattern = map(val_names)),
  tar_target(val_corr_dim, cbind(series = val_names,
                                 corr_dimension(val_series[[val_names]])),
             pattern = map(val_names)),
  tar_target(val_bds_boot_garch, {
    x <- val_series$garch_t
    bds_garch_bootstrap(fit_garch(x, "sGARCH", ar = 1), x, B = 99)
  }),
  tar_target(val_mc, monte_carlo(reps = MC_REPS)),
  tar_target(val_rs, rs_size_power(reps = 200))
)

data_prep <- list(
  tar_target(egx_file, "data/raw/egx30_2000_2025.csv", format = "file"),
  tar_target(egx_raw, read_egx30(egx_file)),
  tar_target(egx_prices, clean_egx30(egx_raw)),
  tar_target(egx_audit, audit_egx30(egx_raw, egx_prices)),
  tar_target(ret_full, make_returns(egx_prices)),
  # Paper window: Jan 1998 - Dec 2015. The supplied file starts Jan 2000.
  tar_target(ret_paper, make_returns(egx_prices, to = "2015-12-31"))
)

replication <- list(
  tar_target(rep_table1, rbind(cbind(source = "paper (1998-2015)", paper_table1()),
                               cbind(source = "replication (2000-2015)", describe_returns(ret_paper$r)),
                               cbind(source = "full sample (2000-2025)", describe_returns(ret_full$r)))),
  tar_target(rep_unit_root, unit_root_tests(ret_paper$r)),
  tar_target(rep_acf, acf_table(ret_paper$r)),
  tar_target(rep_ar_ic, ar_order_selection(ret_paper$r)),
  tar_target(rep_ar2, ar_filter(ret_paper$r, 2)),
  tar_target(rep_spectrum, spectrum_table(ret_paper$r)),
  tar_target(rep_vr_misapplied, vr_misapplied(ret_paper$r)),
  tar_target(rep_bds, bds_paper_table(ret_paper$r, rep_ar2$residuals, reps = 100)),
  tar_target(rep_rs, {
    set.seed(3)
    e <- rep_ar2$residuals
    list(original = rs_table(ret_paper$r, PAPER_RS_GRID),
         filtered = rs_table(e, PAPER_RS_GRID),
         shuffled = rs_table(sample(e), PAPER_RS_GRID),
         gaussian = rs_table(stats::rnorm(length(e), mean(e), stats::sd(e)), PAPER_RS_GRID))
  }),
  tar_target(rep_hurst, rbind(
    cbind(series = "original", as.data.frame(hurst_ranges(ret_paper$r, PAPER_RANGES))),
    cbind(series = "AR(2) filtered", as.data.frame(hurst_ranges(rep_ar2$residuals, PAPER_RANGES))))),
  tar_target(rep_hurst_boot, rbind(
    hurst_bootstrap(rep_ar2$residuals, PAPER_RANGES, B = B_HURST, null = "shuffle")$summary,
    hurst_bootstrap(rep_ar2$residuals, PAPER_RANGES, B = B_HURST, null = "gaussian")$summary)),
  tar_target(rep_lo, rbind(cbind(series = "original", lo_test_table(ret_paper$r)),
                           cbind(series = "AR(2) filtered", lo_test_table(rep_ar2$residuals))))
)

# Referee revisions, run on the paper window and on the full 2000-2025 sample.
samples <- tar_map(
  values = list(sample = c("paper", "full")),
  names = sample,
  tar_target(sret, if (sample == "paper") ret_paper else ret_full),
  tar_target(vr, vr_battery(sret$r, nboot = 999)),
  tar_target(ar_ic, ar_order_selection(sret$r)),
  tar_target(arf, ar_filter(sret$r, 2)),
  tar_target(garch, garch_filters(sret$r, ar = 2)),
  tar_target(archlm, rbind(cbind(series = "AR(2) residuals", arch_lm(arf$residuals)),
                           cbind(series = "AR(2)-GJR-t std. residuals", arch_lm(garch$std_resid$GJR)),
                           cbind(series = "AR(2)-EGARCH-t std. residuals", arch_lm(garch$std_resid$EGARCH)))),
  tar_target(bds_garch, rbind(cbind(filter = "AR(2)-GJR-t", bds_grid(garch$std_resid$GJR)),
                              cbind(filter = "AR(2)-EGARCH-t", bds_grid(garch$std_resid$EGARCH)))),
  tar_target(bds_boot, bds_garch_bootstrap(garch$fits$GJR, sret$r, B = B_BDS_GARCH)),
  tar_target(long_mem, rbind(cbind(series = "AR(2) residuals", long_memory_summary(arf$residuals)),
                             cbind(series = "|GJR std. residuals|", long_memory_summary(abs(garch$std_resid$GJR))))),
  tar_target(lo, lo_test_table(arf$residuals)),
  tar_target(chaos_ar, chaos_battery(arf$residuals, dchaos_B = B_DCHAOS)),
  tar_target(chaos_garch, chaos_battery(garch$std_resid$GJR, dchaos_B = B_DCHAOS))
)

breaks <- list(
  tar_target(brk_bp, bai_perron(ret_full)),
  tar_target(brk_pelt, pelt_breaks(ret_full)),
  tar_target(brk_ecp, ecp_breaks(ret_full, R = 199)),
  tar_target(brk_ms, ms_garch(ret_full$r)),
  tar_target(brk_tv, tv_garch(ret_full$r)),
  tar_target(brk_tv_bds, bds_grid(brk_tv$std_resid)),
  tar_target(sub_list, subsamples(ret_full)),
  tar_target(sub_names, names(sub_list)),
  tar_target(sub_table, {
    x <- sub_list[[sub_names]]$r
    e <- ar_filter(x, 2)$residuals
    g <- fit_garch(x, "gjrGARCH", ar = 2)
    z <- as.numeric(rugarch::residuals(g, standardize = TRUE))
    lm <- long_memory_summary(e)
    l <- dchaos_lle(z, B = 200)
    b <- bds_grid(z)
    data.frame(subsample = sub_names, N = length(x),
               bds_raw_m2_1sd = bds_grid(x)$W[5], bds_gjr_max_abs_W = max(abs(b$W)),
               bds_gjr_min_p = min(b$p), H_AL = lm$H_rs_AL, lw_d = lm$lw_d,
               lo_V = lm$lo_V_andrews, K01 = zero_one_test(z)[["K"]],
               lle = l$lle, lle_p_H0_chaos = l$p_H0_chaos)
  }, pattern = map(sub_names)),
  # CASE 30 values before 2 Feb 2003 are a retroactive reconstruction
  # (CBE Annual Report 2002/2003, p. 87): compare backfilled and live data.
  tar_target(backfill, backfill_check(ret_full, dchaos_B = 200)),
  tar_target(sub_nogap, {
    x <- drop_long_gaps(ret_full)$r
    b <- bds_grid(as.numeric(rugarch::residuals(fit_garch(x, "gjrGARCH", 2), standardize = TRUE)))
    data.frame(N = length(x), bds_gjr_max_abs_W = max(abs(b$W)), bds_gjr_min_p = min(b$p))
  })
)

list(validation, data_prep, replication, samples, breaks,
     tar_quarto(report, "report.qmd"))
