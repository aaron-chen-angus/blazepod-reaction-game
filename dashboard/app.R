# ─────────────────────────────────────────────────────────────
# Virtual BlazePod — Live R Shiny Dashboard
# Reads the Google Sheet written by the app and visualises it live.
# See R_SHINY_DASHBOARD.md for setup.
# ─────────────────────────────────────────────────────────────

library(shiny)
library(googlesheets4)
library(dplyr)
library(tidyr)
library(ggplot2)
library(lubridate)
library(DT)
library(jsonlite)
library(bslib)
library(scales)

# ── CONFIG ───────────────────────────────────────────────────
SHEET_ID   <- "1A76A9WlCKIuPKzYzwmjGy_9Dvkn7Hy0YeTLWh-YEmjM"  # BlazePod data sheet
SHEET_NAME <- "Data"                                    # logger tab name
REFRESH_MS <- 15000                                     # auto-refresh (ms)

# Read-only access to a link-shared sheet. For a private sheet use:
#   gs4_auth(path = "service-account.json")
gs4_deauth()

# ── DATA HELPERS ─────────────────────────────────────────────
read_sessions <- function() {
  df <- tryCatch(
    read_sheet(SHEET_ID, sheet = SHEET_NAME, col_types = "c"),
    error = function(e) NULL
  )
  if (is.null(df) || nrow(df) == 0) {
    return(tibble())
  }

  num_cols <- c("age", "score", "misses", "targets_presented", "accuracy_pct",
                "avg_reaction_time_ms", "best_reaction_time_ms",
                "worst_reaction_time_ms", "median_reaction_time_ms",
                "sd_reaction_time_ms", "hits_per_second", "session_duration_s")
  for (col in intersect(num_cols, names(df))) {
    df[[col]] <- suppressWarnings(as.numeric(df[[col]]))
  }

  if ("access_timestamp_iso" %in% names(df)) {
    df$access_time <- suppressWarnings(ymd_hms(df$access_timestamp_iso, quiet = TRUE))
  } else {
    df$access_time <- as.POSIXct(NA)
  }

  # Age band for group comparisons
  if ("age" %in% names(df)) {
    df$age_band <- cut(
      df$age,
      breaks = c(0, 12, 17, 24, 34, 44, 54, 64, Inf),
      labels = c("<13", "13-17", "18-24", "25-34", "35-44", "45-54", "55-64", "65+"),
      right = TRUE
    )
  }

  df %>% arrange(access_time)
}

# Long table of every individual reaction time (unpacks the JSON array column)
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
      target_index     = seq_along(vals),
      reaction_time_ms = vals
    )
  })
  bind_rows(rows)
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# ── UI ───────────────────────────────────────────────────────
ui <- page_sidebar(
  title = "Virtual BlazePod — Live Dashboard",
  theme = bs_theme(version = 5, bootswatch = "darkly",
                   primary = "#ff6b00", secondary = "#00e5ff"),
  sidebar = sidebar(
    width = 300,
    selectInput("participant", "Participant", choices = c("All"), selected = "All"),
    selectInput("gender", "Gender", choices = c("All"), selected = "All"),
    sliderInput("age_range", "Age range", min = 0, max = 120, value = c(0, 120)),
    dateRangeInput("date_range", "Access date range"),
    hr(),
    div(class = "text-muted small",
        sprintf("Auto-refresh every %.0f s", REFRESH_MS / 1000)),
    div(class = "text-muted small", textOutput("last_update", inline = TRUE))
  ),

  layout_columns(
    fill = FALSE,
    value_box("Sessions", textOutput("kpi_sessions"), theme = "primary"),
    value_box("Participants", textOutput("kpi_participants"), theme = "secondary"),
    value_box("Mean accuracy", textOutput("kpi_accuracy"), theme = "primary"),
    value_box("Mean best RT", textOutput("kpi_bestrt"), theme = "secondary")
  ),

  layout_columns(
    card(card_header("Reaction time over time"), plotOutput("plot_rt_time", height = 300)),
    card(card_header("Accuracy vs. average RT"), plotOutput("plot_scatter", height = 300))
  ),
  layout_columns(
    card(card_header("Reaction-time distribution"), plotOutput("plot_dist", height = 300)),
    card(card_header("Mean RT by group"), plotOutput("plot_group", height = 300))
  ),
  card(card_header("Sessions"), DTOutput("table"))
)

# ── SERVER ───────────────────────────────────────────────────
server <- function(input, output, session) {

  # Poll the sheet on an interval for live updates.
  raw_data <- reactivePoll(
    intervalMillis = REFRESH_MS,
    session = session,
    checkFunc = function() Sys.time(),   # time-based tick
    valueFunc = function() read_sessions()
  )

  # Keep filter choices in sync with the data.
  observe({
    df <- raw_data()
    if (nrow(df) == 0) return()
    updateSelectInput(session, "participant",
                      choices = c("All", sort(unique(na.omit(df$participant_name)))))
    updateSelectInput(session, "gender",
                      choices = c("All", sort(unique(na.omit(df$gender)))))
    if (all(is.na(df$access_time)) == FALSE) {
      rng <- range(as.Date(df$access_time), na.rm = TRUE)
      updateDateRangeInput(session, "date_range", start = rng[1], end = rng[2])
    }
  })

  filtered <- reactive({
    df <- raw_data()
    if (nrow(df) == 0) return(df)
    if (input$participant != "All") df <- df %>% filter(participant_name == input$participant)
    if (input$gender != "All")      df <- df %>% filter(gender == input$gender)
    if ("age" %in% names(df))
      df <- df %>% filter(is.na(age) | (age >= input$age_range[1] & age <= input$age_range[2]))
    if (!is.null(input$date_range) && !any(is.na(input$date_range))) {
      df <- df %>% filter(is.na(access_time) |
                            (as.Date(access_time) >= input$date_range[1] &
                             as.Date(access_time) <= input$date_range[2]))
    }
    df
  })

  output$last_update <- renderText(paste("Updated", format(Sys.time(), "%H:%M:%S")))

  # KPIs
  output$kpi_sessions <- renderText(as.character(nrow(filtered())))
  output$kpi_participants <- renderText({
    df <- filtered(); as.character(length(unique(na.omit(df$participant_name))))
  })
  output$kpi_accuracy <- renderText({
    df <- filtered()
    if (nrow(df) == 0) return("—")
    paste0(round(mean(df$accuracy_pct, na.rm = TRUE), 1), "%")
  })
  output$kpi_bestrt <- renderText({
    df <- filtered()
    if (nrow(df) == 0) return("—")
    paste0(round(mean(df$best_reaction_time_ms, na.rm = TRUE)), " ms")
  })

  # Reaction time over time
  output$plot_rt_time <- renderPlot({
    df <- filtered()
    validate(need(nrow(df) > 0, "No data yet."))
    df %>%
      mutate(idx = row_number()) %>%
      select(idx, access_time, avg_reaction_time_ms, best_reaction_time_ms) %>%
      pivot_longer(c(avg_reaction_time_ms, best_reaction_time_ms),
                   names_to = "metric", values_to = "ms") %>%
      ggplot(aes(x = idx, y = ms, colour = metric)) +
      geom_line(linewidth = 1) + geom_point(size = 2) +
      scale_colour_manual(values = c(avg_reaction_time_ms = "#ff6b00",
                                     best_reaction_time_ms = "#00e5ff"),
                          labels = c("Average", "Best")) +
      labs(x = "Session (chronological)", y = "Reaction time (ms)", colour = NULL) +
      theme_minimal(base_size = 13)
  })

  # Accuracy vs average RT
  output$plot_scatter <- renderPlot({
    df <- filtered()
    validate(need(nrow(df) > 0, "No data yet."))
    ggplot(df, aes(x = avg_reaction_time_ms, y = accuracy_pct, colour = gender)) +
      geom_point(size = 3, alpha = 0.8) +
      labs(x = "Average reaction time (ms)", y = "Accuracy (%)", colour = "Gender") +
      theme_minimal(base_size = 13)
  })

  # Distribution of all individual reaction times
  output$plot_dist <- renderPlot({
    rts <- explode_rts(filtered())
    validate(need(nrow(rts) > 0, "No reaction-time data yet."))
    ggplot(rts, aes(x = reaction_time_ms)) +
      geom_histogram(bins = 30, fill = "#ff6b00", colour = "#111d35") +
      labs(x = "Reaction time (ms)", y = "Count") +
      theme_minimal(base_size = 13)
  })

  # Mean RT by group (gender + age band)
  output$plot_group <- renderPlot({
    df <- filtered()
    validate(need(nrow(df) > 0, "No data yet."))
    df %>%
      group_by(gender) %>%
      summarise(mean_rt = mean(avg_reaction_time_ms, na.rm = TRUE), .groups = "drop") %>%
      ggplot(aes(x = reorder(gender, mean_rt), y = mean_rt, fill = gender)) +
      geom_col() +
      geom_text(aes(label = round(mean_rt)), vjust = -0.4, colour = "#e8eaf0") +
      labs(x = NULL, y = "Mean average RT (ms)") +
      guides(fill = "none") +
      theme_minimal(base_size = 13)
  })

  # Raw table
  output$table <- renderDT({
    df <- filtered()
    validate(need(nrow(df) > 0, "No data yet."))
    cols <- intersect(c("access_timestamp_local", "participant_name", "gender", "age",
                        "score", "misses", "accuracy_pct", "avg_reaction_time_ms",
                        "best_reaction_time_ms"), names(df))
    datatable(df[, cols, drop = FALSE], options = list(pageLength = 10), rownames = FALSE)
  })
}

shinyApp(ui, server)
