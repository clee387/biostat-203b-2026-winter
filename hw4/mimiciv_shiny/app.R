library(shiny)
library(tidyverse)
library(gtsummary)
library(plotly)
library(bigrquery)
library(DBI)
library(glue)

# BigQuery connection (filename in bq_auth is safe to commit -- just not the file itself)
bq_auth(path = "biostat-203b-2026-winter-92fefbfab477.json")
con_bq <- dbConnect(
  bigrquery::bigquery(),
  project = "biostat-203b-2025-winter",
  dataset = "mimiciv_3_1",
  billing = "biostat-203b-2025-winter"
)

mimic_icu_cohort <- read_rds("mimic_icu_cohort.rds")

# ── Shared constants ───────────────────────────────────────────────────────────
var_labels <- list(
  age_intime="Age at ICU Entry", gender="Gender", race="Race",
  insurance="Insurance Type", marital_status="Marital Status",
  heart_rate="Heart Rate (bpm)", systolic_bp="Systolic BP (mmHg)",
  diastolic_bp="Diastolic BP (mmHg)", temp_f="Temperature (°F)",
  resp_rate="Respiratory Rate (breaths/min)", creatinine="Creatinine (mg/dL)",
  wbc="WBC (K/µL)", glucose="Glucose (mg/dL)", albumin="Albumin (g/dL)",
  potassium="Potassium (mEq/L)", sodium="Sodium (mEq/L)",
  chloride="Chloride (mEq/L)", bicarbonate="Bicarbonate (mEq/L)"
)
continuous_vars <- c("age_intime","heart_rate","systolic_bp","diastolic_bp",
                     "temp_f","resp_rate","creatinine","wbc","glucose",
                     "albumin","potassium","sodium","chloride","bicarbonate")

demo_choices   <- c("Gender"="gender","Race"="race","Age"="age_intime",
                    "Insurance"="insurance","Marital Status"="marital_status")
vitals_choices <- c("Heart Rate"="heart_rate","Systolic BP"="systolic_bp",
                    "Diastolic BP"="diastolic_bp","Temperature"="temp_f","Resp Rate"="resp_rate")
labs_choices   <- c("Creatinine"="creatinine","WBC"="wbc","Glucose"="glucose",
                    "Albumin"="albumin","Potassium"="potassium",
                    "Sodium"="sodium","Chloride"="chloride","Bicarbonate"="bicarbonate")

cat_colors <- list(
  gender=c("F"="#FF6B9D","M"="#4A90E2"),
  race=c("ASIAN"="#667eea","BLACK"="#FF6B9D","HISPANIC"="#FFA500","WHITE"="#4A90E2","Other"="#50C878"),
  insurance=c("Medicare"="#667eea","Private"="#FF6B9D","Medicaid"="#FFA500","Other"="#4A90E2","No charge"="#90EE90"),
  marital_status=c("DIVORCED"="#667eea","MARRIED"="#FF6B9D","SINGLE"="#4A90E2","WIDOWED"="#FFA500")
)

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif; background-color:#f5f7fa; }
    .title-section {
      background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);
      color:white; padding:30px; border-radius:8px; margin-bottom:30px;
      box-shadow:0 4px 6px rgba(0,0,0,0.1);
    }
    .title-section h1 { margin:0; font-size:2.5em; font-weight:600; }
    .title-section p  { margin:10px 0 0 0; font-size:1.1em; opacity:0.95; }
    .sidebar-section  { background:white; padding:20px; border-radius:8px; box-shadow:0 2px 4px rgba(0,0,0,0.1); }
    .info-badge { display:inline-block; background:#667eea; color:white; padding:5px 10px;
                  border-radius:20px; font-size:0.85em; margin-right:10px; }
    .plot-card  { background:white; border-radius:8px; padding:12px; margin-bottom:18px;
                  box-shadow:0 2px 8px rgba(0,0,0,0.09); border-left:4px solid #667eea; }
    #age_range .irs-grid { display:none !important; }
  "))),
  
  div(class="title-section",
      h1("🏥 MIMIC-IV ICU Cohort Explorer"),
      p("Interactive exploration of demographic, vital sign, and laboratory data"),
      br(),
      span(class="info-badge", paste0("Total Patients: ", nrow(mimic_icu_cohort))),
      span(class="info-badge", paste0("Prolonged Stay: ", sum(as.logical(mimic_icu_cohort$los_long), na.rm=TRUE),
                                      " (", round(mean(as.logical(mimic_icu_cohort$los_long), na.rm=TRUE)*100,1), "%)"))
  ),
  
  tabsetPanel(
    tabPanel("Patient Explorer",
             sidebarLayout(
               sidebarPanel(
                 div(class="sidebar-section",
                     h4("\U0001F50D Patient Lookup", style="color:#667eea; margin-top:0;"),
                     selectizeInput("patient_id", "Select Patient (subject_id):",
                                    choices  = NULL,
                                    options  = list(placeholder="Type a patient ID...")),
                     hr(),
                     uiOutput("patient_info_box")
                 )
               ),
               mainPanel(
                 plotOutput("adt_plot", height="500px"),
                 br(),
                 plotOutput("icu_plot", height="450px"),
                 br(),
                 br()
               )
             )
    ),
    tabPanel("Cohort Summary",
             sidebarLayout(
               sidebarPanel(
                 div(class="sidebar-section",
                     h4("📊 Filters", style="color:#667eea; margin-top:0;"),
                     radioButtons("var_type","Data Type:",
                                  choices=c("Demographics"="demo","Vitals"="vitals","Labs"="labs"),
                                  selected="demo"),
                     hr(),
                     checkboxInput("filter_los","📌 Prolonged Stay Only",FALSE),
                     sliderInput("age_range","👥 Age Range:",min=20,max=100,value=c(20,100),step=10),
                     hr(),
                     div(style="background:#f0f0f0;padding:10px;border-radius:6px;",
                         h6("Active Filters:",style="margin-top:0;color:#333;"),
                         textOutput("filter_summary"))
                 )
               ),
               mainPanel(
                 conditionalPanel(condition="input.var_type=='demo'",
                                  tabsetPanel(
                                    tabPanel("📋 Summary Table", gt::gt_output("summary_demo")),
                                    tabPanel("📈 Distribution",
                                             uiOutput("dist_checkboxes_demo"),
                                             uiOutput("dist_plots_demo"))
                                  )
                 ),
                 conditionalPanel(condition="input.var_type=='vitals'",
                                  tabsetPanel(
                                    tabPanel("📋 Summary Table", gt::gt_output("summary_vitals")),
                                    tabPanel("📈 Distribution",
                                             uiOutput("dist_checkboxes_vitals"),
                                             uiOutput("dist_plots_vitals")),
                                    tabPanel("📈 Vitals Trends",
                                             selectInput("strat_group_vitals","Group by:",
                                                         choices=c("Age Group"="age_group","Gender"="gender",
                                                                   "Race"="race","Insurance"="insurance",
                                                                   "Marital Status"="marital_status")),
                                             plotlyOutput("vitals_lineplot",height="500px"))
                                  )
                 ),
                 conditionalPanel(condition="input.var_type=='labs'",
                                  tabsetPanel(
                                    tabPanel("📋 Summary Table", gt::gt_output("summary_labs")),
                                    tabPanel("📈 Distribution",
                                             uiOutput("dist_checkboxes_labs"),
                                             uiOutput("dist_plots_labs")),
                                    tabPanel("📦 Boxplots by Group",
                                             selectInput("strat_group_labs","Group by:",
                                                         choices=c("Age Group"="age_group","Gender"="gender",
                                                                   "Race"="race","Insurance"="insurance",
                                                                   "Marital Status"="marital_status")),
                                             plotlyOutput("boxplot_strat",height="500px"))
                                  )
                 )
               )
             )
    )
  )
)

# ── Server ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {
  
  
  # Server-side selectize -- handles 94k patient IDs without browser lag
  updateSelectizeInput(session, "patient_id",
                       choices  = sort(unique(mimic_icu_cohort$subject_id)),
                       selected = NULL,
                       server   = TRUE)
  
  filt_data <- reactive({
    d <- mimic_icu_cohort %>%
      filter(age_intime >= input$age_range[1], age_intime <= input$age_range[2])
    if (isTRUE(input$filter_los)) d <- d %>% filter(los_long==TRUE)
    d
  })
  
  output$filter_summary <- renderText({
    paste0(nrow(filt_data()), " patients | Ages ", input$age_range[1], "-", input$age_range[2])
  })
  
  # Summary tables --------------------------------------------------------------
  output$summary_demo <- gt::render_gt({
    req(filt_data())
    filt_data() %>%
      mutate(
        gender = recode(gender, "F"="Female", "M"="Male"),
        marital_status = str_to_title(marital_status),
        race = str_to_title(race)
      ) %>%
      select(gender, race, age_intime, insurance, marital_status, los_long) %>%
      tbl_summary(label=list(gender~"Gender", race~"Race", age_intime~"Age at ICU Entry",
                             insurance~"Insurance", marital_status~"Marital Status",
                             los_long~"Prolonged Stay (>2 days)"),
                  missing="ifany") %>% as_gt()
  })
  output$summary_vitals <- gt::render_gt({
    req(filt_data())
    filt_data() %>% select(heart_rate,systolic_bp,diastolic_bp,temp_f,resp_rate) %>%
      tbl_summary(label=list(
        heart_rate  ~ "Heart Rate, HR (bpm)",
        systolic_bp ~ "Systolic Blood Pressure, SBP (mmHg)",
        diastolic_bp~ "Diastolic Blood Pressure, DBP (mmHg)",
        temp_f      ~ "Temperature, Temp (°F)",
        resp_rate   ~ "Respiratory Rate, RR (breaths/min)"),
        type=list(everything()~"continuous"),
        statistic=all_continuous()~"{mean} ({sd})",missing="ifany") %>% as_gt()
  })
  output$summary_labs <- gt::render_gt({
    req(filt_data())
    filt_data() %>% select(creatinine,wbc,glucose,albumin,potassium,sodium,chloride,bicarbonate) %>%
      tbl_summary(label=list(
        creatinine  ~ "Creatinine (mg/dL)",
        wbc         ~ "White Blood Cell Count, WBC (K/µL)",
        glucose     ~ "Glucose (mg/dL)",
        albumin     ~ "Albumin (g/dL)",
        potassium   ~ "Potassium (mEq/L)",
        sodium      ~ "Sodium (mEq/L)",
        chloride    ~ "Chloride (mEq/L)",
        bicarbonate ~ "Bicarbonate (mEq/L)"),
        type=list(everything()~"continuous"),
        statistic=all_continuous()~"{mean} ({sd})",missing="ifany") %>% as_gt()
  })
  
  # Checkbox UIs ----------------------------------------------------------------
  mk_cb <- function(id, ch) checkboxGroupInput(id,"Select variables to visualize:",
                                               choices=ch,selected=ch[1],inline=TRUE)
  output$dist_checkboxes_demo   <- renderUI(mk_cb("dist_vars_demo",   demo_choices))
  output$dist_checkboxes_vitals <- renderUI(mk_cb("dist_vars_vitals", vitals_choices))
  output$dist_checkboxes_labs   <- renderUI(mk_cb("dist_vars_labs",   labs_choices))
  
  # Single-variable plot factory ------------------------------------------------
  make_single_plot <- function(var, data) {
    d   <- data %>% filter(!is.na(.data[[var]]))
    if (nrow(d)==0) return(NULL)
    lbl <- var_labels[[var]] %||% var
    
    if (var %in% continuous_vars) {
      mn   <- mean(d[[var]], na.rm=TRUE)
      med  <- median(d[[var]], na.rm=TRUE)
      ymax <- max(hist(d[[var]], breaks=20, plot=FALSE)$counts)
      
      plot_ly(d, x=as.formula(paste0("~`",var,"`"))) %>%
        add_histogram(nbinsx=20,
                      marker=list(color="#667eea",line=list(width=1,color="white")),
                      name="Count",
                      hovertemplate="<b>Value: %{x}</b><br>Count: %{y}<extra></extra>") %>%
        add_trace(x=c(mn,mn),   y=c(0,ymax), type="scatter", mode="lines",
                  line=list(color="#FF6B9D",width=3),
                  name=sprintf("Mean: %.2f",mn), showlegend=TRUE, hoverinfo="skip") %>%
        add_trace(x=c(med,med), y=c(0,ymax), type="scatter", mode="lines",
                  line=list(color="#FFA500",width=3,dash="dash"),
                  name=sprintf("Median: %.2f",med), showlegend=TRUE, hoverinfo="skip") %>%
        layout(
          title  = list(text=lbl, font=list(size=16,color="#333"), x=0),
          xaxis  = list(title=""),
          yaxis  = list(title="Count"),
          legend = list(orientation="v", x=0.78, y=0.95,
                        bgcolor="rgba(255,255,255,0.92)",
                        bordercolor="#ddd", borderwidth=1),
          margin = list(t=55, r=160)   # right margin keeps legend inside card
        )
    } else {
      pal <- cat_colors[[var]]
      
      # Remap raw values to display labels
      label_map <- list(
        gender         = c("F"="Female", "M"="Male"),
        race           = c("ASIAN"="Asian","BLACK"="Black","HISPANIC"="Hispanic",
                           "WHITE"="White","Other"="Other"),
        insurance      = c("Medicare"="Medicare","Private"="Private","Medicaid"="Medicaid",
                           "Other"="Other","No charge"="No Charge"),
        marital_status = c("DIVORCED"="Divorced","MARRIED"="Married",
                           "SINGLE"="Single","WIDOWED"="Widowed")
      )
      lmap <- label_map[[var]]
      
      cnt <- d %>%
        group_by(.data[[var]]) %>% summarise(n=n(), .groups="drop") %>%
        rename(category=!!sym(var)) %>%
        mutate(
          category    = as.character(category),
          label       = sapply(category, function(x) if (!is.null(lmap) && x %in% names(lmap)) lmap[[x]] else x),
          color       = sapply(category, function(x) if (!is.null(pal)  && x %in% names(pal))  pal[[x]]  else "#667eea")
        )
      
      # One trace per category so each gets its own legend entry
      p <- plot_ly()
      for (i in seq_len(nrow(cnt))) {
        p <- p %>% add_bars(
          x    = cnt$label[i],
          y    = cnt$n[i],
          name = cnt$label[i],
          marker = list(color = cnt$color[i], line = list(color="white", width=2)),
          hovertemplate = paste0("<b>", cnt$label[i], "</b><br>Count: %{y}<extra></extra>")
        )
      }
      p %>% layout(
        title      = list(text=lbl, font=list(size=16,color="#333"), x=0),
        xaxis      = list(title="", categoryorder="array", categoryarray=cnt$label),
        yaxis      = list(title="Count"),
        showlegend = TRUE,
        legend     = list(orientation="v", x=0.78, y=0.95,
                          bgcolor="rgba(255,255,255,0.92)",
                          bordercolor="#ddd", borderwidth=1),
        barmode    = "group",
        margin     = list(t=55, r=160)
      )
    }
  }
  
  # Dynamic plot areas: one plotlyOutput per checked variable -------------------
  register_dist_outputs <- function(prefix, selected_reactive, possible_vars) {
    # Render the container UI (one card div per selected var)
    output[[paste0("dist_plots_", prefix)]] <- renderUI({
      vars <- selected_reactive()
      req(length(vars) > 0)
      tagList(lapply(vars, function(var)
        div(class="plot-card",
            plotlyOutput(paste0("dynplot_", prefix, "_", var), height="380px"))
      ))
    })
    # Pre-register a renderPlotly for every possible variable
    lapply(possible_vars, function(var) {
      local({
        v <- var
        output[[paste0("dynplot_", prefix, "_", v)]] <- renderPlotly({
          req(v %in% selected_reactive())
          suppressWarnings(make_single_plot(v, filt_data()))
        })
      })
    })
  }
  
  register_dist_outputs("demo",   reactive(input$dist_vars_demo),   unname(demo_choices))
  register_dist_outputs("vitals", reactive(input$dist_vars_vitals), unname(vitals_choices))
  register_dist_outputs("labs",   reactive(input$dist_vars_labs),   unname(labs_choices))
  
  # Boxplot by group ------------------------------------------------------------
  output$boxplot_strat <- renderPlotly({
    req(filt_data(), input$strat_group_labs)
    data <- filt_data()
    data$group <- if (input$strat_group_labs=="age_group")
      cut(data$age_intime,breaks=c(18,40,60,80,100),labels=c("18-40","41-60","61-80","80+"))
    else data[[input$strat_group_labs]]
    data %>% select(group,creatinine,wbc,glucose,albumin,potassium,sodium) %>%
      pivot_longer(-group) %>%
      plot_ly(x=~group,y=~value,color=~name,type="box") %>%
      layout(title="Lab Values by Group",
             xaxis=list(title=tools::toTitleCase(input$strat_group_labs)),
             yaxis=list(title="Value"), boxmode="group")
  })
  
  # ── Patient Explorer: BigQuery (replicates HW3 Q1) ───────────────────────────
  
  bq_query <- function(sql) {
    dbGetQuery(con_bq, sql)
  }
  
  patient_base <- reactive({
    req(input$patient_id)
    sid <- as.integer(input$patient_id)
    tryCatch(
      bq_query(glue::glue(
        "SELECT subject_id, gender, anchor_age, race
         FROM mimiciv_3_1.patients
         WHERE subject_id = {sid}")),
      error = function(e) { showNotification(paste("BQ error (patients):", e$message), type="error"); NULL }
    )
  })
  
  patient_adt <- reactive({
    req(input$patient_id)
    sid <- as.integer(input$patient_id)
    tryCatch(
      bq_query(glue::glue(
        "SELECT hadm_id, transfer_id, eventtype, careunit, intime, outtime
         FROM mimiciv_3_1.transfers
         WHERE subject_id = {sid} ORDER BY intime")),
      error = function(e) { showNotification(paste("BQ error (transfers):", e$message), type="error"); NULL }
    )
  })
  
  patient_labs <- reactive({
    req(input$patient_id)
    sid <- as.integer(input$patient_id)
    lab_ids <- "50862,50912,50971,50983,50902,50882,51221,51301,50931"
    tryCatch(
      bq_query(glue::glue(
        "SELECT charttime FROM mimiciv_3_1.labevents
         WHERE subject_id = {sid} AND itemid IN ({lab_ids}) AND charttime IS NOT NULL")),
      error = function(e) { showNotification(paste("BQ error (labs):", e$message), type="error"); NULL }
    )
  })
  
  patient_procedures <- reactive({
    req(input$patient_id)
    sid <- as.integer(input$patient_id)
    tryCatch(
      bq_query(glue::glue(
        "SELECT p.chartdate, d.long_title
         FROM mimiciv_3_1.procedures_icd p
         LEFT JOIN mimiciv_3_1.d_icd_procedures d
           ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
         WHERE p.subject_id = {sid}")),
      error = function(e) { showNotification(paste("BQ error (procedures):", e$message), type="error"); NULL }
    )
  })
  
  patient_diagnoses <- reactive({
    req(input$patient_id)
    sid <- as.integer(input$patient_id)
    tryCatch(
      bq_query(glue::glue(
        "SELECT d.long_title
         FROM mimiciv_3_1.diagnoses_icd diag
         LEFT JOIN mimiciv_3_1.d_icd_diagnoses d
           ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
         WHERE diag.subject_id = {sid} LIMIT 3")),
      error = function(e) { showNotification(paste("BQ error (diagnoses):", e$message), type="error"); NULL }
    )
  })
  
  patient_icu <- reactive({
    req(input$patient_id)
    sid <- as.integer(input$patient_id)
    tryCatch(
      bq_query(glue::glue(
        "SELECT stay_id, first_careunit, last_careunit, intime, outtime, los
         FROM mimiciv_3_1.icustays
         WHERE subject_id = {sid} ORDER BY intime")),
      error = function(e) { showNotification(paste("BQ error (icustays):", e$message), type="error"); NULL }
    )
  })
  
  patient_vitals <- reactive({
    req(input$patient_id, patient_icu())
    icu <- patient_icu()
    req(nrow(icu) > 0)
    sid      <- as.integer(input$patient_id)
    stay_ids <- paste(icu$stay_id, collapse=", ")
    vital_ids <- "220045,220179,220180,220210,223761"
    tryCatch(
      bq_query(glue::glue(
        "SELECT c.stay_id, c.charttime, c.valuenum, d.abbreviation
         FROM mimiciv_3_1.chartevents c
         JOIN mimiciv_3_1.d_items d ON c.itemid = d.itemid
         WHERE c.subject_id = {sid}
           AND c.itemid IN ({vital_ids})
           AND c.stay_id IN ({stay_ids})
           AND c.valuenum IS NOT NULL")),
      error = function(e) { showNotification(paste("BQ error (vitals):", e$message), type="error"); NULL }
    )
  })
  
  # ── Sidebar patient info card ─────────────────────────────────────────────────
  output$patient_info_box <- renderUI({
    req(input$patient_id)
    pt <- mimic_icu_cohort %>%
      filter(subject_id == as.integer(input$patient_id)) %>% slice(1)
    req(nrow(pt) > 0)
    div(style="background:#f0f4ff;padding:12px;border-radius:8px;border-left:4px solid #667eea;margin-top:10px;",
        h6("Patient Info", style="margin-top:0;color:#667eea;font-weight:600;"),
        tags$p(tags$b("Gender: "),         ifelse(pt$gender=="F","Female","Male")),
        tags$p(tags$b("Age: "),            round(pt$age_intime, 1)),
        tags$p(tags$b("Race: "),           pt$race),
        tags$p(tags$b("Insurance: "),      pt$insurance),
        tags$p(tags$b("Prolonged Stay: "), ifelse(isTRUE(pt$los_long), "Yes", "No"))
    )
  })
  
  # ── ADT plot (HW3 Q1.1 style) ────────────────────────────────────────────────
  output$adt_plot <- renderPlot({
    req(input$patient_id)
    req(patient_adt(), patient_base())
    
    pt  <- patient_base()
    adt <- patient_adt()
    req(!is.null(pt), !is.null(adt), nrow(adt) > 0)
    
    adt <- adt %>%
      filter(!is.na(intime), !is.na(outtime)) %>%
      mutate(
        intime   = as.POSIXct(intime),
        outtime  = as.POSIXct(outtime),
        careunit = ifelse(is.na(careunit), eventtype, careunit),
        is_icu   = str_detect(careunit, regex("ICU|CCU", ignore_case=TRUE)),
        lw       = ifelse(is_icu, 2.5, 0.7)   # numeric linewidth directly
      )
    
    # labs — safe empty fallback
    lab_events <- tryCatch({
      patient_labs() %>%
        mutate(charttime = as.POSIXct(charttime)) %>% distinct()
    }, error = function(e) tibble(charttime = as.POSIXct(character(0))))
    if (is.null(lab_events)) lab_events <- tibble(charttime = as.POSIXct(character(0)))
    
    # procedures — safe empty fallback
    proc_events <- tryCatch({
      patient_procedures() %>%
        mutate(charttime = as.POSIXct(chartdate)) %>%
        filter(!is.na(long_title))
    }, error = function(e) tibble(charttime = as.POSIXct(character(0)), long_title = character(0)))
    if (is.null(proc_events)) proc_events <- tibble(charttime = as.POSIXct(character(0)), long_title = character(0))
    
    top_diag <- tryCatch(patient_diagnoses() %>% pull(long_title),
                         error = function(e) character(0))
    if (is.null(top_diag)) top_diag <- character(0)
    
    title_text    <- paste0("Patient ", input$patient_id, ", ",
                            pt$gender[1], ", ", pt$anchor_age[1], " years old, ", pt$race[1])
    subtitle_text <- paste(top_diag, collapse="\n")
    
    p <- ggplot() +
      geom_segment(
        data = adt,
        aes(x=intime, xend=outtime, y="ADT", yend="ADT",
            color=careunit, linewidth=lw)
      ) +
      scale_linewidth_identity()
    
    if (nrow(lab_events) > 0) {
      p <- p + geom_point(data=lab_events,
                          aes(x=charttime, y="Lab"),
                          shape=3, size=2, color="black")
    }
    
    if (nrow(proc_events) > 0) {
      p <- p + geom_point(data=proc_events,
                          aes(x=charttime, y="Procedure", shape=long_title),
                          size=3)
    }
    
    p +
      scale_y_discrete(limits=rev) +
      labs(title=title_text, subtitle=subtitle_text,
           x="Calendar Time", y=NULL,
           color="Care Unit", shape="Procedure") +
      theme_minimal(base_size=13) +
      theme(
        plot.title      = element_text(face="bold", size=15),
        plot.subtitle   = element_text(size=10),
        legend.position = "bottom",
        axis.text.y     = element_text(size=12),
        axis.text.x     = element_text(angle=30, hjust=1)
      )
  })
  
  # ── ICU vitals plot (HW3 Q1.2 style) ─────────────────────────────────────────
  output$icu_plot <- renderPlot({
    req(input$patient_id, patient_icu(), patient_vitals())
    icu    <- patient_icu()
    vitals <- patient_vitals()
    req(!is.null(icu), !is.null(vitals), nrow(icu) > 0, nrow(vitals) > 0)
    
    icu <- icu %>% mutate(intime=as.POSIXct(intime), outtime=as.POSIXct(outtime))
    
    vitals <- vitals %>%
      mutate(charttime=as.POSIXct(charttime)) %>%
      filter(!is.na(valuenum)) %>%
      inner_join(icu %>% select(stay_id, intime, outtime), by="stay_id") %>%
      filter(charttime >= intime & charttime <= outtime)
    
    req(nrow(vitals) > 0)
    
    ggplot(vitals, aes(x=charttime, y=valuenum, color=abbreviation)) +
      geom_point(size=1.5) +
      geom_line(alpha=0.6) +
      facet_grid(abbreviation ~ stay_id, scales="free_y") +
      labs(title=paste0("Patient ", input$patient_id, " — ICU Vitals"),
           x="Calendar Time", y="Value", color="Vital") +
      theme_minimal(base_size=12) +
      theme(
        plot.title      = element_text(face="bold", size=14),
        axis.text.x     = element_text(angle=45, hjust=1, size=8),
        legend.position = "right"
      )
  })
  
  # Vitals line plot ------------------------------------------------------------
  output$vitals_lineplot <- renderPlotly({
    req(filt_data(), input$strat_group_vitals)
    data <- filt_data()
    data$group <- if (input$strat_group_vitals=="age_group")
      cut(data$age_intime,breaks=c(18,40,60,80,100),labels=c("18-40","41-60","61-80","80+"))
    else data[[input$strat_group_vitals]]
    data %>%
      pivot_longer(c(heart_rate,systolic_bp,diastolic_bp,resp_rate,temp_f),
                   names_to="vital",values_to="value") %>%
      group_by(group,vital) %>%
      summarise(mean_val=mean(value,na.rm=TRUE),sd_val=sd(value,na.rm=TRUE),.groups="drop") %>%
      plot_ly(x=~group,y=~mean_val,color=~vital,type="scatter",mode="lines+markers",
              error_y=list(array=~sd_val)) %>%
      layout(title="Vitals Across Groups",
             yaxis=list(title="Mean ± SD"),
             xaxis=list(title=tools::toTitleCase(input$strat_group_vitals)))
  })
}

suppressWarnings(shinyApp(ui, server))