# ═══════════════════════════════════════════════════════════════════════════
#  VIRTUAL BLAZEPOD — LIVE PERFORMANCE DASHBOARD (R Shiny)
#  Tron-styled, educational, interactive visualisation of reaction-game results.
#
#  Reads the Google Sheet written to by the Virtual BlazePod web app.
#  See R_SHINY_DASHBOARD.md and GOOGLE_SHEETS_INTEGRATION.md for setup.
#
#  Run locally / on Posit Cloud:  shiny::runApp("dashboard")
# ═══════════════════════════════════════════════════════════════════════════

library(shiny)
library(googlesheets4)
library(dplyr)
library(tidyr)
library(plotly)
library(lubridate)
library(DT)
library(jsonlite)
library(htmltools)

# ── CONFIG ─────────────────────────────────────────────────────────────────
SHEET_ID   <- "1A76A9WlCKIuPKzYzwmjGy_9Dvkn7Hy0YeTLWh-YEmjM"  # BlazePod data sheet
SHEET_NAME <- "Data"                                          # logger tab name
REFRESH_MS <- 15000                                           # auto-refresh (ms)
USE_DEMO_IF_EMPTY <- TRUE   # show synthetic sample data when the sheet is empty

# Read-only access to a link-shared sheet. For a private sheet use:
#   gs4_auth(path = "service-account.json")
gs4_deauth()

# ── THEME PALETTE (matches the game) ─────────────────────────────────────────
CLR <- list(
  bg      = "#050810",
  bg2     = "#0a0f1e",
  surface = "#0d1526",
  surface2= "#111d35",
  orange  = "#ff6b00",
  cyan    = "#00e5ff",
  green   = "#00e676",
  danger  = "#ff3333",
  text    = "#e8eaf0",
  muted   = "#6b7a99",
  grid    = "rgba(0,229,255,0.08)"
)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || all(is.na(a))) b else a

# ── DATA HELPERS ─────────────────────────────────────────────────────────────
demo_data <- function() {
  set.seed(42)
  names_pool <- c("Athlete A", "Athlete B", "Trainee C", "Trainee D", "Player E")
  genders    <- c("Female", "Male", "Non-binary")
  n <- 24
  base_time <- Sys.time() - lubridate::ddays(6)
  tibble(
    submitted_at_iso       = format(base_time + lubridate::dhours(seq_len(n) * 5), "%Y-%m-%dT%H:%M:%SZ"),
    participant_name       = sample(names_pool, n, replace = TRUE),
    gender                 = sample(genders, n, replace = TRUE, prob = c(.45, .45, .1)),
    age                    = sample(16:60, n, replace = TRUE),
    access_timestamp_iso   = format(base_time + lubridate::dhours(seq_len(n) * 5), "%Y-%m-%dT%H:%M:%SZ"),
    access_timestamp_local = format(base_time + lubridate::dhours(seq_len(n) * 5), "%d/%m/%Y %H:%M"),
    score                  = sample(6:18, n, replace = TRUE),
    misses                 = sample(0:6, n, replace = TRUE)
  ) %>%
    rowwise() %>%
    mutate(
      targets_presented = score + misses,
      accuracy_pct      = round(score / targets_presented * 100, 1),
      reaction_times_ms = {
        rts <- round(rnorm(score, mean = 620 - age * 1.5, sd = 90))
        rts <- pmax(280, rts)
        jsonlite::toJSON(as.integer(rts))
      }
    ) %>%
    ungroup() %>%
    mutate(
      avg_reaction_time_ms    = sapply(reaction_times_ms, function(x) round(mean(as.numeric(fromJSON(x))))),
      best_reaction_time_ms   = sapply(reaction_times_ms, function(x) min(as.numeric(fromJSON(x)))),
      worst_reaction_time_ms  = sapply(reaction_times_ms, function(x) max(as.numeric(fromJSON(x)))),
      median_reaction_time_ms = sapply(reaction_times_ms, function(x) round(median(as.numeric(fromJSON(x))))),
      sd_reaction_time_ms     = sapply(reaction_times_ms, function(x) round(sd(as.numeric(fromJSON(x))))),
      hits_per_second         = round(score / 30, 3),
      session_duration_s      = 30,
      user_agent              = "demo",
      app_source              = "virtual-blazepod (DEMO DATA)"
    )
}

coerce_types <- function(df) {
  num_cols <- c("age", "score", "misses", "targets_presented", "accuracy_pct",
                "avg_reaction_time_ms", "best_reaction_time_ms",
                "worst_reaction_time_ms", "median_reaction_time_ms",
                "sd_reaction_time_ms", "hits_per_second", "session_duration_s")
  for (col in intersect(num_cols, names(df))) df[[col]] <- suppressWarnings(as.numeric(df[[col]]))

  df$access_time <- if ("access_timestamp_iso" %in% names(df)) {
    suppressWarnings(ymd_hms(df$access_timestamp_iso, quiet = TRUE))
  } else as.POSIXct(NA)

  if ("age" %in% names(df)) {
    df$age_band <- cut(df$age,
      breaks = c(0, 12, 17, 24, 34, 44, 54, 64, Inf),
      labels = c("<13", "13-17", "18-24", "25-34", "35-44", "45-54", "55-64", "65+"),
      right = TRUE)
  }
  df %>% arrange(access_time)
}

read_sessions <- function() {
  df <- tryCatch(read_sheet(SHEET_ID, sheet = SHEET_NAME, col_types = "c"),
                 error = function(e) NULL)
  is_demo <- FALSE
  if (is.null(df) || nrow(df) == 0) {
    if (USE_DEMO_IF_EMPTY) { df <- demo_data(); is_demo <- TRUE } else return(list(data = tibble(), demo = FALSE))
  }
  list(data = coerce_types(df), demo = is_demo)
}

explode_rts <- function(df) {
  if (nrow(df) == 0 || !"reaction_times_ms" %in% names(df)) return(tibble())
  rows <- lapply(seq_len(nrow(df)), function(i) {
    raw <- df$reaction_times_ms[i]
    if (is.na(raw) || raw == "") return(NULL)
    vals <- tryCatch(as.numeric(fromJSON(raw)), error = function(e) numeric(0))
    if (length(vals) == 0) return(NULL)
    tibble(
      participant_name = df$participant_name[i] %||% NA,
      gender           = df$gender[i] %||% NA,
      age_band         = if ("age_band" %in% names(df)) as.character(df$age_band[i]) else NA,
      access_time      = df$access_time[i],
      target_index     = seq_along(vals),
      reaction_time_ms = vals
    )
  })
  bind_rows(rows)
}

# ── PLOTLY THEME HELPER ──────────────────────────────────────────────────────
style_plot <- function(p, ytitle = "", xtitle = "") {
  p %>%
    layout(
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor  = "rgba(0,0,0,0)",
      font   = list(color = CLR$text, family = "Exo 2, system-ui, sans-serif"),
      xaxis  = list(title = xtitle, gridcolor = CLR$grid, zeroline = FALSE,
                    linecolor = "rgba(0,229,255,0.25)", tickfont = list(color = CLR$muted)),
      yaxis  = list(title = ytitle, gridcolor = CLR$grid, zeroline = FALSE,
                    linecolor = "rgba(0,229,255,0.25)", tickfont = list(color = CLR$muted)),
      legend = list(font = list(color = CLR$text), bgcolor = "rgba(0,0,0,0)"),
      margin = list(l = 55, r = 20, t = 30, b = 45),
      hoverlabel = list(bgcolor = CLR$surface2, font = list(color = CLR$text))
    ) %>%
    config(displayModeBar = FALSE, responsive = TRUE)
}

# ── EDUCATIONAL COPY ─────────────────────────────────────────────────────────
edu <- function(text) div(class = "edu-note", HTML(paste0("&#9432; ", text)))

# ═══════════════════════════════════════════════════════════════════════════
#  UI
# ═══════════════════════════════════════════════════════════════════════════
ui <- fluidPage(
  tags$head(
    tags$link(rel = "preconnect", href = "https://fonts.googleapis.com"),
    tags$link(href = "https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700;900&family=Exo+2:wght@300;400;600&display=swap", rel = "stylesheet"),
    tags$style(HTML(sprintf("
      :root {
        --bg:%s; --surface:%s; --surface2:%s; --orange:%s; --cyan:%s;
        --green:%s; --text:%s; --muted:%s;
      }
      html, body { background: var(--bg); color: var(--text);
        font-family:'Exo 2',system-ui,sans-serif; }
      body::before { content:''; position:fixed; inset:0; z-index:0; pointer-events:none;
        background-image:
          linear-gradient(rgba(0,229,255,0.05) 1px, transparent 1px),
          linear-gradient(90deg, rgba(0,229,255,0.05) 1px, transparent 1px);
        background-size:42px 42px; }
      .container-fluid { position:relative; z-index:1; max-width:1320px; }

      /* Header */
      .app-header { text-align:center; padding:1.6rem 0 0.4rem; }
      .app-eyebrow { font-family:'Orbitron',monospace; letter-spacing:0.35em; font-size:11px;
        color:var(--cyan); text-transform:uppercase; }
      .app-title { font-family:'Orbitron',monospace; font-weight:900; font-size:clamp(24px,5vw,40px);
        color:var(--orange); text-transform:uppercase; letter-spacing:0.05em;
        text-shadow:0 0 14px rgba(255,107,0,0.55), 0 0 34px rgba(255,107,0,0.25); margin:0.2rem 0; }
      .app-sub { color:var(--muted); font-size:14px; }
      .scan { height:1px; margin:0.9rem auto 0; max-width:900px;
        background:linear-gradient(90deg,transparent,var(--cyan),transparent); opacity:0.5; }

      .demo-banner { background:rgba(255,107,0,0.12); border:1px solid var(--orange);
        border-radius:8px; padding:0.6rem 1rem; margin:1rem 0; text-align:center;
        color:#ffc38a; font-size:13px; letter-spacing:0.03em; }

      /* KPI cards */
      .kpi-row { display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr));
        gap:1rem; margin:1.2rem 0; }
      .kpi { background:var(--surface); border:1px solid rgba(0,229,255,0.16);
        border-radius:12px; padding:1.1rem 1rem; position:relative; overflow:hidden; }
      .kpi::before { content:''; position:absolute; top:0; left:0; right:0; height:2px;
        background:var(--orange); opacity:0.7; }
      .kpi.cyan::before { background:var(--cyan); }
      .kpi .k-label { font-family:'Orbitron',monospace; font-size:10px; letter-spacing:0.18em;
        color:var(--muted); text-transform:uppercase; }
      .kpi .k-value { font-family:'Orbitron',monospace; font-size:30px; font-weight:700;
        color:var(--text); margin-top:0.3rem; line-height:1; }
      .kpi.cyan .k-value { color:var(--cyan); text-shadow:0 0 12px rgba(0,229,255,0.4); }
      .kpi.orange .k-value { color:var(--orange); text-shadow:0 0 12px rgba(255,107,0,0.4); }
      .kpi .k-sub { color:var(--muted); font-size:11px; margin-top:0.35rem; }

      /* Panels */
      .panel { background:var(--surface); border:1px solid rgba(0,229,255,0.14);
        border-radius:12px; padding:1.1rem 1.2rem; margin-bottom:1.2rem; }
      .panel-title { font-family:'Orbitron',monospace; font-size:13px; letter-spacing:0.14em;
        color:var(--cyan); text-transform:uppercase; margin-bottom:0.2rem; }
      .edu-note { background:var(--surface2); border-left:3px solid var(--orange);
        border-radius:6px; padding:0.6rem 0.85rem; margin:0.6rem 0 0.9rem;
        color:#c7d0e2; font-size:13px; line-height:1.5; }

      /* Sidebar controls */
      .well, .sidebar-card { background:var(--surface) !important;
        border:1px solid rgba(0,229,255,0.16) !important; border-radius:12px; }
      label { color:var(--cyan) !important; font-family:'Orbitron',monospace;
        font-size:11px; letter-spacing:0.12em; text-transform:uppercase; }
      .form-control, .selectize-input, .irs-bar, .form-select {
        background:var(--surface2) !important; color:var(--text) !important;
        border:1px solid rgba(0,229,255,0.25) !important; }
      .selectize-dropdown { background:var(--surface2) !important; color:var(--text) !important; }
      .irs--shiny .irs-bar { background:var(--orange) !important; border-color:var(--orange) !important; }
      .irs--shiny .irs-handle { border-color:var(--orange) !important; }
      .irs--shiny .irs-single, .irs--shiny .irs-from, .irs--shiny .irs-to {
        background:var(--orange) !important; }

      /* Tabs */
      .nav-tabs { border-bottom:1px solid rgba(0,229,255,0.2); }
      .nav-tabs > li > a, .nav-tabs .nav-link { color:var(--muted) !important;
        font-family:'Orbitron',monospace; font-size:12px; letter-spacing:0.08em;
        text-transform:uppercase; border:none !important; background:transparent !important; }
      .nav-tabs > li.active > a, .nav-tabs .nav-link.active {
        color:var(--orange) !important; border-bottom:2px solid var(--orange) !important; }

      .updated { color:var(--muted); font-size:11px; text-align:right; letter-spacing:0.05em; }
      .footer-note { color:var(--muted); font-size:12px; text-align:center;
        margin:1.5rem 0 2rem; line-height:1.6; }
      a { color:var(--cyan); }
      table.dataTable { color:var(--text) !important; }
      .dataTables_wrapper { color:var(--muted) !important; }
    ", CLR$bg, CLR$surface, CLR$surface2, CLR$orange, CLR$cyan, CLR$green, CLR$text, CLR$muted)))
  ),

  # Header
  div(class = "app-header",
      div(class = "app-eyebrow", "// Performance Analytics //"),
      div(class = "app-title", "Virtual BlazePod"),
      div(class = "app-sub", "Reaction-time & visuomotor performance dashboard"),
      div(class = "scan")
  ),

  uiOutput("demo_banner"),

  sidebarLayout(
    sidebarPanel(
      width = 3, class = "sidebar-card",
      div(class = "panel-title", "Filters"),
      selectInput("participant", "Participant", choices = c("All"), selected = "All"),
      selectInput("gender", "Gender", choices = c("All"), selected = "All"),
      sliderInput("age_range", "Age range", min = 0, max = 100, value = c(0, 100)),
      dateRangeInput("date_range", "Access date range"),
      hr(style = "border-color:rgba(0,229,255,0.15)"),
      div(class = "updated", textOutput("last_update", inline = TRUE)),
      div(class = "kpi-sub", style = "color:#6b7a99;font-size:11px;margin-top:0.5rem;",
          sprintf("Auto-refreshes every %.0fs", REFRESH_MS / 1000))
    ),

    mainPanel(
      width = 9,
      # KPI cards
      uiOutput("kpis"),

      tabsetPanel(
        id = "tabs",
        # ── OVERVIEW ─────────────────────────────────────────
        tabPanel("Overview",
          div(class = "panel",
              div(class = "panel-title", "Reaction Time Progression"),
              edu("Each point is one 30-second session in chronological order. <b>Average</b> (orange) is the mean reaction time across all hits; <b>Best</b> (cyan) is the single fastest hit. Falling lines over repeated sessions suggest a genuine <b>practice / learning effect</b> \u2014 the visuomotor system becoming faster with training."),
              plotlyOutput("plot_rt_time", height = 340)
          ),
          fluidRow(
            column(6, div(class = "panel",
              div(class = "panel-title", "Speed vs. Accuracy"),
              edu("The classic <b>speed\u2013accuracy trade-off</b>: responding faster often costs accuracy. Points toward the <b>top-left</b> (fast <i>and</i> accurate) are the strongest performances."),
              plotlyOutput("plot_scatter", height = 300)
            )),
            column(6, div(class = "panel",
              div(class = "panel-title", "Throughput per Session"),
              edu("<b>Hits per second</b> combines speed and accuracy into one tempo measure \u2014 how many targets were successfully acquired per second of play."),
              plotlyOutput("plot_throughput", height = 300)
            ))
          )
        ),

        # ── REACTION TIME ────────────────────────────────────
        tabPanel("Reaction Time",
          div(class = "panel",
              div(class = "panel-title", "Distribution of Individual Reaction Times"),
              edu("Every single target hit is pooled here. Human visual reaction times are <b>right-skewed</b> \u2014 a fast cluster with a long slow tail. Note that BlazePod times include <b>movement time</b> (moving the head/eye onto the target), so they run longer than a simple key-press reaction time (~200\u2013270 ms in young adults)."),
              plotlyOutput("plot_dist", height = 320)
          ),
          fluidRow(
            column(6, div(class = "panel",
              div(class = "panel-title", "Consistency (Variability)"),
              edu("The <b>standard deviation</b> of reaction times within a session measures <b>consistency</b>. Lower variability indicates steadier attention and control; a high spread can signal fatigue or lapses in concentration."),
              plotlyOutput("plot_consistency", height = 300)
            )),
            column(6, div(class = "panel",
              div(class = "panel-title", "Within-Session Fatigue Curve"),
              edu("Reaction time by <b>target order</b> (1st, 2nd, 3rd\u2026 hit). A rising trend across a session can indicate <b>vigilance decrement</b> \u2014 performance dropping as sustained attention is taxed."),
              plotlyOutput("plot_fatigue", height = 300)
            ))
          )
        ),

        # ── GROUPS ───────────────────────────────────────────
        tabPanel("Group Comparison",
          fluidRow(
            column(6, div(class = "panel",
              div(class = "panel-title", "Mean Reaction Time by Gender"),
              edu("Group means with individual sessions overlaid. Interpret cautiously \u2014 differences are influenced by age, training, and sample size. Always compare like with like."),
              plotlyOutput("plot_gender", height = 320)
            )),
            column(6, div(class = "panel",
              div(class = "panel-title", "Reaction Time by Age Band"),
              edu("Reaction time typically <b>slows with age</b> in adulthood (well documented in the literature). This chart lets you see that relationship in your own cohort."),
              plotlyOutput("plot_age", height = 320)
            ))
          ),
          div(class = "panel",
              div(class = "panel-title", "Leaderboard \u2014 Best Reaction Times"),
              edu("Ranked by fastest single hit. A friendly, motivating way to surface top performances."),
              plotlyOutput("plot_leaderboard", height = 320)
          )
        ),

        # ── SESSIONS TABLE ───────────────────────────────────
        tabPanel("Session Records",
          div(class = "panel",
              div(class = "panel-title", "All Sessions"),
              edu("The raw records behind every chart. Use the filters on the left, sort any column, or search. This is exactly what is stored in the Google Sheet."),
              DTOutput("table")
          )
        ),

        # ── SCIENCE / EDUCATION ──────────────────────────────
        tabPanel("The Science",
          div(class = "panel",
            div(class = "panel-title", "What is Reaction Time?"),
            HTML("<p style='color:#c7d0e2;line-height:1.7'>
              <b>Reaction time (RT)</b> is the interval between a stimulus appearing and the start of your
              response. It is one of the oldest and most widely used measures in psychology and
              neuroscience, tracing back to <b>Donders'</b> 19th-century work on <i>mental chronometry</i>.
              RT reflects three stages chained together: <b>(1) sensory detection</b> of the stimulus,
              <b>(2) central processing / decision</b>, and <b>(3) motor execution</b> of the response.</p>")
          ),
          div(class = "panel",
            div(class = "panel-title", "What Virtual BlazePod Measures"),
            HTML("<p style='color:#c7d0e2;line-height:1.7'>
              A target ('pod') appears at a random screen position; you move your head so a camera-tracked
              <b>eye landmark</b> lands on it. The recorded RT therefore bundles <b>detection + movement</b>
              of the head/gaze to a spatially unpredictable target \u2014 a <b>visuomotor, choice-style</b>
              task rather than a simple key-press. This is why absolute values are longer than laboratory
              key-press norms, and why results are best read <b>within-person and within-device</b> over
              repeated sessions.</p>")
          ),
          fluidRow(
            column(6, div(class = "panel",
              div(class = "panel-title", "How to Read the Metrics"),
              HTML("<ul style='color:#c7d0e2;line-height:1.8'>
                <li><b>Score</b> \u2014 targets hit in 30 s.</li>
                <li><b>Accuracy</b> \u2014 hits \u00f7 targets shown.</li>
                <li><b>Average RT</b> \u2014 mean speed of your hits.</li>
                <li><b>Best RT</b> \u2014 your single fastest hit.</li>
                <li><b>SD of RT</b> \u2014 consistency (lower = steadier).</li>
                <li><b>Hits/sec</b> \u2014 overall reactive tempo.</li>
              </ul>")
            )),
            column(6, div(class = "panel",
              div(class = "panel-title", "Good to Know"),
              HTML("<ul style='color:#c7d0e2;line-height:1.8'>
                <li>RT improves with <b>practice</b> \u2014 watch your progression trend.</li>
                <li>RT <b>slows with age</b> and with <b>fatigue</b>.</li>
                <li>There is a <b>speed\u2013accuracy trade-off</b>: rushing lowers accuracy.</li>
                <li>Camera, lighting, and device affect timing \u2014 keep conditions consistent.</li>
              </ul>")
            ))
          ),
          div(class = "panel",
            div(class = "panel-title", "Not a Medical Device"),
            HTML("<p style='color:#c7d0e2;line-height:1.7'>Virtual BlazePod is a research, training and
              educational tool. It is <b>not</b> a certified diagnostic instrument and must not be used as
              the sole basis for any clinical decision. See the project README references for the
              peer-reviewed literature behind these concepts.</p>")
          )
        )
      ),

      div(class = "footer-note",
          HTML("Virtual BlazePod \u00b7 <a href='https://aaron-chen-angus.github.io/blazepod-reaction-game/' target='_blank'>Play the game</a> \u00b7 <a href='https://github.com/aaron-chen-angus/blazepod-reaction-game' target='_blank'>Source</a><br>Data updates live from Google Sheets. For research & education only \u2014 not a medical device."))
    )
  )
)

# ═══════════════════════════════════════════════════════════════════════════
#  SERVER
# ═══════════════════════════════════════════════════════════════════════════
server <- function(input, output, session) {

  poll <- reactivePoll(
    intervalMillis = REFRESH_MS, session = session,
    checkFunc = function() Sys.time(),
    valueFunc = function() read_sessions()
  )

  raw_data <- reactive(poll()$data)
  is_demo  <- reactive(isTRUE(poll()$demo))

  output$demo_banner <- renderUI({
    if (is_demo())
      div(class = "demo-banner",
          HTML("&#9888; Showing <b>DEMO DATA</b> \u2014 no sessions found in the sheet yet. Play a session in the app and the dashboard will switch to live data automatically."))
  })

  observe({
    df <- raw_data(); if (nrow(df) == 0) return()
    updateSelectInput(session, "participant",
      choices = c("All", sort(unique(na.omit(df$participant_name)))))
    updateSelectInput(session, "gender",
      choices = c("All", sort(unique(na.omit(df$gender)))))
    if ("age" %in% names(df) && any(!is.na(df$age))) {
      updateSliderInput(session, "age_range",
        min = floor(min(df$age, na.rm = TRUE)), max = ceiling(max(df$age, na.rm = TRUE)),
        value = c(floor(min(df$age, na.rm = TRUE)), ceiling(max(df$age, na.rm = TRUE))))
    }
    if (any(!is.na(df$access_time))) {
      rng <- range(as.Date(df$access_time), na.rm = TRUE)
      updateDateRangeInput(session, "date_range", start = rng[1], end = rng[2])
    }
  })

  filtered <- reactive({
    df <- raw_data(); if (nrow(df) == 0) return(df)
    if (input$participant != "All") df <- df %>% filter(participant_name == input$participant)
    if (input$gender != "All")      df <- df %>% filter(gender == input$gender)
    if ("age" %in% names(df))
      df <- df %>% filter(is.na(age) | (age >= input$age_range[1] & age <= input$age_range[2]))
    if (!is.null(input$date_range) && !any(is.na(input$date_range)))
      df <- df %>% filter(is.na(access_time) |
        (as.Date(access_time) >= input$date_range[1] & as.Date(access_time) <= input$date_range[2]))
    df
  })

  output$last_update <- renderText(paste("Updated", format(Sys.time(), "%H:%M:%S")))

  # ── KPI CARDS ──────────────────────────────────────────────────────────────
  output$kpis <- renderUI({
    df <- filtered()
    kpi <- function(cls, label, value, sub = "")
      div(class = paste("kpi", cls),
          div(class = "k-label", label), div(class = "k-value", value),
          if (nzchar(sub)) div(class = "k-sub", sub))
    if (nrow(df) == 0)
      return(div(class = "kpi-row",
        kpi("orange", "Sessions", "0"), kpi("cyan", "Participants", "0"),
        kpi("orange", "Mean Accuracy", "\u2014"), kpi("cyan", "Fastest Hit", "\u2014")))
    div(class = "kpi-row",
      kpi("orange", "Sessions", nrow(df), "completed blocks"),
      kpi("cyan", "Participants", length(unique(na.omit(df$participant_name))), "unique players"),
      kpi("orange", "Mean Accuracy", paste0(round(mean(df$accuracy_pct, na.rm = TRUE), 1), "%"), "hits / targets"),
      kpi("cyan", "Fastest Hit", paste0(round(min(df$best_reaction_time_ms, na.rm = TRUE)), " ms"), "best reaction"),
      kpi("orange", "Mean RT", paste0(round(mean(df$avg_reaction_time_ms, na.rm = TRUE)), " ms"), "average speed")
    )
  })

  need_data <- function(df) validate(need(nrow(df) > 0, "No sessions match the current filters yet."))

  # ── OVERVIEW ────────────────────────────────────────────────────────────────
  output$plot_rt_time <- renderPlotly({
    df <- filtered(); need_data(df)
    df <- df %>% mutate(idx = row_number(),
      tip = paste0(participant_name, "<br>Avg ", avg_reaction_time_ms, " ms<br>Best ", best_reaction_time_ms, " ms"))
    plot_ly(df, x = ~idx) %>%
      add_trace(y = ~avg_reaction_time_ms, name = "Average", type = "scatter", mode = "lines+markers",
                line = list(color = CLR$orange, width = 3), marker = list(color = CLR$orange, size = 8),
                text = ~tip, hoverinfo = "text") %>%
      add_trace(y = ~best_reaction_time_ms, name = "Best", type = "scatter", mode = "lines+markers",
                line = list(color = CLR$cyan, width = 2, dash = "dot"), marker = list(color = CLR$cyan, size = 6),
                text = ~tip, hoverinfo = "text") %>%
      style_plot("Reaction time (ms)", "Session (chronological)")
  })

  output$plot_scatter <- renderPlotly({
    df <- filtered(); need_data(df)
    plot_ly(df, x = ~avg_reaction_time_ms, y = ~accuracy_pct, color = ~gender,
            colors = c(CLR$orange, CLR$cyan, CLR$green),
            type = "scatter", mode = "markers",
            marker = list(size = 12, opacity = 0.85, line = list(color = "rgba(255,255,255,0.25)", width = 1)),
            text = ~paste0(participant_name, "<br>", avg_reaction_time_ms, " ms<br>", accuracy_pct, "%"),
            hoverinfo = "text") %>%
      style_plot("Accuracy (%)", "Average reaction time (ms)")
  })

  output$plot_throughput <- renderPlotly({
    df <- filtered(); need_data(df)
    df <- df %>% mutate(idx = row_number())
    plot_ly(df, x = ~idx, y = ~hits_per_second, type = "bar",
            marker = list(color = CLR$cyan, line = list(color = CLR$surface2, width = 1)),
            text = ~paste0(participant_name, "<br>", hits_per_second, " hits/s"), hoverinfo = "text") %>%
      style_plot("Hits per second", "Session")
  })

  # ── REACTION TIME ────────────────────────────────────────────────────────────
  output$plot_dist <- renderPlotly({
    rts <- explode_rts(filtered()); validate(need(nrow(rts) > 0, "No reaction-time data yet."))
    plot_ly(rts, x = ~reaction_time_ms, type = "histogram", nbinsx = 30,
            marker = list(color = CLR$orange, line = list(color = CLR$surface2, width = 1)),
            hovertemplate = "%{x} ms: %{y}<extra></extra>") %>%
      layout(shapes = list(list(type = "line", x0 = mean(rts$reaction_time_ms), x1 = mean(rts$reaction_time_ms),
              y0 = 0, y1 = 1, yref = "paper", line = list(color = CLR$cyan, width = 2, dash = "dash")))) %>%
      add_annotations(x = mean(rts$reaction_time_ms), y = 1, yref = "paper",
              text = paste0("mean ", round(mean(rts$reaction_time_ms)), " ms"),
              showarrow = FALSE, font = list(color = CLR$cyan, size = 11), yshift = 8) %>%
      style_plot("Number of hits", "Reaction time (ms)")
  })

  output$plot_consistency <- renderPlotly({
    df <- filtered(); need_data(df)
    df <- df %>% mutate(idx = row_number())
    plot_ly(df, x = ~idx, y = ~sd_reaction_time_ms, type = "scatter", mode = "lines+markers",
            line = list(color = CLR$green, width = 2), marker = list(color = CLR$green, size = 7),
            text = ~paste0(participant_name, "<br>SD ", sd_reaction_time_ms, " ms"), hoverinfo = "text") %>%
      style_plot("SD of reaction time (ms)", "Session")
  })

  output$plot_fatigue <- renderPlotly({
    rts <- explode_rts(filtered()); validate(need(nrow(rts) > 0, "No reaction-time data yet."))
    agg <- rts %>% group_by(target_index) %>%
      summarise(mean_rt = mean(reaction_time_ms), .groups = "drop")
    plot_ly() %>%
      add_trace(data = rts, x = ~target_index, y = ~reaction_time_ms, type = "scatter", mode = "markers",
                marker = list(color = "rgba(255,107,0,0.35)", size = 6), name = "hits", hoverinfo = "skip") %>%
      add_trace(data = agg, x = ~target_index, y = ~mean_rt, type = "scatter", mode = "lines+markers",
                line = list(color = CLR$cyan, width = 3), marker = list(color = CLR$cyan, size = 7),
                name = "mean", text = ~paste0("Target ", target_index, "<br>", round(mean_rt), " ms"),
                hoverinfo = "text") %>%
      style_plot("Reaction time (ms)", "Target order within session")
  })

  # ── GROUP COMPARISON ──────────────────────────────────────────────────────────
  output$plot_gender <- renderPlotly({
    df <- filtered(); need_data(df)
    plot_ly(df, x = ~gender, y = ~avg_reaction_time_ms, color = ~gender,
            colors = c(CLR$orange, CLR$cyan, CLR$green), type = "box",
            boxpoints = "all", jitter = 0.4, pointpos = 0,
            marker = list(size = 6, opacity = 0.6)) %>%
      style_plot("Average reaction time (ms)", "") %>% layout(showlegend = FALSE)
  })

  output$plot_age <- renderPlotly({
    df <- filtered(); need_data(df)
    if (!"age_band" %in% names(df)) return(plotly_empty())
    agg <- df %>% filter(!is.na(age_band)) %>% group_by(age_band) %>%
      summarise(mean_rt = mean(avg_reaction_time_ms, na.rm = TRUE), n = n(), .groups = "drop")
    plot_ly(agg, x = ~age_band, y = ~mean_rt, type = "bar",
            marker = list(color = CLR$orange, line = list(color = CLR$cyan, width = 1)),
            text = ~paste0(round(mean_rt), " ms<br>n=", n), hoverinfo = "text",
            textposition = "none") %>%
      style_plot("Mean reaction time (ms)", "Age band")
  })

  output$plot_leaderboard <- renderPlotly({
    df <- filtered(); need_data(df)
    lb <- df %>% group_by(participant_name) %>%
      summarise(best = min(best_reaction_time_ms, na.rm = TRUE), .groups = "drop") %>%
      arrange(best) %>% head(10) %>% mutate(participant_name = factor(participant_name, levels = rev(participant_name)))
    plot_ly(lb, x = ~best, y = ~participant_name, type = "bar", orientation = "h",
            marker = list(color = CLR$cyan, line = list(color = CLR$orange, width = 1)),
            text = ~paste0(best, " ms"), hoverinfo = "text", textposition = "auto") %>%
      style_plot("Best reaction time (ms)", "")
  })

  # ── TABLE ──────────────────────────────────────────────────────────────────────
  output$table <- renderDT({
    df <- filtered(); need_data(df)
    cols <- intersect(c("access_timestamp_local", "participant_name", "gender", "age",
                        "score", "misses", "accuracy_pct", "avg_reaction_time_ms",
                        "best_reaction_time_ms", "median_reaction_time_ms",
                        "sd_reaction_time_ms", "hits_per_second"), names(df))
    datatable(df[, cols, drop = FALSE], rownames = FALSE,
              colnames = gsub("_", " ", cols),
              options = list(pageLength = 12, dom = "ftip",
                             columnDefs = list(list(className = "dt-center", targets = "_all")))) 
  })
}

shinyApp(ui, server)
