# Running the EGX30 replication in Google Colab

| File | Use it for |
|---|---|
| `egx30_replication_colab.R` | The self-contained script: installs packages, defines every function, runs the whole analysis |
| `egx30_replication_colab.ipynb` | The same code split into 9 notebook cells, set to open in Colab's R runtime |
| `make_notebook.py` | Regenerates the notebook from the script after you edit the script |

The script needs nothing from the rest of the repository. It does not use
`targets`, `renv` or Quarto, and it contains its own copy of the functions in `../R/`.

## Prerequisites

- A Google account and a browser. Nothing is installed on your PC.
- The data file `egx30_2000_2025.csv` (in `../data/raw/`). The script accepts
  any CSV with a date column and a close column; see the header of the script
  for the accepted date formats.
- Time: about 45–60 minutes with `RUN_MODE = "full"`, or 15–20 minutes with
  `"quick"`, on free Colab. The first run adds 2–4 minutes of package
  installation.

## Option A: R runtime (recommended)

1. Go to <https://colab.research.google.com>. Choose one of:
   - **Upload the notebook:** *File > Upload notebook >* `egx30_replication_colab.ipynb`.
   - **Start blank:** create a new notebook, then *Runtime > Change runtime
     type > R*. Upload the script too (step 2), and run
     `source("/content/egx30_replication_colab.R")` in a cell.
2. Upload the data. Click the **folder icon** in the left sidebar, then the
   **upload icon**, and pick `egx30_2000_2025.csv`. Colab stores it as
   `/content/egx30_2000_2025.csv`, which is the default `DATA_PATH`.
3. Check that the runtime says **R**: *Runtime > Change runtime type*.
4. Click *Runtime > Run all*.

Files uploaded this way are deleted when the Colab session ends. Upload the
data again in a new session.

## Option B: Python runtime with rpy2 (lets you read from Google Drive)

The R runtime cannot mount Google Drive, so use this route if the data lives
in Drive. Put the script in Drive or upload it to `/content/`, then run these
three cells:

```python
from google.colab import drive
drive.mount('/content/drive')
```

```python
%load_ext rpy2.ipython
```

```r
%%R
DATA_PATH <- "/content/drive/MyDrive/egx30_2000_2025.csv"
OUT_DIR   <- "/content/drive/MyDrive/egx30_results"   # results survive the session
source("/content/drive/MyDrive/egx30_replication_colab.R")
```

In this mode figures are saved as PNG files in `OUT_DIR/figures` rather than
shown inline.

## What you may change

Only `DATA_PATH` is ever required. The other settings are optional, and you
can set any of them before the script runs (or before `source()`):

| Setting | Default | Meaning |
|---|---|---|
| `DATA_PATH` | `/content/egx30_2000_2025.csv` | Location of the price file |
| `RUN_MODE` | `"full"` | `"full"` uses report-grade bootstrap sizes; `"quick"` gives the same outputs with fewer draws |
| `OUT_DIR` | `/content/egx30_results` | Where tables, figures and the cache go |

## Outputs

`OUT_DIR` contains the following:

- `tables/`: 36 CSV files, including paper Tables 1–7, the referee revisions, the backfill check,
  validation, breaks and subsamples.
- `figures/`: 7 PNG figures.
- `results.rds`: every result object, plus the run settings and package
  versions.
- `egx30_results.zip`: all of the above in one file. Right-click it in the
  Files pane and choose *Download*.

The run ends by printing a short summary of the main findings.

## Resuming after a disconnect

Free Colab can disconnect long runs. Each analysis step is saved to
`OUT_DIR/cache`, so choose *Run all* again and finished steps load in seconds.
The cache resets automatically when the data file or `RUN_MODE` changes. If
you edit the code, delete `OUT_DIR/cache` first.

## Environment notes

- **Package installation.** The script installs from Posit Package Manager's
  precompiled binaries for Colab's Ubuntu release. It falls back to CRAN
  source builds if that fails, which is slower (about 20 minutes).
- **Locale.** Month names are parsed without relying on the machine's locale,
  so the script also works on computers set to Arabic or French.
- **Data errors.** The reader stops with a clear message if more than 1% of
  rows fail to parse, and it reports every row it removes. It drops stale
  weekend carry-forwards, such as 2005-06-18 in the supplied file, and warns
  about any other weekend rows.
- **Tested versions.** The script was tested end to end with R 4.3.3, in
  `quick` and `full` modes, both through `Rscript` and through rpy2. The
  notebook's plotting branch and resuming from the cache were also tested.
  Colab itself was not available in the build environment. The package
  installation step is the one part not exercised there.
