# R Shiny Live Dashboard

This dashboard reads the **same Google Sheet** that Virtual BlazePod writes to (see
[`GOOGLE_SHEETS_INTEGRATION.md`](GOOGLE_SHEETS_INTEGRATION.md)) and renders **live visualisations** of
reaction-time and performance data. It auto-refreshes on an interval, so new sessions appear without
restarting the app.

- **Live dashboard:** https://smile-rp.shinyapps.io/Virtual_BlazePod/

A ready-to-run app is provided in [`dashboard/app.R`](dashboard/app.R). It is a Tron-styled, educational
dashboard whose charts are rendered with **`ggplot2`** (static, for maximum portability across R
environments); interactivity is provided through the filters, tabs, live refresh, and sortable table.

---

## What it shows

Organised into five tabs:

- **Overview** — KPI cards (sessions, participants, mean accuracy, fastest hit, mean RT); reaction-time
  progression per session (average + best); speed vs. accuracy scatter; throughput per session.
- **Reaction Time** — distribution of individual reaction times with mean line; consistency (SD)
  trend; within-session fatigue curve by target order.
- **Group Comparison** — reaction time by gender (box + jitter); mean RT by age band; best-time
  leaderboard.
- **Session Records** — the raw rows in a filterable, sortable table.
- **The Science** — an educational explainer of reaction time, mental chronometry, what the tool
  measures, how to read each metric, and the not-a-medical-device caveat.

Filters: participant, gender, age range, and date range. Auto-refresh interval is configurable.

---

## Prerequisites

- **R ≥ 4.1** and (recommended) **RStudio**.
- Install packages:

```r
install.packages(c(
  "shiny", "googlesheets4", "dplyr", "tidyr",
  "ggplot2", "scales", "lubridate", "DT", "jsonlite", "htmltools"
))
```

---

## Connect to your Google Sheet

Because the sheet is used for **read-only** dashboarding, the simplest robust setup is to make the
sheet readable and use `googlesheets4` in de-authenticated mode.

1. In Google Sheets: **Share ▸ General access ▸ "Anyone with the link" ▸ Viewer**.
2. Copy the spreadsheet URL (or just its ID — the long token between `/d/` and `/edit`).
3. In `dashboard/app.R`, set the spreadsheet ID and tab (already configured for this project):

   ```r
   SHEET_ID   <- "1A76A9WlCKIuPKzYzwmjGy_9Dvkn7Hy0YeTLWh-YEmjM"
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

## Deployment

The dashboard is deployed live at:

- **https://smile-rp.shinyapps.io/Virtual_BlazePod/**

Other options:

- **shinyapps.io** — `rsconnect::deployApp("dashboard")`. Because the app runs non-interactively when
  hosted, the sheet must be readable without interactive login: either keep it link-shared as Viewer
  (with `gs4_deauth()`, as configured) or use a service account for a private sheet.
- **Posit Cloud / Posit Connect / Shiny Server** — for institutional hosting.
- **Local** — run on a lab machine and view at `http://localhost:<port>`.

To redeploy after changes, re-run `rsconnect::deployApp("dashboard")` (or use the Publish button in
RStudio / Posit Cloud) against the same shinyapps.io destination.

---

## Notes on the data

- Column names and meanings are defined in the [Data Dictionary](README.md#4-full-data-dictionary) and
  match what the logger writes.
- `reaction_times_ms` is stored as a JSON array string per session; `app.R` unpacks it with
  `jsonlite::fromJSON()` for the distribution plots.
- Interpret reaction times **within participant / within device** (see README §2.4). The dashboard is
  for monitoring and exploration, not clinical diagnosis.
