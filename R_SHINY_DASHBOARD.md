# R Shiny Live Dashboard

This dashboard reads the **same Google Sheet** that Virtual BlazePod writes to (see
[`GOOGLE_SHEETS_INTEGRATION.md`](GOOGLE_SHEETS_INTEGRATION.md)) and renders **live visualisations** of
reaction-time and performance data. It auto-refreshes on an interval, so new sessions appear without
restarting the app.

A ready-to-run app is provided in [`dashboard/app.R`](dashboard/app.R).

---

## What it shows

- **KPI cards** — total sessions, unique participants, mean accuracy, mean best reaction time.
- **Reaction time over time** — average and best RT per session, ordered by access time.
- **Accuracy vs. reaction time** — scatter showing the speed/accuracy trade-off.
- **RT distribution** — histogram/boxplot of per-target reaction times across the cohort.
- **Group comparisons** — mean RT / accuracy by **gender** and by **age band**.
- **Session table** — the raw rows, filterable by participant.

Filters: participant, gender, age range, and date range. Auto-refresh interval is configurable.

---

## Prerequisites

- **R ≥ 4.1** and (recommended) **RStudio**.
- Install packages:

```r
install.packages(c(
  "shiny", "googlesheets4", "dplyr", "tidyr",
  "ggplot2", "lubridate", "DT", "jsonlite", "bslib", "scales"
))
```

---

## Connect to your Google Sheet

Because the sheet is used for **read-only** dashboarding, the simplest robust setup is to make the
sheet readable and use `googlesheets4` in de-authenticated mode.

1. In Google Sheets: **Share ▸ General access ▸ "Anyone with the link" ▸ Viewer**.
2. Copy the spreadsheet URL (or just its ID — the long token between `/d/` and `/edit`).
3. In `dashboard/app.R`, set:

   ```r
   SHEET_ID   <- "PASTE_YOUR_SPREADSHEET_ID_OR_URL_HERE"
   SHEET_NAME <- "Data"   # tab name used by the logger
   ```

> **Private sheet instead?** Use a Google service account: share the sheet with the service-account
> email as Viewer, then authenticate with
> `googlesheets4::gs4_auth(path = "service-account.json")` in place of `gs4_deauth()`. Keep the JSON
> key out of version control.

---

## Run it

From R / RStudio, with the working directory at the project root:

```r
shiny::runApp("dashboard")
```

RStudio users can also open `dashboard/app.R` and click **Run App**. The dashboard polls the sheet on
the configured interval (default 15 s); play a session in the app and watch a new row appear.

---

## How real-time refresh works

The app uses `shiny::reactivePoll()` (via a timer) to re-read the sheet on an interval. Each poll
pulls the full `Data` tab, parses timestamps and the `reaction_times_ms` JSON array, and recomputes
all views. Set the interval near the top of `app.R`:

```r
REFRESH_MS <- 15000   # 15 seconds
```

Lower values feel more "live" but increase reads against the Google Sheets API. 10–30 s is a good
balance for classroom/lab use.

---

## Deployment options

- **shinyapps.io** — free tier; `rsconnect::deployApp("dashboard")`. Use a service account for a
  private sheet, since the hosted app runs non-interactively.
- **Posit Connect / Shiny Server** — for institutional hosting.
- **Local** — run on a lab machine and view at `http://localhost:<port>`.

---

## Notes on the data

- Column names and meanings are defined in the [Data Dictionary](README.md#4-full-data-dictionary) and
  match what the logger writes.
- `reaction_times_ms` is stored as a JSON array string per session; `app.R` unpacks it with
  `jsonlite::fromJSON()` for the distribution plots.
- Interpret reaction times **within participant / within device** (see README §2.4). The dashboard is
  for monitoring and exploration, not clinical diagnosis.
