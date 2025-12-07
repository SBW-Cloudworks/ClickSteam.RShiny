.libPaths(c("/home/shiny/R/x86_64-pc-linux-gnu-library/4.1", .libPaths()))
cat("APP .libPaths():\n"); print(.libPaths())
library(shiny)
library(DBI)
library(RPostgres)
library(dplyr)
library(ggplot2)
library(lubridate)
library(pool)

# ---- DB config (demo: hard-code, EC2 này private) ----
PG_DB   <- "clickstream_dw"
PG_HOST <- "127.0.0.1"      # vì Postgres nằm cùng EC2
PG_PORT <- 5432L
PG_USER <- "postgres"
PG_PASS <- "sbw@123"
PG_SSL  <- "disable"
TB      <- "clickstream_events"   # bảng DWH của bạn

# ---- DB pool ----
pool <- dbPool(
  drv      = RPostgres::Postgres(),
  dbname   = PG_DB,
  host     = PG_HOST,
  port     = PG_PORT,
  user     = PG_USER,
  password = PG_PASS,
  sslmode  = PG_SSL
)

onStop(function() {
  poolClose(pool)
})

# ---- Helper: fetch data theo date range + login_state ----

fetch_events <- function(start_ts, end_ts, login_state = "ALL") {
  base_sql <- paste0(
    "SELECT ",
    "  event_timestamp, ",
    "  event_name, ",
    "  user_login_state, ",
    "  client_id, ",
    "  session_id, ",
    "  is_first_visit, ",
    "  context_product_id              AS product_id, ",
    "  context_product_name            AS product_name, ",
    "  context_product_category        AS product_category, ",
    "  context_product_brand           AS product_brand, ",
    "  context_product_price::numeric  AS product_price, ",
    "  context_product_discount_price  AS product_discount_price, ",
    "  context_product_url_path        AS product_url_path ",
    "FROM ", TB, " ",
    "WHERE event_timestamp >= $1 AND event_timestamp < $2 "
  )
  
  if (login_state != "ALL") {
    sql <- paste0(base_sql, "AND user_login_state = $3")
    DBI::dbGetQuery(pool, sql, params = list(start_ts, end_ts, login_state))
  } else {
    DBI::dbGetQuery(pool, base_sql, params = list(start_ts, end_ts))
  }
}

#UI
ui <- fluidPage(
  # CSS tổng thể
  tags$head(
    tags$style(HTML("
      body {
        background-color: #f4f6fb;
        font-family: -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;
      }
      h2 {
        font-weight: 700;
        font-size: 26px;
        margin-bottom: 10px;
        color: #111827;
      }

      /* Sidebar (filter) */
      .well {
        background-color: #ffffff !important;
        border-radius: 14px !important;
        border: none !important;
        box-shadow: 0 2px 8px rgba(15, 23, 42, 0.08);
      }

      /* Card chính bên phải */
      .tab-content {
        background-color: #ffffff;
        border-radius: 14px;
        padding: 16px 24px 24px 24px;
        box-shadow: 0 2px 8px rgba(15, 23, 42, 0.08);
      }

      /* Tabs */
      .nav-tabs>li>a {
        font-weight: 600;
        font-size: 14px;
        color: #6b7280;
      }
      .nav-tabs>li>a:hover {
        color: #2563eb;
      }
      .nav-tabs>li.active>a,
      .nav-tabs>li.active>a:focus,
      .nav-tabs>li.active>a:hover {
        color: #2563eb;
        border-color: #e5e7eb #e5e7eb transparent;
        border-top-width: 3px;
      }

      .shiny-plot-output {
        margin-bottom: 24px;
      }
      .control-label {
        font-weight: 600;
      }

      /* Nút bấm */
      .btn,
      .action-button {
        border-radius: 999px !important;
        font-weight: 500;
      }
      .btn-default,
      .action-button {
        background-color: #e5edff;
        border-color: #c7d2fe;
        color: #1d4ed8;
      }
      .btn-default:hover,
      .action-button:hover {
        background-color: #d4e1ff;
        border-color: #a5b4fc;
        color: #1d4ed8;
      }

      /* Bảng */
      table {
        font-size: 13px;
        width: 100%;
      }
      th, td {
        white-space: nowrap;
      }
      thead th {
        background-color: #eef2ff;
        border-bottom: 1px solid #e5e7eb;
        font-weight: 600;
        color: #374151;
      }
      .table>tbody>tr:nth-child(even)>td,
      .table>tbody>tr:nth-child(even)>th {
        background-color: #f9fafb;
      }
      .table>tbody>tr:hover>td,
      .table>tbody>tr:hover>th {
        background-color: #e5f2ff;
      }

      #page_info {
        font-weight: 600;
        text-align: right;
        padding-top: 8px;
        color: #4b5563;
      }

      /* KPI cards */
      .kpi-card {
        background-color: #ffffff;
        border-radius: 16px;
        padding: 14px 18px;
        box-shadow: 0 1px 6px rgba(15,23,42,0.08);
        border: 1px solid #e5e7eb;
        margin-bottom: 16px;
      }
      .kpi-title {
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: #6b7280;
        margin-bottom: 4px;
      }
      .kpi-value {
        font-size: 24px;
        font-weight: 700;
        color: #111827;
        margin-bottom: 2px;
      }
      .kpi-sub {
        font-size: 11px;
        color: #9ca3af;
        margin-bottom: 0;
      }
    "))
  ),
  
  titlePanel("SBW Clickstream Dashboard"),
  
  sidebarLayout(
    sidebarPanel(
      dateRangeInput(
        "dr", "Date range",
        start = Sys.Date() - 7,
        end   = Sys.Date()
      ),
      selectInput(
        "login",
        "user_login_state",
        choices  = c("ALL", "logged_in", "anonymous"),
        selected = "ALL"
      )
    ),
    
    mainPanel(
      tabsetPanel(
        # ==== OVERVIEW TAB ====
        tabPanel(
          "Overview",
          
          # Hàng KPI trên cùng
          fluidRow(
            column(
              4,
              div(
                class = "kpi-card",
                div(class = "kpi-title", "Total events"),
                div(class = "kpi-value", textOutput("kpi_total_events")),
                div(class = "kpi-sub", "Trong khoảng thời gian đã chọn")
              )
            ),
            column(
              4,
              div(
                class = "kpi-card",
                div(class = "kpi-title", "Unique clients"),
                div(class = "kpi-value", textOutput("kpi_unique_clients")),
                div(class = "kpi-sub", "Số client_id khác nhau")
              )
            ),
            column(
              4,
              div(
                class = "kpi-card",
                div(class = "kpi-title", "Checkout rate"),
                div(class = "kpi-value", textOutput("kpi_checkout_rate")),
                div(class = "kpi-sub", "% checkout_complete / add_to_cart_click")
              )
            )
          ),
          
          br(),
          
          # Hàng 2 biểu đồ cạnh nhau
          fluidRow(
            column(6, plotOutput("p_events_over_time", height = 320)),
            column(6, plotOutput("p_event_mix",         height = 320))
          ),
          
          br(),
          
          # Biểu đồ events theo user_login_state
          fluidRow(
            column(12, plotOutput("p_event_by_login", height = 300))
          )
        ),
        
        # ==== PRODUCTS TAB ====
        tabPanel(
          "Products",
          plotOutput("p_top_category", height = 300),
          plotOutput("p_top_brand",    height = 300)
        ),
        
        # ==== RAW SAMPLE TAB ====
        tabPanel(
          "Raw sample",
          fluidRow(
            column(3, actionButton("prev_page", "Prev")),
            column(3, actionButton("next_page", "Next")),
            column(6, textOutput("page_info"))
          ),
          br(),
          div(
            style = "
              max-height: 600px;
              overflow-y: auto;
              overflow-x: auto;
              border-radius: 12px;
              border: 1px solid #e5e7eb;
              background-color: #ffffff;
            ",
            tableOutput("t_sample")
          )
        )
      )
    )
  )
)


# ---- Server ----
server <- function(input, output, session) {
  #Page size cho Raw sample
  page_size <- 20L
  current_page <- reactiveVal(1L)
  # Khi đổi date range hoặc login state thì reset về trang 1
  observeEvent(list(input$dr, input$login), {
    current_page(1L)
  })
  
  data <- reactive({
    # Tự động refresh dữ liệu mỗi 10 giây
    invalidateLater(10000, session)  # 10000 ms = 10s
    
    req(input$dr)
    
    start_ts <- as.POSIXct(input$dr[1], tz = "UTC")
    end_ts   <- as.POSIXct(input$dr[2] + 1, tz = "UTC")  # include end day
    
    df <- fetch_events(start_ts, end_ts, input$login)
    
    if (!nrow(df)) return(df)
    
    # Nếu driver trả về numeric (epoch), convert lại thành timestamp
    if (is.numeric(df$event_timestamp)) {
      df$event_timestamp <- as.POSIXct(
        df$event_timestamp,
        origin = "1970-01-01",
        tz = "UTC"
      )
    }
    
    df
  })
  
  
  # Dữ liệu cho tab Raw sample: chỉ giữ event có product
  raw_df <- reactive({
    df <- data()
    if (!nrow(df)) return(df)
    
    # Chỉ lấy những dòng có product_id hoặc product_name
    df <- df %>% dplyr::filter(!is.na(product_id) | !is.na(product_name))
    
    # Sắp xếp: mới nhất trước (giảm dần theo event_timestamp)
    df <- df %>% dplyr::arrange(dplyr::desc(event_timestamp))
    
    df
  })
  
  # --- Metrics cho KPI cards ---
  metrics <- reactive({
    df <- data()
    if (!nrow(df)) {
      return(list(
        total_events      = 0L,
        unique_clients    = 0L,
        checkout_rate_txt = "0 %"
      ))
    }
    
    total_events   <- nrow(df)
    unique_clients <- dplyr::n_distinct(df$client_id)
    
    add_to_cart       <- sum(df$event_name == "add_to_cart_click", na.rm = TRUE)
    checkout_complete <- sum(df$event_name == "checkout_complete", na.rm = TRUE)
    
    checkout_rate <- if (add_to_cart > 0) {
      round(checkout_complete / add_to_cart * 100, 1)
    } else {
      0
    }
    
    list(
      total_events      = total_events,
      unique_clients    = unique_clients,
      checkout_rate_txt = paste0(checkout_rate, " %")
    )
  })
  
  output$kpi_total_events <- renderText({
    m <- metrics()
    format(m$total_events, big.mark = ",")
  })
  
  output$kpi_unique_clients <- renderText({
    m <- metrics()
    format(m$unique_clients, big.mark = ",")
  })
  
  output$kpi_checkout_rate <- renderText({
    m <- metrics()
    m$checkout_rate_txt
  })
  
  
  # 1) Events over time (daily)
  output$p_events_over_time <- renderPlot({
    df <- data()
    req(nrow(df) > 0)
    
    df2 <- df %>%
      mutate(day = as.Date(event_timestamp)) %>%
      count(day, name = "events")
    
    ggplot(df2, aes(x = day, y = events)) +
      geom_line(color = "#2563eb", size = 1.4) +
      geom_point(color = "#1d4ed8", size = 3) +
      scale_x_date(date_labels = "%d %b", date_breaks = "1 day") +
      labs(
        x = "Day",
        y = "Events",
        title = "Events over time"
      ) +
      theme_minimal(base_size = 14) +
      theme(
        plot.title = element_text(face = "bold", size = 18,
                                  margin = margin(b = 8)),
        axis.title = element_text(face = "bold", size = 13),
        axis.text  = element_text(size = 12),
        panel.grid.minor = element_blank()
      )
  })
  
  
  # 2) Event mix (top 10 event_name)
  output$p_event_mix <- renderPlot({
    df <- data()
    req(nrow(df) > 0)
    
    top <- df %>%
      count(event_name, sort = TRUE) %>%
      slice_head(n = 10)
    
    ggplot(top, aes(x = reorder(event_name, n), y = n)) +
      geom_col(fill = "#22c55e") +
      geom_text(aes(label = n), hjust = -0.15, size = 4) +
      coord_flip(clip = "off") +
      expand_limits(y = max(top$n) * 1.15) +
      labs(
        x = "Event name",
        y = "Count",
        title = "Top 10 event types"
      ) +
      theme_minimal(base_size = 14) +
      theme(
        plot.title = element_text(face = "bold", size = 18,
                                  margin = margin(b = 8)),
        axis.title = element_text(face = "bold", size = 13),
        axis.text  = element_text(size = 12)
      )
  })
  
  # 3) Events theo user_login_state
  output$p_event_by_login <- renderPlot({
    df <- data()
    req(nrow(df) > 0)
    
    df2 <- df %>%
      dplyr::mutate(
        user_login_state = ifelse(
          is.na(user_login_state) | user_login_state == "",
          "UNKNOWN",
          user_login_state
        )
      ) %>%
      dplyr::count(user_login_state, name = "events") %>%
      dplyr::arrange(dplyr::desc(events))
    
    ggplot(df2, aes(x = reorder(user_login_state, events), y = events)) +
      geom_col(fill = "#6366f1") +
      geom_text(aes(label = events), hjust = -0.15, size = 4) +
      coord_flip(clip = "off") +
      expand_limits(y = max(df2$events) * 1.15) +
      labs(
        x = "user_login_state",
        y = "Events",
        title = "Events by user_login_state"
      ) +
      theme_minimal(base_size = 14) +
      theme(
        plot.title = element_text(face = "bold", size = 18,
                                  margin = margin(b = 8)),
        axis.title = element_text(face = "bold", size = 13),
        axis.text  = element_text(size = 12)
      )
  })
  
  # 4) Top categories (by events)
  output$p_top_category <- renderPlot({
    df <- raw_df()   # chỉ lấy event có product
    req(nrow(df) > 0)
    
    top <- df %>%
      mutate(
        product_category = ifelse(
          is.na(product_category) | product_category == "",
          "UNKNOWN",
          product_category
        )
      ) %>%
      count(product_category, sort = TRUE) %>%
      slice_head(n = 10)
    
    ggplot(top, aes(x = reorder(product_category, n), y = n)) +
      geom_col(fill = "#38bdf8") +
      geom_text(aes(label = n), hjust = -0.15, size = 4) +
      coord_flip(clip = "off") +
      expand_limits(y = max(top$n) * 1.15) +
      labs(
        x = "Category",
        y = "Events",
        title = "Top categories (by events)"
      ) +
      theme_minimal(base_size = 14) +
      theme(
        plot.title = element_text(face = "bold", size = 18,
                                  margin = margin(b = 8)),
        axis.title = element_text(face = "bold", size = 13),
        axis.text  = element_text(size = 12)
      )
  })
  
  
  # 5) Top brands (by events)
  output$p_top_brand <- renderPlot({
    df <- raw_df()
    req(nrow(df) > 0)
    
    top <- df %>%
      mutate(
        product_brand = ifelse(
          is.na(product_brand) | product_brand == "",
          "UNKNOWN",
          product_brand
        )
      ) %>%
      count(product_brand, sort = TRUE) %>%
      slice_head(n = 10)
    
    ggplot(top, aes(x = reorder(product_brand, n), y = n)) +
      geom_col(fill = "#a855f7") +
      geom_text(aes(label = n), hjust = -0.15, size = 4) +
      coord_flip(clip = "off") +
      expand_limits(y = max(top$n) * 1.15) +
      labs(
        x = "Brand",
        y = "Events",
        title = "Top brands (by events)"
      ) +
      theme_minimal(base_size = 14) +
      theme(
        plot.title = element_text(face = "bold", size = 18,
                                  margin = margin(b = 8)),
        axis.title = element_text(face = "bold", size = 13),
        axis.text  = element_text(size = 12)
      )
  })
  
  # Thêm trang
  observeEvent(input$next_page, {
    df <- raw_df()
    req(nrow(df) > 0)
    max_page <- ceiling(nrow(df) / page_size)
    if (current_page() < max_page) {
      current_page(current_page() + 1L)
    }
  })
  
  observeEvent(input$prev_page, {
    df <- raw_df()
    req(nrow(df) > 0)
    if (current_page() > 1L) {
      current_page(current_page() - 1L)
    }
  })
  
  output$page_info <- renderText({
    df <- raw_df()
    if (!nrow(df)) return("No data")
    max_page <- ceiling(nrow(df) / page_size)
    paste("Page", current_page(), "of", max_page)
  })
  
  
  # Bảng sample dữ liệu (paging + chỉ event có product)
  output$t_sample <- renderTable({
    df <- raw_df()
    if (!nrow(df)) return(df)
    
    # raw_df đã sort & filter rồi, chỉ cần format lại timestamp
    df$event_timestamp <- format(df$event_timestamp, "%Y-%m-%d %H:%M:%S")
    
    # Pagination
    start <- (current_page() - 1L) * page_size + 1L
    end   <- min(current_page() * page_size, nrow(df))
    
    df[start:end, , drop = FALSE]
  })
  
}

shinyApp(ui, server)