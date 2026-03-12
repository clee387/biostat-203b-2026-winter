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
                 )
               )
             )
    )
  )
)
server <- function(input, output, session) {
  
  # Filter data reactively
  filt_data <- reactive({
    data <- mimic_icu_cohort %>%
      filter(age_intime >= input$age_range[1] & age_intime <= input$age_range[2])
    if (input$filter_los) data <- data %>% filter(los_long == TRUE)
    data
  })
  
  # Active filters text
  output$filter_summary <- renderText({
    paste0("<strong>", nrow(filt_data()), "</strong> patients | Ages ", 
           input$age_range[1], "-", input$age_range[2])
  })
  
  # Summary Table
  output$numerical_summary <- gt::render_gt({
    data <- filt_data()
    if (input$var_type == "demo") {
      data %>%
        select(gender, race, age_intime, insurance, marital_status, los_long) %>%
        tbl_summary(
          label = list(
            gender ~ "Gender", race ~ "Race", age_intime ~ "Age",
            insurance ~ "Insurance", marital_status ~ "Marital Status",
            los_long ~ "Prolonged Stay"
          ),
          missing = "ifany"
        ) %>% as_gt()
    } else if (input$var_type == "vitals") {
      data %>%
        select(heart_rate, systolic_bp, diastolic_bp, temp_f, resp_rate) %>%
        tbl_summary(
          type = list(everything() ~ "continuous"),
          statistic = all_continuous() ~ "{mean} ({sd})",
          missing = "ifany"
        ) %>% as_gt()
    } else {
      data %>%
        select(creatinine, wbc, glucose, albumin, potassium, sodium, chloride, bicarbonate) %>%
        tbl_summary(
          type = list(everything() ~ "continuous"),
          statistic = all_continuous() ~ "{mean} ({sd})",
          missing = "ifany"
        ) %>% as_gt()
    }
  })
  
  # Distribution checkbox UI
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
      selected = names(choices)[1]
    )
  })
  
  # Distribution Plot
  output$distribution_plot <- renderPlotly({
    req(input$dist_vars)
    var <- input$dist_vars[1]
    data <- filt_data() %>% filter(!is.na(.[[var]]))
    if (nrow(data) == 0) return(NULL)
    
    # Continuous vs categorical
    continuous_vars <- c("age_intime","heart_rate","systolic_bp","diastolic_bp",
                         "temp_f","resp_rate","creatinine","wbc","glucose",
                         "albumin","potassium","sodium","chloride","bicarbonate")
    
    if (var %in% continuous_vars) {
      hist_data <- hist(data[[var]], breaks = 20, plot = FALSE)
      plot_ly(x = data[[var]], type = "histogram", nbinsx = 20,
              marker = list(color = "#667eea", line = list(width = 1, color = "white"))) %>%
        layout(title = var, xaxis = list(title = ""), yaxis = list(title = "Count"))
    } else {
      count_data <- data %>% count(!!sym(var))
      plot_ly(count_data, x = ~get(var), y = ~n, type = "bar",
              marker = list(color = "#667eea", line = list(color = "white", width = 1))) %>%
        layout(title = var, xaxis = list(title = ""), yaxis = list(title = "Count"))
    }
  })
  
  # Boxplots (labs & vitals)
  output$boxplot_strat <- renderPlotly({
    data <- filt_data()
    
    if(input$strat_group == "age_group"){
      data$group <- cut(data$age_intime,
                        breaks = c(18,40,60,80,100),
                        labels = c("18-40","41-60","61-80","80+"))
    } else{
      data$group <- data[[input$strat_group]]
    }
    
    vars <- if(input$var_type == "vitals"){
      c("heart_rate","systolic_bp","diastolic_bp","resp_rate","temp_f")
    } else{
      c("creatinine","wbc","glucose","albumin","potassium","sodium")
    }
    
    plot_data <- data %>% select(group, all_of(vars)) %>% pivot_longer(-group)
    
    plot_ly(plot_data, x = ~group, y = ~value, color = ~name, type = "box") %>%
      layout(title = "Vitals/Labs by Group", xaxis = list(title="Group"), yaxis = list(title="Value"))
  })
  
  # Vitals lineplot
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
    
    plot_ly(plot_data, x = ~group, y = ~mean_val, color = ~vital,
            type = 'scatter', mode = 'lines+markers',
            error_y = list(array = ~sd_val)) %>%
      layout(title = "Vitals Across Groups",
             yaxis = list(title = "Mean ± SD"),
             xaxis = list(title = tools::toTitleCase(input$strat_group)))
  })
  
}
shinyApp(ui, server)