################################################################
# create_imputation_diagnostics ---
# Aim:
# Create Table 17 outcome imputation diagnostics for estimand 1.
################################################################

# Initial setup ---
log_starter()
logger::log_info("[Imputation diagnostics] - START")

# Config loading ---
picard::load_config()
imp_cfg <- config_project$impute_diagnosis
dir_d4 <- config_project$outputs$dir_d4
dir_d5 <- config_project$outputs$dir_d5

# source function 
source(file.path(config_t4$T4$root, config_t4$T4$functions, imp_cfg$fn_name))

picard::audit_start(
  file_name = "create_imputation_diagnostics",
  deap_name = config_project$DEAP_configuration$name
)

for (mode in imp_cfg$modes) {
  logger::log_info(glue::glue("[Imputation diagnostics] Processing mode: {mode}"))

  imp_dt <- picard::load(
    file_path = dir_d4,
    file_name = glue::glue("{imp_cfg$input$fup_file}_{mode}.{imp_cfg$input$ext}")
  )

  req_cols <- c("person_id", "group", "imputation_id", "admin_censor_est1", "event_est1", "event_est1_observed")
  missing_cols <- setdiff(req_cols, names(imp_dt))
  if (length(missing_cols) > 0L) {
    stop(glue::glue("Missing required columns in MI data: {paste(missing_cols, collapse = ', ')}"))
  }

  imp_dt[, outcome_missing_estimand1 := admin_censor_est1 == "non-admin"]
  imp_dt[, event_est1 := as.integer(as.character(event_est1))]
  imp_dt[, event_est1_observed := as.integer(as.character(event_est1_observed))]

  imp_table <- fn_imp_diag(
    data = imp_dt,
    missing_col = "outcome_missing_estimand1",
    observed_col = "event_est1_observed",
    imputed_col = "event_est1",
    impute_id = "imputation_id",
    group_col = "group",
    exposed_val = "EXPOSED",
    control_val = "CONTROL",
    digits = 1
  )

  out_file <- glue::glue("{config_project$DEAP_configuration$name}_{imp_cfg$output$dianosis}_{mode}.{imp_cfg$output$ext}")
  picard::save(
    data = imp_table,
    file_path = dir_d5,
    file_name = out_file
  )

  rm(imp_dt, one_imp, imp_table)
  gc()
}

picard::audit_end()
logger::log_info("[Imputation diagnostics] - SUCCESS")
log_ender()
