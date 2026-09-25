# Independent anomaly scan of the raw EGX30 file (does not use R/data.R).
# Rscript scripts/scan_egx30_raw.R   -- evidence for docs/data_quality_report.md
Sys.setlocale("LC_TIME", "C")
raw <- read.csv("data/raw/egx30_2000_2025.csv", colClasses = "character")
d <- as.Date(raw$Date, "%d-%b-%y"); p <- as.numeric(gsub(",", "", raw$Close))
cat("rows", nrow(raw), "| unparsed dates", sum(is.na(d)), "| unparsed prices", sum(is.na(p)),
    "| date range", format(range(d)), "| strictly increasing", all(diff(d) > 0), "\n")
cat("date format regex fails:", sum(!grepl("^[0-9]{2}-[A-Z][a-z]{2}-[0-9]{2}$", raw$Date)),
    "| price format fails:", sum(!grepl("^([0-9]{1,3}(,[0-9]{3})*|[0-9]+)\\.[0-9]{2}$", raw$Close)), "\n")
wd <- as.POSIXlt(d)$wday
cat("\n[1] Non-trading weekdays (Fri=5, Sat=6):\n"); print(data.frame(line = which(wd %in% 5:6) + 1, date = d[wd %in% 5:6], wday = weekdays(d[wd %in% 5:6]), close = p[wd %in% 5:6]))
rep0 <- which(c(FALSE, diff(p) == 0))
cat("\n[2] Rows repeating the previous close:\n"); print(data.frame(line = rep0 + 1, date = d[rep0], wday = weekdays(d[rep0]), close = p[rep0], prev_date = d[rep0 - 1]))
r <- diff(log(p))
cat("\n[3] Spike-and-reversal (|r_t|>5%, r_{t+1} opposite sign and >=80% of size):\n")
i <- which(abs(r[-length(r)]) > 0.05 & sign(r[-1]) != sign(r[-length(r)]) & abs(r[-1]) >= 0.8 * abs(r[-length(r)]))
print(data.frame(date = d[i + 1], r = round(r[i], 4), r_next = round(r[i + 1], 4)))
cat("\n[4] Decimal-shift / scale errors (price ratio to neighbours >1.5 or <0.67):\n")
ratio <- p[-1] / p[-length(p)]; print(data.frame(date = d[which(ratio > 1.5 | ratio < 0.67) + 1]))
cat("\n[5] Robust outliers |r - median| > 8 MAD:\n")
z <- (r - median(r)) / mad(r); j <- which(abs(z) > 8); print(data.frame(date = d[j + 1], r = round(r[j], 4), z = round(z[j], 1), gap = as.numeric(diff(d))[j]))
cat("\n[6] Gaps between rows: \n"); print(table(cut(as.numeric(diff(d)), c(0, 1, 3, 4, 6, 10, 60), right = TRUE)))
cat("\n[7] Rows per ISO week > 5:\n"); wk <- format(d, "%G-%V"); tw <- table(wk); print(tw[tw > 5])
cat("\n[8] Neighbourhood of the flagged row:\n"); k <- which(d == as.Date("2005-06-18")); print(data.frame(line = (k-4):(k+3) + 1, date = d[(k-4):(k+3)], wday = weekdays(d[(k-4):(k+3)]), close = p[(k-4):(k+3)]))
cat("\n[9] Other weeks in June 2005 (row count per week):\n"); m <- d >= as.Date("2005-05-29") & d <= as.Date("2005-07-09"); print(table(format(d[m], "%G-W%V"), weekdays(d[m]))[, c("Sunday","Monday","Tuesday","Wednesday","Thursday","Saturday")])
cat("\n[10] 2-digit-year pivot check: years present", paste(range(as.integer(format(d, "%Y"))), collapse = "-"), "\n")
