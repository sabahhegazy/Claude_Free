# Raw data

`egx30_2000_2025.csv` holds the EGX30 daily closing index, 2 Jan 2000 – 30 Oct 2025
(6,283 rows, columns `Date` in `dd-Mon-yy` and `Close` with thousands separators).
It was supplied by the project owner. `R/data.R::read_egx30()` reads it,
and `clean_egx30()` drops one stale Saturday row (2005-06-18).

The paper's sample starts in January 1998. To reproduce its exact window, add
1998–1999 rows in the same format; nothing else needs to change.
