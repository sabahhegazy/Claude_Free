root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
for (f in list.files(file.path(root, "R"), full.names = TRUE)) source(f)
egx_path <- file.path(root, "data", "raw", "egx30_2000_2025.csv")
