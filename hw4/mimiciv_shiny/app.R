library(shiny)
library(tidyverse)
library(gtsummary)
library(plotly)
library(bigrquery)
library(dotenv)


# Load the preprocessed cohort data ONCE
mimic_icu_cohort <- read_rds("mimic_icu_cohort.rds")

# load_dot_env(".env")
# con <- bigrquery::bq_auth(path = Sys.getenv("BIGQUERY_KEY"))
library(shiny)
library(tidyverse)
library(gtsummary)
library(plotly)

mimic_icu_cohort <- read_rds("mimic_icu_cohort.rds")

ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      body {
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        background-color: #f5f7fa;
      }
      .title-section {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        padding: 30px;
        border-radius: 8px;
        margin-bottom: 30px;
        box-shadow: 0 4px 6px rgba(0,0,0,0.1);
      }
      .title-section h1 { margin: 0; font-size: 2.5em; font-weight: 600; }
      .title-section p { margin: 10px 0 0 0; font-size: 1.1em; opacity: 0.95; }
      .sidebar-section { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
      .stat-box { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); border-left: 4px solid #667eea; }
      .info-badge { display: inline-block; background: #667eea; color: white; padding: 5px 10px; border-radius: 20px; font-size: 0.85em; margin-right: 10px; }
    "))
  ),
  
  div(class = "title-section",
      h1("🏥 MIMIC-IV ICU Cohort Explorer"),
      p("Interactive exploration of demographic, vital sign, and laboratory data"),
      br(),
      span(class = "info-badge", paste0("Total Patients: ", nrow(mimic_icu_cohort))),
      span(class = "info-badge", paste0("Prolonged Stay: ", sum(mimic_icu_cohort$los_long == TRUE), " (", 
                                        round(mean(mimic_icu_cohort$los_long == TRUE)*100, 1), "%)"))
  ),
  
  tabsetPanel(
    tabPanel("Cohort Summary",
             sidebarLayout(
               sidebarPanel(
                 div(class = "sidebar-section",
                     h4("📊 Filters", style = "color: #667eea; margin-top: 0;"),
                     radioButtons("var_type", "Data Type:",
                                  choices = c("Demographics" = "demo", "Vitals" = "vitals", "Labs" = "labs"),
                                  selected = "demo"),
                     hr(),
                     checkboxInput("filter_los", "📌 Prolonged Stay Only", FALSE),
                     sliderInput("age_range", "👥 Age Range:", min = 18, max = 100, value = c(18, 100), step = 1),
                     hr(),
                     div(style = "background: #f0f0f0; padding: 10px; border-radius: 6px;",
                         h6("Active Filters:", style = "margin-top: 0; color: #333;"),
                         textOutput("filter_summary"),
                         style = "font-size: 0.9em; color: #666;")
                 )
               ),
               mainPanel(
                 # Demographics
                 conditionalPanel(
                   condition = "input.var_type == 'demo'",
                   tabsetPanel(
                     tabPanel("📋 Summary Table", gt::gt_output("numerical_summary")),
                     tabPanel("📈 Distribution", 
                              uiOutput("dist_checkboxes"),
                              plotlyOutput("distribution_plot", height = "500px"))
                   )
                 ),
                 
                 # Vitals
                 conditionalPanel(
                   condition = "input.var_type == 'vitals'",
                   tabsetPanel(
                     tabPanel("📋 Summary Table", gt::gt_output("numerical_summary")),
                     tabPanel("📈 Distribution", 
                              uiOutput("dist_checkboxes"),
                              plotlyOutput("distribution_plot", height = "500px")),
                     tabPanel("📈 Vitals Trends",
                              selectInput("strat_group", "Group by:",
                                          choices = c("Age Group" = "age_group",
                                                      "Gender" = "gender",
                                                      "Race" = "race",
                                                      "Insurance" = "insurance",
                                                      "Marital Status" = "marital_status")),
                              plotlyOutput("vitals_lineplot", height = "500px"))
                   )
                 ),
                 
                 # Labs
                 conditionalPanel(
                   condition = "input.var_type == 'labs'",
                   tabsetPanel(
                     tabPanel("📋 Summary Table", gt::gt_output("numerical_summary")),
                     tabPanel("📈 Distribution", 
                              uiOutput("dist_checkboxes"),
                              plotlyOutput("distribution_plot", height = "500px")),
                     tabPanel("📦 Boxplots by Group",
                              selectInput("strat_group", "Group by:",
                                          choices = c("Age Group" = "age_group",
                                                      "Gender" = "gender",
                                                      "Race" = "race",
                                                      "Insurance" = "insurance",
                                                      "Marital Status" = "marital_status")),
                              plotlyOutput("boxplot_strat", height = "500px"))
                   )
)) )
server <- function(input, output, session) {
  
  # Filter data
  filt_data <- reactive({
    data <- mimic_icu_cohort %>%
      filter(age_intime >= input$age_range[1] & age_intime <= input$age_range[2])
    if (input$filter_los) data <- data %>% filter(los_long == TRUE)
    data
  })
  
  output$filter_summary <- renderText({
    paste0("<strong>", nrow(filt_data()), "</strong> patients | Ages ", 
           input$age_range[1], "-", input$age_range[2])
  })
  
  # Summary Table
  output$numerical_summary <- gt::render_gt({
    if (input$var_type == "demo") {
      filt_data() %>%
        select(gender, race, age_intime, insurance, marital_status, los_long) %>%
        tbl_summary(label = list(gender ~ "Gender", race ~ "Race", age_intime ~ "Age",
                                 insurance ~ "Insurance", marital_status ~ "Marital Status",
                                 los_long ~ "Prolonged Stay"),
                    missing = "ifany") %>% as_gt()
    } else if (input$var_type == "vitals") {
      filt_data() %>%
        select(heart_rate, systolic_bp, diastolic_bp, temp_f, resp_rate) %>%
        tbl_summary(label = list(heart_rate ~ "HR", systolic_bp ~ "SBP",
                                 diastolic_bp ~ "DBP", temp_f ~ "Temp", resp_rate ~ "RR"),
                    type = list(everything() ~ "continuous"),
                    statistic = all_continuous() ~ "{mean} ({sd})",
                    missing = "ifany") %>% as_gt()
    } else {
      filt_data() %>%
        select(creatinine, wbc, glucose, albumin, potassium, sodium, chloride, bicarbonate) %>%
        tbl_summary(type = list(everything() ~ "continuous"),
                    statistic = all_continuous() ~ "{mean} ({sd})",
                    missing = "ifany") %>% as_gt()
    }
  })
  

  output$dist_checkboxes <- renderUI({
    if (input$var_type == "demo") {
      choices <- c("Gender" = "gender", "Race" = "race", "Age" = "age_intime",
                   "Insurance" = "insurance", "Marital Status" = "marital_status")
    } else if (input$var_type == "vitals") {
      choices <- c("Heart Rate" = "heart_rate", "Systolic BP" = "systolic_bp",
                   "Diastolic BP" = "diastolic_bp", "Temperature" = "temp_f",
                   "Respiratory Rate" = "resp_rate")
    } else {
      choices <- c("Creatinine" = "creatinine", "WBC" = "wbc", "Glucose" = "glucose",
                   "Albumin" = "albumin", "Potassium" = "potassium",
                   "Sodium" = "sodium", "Chloride" = "chloride", "Bicarbonate" = "bicarbonate")
    }
    
    checkboxGroupInput(
      "dist_vars",
      "Select variables to visualize:",
      choices = choices,
      selected = choices[1]
    )
  })
  
 
  # Hide the actual checkboxes
  output$dist_checkboxes <- renderUI({
    if (input$var_type == "demo") {
      vars <- c("gender", "race", "age_intime", "insurance", "marital_status")
      labels <- c("Gender", "Race", "Age", "Insurance", "Marital Status")
    } else if (input$var_type == "vitals") {
      vars <- c("heart_rate", "systolic_bp", "diastolic_bp", "temp_f", "resp_rate")
      labels <- c("Heart Rate", "Systolic BP", "Diastolic BP", "Temperature", "Respiratory Rate")
    } else {
      vars <- c("creatinine", "wbc", "glucose", "albumin", "potassium", "sodium", "chloride", "bicarbonate")
      labels <- c("Creatinine", "WBC", "Glucose", "Albumin", "Potassium", "Sodium", "Chloride", "Bicarbonate")
    }
    
    div(
      h5("Select a variable to visualize:"),
      fluidRow(
        lapply(seq_along(vars), function(i) {
          col_width <- if(length(vars) <= 3) 4 else if(length(vars) <= 5) 3 else 2
          column(col_width,
                 actionButton(paste0("dist_btn_", vars[i]), labels[i],
                              class = if(vars[i] %in% input$dist_vars) "btn btn-primary btn-block" else "btn btn-default btn-block",
                              width = "100%")
          )
        })
      ),
      # Hidden checkbox for tracking state
      checkboxGroupInput("dist_vars", label = NULL, choices = structure(vars, names = labels),
                         selected = if(input$var_type == "demo") "gender" else if(input$var_type == "vitals") "heart_rate" else "creatinine",
                         inline = FALSE)
    )
  })
  
  # Statistics checkboxes - only continuous
  # Distribution checkboxes
  output$dist_checkboxes <- renderUI({
    if (input$var_type == "demo") {
      choices <- c("Gender" = "gender", "Race" = "race", "Age" = "age_intime",
                   "Insurance" = "insurance", "Marital Status" = "marital_status")
    } else if (input$var_type == "vitals") {
      choices <- c("Heart Rate" = "heart_rate", "Systolic BP" = "systolic_bp",
                   "Diastolic BP" = "diastolic_bp", "Temperature" = "temp_f",
                   "Respiratory Rate" = "resp_rate")
    } else {
      choices <- c("Creatinine" = "creatinine", "WBC" = "wbc", "Glucose" = "glucose",
                   "Albumin" = "albumin", "Potassium" = "potassium",
                   "Sodium" = "sodium", "Chloride" = "chloride", "Bicarbonate" = "bicarbonate")
    }
    
    checkboxGroupInput("dist_vars", "Select variables to visualize:",
                       choices = choices,
                       selected = names(choices)[1])
  })
  
  # Distribution Plot
  output$distribution_plot <- renderPlotly({
    if (is.null(input$dist_vars) || length(input$dist_vars) == 0) return(NULL)
    
    # Color palettes
    gender_colors <- c("F" = "#FF6B9D", "M" = "#4A90E2")
    race_colors <- c("ASIAN" = "#667eea", "BLACK" = "#FF6B9D", "HISPANIC" = "#FFA500", 
                     "WHITE" = "#4A90E2", "Other" = "#50C878")
    insurance_colors <- c("Medicare" = "#667eea", "Private" = "#FF6B9D", "Medicaid" = "#FFA500", 
                          "Other" = "#4A90E2", "No charge" = "#90EE90")
    marital_colors <- c("DIVORCED" = "#667eea", "MARRIED" = "#FF6B9D", "SINGLE" = "#4A90E2", 
                        "WIDOWED" = "#FFA500")
    
    # Nice labels
    var_labels <- list(
      age_intime = "Age at ICU Entry",
      gender = "Gender",
      race = "Race",
      insurance = "Insurance Type",
      marital_status = "Marital Status",
      heart_rate = "Heart Rate (bpm)",
      systolic_bp = "Systolic BP (mmHg)",
      diastolic_bp = "Diastolic BP (mmHg)",
      temp_f = "Temperature (°F)",
      resp_rate = "Respiratory Rate (breaths/min)",
      creatinine = "Creatinine (mg/dL)",
      wbc = "WBC (K/µL)",
      glucose = "Glucose (mg/dL)",
      albumin = "Albumin (g/dL)",
      potassium = "Potassium (mEq/L)",
      sodium = "Sodium (mEq/L)",
      chloride = "Chloride (mEq/L)",
      bicarbonate = "Bicarbonate (mEq/L)"
    )
    
    # Create one plot per selected variable
    var <- input$dist_vars[1]  # Show first selected variable
    data_plot <- filt_data() %>% filter(!is.na(.[[var]]))
    if (nrow(data_plot) == 0) return(NULL)
    
    var_label <- var_labels[[var]] %||% var
    
    if (var %in% c("age_intime", "heart_rate", "systolic_bp", "diastolic_bp", "temp_f", "resp_rate",
                   "creatinine", "wbc", "glucose", "albumin", "potassium", "sodium", "chloride", "bicarbonate")) {
      # Continuous - histogram with mean/median
      mean_val <- mean(data_plot[[var]], na.rm = TRUE)
      median_val <- median(data_plot[[var]], na.rm = TRUE)
      max_count <- max(hist(data_plot[[var]], breaks = 20, plot = FALSE)$counts)
      
      plot_ly(data_plot, x = as.formula(paste0("~`", var, "`"))) %>%
        add_histogram(nbinsx = 20, marker = list(color = "#667eea", line = list(width = 1, color = "white")),
                      name = "Count", hovertemplate = "<b>Value: %{x}</b><br>Count: %{y}<extra></extra>") %>%
        add_trace(x = c(mean_val, mean_val), y = c(0, max_count), 
                  type = "scatter", mode = "lines", line = list(color = "#FF6B9D", width = 3),
                  name = sprintf("Mean: %.2f", mean_val), hoverinfo = "skip") %>%
        add_trace(x = c(median_val, median_val), y = c(0, max_count),
                  type = "scatter", mode = "lines", line = list(color = "#FFA500", width = 3, dash = "dash"),
                  name = sprintf("Median: %.2f", median_val), hoverinfo = "skip") %>%
        layout(title = var_label,
               xaxis = list(title = ""), yaxis = list(title = "Count"),
               legend = list(x = 0.65, y = 0.95, bgcolor = "rgba(255,255,255,0.9)"))
    } else {
      # Categorical - bar chart
      count_data <- data_plot %>% group_by(.data[[var]]) %>% 
        summarise(n = n(), .groups = "drop") %>%
        rename(category = !!sym(var)) %>%
        mutate(category = as.character(category))
      
      # Assign colors
      if (var == "gender") {
        count_data$color <- sapply(count_data$category, function(x) gender_colors[x] %||% "#667eea")
        count_data$legend_label <- ifelse(count_data$category == "F", "Female", "Male")
      } else if (var == "race") {
        count_data$color <- sapply(count_data$category, function(x) race_colors[x] %||% "#667eea")
        count_data$legend_label <- count_data$category
      } else if (var == "insurance") {
        count_data$color <- sapply(count_data$category, function(x) insurance_colors[x] %||% "#667eea")
        count_data$legend_label <- count_data$category
      } else if (var == "marital_status") {
        count_data$color <- sapply(count_data$category, function(x) marital_colors[x] %||% "#667eea")
        count_data$legend_label <- count_data$category
      } else {
        count_data$color <- "#667eea"
        count_data$legend_label <- count_data$category
      }
      
      plot_ly(count_data, x = ~category, y = ~n, type = "bar",
              marker = list(color = ~color, line = list(color = "white", width = 2)),
              name = ~legend_label,
              hovertemplate = "<b>%{x}</b><br>Count: %{y}<extra></extra>") %>%
        layout(title = var_label,
               xaxis = list(title = ""), yaxis = list(title = "Count"),
               height = 400,
               legend = list(x = 0.65, y = 0.95, bgcolor = "rgba(255,255,255,0.9)"),
               showlegend = TRUE)
    }

  })
  
  output$boxplot_strat <- renderPlotly({
    
    data <- filt_data()
    
    # Set the group
    if(input$strat_group == "age_group"){
      data$group <- cut(data$age_intime,
                        breaks = c(18,40,60,80,100),
                        labels = c("18-40","41-60","61-80","80+"))
    } else{
      data$group <- data[[input$strat_group]]
    }
    
    # Set vars based on var_type
    vars <- if(input$var_type == "demo"){
      c("marital_status")  # add other demo vars if you want
    } else if(input$var_type == "vitals"){
      c("heart_rate","systolic_bp","diastolic_bp","resp_rate","temp_f")
    } else{
      c("creatinine","wbc","glucose","albumin","potassium","sodium")
    }
    
    plot_data <- data %>%
      select(group, all_of(vars)) %>%
      pivot_longer(-group)
    
    plot_ly(plot_data,
            x = ~group,
            y = ~value,
            color = ~name,
            type = "box") %>%
      layout(
        title = "Vitals/Labs/Demo by Group",
        xaxis = list(title = "Group"),
        yaxis = list(title = "Value")
      )
 
    
     })
  output$vitals_lineplot <- renderPlotly({
    req(filt_data())
    data <- filt_data()
    
    if(input$strat_group == "age_group"){
      data$group <- cut(data$age_intime,
                        breaks=c(18,40,60,80,100),
                        labels=c("18-40","41-60","61-80","80+"))
    } else{
      data$group <- data[[input$strat_group]]
    }
    
    vars <- c("heart_rate","systolic_bp","diastolic_bp","resp_rate","temp_f")
    
    plot_data <- data %>%
      pivot_longer(all_of(vars), names_to="vital", values_to="value") %>%
      group_by(group, vital) %>%
      summarise(mean_val = mean(value, na.rm=TRUE),
                sd_val = sd(value, na.rm=TRUE),
                .groups="drop")
    
    plot_ly(plot_data, 
            x = ~group, 
            y = ~mean_val, 
            color = ~vital, 
            type = 'scatter', 
            mode = 'lines+markers',
            error_y = list(array = ~sd_val)) %>%
      layout(title = "Vitals Across Groups",
             yaxis = list(title = "Mean ± SD"),
             xaxis = list(title = tools::toTitleCase(input$strat_group)))
  })
  
}

shinyApp(ui, server)