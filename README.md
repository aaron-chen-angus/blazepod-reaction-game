# Virtual BlazePod — Reaction Game

**A browser-based, camera-driven visuomotor reaction-time assessment tool.**

| | |
|---|---|
| **Live application** | https://aaron-chen-angus.github.io/blazepod-reaction-game/ |
| **Source repository** | https://github.com/aaron-chen-angus/blazepod-reaction-game |
| **Platform** | Client-side web application (HTML5 / JavaScript / WebGL-accelerated canvas) |
| **Face / eye tracking** | Google MediaPipe Face Mesh (468–478 landmark model) |
| **Session length** | 30 seconds per trial block |
| **Target device** | Mobile / tablet / desktop with a front-facing camera, portrait orientation |

---

## Table of Contents

1. [Overview](#1-overview)
2. [Scientific Basis of the Game](#2-scientific-basis-of-the-game)
3. [How the Game Works](#3-how-the-game-works)
4. [Full Data Dictionary](#4-full-data-dictionary)
5. [Technical Details](#5-technical-details)
6. [Data Capture, Privacy & Ethics](#6-data-capture-privacy--ethics)
7. [Deployment & Usage](#7-deployment--usage)
8. [Roadmap: Google Sheets & R Shiny Integration](#8-roadmap-google-sheets--r-shiny-integration)
9. [References](#9-references)

---

## 1. Overview

Virtual BlazePod is a lightweight, web-native re-implementation of the reaction-training concept
popularised by physical light-pod systems (e.g., commercial "BlazePod" reaction trainers). Instead
of tapping physical illuminated pods, the participant moves their head so that a tracked **eye
landmark** intersects an on-screen target ("pod"). The application measures how quickly and how
accurately the participant can acquire each target over a fixed 30-second block.

The tool is designed for **research, screening, rehabilitation, sports-science, and educational**
contexts where a low-cost, hardware-free measure of **choice/simple visuomotor reaction time**,
**sustained attention**, and **hand-free (head/gaze) targeting accuracy** is useful. It runs entirely
in the browser and requires only a camera; no application install is needed.

Before each session the participant registers a short profile (name, gender, age) and an **access
timestamp is captured automatically**. Together with the performance metrics, this forms a single
session record suitable for longitudinal tracking and export to a data store (see §8).

---

## 2. Scientific Basis of the Game

### 2.1 Reaction time as a construct

**Reaction time (RT)** — the interval between the onset of a stimulus and the initiation of a motor
response — is one of the most widely used behavioural measures in psychology, neuroscience, and
sports science. RT reflects the combined latency of sensory encoding, central processing / decision,
and motor execution, and has been studied since the classic work of Donders on mental chronometry
(Donders, 1868/1969) and Hick's and Hyman's characterisation of how RT scales with the amount of
information to be processed (Hick, 1952; Hyman, 1953).

In this application each target is a **visual stimulus of known onset time** (`spawnTime`), and the
"response" is the moment a tracked eye landmark enters the target radius. The recorded reaction time
is therefore a **visuomotor RT** that bundles: (a) visual detection of the newly appeared target,
(b) planning of a head/gaze re-orientation, and (c) the physical movement bringing the eye landmark
onto the target. Because the participant must localise a target that appears at an unpredictable
screen position, the task has a **spatial / choice component** rather than being a pure simple-RT
task (Hick, 1952; Hyman, 1953).

### 2.2 Visuomotor integration and eye–head coordination

Orienting the gaze to a suddenly appearing peripheral target is a canonical **visuomotor
integration** behaviour that recruits coordinated eye and head movements and the oculomotor /
attentional networks (Land & Hayhoe, 2001; Corbetta & Shulman, 2002). Speeded target acquisition of
this kind is sensitive to attention, arousal, fatigue, ageing, and neurological status, which is why
target-acquisition and go/no-go paradigms are used both in cognitive assessment and in sports
performance profiling (Der & Deary, 2006; Wilkinson & Allison, 1989).

### 2.3 Reaction-time light-pod training

Commercial reaction-light training systems and their research analogues have been used to develop and
assess **agility, perceptual-cognitive speed, and reactive decision-making** in athletes and in
clinical populations. Studies of light-based reaction training report improvements in reaction speed
and have examined validity and reliability of such devices for measuring reactive agility
(e.g., studies of the "BlazePod" and similar Fitlight-style systems; see Referenced literature in §9).
Virtual BlazePod adapts this paradigm to a camera-only, screen-based medium.

### 2.4 Determinants and normative context of reaction time

Reported human RTs vary with the paradigm. Simple visual RT in healthy young adults is typically in
the region of **~200–270 ms**, with choice RT being longer, and RT increasing with age and with task
complexity (Der & Deary, 2006; Woods et al., 2015; Jain et al., 2015). Because Virtual BlazePod's RT
includes a **movement component** (head/gaze travel to a spatially variable target), absolute values
recorded here will be **longer than laboratory keypress simple-RT** and should be interpreted
**within-participant and within-device** rather than against keypress norms. This makes the tool most
powerful for **repeated-measures** designs (e.g., pre/post an intervention, fatigue monitoring,
training progression), where each participant serves as their own control.

### 2.5 Intended, evidence-informed uses

- **Sports science / athletic screening** — reactive speed and agility profiling.
- **Rehabilitation & ageing** — tracking visuomotor speed over time (with clinical oversight).
- **Attention / arousal monitoring** — sustained-attention and vigilance-style tracking across a block.
- **Education & outreach** — an engaging, tangible demonstration of mental chronometry.

> **Clinical note.** Virtual BlazePod is a **research and screening instrument, not a medical
> diagnostic device.** It has not been cleared or certified as a diagnostic tool. Any clinical
> interpretation must be performed by a qualified professional, and device/browser/camera differences
> must be controlled when comparing sessions.

---

## 3. How the Game Works

1. **Registration.** The participant enters **Name**, **Gender**, and **Age**. On submission the app
   records an **automatic access timestamp** (ISO 8601 + local time).
2. **Calibration.** The camera starts and MediaPipe Face Mesh detects the face. The participant holds
   still until both eyes are locked (a short hold, ~1.2 s), which confirms tracking quality.
3. **Play (30 s).** Orange circular targets ("pods") appear one at a time at pseudo-random positions.
   Each target is live for up to **3 s**. The participant moves their head so a tracked eye landmark
   enters the target:
   - If the eye reaches the target in time → **hit** (reaction time recorded).
   - If the target expires first → **miss**.
   A new target is scheduled shortly after each hit or miss until the 30 s block ends.
4. **Results.** A performance report shows score, accuracy, average and best reaction time, a per-target
   reaction-time chart, and the participant summary.

---

## 4. Full Data Dictionary

The following is the complete set of fields the application captures or derives per session. Field
names in the "Field" column are the canonical export names recommended for the data store (§8).

### 4.1 Participant / session-header fields

| Field | Type | Unit / Format | Source | Description |
|---|---|---|---|---|
| `participant_name` | string | free text (≤ 80 chars) | Registration form | Participant's name as entered. Free text; may be an ID/pseudonym for anonymised studies. |
| `gender` | categorical | `Female` / `Male` / `Non-binary` / `Prefer not to say` | Registration form | Self-reported gender. |
| `age` | integer | years (1–120) | Registration form | Self-reported age in whole years. Validated to the 1–120 range. |
| `access_timestamp_iso` | datetime | ISO 8601 UTC (e.g. `2026-09-22T08:15:30.000Z`) | Auto-captured on form submit | Machine-readable timestamp of when the participant began the session. Primary time key. |
| `access_timestamp_local` | string | locale-formatted local time | Auto-captured on form submit | Human-readable local time of access, from the device locale/timezone. |

### 4.2 Core performance metrics

| Field | Type | Unit | Source (code) | Description |
|---|---|---|---|---|
| `score` | integer | count | `GameState.score` | Number of targets successfully hit during the block. |
| `misses` | integer | count | `GameState.misses` | Number of targets that expired (3 s) without a hit. |
| `targets_presented` | integer | count | `score + misses` | Total targets shown in the block. |
| `accuracy_pct` | number | percent (0–100) | `score / (score + misses) × 100` | Hit rate. Reported as `N/A` if no targets were presented. |
| `avg_reaction_time_ms` | number | milliseconds | mean of `reactionTimes` | Mean reaction time across all **hits**. Reported as `N/A` if no hits. |
| `best_reaction_time_ms` | number | milliseconds | min of `reactionTimes` | Fastest single hit reaction time. Reported as `N/A` if no hits. |
| `reaction_times_ms` | array of integers | milliseconds | `GameState.reactionTimes[]` | Ordered list of per-hit reaction times (target 1, 2, 3 …). Basis of the results chart. |

### 4.3 Derived / recommended fields (computed on export)

These are not stored in the running game but are trivially derivable and recommended for analysis.

| Field | Type | Unit | Computation | Description |
|---|---|---|---|---|
| `median_reaction_time_ms` | number | ms | median(`reaction_times_ms`) | More robust central tendency than the mean for skewed RT distributions. |
| `sd_reaction_time_ms` | number | ms | stdev(`reaction_times_ms`) | Intra-session RT variability — a proxy for attentional consistency. |
| `worst_reaction_time_ms` | number | ms | max(`reaction_times_ms`) | Slowest hit. |
| `hits_per_second` | number | hits/s | `score / 30` | Throughput / reactive tempo over the fixed block. |
| `session_duration_s` | number | s | constant `30` | Block length. Fixed by `SESSION_DURATION`. |

### 4.4 Fixed session parameters (game constants)

These constants define the task and should be recorded alongside data for reproducibility. Changing
them changes the meaning of the metrics.

| Constant (code) | Value | Meaning |
|---|---|---|
| `SESSION_DURATION` | 30000 ms | Total block duration (30 s). |
| `TARGET_DURATION` | 3000 ms | Maximum time a target is live before it is scored as a miss. |
| `TARGET_RADIUS` | 55 px | Target ("pod") radius. |
| `EYE_DOT_RADIUS` | 14 px | Rendered radius of the tracked eye cursor. |
| `MIN_TARGET_DISTANCE` | 60 px | Minimum spatial separation between consecutive targets. |
| `NEXT_TARGET_DELAY` | 300 ms | Gap after a hit/miss before the next target spawns. |
| `FIRST_TARGET_DELAY` | 600 ms | Delay before the first target of a block. |
| `CALIB_HOLD_MS` | 1200 ms | Hold time required to confirm eye calibration. |

> **RT definition (exact).** For each hit, `reaction_time_ms = round(hit_time − spawn_time)`, both
> measured with the browser's high-resolution monotonic clock (`performance.now()`). RT therefore
> includes visual detection + movement time to bring the eye landmark into the 55 px target.

---

## 5. Technical Details

### 5.1 Architecture

Virtual BlazePod is a **single-file, client-side web application** (`index.html`) with no build step
and no server dependency for gameplay. Its runtime modules (all in one script) are:

- **FaceTracker** — wraps MediaPipe Face Mesh + the MediaPipe Camera utility; streams webcam frames,
  extracts iris/eye landmarks, and maps them to canvas coordinates (mirrored horizontally to match a
  selfie view).
- **TargetManager** — spawns targets at pseudo-random, well-separated positions; detects hits
  (eye-within-radius) and misses (timeout); records reaction times.
- **AnimationManager** — transient hit/miss visual effects.
- **Renderer** — draws targets, eye cursors, HUD (score + countdown), and prompts to a `<canvas>`.
- **UIManager** — screen routing (start → **register** → calibration → game → results) and results
  rendering, including the participant summary and the reaction-time bar chart.
- **GameState / Participant** — in-memory session state. `Participant` holds the profile and access
  timestamp and is intentionally decoupled from the core game loop.

### 5.2 Eye / face tracking

- Uses **MediaPipe Face Mesh** with `refineLandmarks: true`, enabling the iris landmark set.
- Preferred landmarks: left iris (index 468) and right iris (index 473); falls back to eyelid
  landmarks (159 / 386) if the iris set is unavailable.
- Detection/tracking confidence thresholds are set to 0.6. A single face is tracked (`maxNumFaces: 1`).
- Landmark coordinates are normalised (0–1); the app converts them to canvas pixels and mirrors X so
  movement matches the on-screen selfie image.

### 5.3 Timing & scoring

- All gameplay timing uses `performance.now()` (monotonic, sub-millisecond resolution) rather than
  wall-clock time, so RTs are unaffected by clock adjustments.
- A hit is registered when the Euclidean distance from either tracked eye to the target centre is
  ≤ the target radius. The **active eye** is the one nearest the current target.
- The main loop is driven by `requestAnimationFrame`, so rendering/scoring runs at the display refresh
  rate (typically 60 Hz).

### 5.4 Technology stack

| Layer | Technology |
|---|---|
| Markup / styling | HTML5, CSS3 (custom properties, responsive layout, portrait guard) |
| Logic | Vanilla JavaScript (ES2020+, `'use strict'`) |
| Rendering | HTML5 Canvas 2D |
| Computer vision | MediaPipe Face Mesh + Camera/Control utilities (loaded from jsDelivr CDN) |
| Fonts | Google Fonts — Orbitron, Exo 2 |
| Hosting | Static hosting (GitHub Pages) over HTTPS |

### 5.5 Requirements & constraints

- **HTTPS (or `localhost`)** is required — browsers only grant camera access in a secure context.
- A **front-facing camera** and camera permission are required.
- **Portrait orientation** is expected; a rotate overlay prompts in landscape.
- An internet connection is required on first load to fetch the MediaPipe library and fonts from the CDN.

### 5.6 Browser compatibility

Targets current evergreen browsers (Chrome/Edge/Firefox/Safari) that support `getUserMedia`, Canvas 2D,
and WebAssembly (used by MediaPipe). Performance depends on device camera and CPU/GPU.

---

## 6. Data Capture, Privacy & Ethics

- **What is captured:** the participant profile (name, gender, age), the automatic access timestamp,
  and the performance metrics in §4. **Raw video frames are processed in-browser and are not recorded
  or transmitted** by the application.
- **Where it lives today:** in-memory for the session and shown on the results screen. Persistent
  export (Google Sheets) is described in §8 and is opt-in at deployment time.
- **Personal data:** `participant_name` may be personally identifying. For studies, prefer a
  pseudonymous ID and obtain informed consent covering data capture, storage, and export.
- **Compliance:** when deploying with a data store, follow your institution's ethics/IRB requirements
  and applicable data-protection law (e.g., GDPR/PDPA), including lawful basis, retention limits, and
  the right to erasure.

---

## 7. Deployment & Usage

### 7.1 Run locally

Because camera access needs a secure context, serve the folder over `localhost` (any static server),
then open the served URL. Opening the file directly via `file://` will block the camera.

### 7.2 GitHub Pages

The app is published as a static site:

- **Repository:** https://github.com/aaron-chen-angus/blazepod-reaction-game
- **Live site:** https://aaron-chen-angus.github.io/blazepod-reaction-game/

To update the live site, commit `index.html` to the Pages-enabled branch; GitHub Pages serves it over
HTTPS, satisfying the camera-permission requirement.

---

## 8. Google Sheets & R Shiny Integration

**Automatic Google Sheets logging — implemented.** On session completion the app automatically `POST`s
the session record (participant fields + metrics from §4) to a Google Apps Script Web App bound to a
Google Sheet. This write is **fully automatic** — fired from the end-of-session code path
(`DataLogger.send()` inside `endSession()`) and requires **no button press**. Each completed session
becomes one row; the sheet becomes the live data source. Logging is enabled by pasting your Web App URL
into the `SHEETS_WEBAPP_URL` constant in `index.html`; when empty, logging is disabled and the game runs
unchanged. Full setup: **[`GOOGLE_SHEETS_INTEGRATION.md`](GOOGLE_SHEETS_INTEGRATION.md)**.

**R Shiny live dashboard — implemented.** A ready-to-run R Shiny application (`dashboard/app.R`) reads
the same Google Sheet in near real time (via `googlesheets4`, polled on an interval) and renders live
visualisations: reaction-time trends per session, accuracy vs. RT trade-off, RT distribution, and cohort
comparisons by gender and age band, plus KPI cards and a filterable session table. Full setup:
**[`R_SHINY_DASHBOARD.md`](R_SHINY_DASHBOARD.md)**.

---

## 9. References

*Reproduced/summarised for compliance with licensing restrictions; consult the originals for full text.*

1. Donders, F. C. (1969). On the speed of mental processes (W. G. Koster, Trans.). *Acta Psychologica*,
   30, 412–431. (Original work published 1868.)
2. Hick, W. E. (1952). On the rate of gain of information. *Quarterly Journal of Experimental
   Psychology*, 4(1), 11–26.
3. Hyman, R. (1953). Stimulus information as a determinant of reaction time. *Journal of Experimental
   Psychology*, 45(3), 188–196.
4. Der, G., & Deary, I. J. (2006). Age and sex differences in reaction time in adulthood: Results from
   the United Kingdom Health and Lifestyle Survey. *Psychology and Aging*, 21(1), 62–73.
5. Woods, D. L., Wyma, J. M., Yund, E. W., Herron, T. J., & Reed, B. (2015). Factors influencing the
   latency of simple reaction time. *Frontiers in Human Neuroscience*, 9, 131.
6. Jain, A., Bansal, R., Kumar, A., & Singh, K. D. (2015). A comparative study of visual and auditory
   reaction times on the basis of gender and physical activity levels of medical first year students.
   *International Journal of Applied and Basic Medical Research*, 5(2), 124–127.
7. Land, M. F., & Hayhoe, M. (2001). In what ways do eye movements contribute to everyday activities?
   *Vision Research*, 41(25–26), 3559–3565.
8. Corbetta, M., & Shulman, G. L. (2002). Control of goal-directed and stimulus-driven attention in the
   brain. *Nature Reviews Neuroscience*, 3(3), 201–215.
9. Wilkinson, R. T., & Allison, S. (1989). Age and simple reaction time: Decade differences for 5,325
   subjects. *Journal of Gerontology*, 44(2), P29–P35.
10. Kosinski, R. J. (2008/updated). *A Literature Review on Reaction Time.* Clemson University.
    (Technical review compiling RT determinants across studies.)

### Technical manuals & documentation

11. Google MediaPipe — Face Mesh / Face Landmarker documentation.
    https://developers.google.com/mediapipe (and the legacy Face Mesh solution docs).
12. Lugaresi, C., et al. (2019). *MediaPipe: A Framework for Building Perception Pipelines.* arXiv:1906.08172.
13. Kartynnik, Y., Ablavatski, A., Grishchenko, I., & Grundmann, M. (2019). *Real-time Facial Surface
    Geometry from Monocular Video on Mobile GPUs.* arXiv:1907.06724 (the model behind Face Mesh).
14. MDN Web Docs — `MediaDevices.getUserMedia()`, Canvas API, and `performance.now()`.
    https://developer.mozilla.org/
15. R package `googlesheets4` and Google Apps Script Web Apps documentation (for §8 integration).

---

*Virtual BlazePod is provided for research, training, and educational use. It is not a certified
medical device and must not be used as the sole basis for any clinical decision.*
