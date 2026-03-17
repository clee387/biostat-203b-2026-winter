library(shiny)
library(tidyverse)
library(gtsummary)
library(plotly)
library(bigrquery)
library(DBI)
library(glue)
library(glmnet)
library(gt)

# ── Load data ─────────────────────────────────────────────────────────────────
app_data     <- readRDS("app_data.rds")
cohort       <- app_data$cohort
#cohort_raw   <- app_data$cohort_raw
lasso_model  <- app_data$lasso_model
model_vars   <- app_data$model_vars

# ── BQ connection ─────────────────────────────────────────────────────────────
bq_auth(path = "biostat-203b-2026-winter-92fefbfab477.json")
con_bq <- dbConnect(
  bigrquery::bigquery(),
  project = "biostat-203b-2025-winter",
  dataset = "mimiciv_3_1",
  billing = "biostat-203b-2025-winter"
)
bq_query <- function(sql) dbGetQuery(con_bq, sql)

# ── Colors ────────────────────────────────────────────────────────────────────
normal_color    <- "#2196A6"
prolonged_color <- "#E07B54"

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { font-family:'Segoe UI',sans-serif; background:#f5f7fa; }
    .title-section {
      background:linear-gradient(135deg,#667eea,#764ba2);
      color:white; padding:30px; border-radius:8px; margin-bottom:20px;
    }
    .title-section h1 { margin:0; font-size:2em; font-weight:600; }
    .title-section p  { margin:8px 0 0; font-size:1em; opacity:0.9; }
    .info-badge { background:#667eea; color:white; padding:5px 10px;
                  border-radius:20px; font-size:0.85em; margin-right:8px;
                  display:inline-block; }
    .sidebar-section { background:white; padding:16px; border-radius:8px;
                       box-shadow:0 2px 4px rgba(0,0,0,0.1); }
    .plot-card { background:white; border-radius:8px; padding:12px;
                 margin-bottom:16px; box-shadow:0 2px 8px rgba(0,0,0,0.09);
                 border-left:4px solid #667eea; }
    .pred-box  { background:#f0f4ff; padding:16px; border-radius:8px;
                 border-left:4px solid #667eea; margin-top:12px; }
    .pred-high { border-left-color:#e74c3c; background:#fff0f0; }
    .pred-low  { border-left-color:#27ae60; background:#f0fff4; }
    .comorbid-tag { display:inline-block; background:#667eea; color:white;
                    padding:3px 8px; border-radius:12px; font-size:0.8em;
                    margin:2px; }
    .data-note { background:#f8f9fa; border-left:3px solid #adb5bd;
                 padding:8px 12px; border-radius:4px; margin-bottom:16px;
                 font-size:0.82em; color:#6c757d; font-style:italic; }
    .interp-box { margin-top:12px; padding:0 8px;
                  font-size:0.88em; color:#444; }
    .interp-box p { margin:6px 0; line-height:1.5; }
    .icu-stay-table { width:100%; border-collapse:collapse; font-size:0.92em; }
    .icu-stay-table th { background:#667eea; color:white; padding:8px 12px;
                         text-align:left; }
    .icu-stay-table td { padding:8px 12px; border-bottom:1px solid #e9ecef; }
    .icu-stay-table tr:hover td { background:#f0f4ff; }
    .badge-normal    { background:#2196A6; color:white; padding:2px 8px;
                       border-radius:10px; font-size:0.8em; }
    .badge-prolonged { background:#E07B54; color:white; padding:2px 8px;
                       border-radius:10px; font-size:0.8em; }
    #age_range .irs-grid-text { display:none !important; }
  "))),
  
  div(class="title-section",
      h1("Sepsis ICU Prolonged Stay Prediction"),
      p("MIMIC-IV Cohort Explorer, Patient Trajectory & Machine Learning Prediction"),
      br(),
      span(class="info-badge", paste0("Total Patients: ", nrow(cohort))),
      span(class="info-badge", paste0("Prolonged Stay (>=14 days): ",
                                      sum(cohort$prolonged_stay == 1),
                                      " (",
                                      round(mean(cohort$prolonged_stay == 1)*100,1),
                                      "%)"))
  ),
  
  tabsetPanel(
    
    # TAB 1: COHORT EXPLORER
    tabPanel("Cohort Explorer",
             sidebarLayout(
               sidebarPanel(
                 div(class="sidebar-section",
                     h4("Filters", style="color:#667eea;margin-top:0;"),
                     radioButtons("var_type", "Variable Group:",
                                  choices  = c("Demographics"  = "demo",
                                               "Vitals"        = "vitals",
                                               "Labs"          = "labs",
                                               "Comorbidities" = "comorbid"),
                                  selected = "demo"),
                     hr(),
                     checkboxInput("filter_prolonged",
                                   "Prolonged Stay Only (>=14 days)",
                                   FALSE),
                     sliderInput("age_range", "Age Range:",
                                 min=18, max=91, value=c(18,91), step=1, ticks=FALSE),
                     hr(),
                     textOutput("filter_summary")
                 )
               ),
               mainPanel(
                 div(class="data-note",
                     "Data source: Final analytic cohort (n = 4,179) — adult sepsis ICU
               patients from MIMIC-IV, with outlier removal, mean/median imputation,
               first admission per patient, and exclusion of patients who died within
               48h of ICU admission (competing risk). Comorbidities derived from
               ICD-9 and ICD-10 secondary diagnosis codes."),
                 tabsetPanel(
                   tabPanel("Summary Table", br(), gt::gt_output("summary_gt")),
                   tabPanel("Distributions", br(), uiOutput("dist_plots"))
                 )
               )
             )
    ),
    
    # TAB 2: PATIENT TRAJECTORY
    tabPanel("Patient Trajectory",
             sidebarLayout(
               sidebarPanel(
                 div(class="sidebar-section",
                     h4("Patient Lookup", style="color:#667eea;margin-top:0;"),
                     # fix 1: proper placeholder with onInitialize
                     selectizeInput("patient_id",
                                    "Select Patient (subject_id):",
                                    choices  = NULL,
                                    selected = "",
                                    options  = list(
                                      placeholder = "Search by patient ID...",
                                      onInitialize = I('function() { this.setValue(""); }')
                                    )),
                     hr(),
                     uiOutput("patient_info_box")
                 )
               ),
               mainPanel(
                 div(class="data-note",
                     "Data source: The single index ICU admission used in the final analytic
               cohort — each patient's first qualifying sepsis ICU stay. ICU stay
               details and vital signs are queried live from MIMIC-IV BigQuery using
               the cohort admission ID. This is the same stay the prediction model
               was trained on."),
                 div(class="plot-card",
                     h5("ICU Stay — Analytic Cohort Admission",
                        style="color:#333;margin:0 0 8px 0;"),
                     uiOutput("icu_stay_table")),
                 br(),
                 div(class="plot-card",
                     h5("Vital Signs — First 24 Hours of ICU Admission",
                        style="color:#333;margin:0 0 4px 0;"),
                     p("The exact vital sign values used as model inputs for prolonged stay prediction.",
                       style="font-size:0.82em;color:#6c757d;font-style:italic;margin:0 0 8px 0;"),
                     plotOutput("vitals_24h", height="420px"))
               )
             )
    ),
    
    # TAB 3: ML PREDICTION
    tabPanel("ML Prediction",
             sidebarLayout(
               sidebarPanel(
                 div(class="sidebar-section",
                     h4("Patient Inputs", style="color:#667eea;margin-top:0;"),
                     # fix 2: prompt above inputs
                     div(style="background:#f0f4ff;border-radius:6px;padding:10px;
                         margin-bottom:12px;font-size:0.85em;color:#667eea;
                         border-left:3px solid #667eea;",
                         "Enter patient clinical values below and click",
                         tags$b("Predict Prolonged Stay"),
                         "to generate a personalized ICU prolonged stay risk estimate."),
                     h5("Demographics"),
                     numericInput("p_age",       "Age (years):",                         value=65,  min=18,  max=91),
                     selectInput( "p_gender",    "Gender:",                              choices=c("Male"=1,"Female"=0)),
                     selectInput( "p_race",      "Race:",                                choices=c("WHITE","BLACK","HISPANIC","ASIAN","UNKNOWN","OTHER")),
                     selectInput( "p_insurance", "Insurance:",                           choices=c("Medicare","Medicaid","Private","Other","Unknown")),
                     hr(),
                     h5("Vitals (first 24h worst value)"),
                     numericInput("p_hr",   "Heart Rate - HR (max bpm):",                value=100, min=20,  max=300),
                     numericInput("p_map",  "Mean Arterial Pressure - MAP (min mmHg):",  value=65,  min=1,   max=200),
                     numericInput("p_rr",   "Respiratory Rate - RR (max /min):",         value=20,  min=5,   max=80),
                     numericInput("p_temp", "Temperature (max deg C):",                  value=37.5,min=25,  max=45),
                     hr(),
                     h5("Labs (first 24h worst value)"),
                     numericInput("p_creat", "Creatinine (max mg/dL):",                  value=1.5, min=0.1, max=50),
                     numericInput("p_wbc",   "White Blood Cell Count - WBC (max K/uL):", value=12,  min=0.1, max=500),
                     numericInput("p_plat",  "Platelets (min K/uL):",                    value=180, min=5,   max=3000),
                     numericInput("p_gcs",   "Glasgow Coma Scale - GCS (min 3-15):",     value=13,  min=3,   max=15),
                     hr(),
                     h5("Comorbidities"),
                     checkboxInput("p_htn",    "Hypertension",                 FALSE),
                     checkboxInput("p_dm",     "Diabetes",                     FALSE),
                     checkboxInput("p_ckd",    "Chronic Kidney Disease (CKD)",  FALSE),
                     checkboxInput("p_cvd",    "Cardiovascular Disease (CVD)",  FALSE),
                     checkboxInput("p_liver",  "Chronic Liver Disease",        FALSE),
                     checkboxInput("p_immuno", "Immunosuppression",            FALSE),
                     checkboxInput("p_vaso",   "Vasopressor Use",              FALSE),
                     hr(),
                     actionButton("predict_btn", "Predict Prolonged Stay",
                                  style="background:#667eea;color:white;width:100%;
                                  border:none;padding:10px;border-radius:6px;
                                  font-size:1em;cursor:pointer;")
                 )
               ),
               mainPanel(
                 div(class="data-note",
                     "Model: LASSO logistic regression with Youden-optimal threshold (0.402).
               Trained on 80% of the analytic cohort (n = 3,343 training patients;
               n = 836 test patients). Predictors: 19 clinical variables (first 24h
               worst-case vitals and labs, demographics, comorbidities from ICD-9/10
               codes) plus 3 clinically motivated interaction terms (CKD x Diabetes,
               Chronic Liver x CVD, GCS x Vasopressor). Bilirubin and lactate were
               excluded after sensitivity analysis showed no change in predictive
               performance (AUC 0.680 with and without). Final model performance:
               AUC = 0.680, Sensitivity = 55.6%, Specificity = 71.7%."),
                 # fix 3: default message before prediction is run
                 uiOutput("prediction_output"),
                 br(),
                 div(class="plot-card",
                     h5("Predicted Probability Gauge",
                        style="text-align:center;color:#667eea;margin-bottom:0;"),
                     plotlyOutput("prob_gauge", height="280px"),
                     div(class="interp-box",
                         p(HTML("<b>How to read this:</b> The gauge shows the model's estimated
                         probability that this patient will have a prolonged ICU stay
                         (>=14 days). The red line marks the decision threshold of 40.2%
                         — patients above this are classified as high risk.")),
                         p(HTML("<b>Clinical application:</b> A high-risk prediction suggests
                         early discharge planning, proactive resource allocation, and
                         closer monitoring may be warranted. A low-risk prediction
                         supports standard care pathways.")),
                         p(HTML("<b>Limitations:</b> This model was trained on a single-center
                         ICU cohort (MIMIC-IV, Beth Israel Deaconess Medical Center) and
                         may not generalize to other institutions. AUC = 0.680 reflects
                         moderate discriminative ability. Additionally, the model uses
                         first-admission worst-case values and may not capture dynamic
                         changes in patient status over time. Clinical judgment should
                         always supplement model predictions."),
                           style="color:#888;font-style:italic;")
                     )
                 ),
                 br(),
                 div(class="plot-card",
                     h5("LASSO Coefficients - Predictors of Prolonged ICU Stay",
                        style="color:#333;margin-top:0;"),
                     plotOutput("coef_plot", height="420px"),
                     div(class="interp-box",
                         p(HTML("<b>How to read this:</b> Each bar shows a LASSO coefficient —
                         the direction and magnitude of each predictor's association
                         with prolonged stay after penalization. Positive (coral) bars
                         increase predicted risk; negative (teal) bars decrease it.
                         Variables shrunk to zero by LASSO are not shown.")),
                         p(HTML("<b>Key findings:</b> Chronic liver disease and cardiovascular
                         disease are the strongest individual risk factors. Insurance
                         type and race capture social determinants of health independent
                         of clinical severity. GCS and vasopressor use capture
                         neurological and hemodynamic severity. The large negative
                         coefficient for Insurance: Unknown may reflect that patients
                         with unresolved insurance documentation have shorter recorded
                         stays, though the mechanism warrants further investigation.")),
                         p(HTML("<b>For clinicians and hospitals:</b> Comorbidity burden —
                         particularly liver disease and CVD — drives prolonged stay
                         more than acute physiological derangements alone. This suggests
                         pre-admission health status should be a key focus in discharge
                         planning conversations, and that hospitals may benefit from
                         targeted early intervention programs for high-comorbidity
                         sepsis patients."),
                           style="color:#555;")
                     )
                 )
               )
             )
    )
  )
)

# SERVER
server <- function(input, output, session) {
  
  updateSelectizeInput(session, "patient_id",
                       choices  = sort(unique(cohort$subject_id)),
                       selected = "",
                       server   = TRUE)
  
  # ── TAB 1 ────────────────────────────────────────────────────────────────────
  filt_data <- reactive({
    d <- cohort |>
      filter(anchor_age >= input$age_range[1],
             anchor_age <= input$age_range[2]) |>
      mutate(
        gender = recode(gender, "F" = "Female", "M" = "Male"),
        race_collapsed = case_when(
          str_detect(race, "WHITE")    ~ "White",
          str_detect(race, "BLACK")    ~ "Black",
          str_detect(race, "HISPANIC") ~ "Hispanic",
          str_detect(race, "ASIAN")    ~ "Asian",
          race %in% c("UNKNOWN","UNABLE TO OBTAIN",
                      "PATIENT DECLINED TO ANSWER") ~ "Unknown",
          TRUE ~ "Other"
        )
      )
    if (isTRUE(input$filter_prolonged)) d <- d |> filter(prolonged_stay == 1)
    d
  })
  
  output$filter_summary <- renderText({
    paste0(nrow(filt_data()), " patients | Ages ",
           input$age_range[1], "-", input$age_range[2])
  })
  
  output$summary_gt <- gt::render_gt({
    req(filt_data())
    d <- filt_data() |>
      mutate(prolonged_stay = factor(prolonged_stay,
                                     levels = c(0,1),
                                     labels = c("Normal (<14 days)",
                                                "Prolonged (>=14 days)")))
    if (input$var_type == "demo") {
      d |>
        select(anchor_age, gender, race_collapsed, insurance, los_days,
               prolonged_stay) |>
        tbl_summary(
          by        = prolonged_stay,
          statistic = list(
            all_continuous()  ~ "{median} ({p25}-{p75}); {mean} ({sd})",
            all_categorical() ~ "{n} ({p}%)"
          ),
          digits = list(all_continuous() ~ 1),
          label = list(
            anchor_age     ~ "Age (years)",
            gender         ~ "Gender",
            race_collapsed ~ "Race",
            insurance      ~ "Insurance",
            los_days       ~ "Length of Stay (days)"
          )
        ) |>
        add_overall() |>
        add_p(test = list(
          race_collapsed ~ "chisq.test",
          gender         ~ "chisq.test",
          insurance      ~ "chisq.test"
        )) |>
        modify_footnote(
          all_stat_cols() ~ "Continuous: Median (Q1-Q3); Mean (SD). Categorical: n (%)"
        ) |>
        as_gt()
    } else if (input$var_type == "vitals") {
      d |>
        select(heart_rate, map, resp_rate, temperature, prolonged_stay) |>
        tbl_summary(
          by        = prolonged_stay,
          statistic = list(
            all_continuous() ~ "{median} ({p25}-{p75}); {mean} ({sd})"
          ),
          digits = list(all_continuous() ~ 1),
          label = list(
            heart_rate  ~ "Heart Rate - HR (bpm)",
            map         ~ "Mean Arterial Pressure - MAP (mmHg)",
            resp_rate   ~ "Respiratory Rate - RR (/min)",
            temperature ~ "Temperature (deg C)"
          )
        ) |>
        add_overall() |>
        add_p() |>
        modify_footnote(all_stat_cols() ~ "Median (Q1-Q3); Mean (SD)") |>
        as_gt()
    } else if (input$var_type == "labs") {
      d |>
        select(creatinine, wbc, platelets, gcs_total, prolonged_stay) |>
        tbl_summary(
          by        = prolonged_stay,
          statistic = list(
            all_continuous() ~ "{median} ({p25}-{p75}); {mean} ({sd})"
          ),
          digits = list(all_continuous() ~ 1),
          label = list(
            creatinine ~ "Creatinine (mg/dL)",
            wbc        ~ "White Blood Cell Count - WBC (K/uL)",
            platelets  ~ "Platelets (K/uL)",
            gcs_total  ~ "Glasgow Coma Scale - GCS Total"
          )
        ) |>
        add_overall() |>
        add_p() |>
        modify_footnote(all_stat_cols() ~ "Median (Q1-Q3); Mean (SD)") |>
        as_gt()
    } else {
      d |>
        select(hypertension, diabetes, ckd, cvd,
               chronic_liver, immunosuppression, vasopressor, prolonged_stay) |>
        tbl_summary(
          by        = prolonged_stay,
          statistic = list(all_categorical() ~ "{n} ({p}%)"),
          label = list(
            hypertension      ~ "Hypertension",
            diabetes          ~ "Diabetes",
            ckd               ~ "Chronic Kidney Disease (CKD)",
            cvd               ~ "Cardiovascular Disease (CVD)",
            chronic_liver     ~ "Chronic Liver Disease",
            immunosuppression ~ "Immunosuppression",
            vasopressor       ~ "Vasopressor Use"
          )
        ) |>
        add_overall() |>
        add_p() |>
        modify_footnote(all_stat_cols() ~ "n (%)") |>
        as_gt()
    }
  })
  
  output$dist_plots <- renderUI({
    if (input$var_type == "demo") {
      tagList(
        div(class="plot-card",
            h5("Age Distribution by Outcome", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_age",       height="260px")),
        div(class="plot-card",
            h5("Gender Distribution by Outcome", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_gender",    height="260px")),
        div(class="plot-card",
            h5("Race Distribution by Outcome", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_race",      height="300px")),
        div(class="plot-card",
            h5("Insurance Distribution by Outcome", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_insurance", height="260px")),
        div(class="plot-card",
            h5("Length of Stay by Outcome", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_los",       height="260px"))
      )
    } else if (input$var_type == "vitals") {
      tagList(
        div(class="plot-card",
            h5("Heart Rate - HR (bpm)", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_hr",   height="260px")),
        div(class="plot-card",
            h5("Mean Arterial Pressure - MAP (mmHg)", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_map",  height="260px")),
        div(class="plot-card",
            h5("Respiratory Rate - RR (/min)", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_rr",   height="260px")),
        div(class="plot-card",
            h5("Temperature (deg C)", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_temp", height="260px"))
      )
    } else if (input$var_type == "labs") {
      tagList(
        div(class="plot-card",
            h5("Creatinine (mg/dL)", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_creat", height="260px")),
        div(class="plot-card",
            h5("White Blood Cell Count - WBC (K/uL)", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_wbc",   height="260px")),
        div(class="plot-card",
            h5("Platelets (K/uL)", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_plat",  height="260px")),
        div(class="plot-card",
            h5("Glasgow Coma Scale - GCS Total (3-15)", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_gcs",   height="260px"))
      )
    } else {
      tagList(
        div(class="plot-card",
            h5("Comorbidity Prevalence (%) by Outcome", style="color:#333;margin:0 0 8px 0;"),
            plotlyOutput("plot_comorbid", height="380px"))
      )
    }
  })
  
  make_hist <- function(var) {
    renderPlotly({
      d <- filt_data() |>
        filter(!is.na(.data[[var]])) |>
        mutate(outcome = factor(prolonged_stay,
                                levels = c(0,1),
                                labels = c("Normal (<14 days)",
                                           "Prolonged Stay (>=14 days)")))
      d_normal    <- d |> filter(outcome == "Normal (<14 days)")
      d_prolonged <- d |> filter(outcome == "Prolonged Stay (>=14 days)")
      plot_ly(opacity=0.75, nbinsx=30) |>
        add_histogram(data=d_normal,
                      x=as.formula(paste0("~`",var,"`")),
                      name="Normal (<14 days)",
                      marker=list(color=normal_color)) |>
        add_histogram(data=d_prolonged,
                      x=as.formula(paste0("~`",var,"`")),
                      name="Prolonged Stay (>=14 days)",
                      marker=list(color=prolonged_color)) |>
        layout(barmode="overlay",
               xaxis=list(title="Value"), yaxis=list(title="Count"),
               legend=list(orientation="h", xanchor="center", x=0.5,
                           yanchor="top", y=-0.4),
               margin=list(t=10, b=100))
    })
  }
  
  output$plot_age   <- make_hist("anchor_age")
  output$plot_hr    <- make_hist("heart_rate")
  output$plot_map   <- make_hist("map")
  output$plot_rr    <- make_hist("resp_rate")
  output$plot_temp  <- make_hist("temperature")
  output$plot_creat <- make_hist("creatinine")
  output$plot_wbc   <- make_hist("wbc")
  output$plot_plat  <- make_hist("platelets")
  output$plot_gcs   <- make_hist("gcs_total")
  
  make_bar <- function(var_col) {
    renderPlotly({
      filt_data() |>
        count(.data[[var_col]], prolonged_stay) |>
        rename(category = all_of(var_col)) |>
        mutate(outcome = factor(prolonged_stay, levels=c(0,1),
                                labels=c("Normal (<14 days)",
                                         "Prolonged Stay (>=14 days)"))) |>
        plot_ly(x=~category, y=~n, color=~outcome,
                colors=c(normal_color, prolonged_color), type="bar") |>
        layout(barmode="group",
               xaxis=list(title=""), yaxis=list(title="Count"),
               legend=list(orientation="h", xanchor="center", x=0.5,
                           yanchor="top", y=-0.4),
               margin=list(t=10, b=100))
    })
  }
  
  output$plot_gender    <- make_bar("gender")
  output$plot_race      <- make_bar("race_collapsed")
  output$plot_insurance <- make_bar("insurance")
  
  output$plot_los <- renderPlotly({
    filt_data() |>
      mutate(outcome = factor(prolonged_stay, levels=c(0,1),
                              labels=c("Normal (<14 days)",
                                       "Prolonged Stay (>=14 days)"))) |>
      plot_ly(x=~outcome, y=~los_days, color=~outcome,
              colors=c(normal_color, prolonged_color),
              type="box", boxpoints="outliers", showlegend=FALSE) |>
      layout(xaxis=list(title=""), yaxis=list(title="Length of Stay (days)"),
             margin=list(t=10, b=40))
  })
  
  output$plot_comorbid <- renderPlotly({
    filt_data() |>
      mutate(outcome = factor(prolonged_stay, levels=c(0,1),
                              labels=c("Normal (<14 days)",
                                       "Prolonged Stay (>=14 days)"))) |>
      group_by(outcome) |>
      summarise(across(c(hypertension, diabetes, ckd, cvd,
                         chronic_liver, immunosuppression, vasopressor),
                       ~round(mean(.x)*100,1))) |>
      pivot_longer(-outcome, names_to="comorbidity", values_to="pct") |>
      mutate(comorbidity = recode(comorbidity,
                                  hypertension="Hypertension", diabetes="Diabetes",
                                  ckd="CKD", cvd="CVD", chronic_liver="Chronic Liver",
                                  immunosuppression="Immunosuppression", vasopressor="Vasopressor")) |>
      plot_ly(x=~comorbidity, y=~pct, color=~outcome,
              colors=c(normal_color, prolonged_color), type="bar") |>
      layout(barmode="group",
             xaxis=list(title=""), yaxis=list(title="Prevalence (%)"),
             legend=list(orientation="h", xanchor="center", x=0.5,
                         yanchor="top", y=-0.4),
             margin=list(t=10, b=100))
  })
  
  # ── TAB 2 ────────────────────────────────────────────────────────────────────
  cohort_patient <- reactive({
    req(input$patient_id)
    req(input$patient_id != "")
    sid <- as.integer(input$patient_id)
    cohort |> filter(subject_id == sid) |> slice(1)
  })
  
  output$patient_info_box <- renderUI({
    req(input$patient_id)
    req(input$patient_id != "")
    pt <- cohort_patient()
    if (nrow(pt) == 0) return(
      div(class="pred-box",
          p("Patient not found in analytic cohort.", style="color:#999;"))
    )
    
    comorbid_vars  <- c("hypertension","diabetes","ckd","cvd",
                        "chronic_liver","immunosuppression")
    comorbid_names <- c("Hypertension","Diabetes","CKD","CVD",
                        "Chronic Liver","Immunosuppression")
    flags  <- tryCatch(as.logical(unlist(pt[comorbid_vars])),
                       error=function(e) rep(FALSE,6))
    active <- comorbid_names[flags]
    
    comorbid_tags <- if (length(active) > 0) {
      tagList(lapply(active, function(x) span(class="comorbid-tag", x)))
    } else {
      p("None recorded", style="color:#999;font-size:0.85em;")
    }
    
    div(class="pred-box",
        h6("Patient Info", style="color:#667eea;font-weight:600;margin-top:0;"),
        tags$p(tags$b("Age: "),           pt$anchor_age, " years"),
        tags$p(tags$b("Gender: "),        ifelse(pt$gender=="M","Male","Female")),
        tags$p(tags$b("Race: "),          pt$race),
        tags$p(tags$b("Insurance: "),     pt$insurance),
        tags$p(tags$b("LOS: "),           pt$los_days, " days"),
        tags$p(tags$b("Vasopressor: "),   ifelse(pt$vasopressor==1,"Yes","No")),
        tags$p(tags$b("Prolonged Stay (>=14 days): "),
               ifelse(pt$prolonged_stay==1,"Yes","No")),
        hr(),
        tags$b("Comorbidities:"), br(), br(),
        comorbid_tags
    )
  })
  
  cohort_icu_stay <- reactive({
    req(input$patient_id)
    req(input$patient_id != "")
    pt <- cohort_patient()
    req(nrow(pt) > 0)
    sid     <- as.integer(input$patient_id)
    hadm_id <- pt$hadm_id
    tryCatch(
      bq_query(glue(
        "SELECT stay_id, first_careunit, intime, outtime, los
         FROM mimiciv_3_1.icustays
         WHERE subject_id = {sid}
           AND hadm_id = {hadm_id}
         ORDER BY intime
         LIMIT 1")),
      error=function(e) NULL
    )
  })
  
  patient_vitals_24h <- reactive({
    req(input$patient_id, cohort_icu_stay())
    req(input$patient_id != "")
    icu <- cohort_icu_stay()
    req(!is.null(icu), nrow(icu) > 0)
    sid           <- as.integer(input$patient_id)
    first_stay_id <- icu$stay_id[1]
    tryCatch(
      bq_query(glue(
        "SELECT c.charttime, c.valuenum, d.abbreviation
         FROM mimiciv_3_1.chartevents c
         JOIN mimiciv_3_1.d_items d ON c.itemid = d.itemid
         JOIN mimiciv_3_1.icustays i ON c.stay_id = i.stay_id
         WHERE c.subject_id = {sid}
           AND c.stay_id = {first_stay_id}
           AND c.itemid IN (220045, 220052, 220181, 220210, 223762)
           AND c.charttime >= i.intime
           AND c.charttime <= TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
           AND c.valuenum IS NOT NULL
         ORDER BY c.charttime")),
      error=function(e) NULL
    )
  })
  
  output$icu_stay_table <- renderUI({
    if (is.null(input$patient_id) || input$patient_id == "") {
      return(div(style="color:#adb5bd;font-style:italic;padding:12px;",
                 "Select a patient to view their ICU stay details."))
    }
    req(cohort_icu_stay())
    icu <- cohort_icu_stay()
    if (is.null(icu) || nrow(icu) == 0) return(
      p("ICU stay data not available.", style="color:#999;font-style:italic;")
    )
    
    icu <- icu |>
      mutate(
        intime   = as.POSIXct(intime),
        outtime  = as.POSIXct(outtime),
        los_days = round(as.numeric(difftime(outtime, intime, units="days")), 1),
        outcome  = if_else(los_days >= 14,
                           "<span class='badge-prolonged'>Prolonged (>=14 days)</span>",
                           "<span class='badge-normal'>Normal (<14 days)</span>"),
        admit_dt = format(intime,  "%b %d, %Y %H:%M"),
        disch_dt = format(outtime, "%b %d, %Y %H:%M")
      )
    
    tagList(
      tags$table(class="icu-stay-table",
                 tags$thead(
                   tags$tr(
                     tags$th("ICU Unit"),
                     tags$th("Admission Time"),
                     tags$th("Discharge Time"),
                     tags$th("Length of Stay"),
                     tags$th("Outcome")
                   )
                 ),
                 tags$tbody(
                   tags$tr(
                     tags$td(icu$first_careunit[1]),
                     tags$td(icu$admit_dt[1]),
                     tags$td(icu$disch_dt[1]),
                     tags$td(paste0(icu$los_days[1], " days")),
                     tags$td(HTML(icu$outcome[1]))
                   )
                 )
      ),
      p("Showing the index ICU admission included in the analytic cohort.",
        style="font-size:0.82em;color:#6c757d;margin-top:8px;font-style:italic;")
    )
  })
  
  output$vitals_24h <- renderPlot({
    if (is.null(input$patient_id) || input$patient_id == "") {
      return(ggplot() +
               annotate("text", x=0.5, y=0.5,
                        label="Select a patient to view their vital signs.",
                        size=5, color="#adb5bd") +
               theme_void())
    }
    req(patient_vitals_24h())
    vitals <- patient_vitals_24h()
    req(!is.null(vitals), nrow(vitals) > 0)
    
    vitals <- vitals |>
      mutate(
        charttime   = as.POSIXct(charttime),
        vital_label = recode(abbreviation,
                             "HR"    = "Heart Rate (bpm)",
                             "ABPm"  = "MAP (mmHg)",
                             "NBPm"  = "MAP (mmHg)",
                             "RR"    = "Resp Rate (/min)",
                             "TempC" = "Temperature (deg C)"
        )
      ) |>
      filter(!is.na(valuenum))
    
    if (nrow(vitals) == 0) return(
      ggplot() +
        annotate("text", x=0.5, y=0.5,
                 label="No vital sign data available in first 24h",
                 size=5, color="#6c757d") +
        theme_void()
    )
    
    ggplot(vitals, aes(x=charttime, y=valuenum, color=vital_label)) +
      geom_point(size=2.5, alpha=0.85) +
      geom_line(linewidth=1, alpha=0.7) +
      facet_wrap(~vital_label, scales="free_y", ncol=2) +
      scale_x_datetime(date_labels="%H:%M") +
      scale_color_manual(values=c(
        "Heart Rate (bpm)"    = "#E07B54",
        "MAP (mmHg)"          = "#2196A6",
        "Resp Rate (/min)"    = "#667eea",
        "Temperature (deg C)" = "#e74c3c"
      )) +
      labs(x="Time", y="Value",
           caption="First 24 hours of index ICU admission. These values are the inputs used by the prediction model.") +
      theme_minimal(base_size=11) +
      theme(legend.position  = "none",
            strip.text       = element_text(size=10, face="bold", color="#333"),
            strip.background = element_rect(fill="#f0f4ff", color=NA),
            panel.grid.minor = element_blank(),
            plot.caption     = element_text(size=8, color="#6c757d", face="italic"))
  })
  
  # ── TAB 3 ────────────────────────────────────────────────────────────────────
  prediction <- eventReactive(input$predict_btn, {
    input_df <- data.frame(
      anchor_age        = input$p_age,
      gender            = as.integer(input$p_gender),
      race_collapsed    = factor(input$p_race,
                                 levels=c("ASIAN","BLACK","HISPANIC",
                                          "OTHER","UNKNOWN","WHITE")),
      heart_rate        = input$p_hr,
      map               = input$p_map,
      resp_rate         = input$p_rr,
      temperature       = input$p_temp,
      creatinine        = input$p_creat,
      wbc               = input$p_wbc,
      platelets         = input$p_plat,
      gcs_total         = input$p_gcs,
      hypertension      = as.integer(input$p_htn),
      diabetes          = as.integer(input$p_dm),
      ckd               = as.integer(input$p_ckd),
      cvd               = as.integer(input$p_cvd),
      chronic_liver     = as.integer(input$p_liver),
      immunosuppression = as.integer(input$p_immuno),
      vasopressor       = as.integer(input$p_vaso),
      insurance         = factor(input$p_insurance,
                                 levels=c("Medicaid","Medicare",
                                          "Other","Private","Unknown")),
      prolonged_stay    = 0L
    )
    
    X_new <- model.matrix(
      ~ . - prolonged_stay - 1 +
        chronic_liver:cvd +
        ckd:diabetes +
        gcs_total:vasopressor,
      data = input_df
    )
    
    train_cols   <- rownames(lasso_model$beta)
    missing_cols <- setdiff(train_cols, colnames(X_new))
    for (col in missing_cols) {
      X_new <- cbind(X_new, setNames(data.frame(rep(0, nrow(X_new))), col))
    }
    X_new <- X_new[, train_cols, drop=FALSE]
    as.numeric(predict(lasso_model, newx=X_new, type="response"))
  })
  
  output$prediction_output <- renderUI({
    if (is.null(input$predict_btn) || input$predict_btn == 0) {
      return(div(class="plot-card",
                 style="border-left-color:#adb5bd;",
                 p("No prediction generated yet.",
                   style="color:#adb5bd;font-style:italic;margin:0;"),
                 p("Enter patient values in the panel on the left and click",
                   tags$b("Predict Prolonged Stay"), "to generate a risk estimate.",
                   style="color:#6c757d;font-size:0.88em;margin:4px 0 0 0;")))
    }
    req(prediction())
    prob <- prediction()
    pct  <- round(prob * 100, 1)
    high <- prob >= 0.402
    div(class = paste0("plot-card", ifelse(high, " pred-high", " pred-low")),
        style = "border-left-width:6px;",
        h4(ifelse(high, "High Risk of Prolonged Stay",
                  "Lower Risk of Prolonged Stay"),
           style=paste0("margin-top:0;color:",
                        ifelse(high,"#e74c3c","#27ae60"), ";")),
        h3(paste0(pct, "% predicted probability of prolonged stay (>=14 days)"),
           style="margin:8px 0;"),
        tags$hr(),
        p(paste0("Decision threshold: 0.402 (Youden-optimal)  |  ",
                 "Model: LASSO Logistic Regression  |  Test AUC: 0.680  |  ",
                 "Sensitivity: 55.6%  |  Specificity: 71.7%"),
          style="color:#666;font-size:0.85em;margin:4px 0;"),
        p(ifelse(high,
                 "Predicted prolonged ICU stay (>=14 days). Consider early discharge planning.",
                 "Predicted normal ICU stay (<14 days)."),
          style="margin:6px 0 0 0;")
    )
  })
  
  output$prob_gauge <- renderPlotly({
    if (is.null(input$predict_btn) || input$predict_btn == 0) {
      return(plot_ly(type="indicator", mode="gauge+number",
                     value=0, number=list(suffix="%"),
                     gauge=list(axis=list(range=list(0,100), ticksuffix="%"),
                                bar=list(color="#e9ecef", thickness=0.3),
                                bgcolor="white",
                                steps=list(list(range=c(0,100), color="#f8f9fa")),
                                threshold=list(line=list(color="#e74c3c",width=3),
                                               thickness=0.75, value=40.2))) |>
               layout(margin=list(t=20,b=10,l=30,r=30), height=260))
    }
    req(prediction())
    prob <- prediction()
    plot_ly(
      type="indicator", mode="gauge+number",
      value=round(prob*100,1), number=list(suffix="%"),
      gauge=list(
        axis      = list(range=list(0,100), ticksuffix="%",
                         tickvals=c(0,20,40,60,80,100)),
        bar       = list(color=ifelse(prob>=0.402, prolonged_color, normal_color),
                         thickness=0.3),
        bgcolor   = "white",
        steps     = list(list(range=c(0,40.2),   color="#e8f5f5"),
                         list(range=c(40.2,100), color="#ffebee")),
        threshold = list(line=list(color="#e74c3c", width=3),
                         thickness=0.75, value=40.2)
      )
    ) |> layout(margin=list(t=20,b=10,l=30,r=30), height=260)
  })
  
  output$coef_plot <- renderPlot({
    coef(lasso_model) |>
      as.matrix() |>
      as.data.frame() |>
      rownames_to_column("Variable") |>
      filter(Variable != "(Intercept)", s0 != 0) |>
      mutate(Variable = recode(Variable,
                               "anchor_age"             = "Age",
                               "gender"                 = "Gender (Male vs Female)",
                               "heart_rate"             = "Heart Rate (HR)",
                               "map"                    = "Mean Arterial Pressure (MAP)",
                               "resp_rate"              = "Respiratory Rate (RR)",
                               "temperature"            = "Temperature",
                               "creatinine"             = "Creatinine",
                               "wbc"                    = "White Blood Cell Count (WBC)",
                               "platelets"              = "Platelets",
                               "gcs_total"              = "Glasgow Coma Scale (GCS)",
                               "hypertension"           = "Hypertension",
                               "diabetes"               = "Diabetes",
                               "ckd"                    = "Chronic Kidney Disease (CKD)",
                               "cvd"                    = "Cardiovascular Disease (CVD)",
                               "chronic_liver"          = "Chronic Liver Disease",
                               "immunosuppression"      = "Immunosuppression",
                               "vasopressor"            = "Vasopressor Use",
                               "race_collapsedBLACK"    = "Race: Black (vs Asian)",
                               "race_collapsedHISPANIC" = "Race: Hispanic (vs Asian)",
                               "race_collapsedOTHER"    = "Race: Other (vs Asian)",
                               "race_collapsedUNKNOWN"  = "Race: Unknown (vs Asian)",
                               "race_collapsedWHITE"    = "Race: White (vs Asian)",
                               "insuranceMedicare"      = "Insurance: Medicare (vs Medicaid)",
                               "insuranceOther"         = "Insurance: Other (vs Medicaid)",
                               "insurancePrivate"       = "Insurance: Private (vs Medicaid)",
                               "insuranceUnknown"       = "Insurance: Unknown (vs Medicaid)",
                               "chronic_liver:cvd"      = "Interaction: Chronic Liver x CVD",
                               "cvd:chronic_liver"      = "Interaction: Chronic Liver x CVD",
                               "ckd:diabetes"           = "Interaction: CKD x Diabetes",
                               "diabetes:ckd"           = "Interaction: CKD x Diabetes",
                               "gcs_total:vasopressor"  = "Interaction: GCS x Vasopressor"
      )) |>
      arrange(s0) |>
      mutate(Variable  = factor(Variable, levels=Variable),
             direction = if_else(s0>0,"Increases Risk","Decreases Risk")) |>
      ggplot(aes(x=s0, y=Variable, fill=direction)) +
      geom_col() +
      scale_fill_manual(values=c("Increases Risk"=prolonged_color,
                                 "Decreases Risk"=normal_color)) +
      geom_vline(xintercept=0, linetype="dashed", color="gray40") +
      labs(x="Coefficient (positive = increases risk of prolonged stay)",
           y=NULL, fill=NULL,
           caption="Reference categories: Race = Asian; Insurance = Medicaid") +
      theme_minimal(base_size=11) +
      theme(legend.position="bottom",
            plot.caption=element_text(size=8, color="#6c757d", face="italic"))
  })
}

shinyApp(ui, server)