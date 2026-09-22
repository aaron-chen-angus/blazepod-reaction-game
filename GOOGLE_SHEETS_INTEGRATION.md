# Google Sheets Live Data Integration

This guide connects **Virtual BlazePod** to a Google Sheet so that **every completed session is
written automatically** — no button press, no manual export. When a 30-second block ends, the app
fires a background `POST` to a Google Apps Script Web App, which appends one row per session.

The app code is **already wired**. You only need to (1) create the Sheet + Apps Script, (2) deploy it,
and (3) paste the deployment URL into `index.html`.

---

## How it works

```
Browser (index.html)                Google Cloud                 Google Sheet
────────────────────                ────────────                 ────────────
session ends  ──► DataLogger.send() ──► Apps Script doPost(e) ──► appendRow(...)
(automatic, fire-and-forget)             (Web App endpoint)        (one row per session)
```

- The write is triggered inside `endSession()` via `DataLogger.send()` — automatic on completion.
- It uses `fetch(..., { mode: 'no-cors' })` with a URL-encoded body, so the browser sends the request
  without a CORS pre-flight. The app does not read the response (fire-and-forget); it never blocks or
  interrupts the results screen.
- Only **completed** sessions are logged. Quitting early via **Home** does not write a row.

---

## Step 1 — Create the Google Sheet

1. Go to <https://sheets.google.com> and create a new spreadsheet, e.g. **"BlazePod Data"**.
2. Rename the first tab to `Data`.
3. Note the spreadsheet is now open; the Apps Script you add next will belong to it.

You do **not** need to add headers manually — the script writes them automatically on first run.

---

## Step 2 — Add the Apps Script

1. In the sheet: **Extensions ▸ Apps Script**.
2. Delete any placeholder code and paste the script below.
3. Save (disk icon). Name the project e.g. **"BlazePod Logger"**.

```javascript
/**
 * Virtual BlazePod — Google Sheets logger.
 * Receives one session record per POST and appends it as a row.
 */

// Column order = header row. Must match the fields sent by the app.
var HEADERS = [
  'submitted_at_iso',
  'participant_name',
  'gender',
  'age',
  'access_timestamp_iso',
  'access_timestamp_local',
  'score',
  'misses',
  'targets_presented',
  'accuracy_pct',
  'avg_reaction_time_ms',
  'best_reaction_time_ms',
  'worst_reaction_time_ms',
  'median_reaction_time_ms',
  'sd_reaction_time_ms',
  'hits_per_second',
  'session_duration_s',
  'reaction_times_ms',
  'user_agent',
  'app_source'
];

var SHEET_NAME = 'Data';

function doPost(e) {
  var lock = LockService.getScriptLock();
  lock.waitLock(30000); // avoid concurrent-write collisions
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName(SHEET_NAME) || ss.insertSheet(SHEET_NAME);

    // Write header row once.
    if (sheet.getLastRow() === 0) {
      sheet.appendRow(HEADERS);
      sheet.setFrozenRows(1);
    }

    var params = (e && e.parameter) ? e.parameter : {};
    var row = HEADERS.map(function (key) {
      return params.hasOwnProperty(key) ? params[key] : '';
    });
    sheet.appendRow(row);

    return ContentService
      .createTextOutput(JSON.stringify({ status: 'ok' }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: 'error', message: String(err) }))
      .setMimeType(ContentService.MimeType.JSON);
  } finally {
    lock.releaseLock();
  }
}

// Optional: lets you open the Web App URL in a browser to confirm it is live.
function doGet() {
  return ContentService
    .createTextOutput(JSON.stringify({ status: 'ok', message: 'BlazePod logger is running' }))
    .setMimeType(ContentService.MimeType.JSON);
}
```

---

## Step 3 — Deploy as a Web App

1. In the Apps Script editor: **Deploy ▸ New deployment**.
2. Click the gear ▸ **Web app**.
3. Configure:
   - **Description:** `BlazePod logger`
   - **Execute as:** **Me** (your account).
   - **Who has access:** **Anyone**. *(Required so the browser can POST without a Google login. The
     script only appends rows; it does not expose read access to the sheet.)*
4. Click **Deploy**, then **Authorize access** and approve the permissions for your account.
5. Copy the **Web app URL**. It looks like:
   `https://script.google.com/macros/s/AKfy........../exec`

> **Tip:** open that URL in a browser tab — you should see `{"status":"ok","message":"BlazePod logger is running"}`.

---

## Step 4 — Connect the app

1. Open `index.html`.
2. Find this line near the top of the script (in the CONSTANTS section):

   ```javascript
   const SHEETS_WEBAPP_URL = '';
   ```

3. Paste your Web app URL between the quotes:

   ```javascript
   const SHEETS_WEBAPP_URL = 'https://script.google.com/macros/s/AKfy........../exec';
   ```

4. Save, then commit and push so GitHub Pages serves the updated file.

That is the only change required. Logging is now automatic on every completed session.

---

## Step 5 — Test end-to-end

1. Open the live app (or a local `https`/`localhost` server).
2. Register (name, gender, age) and play a full 30-second block.
3. When the results screen appears, open your Google Sheet — a **new row** should be present within a
   few seconds, with the header row auto-created on the first write.
4. If nothing appears, see Troubleshooting.

---

## Data written per row

Columns match the [Data Dictionary](README.md#4-full-data-dictionary). Summary:

| Column | Meaning |
|---|---|
| `submitted_at_iso` | When the session record was sent (session end). |
| `participant_name`, `gender`, `age` | Registration profile. |
| `access_timestamp_iso`, `access_timestamp_local` | Auto-captured access time (UTC + local). |
| `score`, `misses`, `targets_presented`, `accuracy_pct` | Outcome counts and hit rate. |
| `avg/best/worst/median/sd_reaction_time_ms` | Reaction-time summary statistics. |
| `hits_per_second`, `session_duration_s` | Throughput and block length. |
| `reaction_times_ms` | JSON array of per-target reaction times (for detailed analysis / charts). |
| `user_agent`, `app_source` | Provenance for filtering by device/app. |

---

## Troubleshooting

- **No row appears.** Confirm `SHEETS_WEBAPP_URL` is set and saved; confirm the deployment access is
  **Anyone**; open the Web app URL directly to confirm it returns the "running" JSON.
- **Rows appear but columns are misaligned.** Ensure the `HEADERS` array in the script matches the
  field names the app sends (they do by default). If you change fields, update `HEADERS` to match.
- **You changed the script but nothing updates.** Apps Script Web Apps are versioned. Use
  **Deploy ▸ Manage deployments ▸ Edit ▸ New version** to publish changes to the **same** URL.
- **CORS errors in the console.** Expected/harmless: the app uses `mode: 'no-cors'` and does not read
  the response. The row is still written.
- **Privacy.** `participant_name` may be identifying. For studies, enter a pseudonymous ID and follow
  your institution's ethics/data-protection requirements (see README §6).

---

## Next

Once data is flowing into the sheet, see **[`R_SHINY_DASHBOARD.md`](R_SHINY_DASHBOARD.md)** to build a
live R Shiny dashboard on top of it.
