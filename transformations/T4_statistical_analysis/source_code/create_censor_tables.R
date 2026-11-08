###############################################################
# create_censor_tables ---
# Aim:
# Create censor descriptive tables (Tables 6, 6.1, 7, 8) for the
# main and supplementary matched cohorts.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D4_analytic_datasets/D4_StudyCohortFUP_{Main,Supplementary}.parquet
# - transformations/T4_statistical_analysis/table_metadata/BaselineDescriptives_Metadata.csv
# - transformations/T4_statistical_analysis/table_metadata/table_scenarios.csv
#
# Output: ---
# - data/D5_results/{deap_name}_Table{6,6,1,7,8}_Censor.csv
###############################################################

# Initial setup ---
log_starter()
logger::log_info("[Censor tables] - START")

# Config loading ---
picard::load_config()

# testing setup --
is_testing <- isTRUE(config_pipeline$pipeline_test$testing)

if (!is_testing) {
  cen_config <- config_project$create_censor_tables
  picard::audit_start(
    file_name = "create_censor_tables",
    deap_name = config_project$DEAP_configuration$name
  )
} else {
  config_test <- picard::load_config("configuration/config_test.yaml")
  cen_config <- config_test$T4$create_censor_tables
}

# Extract config parameters ---
deap_name <- config_project$DEAP_configuration$name
dir_d4 <- cen_config$input$dir_d4
dir_metadata <- file.path(config_t4$T4$root, cen_config$input$dir_metadata)
dif_function <- file.path(config_t4$T4$root, config_t4$T4$functions)
dir_d5 <- cen_config$output$dir_d5
file_ext <- cen_config$input$file_ext

# Load scenario and variable metadata ---
table_scenarios <- picard::load(file_path = dir_metadata, file_name = "table_scenarios.csv")
label_lookup <- picard::load(file_path = dir_metadata, file_name = "FUP_LabelLookup.csv")

# Restrict to enabled censor scenarios
table_scenarios <- table_scenarios[table_type == "censor" & enabled == TRUE]

# dependency functions
source(file.path(dif_function, "fup_ie_cens_tab.R"))

# ============================================================
# Main loop: iterate over enabled scenarios
# ============================================================
for (i in seq_len(nrow(table_scenarios))) {
  scenario <- table_scenarios[i]

  logger::log_info(paste0(
    "[Censor tables] Scenario ", scenario$table_id,
    ": cohort=", scenario$cohort,
    ", estimand=", scenario$suffix
  ))

  fup_file <- glue::glue("{cen_config$input$fup}_{scenario$cohort}.{file_ext}")
  d4_fup <- picard::load(file_path = dir_d4, file_name = fup_file)

  if (!is.na(scenario$subset) && scenario$subset != "") {
    d4_fup <- d4_fup[eval(parse(text = scenario$subset))]
  }

  fup_col <- paste0("fup_length_pm_", scenario$suffix)
  cens_col <- paste0("reason_censoring_col_", scenario$suffix)

  if (!all(c("group", fup_col, cens_col) %in% names(d4_fup))) {
    logger::log_warn(paste0(
      "[Censor tables] Scenario ", scenario$table_id,
      " skipped: required columns missing."
    ))
    next
  }

  split_var <- NULL
  split_levels <- NULL
  split_labels <- NULL

  if (as.character(scenario$table_id) == "6.1") {
    if (!"admin_censor_est1" %in% names(d4_fup)) {
      logger::log_warn("[Censor tables] Scenario 6.1 skipped: admin_censor_est1 not found.")
      next
    }
    d4_fup[, imputation_status := data.table::fifelse(
      admin_censor_est1 == "non-admin",
      "imputed",
      "observed"
    )]

    split_var <- "imputation_status"
    split_levels <- c("observed", "imputed")
    split_labels <- c("Observed (not imputed)", "Missing (imputed)")
  }

  tab_exposed <- fup_ie_cens_tab(
    d = d4_fup[group == "EXPOSED", ],
    fup_time = fup_col,
    reas_cens = cens_col,
    header = "Exposed",
    ie_vars = label_lookup[type == "IE", variable],
    ie_labels = label_lookup[type == "IE", label],
    eof_vars = label_lookup[type == "censor", variable],
    eof_labels = label_lookup[type == "censor", label],
    cens_vars = c(),
    cens_labels = c(),
    row_structure = c("header", "fup", "ie", "eof"),
    section_labels = list(
      fup = "Person-months of follow-up",
      ie = "Occurrence of Intercurrent Events during follow-up, n (%)",
      eof = "Reason for end of follow-up, n (%)"
    ),
    cens_fup = TRUE,
    split_var = split_var,
    split_levels = split_levels,
    split_labels = split_labels
  )

  tab_control <- fup_ie_cens_tab(
    d = d4_fup[group == "CONTROL", ],
    fup_time = fup_col,
    reas_cens = cens_col,
    header = "Control",
    ie_vars = label_lookup[type == "IE", variable],
    ie_labels = label_lookup[type == "IE", label],
    eof_vars = label_lookup[type == "censor", variable],
    eof_labels = label_lookup[type == "censor", label],
    cens_vars = c(),
    cens_labels = c(),
    row_structure = c("header", "fup", "ie", "eof"),
    section_labels = list(
      fup = "Person-months of follow-up",
      ie = "Occurrence of Intercurrent Events during follow-up, n (%)",
      eof = "Reason for end of follow-up, n (%)"
    ),
    cens_fup = TRUE,
    split_var = split_var,
    split_levels = split_levels,
    split_labels = split_labels
  )

  tab <- cbind(tab_exposed, tab_control[, -1])

  out_file <- paste0(deap_name, "_Table", scenario$table_id, "_Censor.csv")
  picard::save(
    data = tab,
    file_path = dir_d5,
    file_name = out_file
  )

  rm(d4_fup, tab_exposed, tab_control, tab)
  gc()
}

logger::log_info("[Censor tables] - SUCCESS")

if (!is_testing) {
  picard::audit_end()
}

log_ender()
