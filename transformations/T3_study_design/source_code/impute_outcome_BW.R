################################################################
# impute_outcome_bw ---
# Aim:
# Create best/worst-case follow-up data for estimand 1 by assuming
# event_est1 values for records with non-administrative censoring.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D4_analytic_datasets/D4_StudyCohortFup_<Main>.RDS
# - data/D4_analytic_datasets/D4_StudyCohortCovariates_<Main>.RDS
#
# Output: ---
# - data/D4_analytic_datasets/D4_StudyCohort_FUP_BW_<Main>_BW.RDS
################################################################

# Initial setup ---
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("impute_outcome_BW.R")
  lm$start_capturing_prints()
}

# Config loading ---
picard::load_config()
imp_cfg <- config_project$impute_outcome

picard::audit_start(
  file_name = "impute_outcome_BW",
  deap_name = config_project$DEAP_configuration$name
)

for (mode in imp_cfg$modes) {
  logger::log_info(glue::glue("Processing mode: {mode}"))

  mode_key <- tolower(mode)
  fup_path <- imp_cfg$input$fup[[mode_key]]
  out_path <- imp_cfg$output$fup_bw[[mode_key]]

  if (is.null(fup_path) || !nzchar(fup_path)) {
    stop(glue::glue("Missing config_project$impute_outcome$input$fup${mode_key}"))
  }
  if (is.null(out_path) || !nzchar(out_path)) {
    stop(glue::glue("Missing config_project$impute_outcome$output$fup_bw${mode_key}"))
  }

  fup <- picard::load(
    file_path = dirname(fup_path),
    file_name = basename(fup_path)
  )
  fup_keep <- c("person_id", "T0", "group", "match_id", "event_est1", "admin_censor_est1", "general_fup_d", "fup_d_est1")

  bw_dt <-fup[, ..fup_keep]

  bw_dt[, event_est1_observed := as.integer(event_est1)]

  impute_index <- which(bw_dt$admin_censor_est1 == "non-admin")
  logger::log_info(glue::glue("non-admin rows for best/worst scenarios: {length(impute_index)}"))

  if (length(impute_index) == 0L) {
    logger::log_error("No non-admin rows found. Cannot create scenarios.")
    stop()
  }

  # Create best best scenario (event_est1 = 0 for both exposed and control)
  bb <- data.table::copy(bw_dt)
  bb[impute_index, event_est1 := 0L]
  bb[impute_index, fup_d_est1 := general_fup_d] # best: no event, extend follow-up to the max
  bb[, bw_scenario := "bb"]
  bb[, bw_id := 3] # As table 15 in table shell

  # Create worst scenario (event_est1 = 1)
  ww <- data.table::copy(bw_dt)
  ww[impute_index, event_est1 := 1L] # worst: event on the non-admin censoring date, keep fup_d_est1 as is
  ww[, bw_scenario := "ww"]
  ww[, bw_id := 4] # As table 15 in table shell

  # best exposed and worst control scenario (event_est1 = 0 for exposed, 1 for control)
  impute_exposed_index <- which(bw_dt$admin_censor_est1 == "non-admin" & bw_dt$group == "EXPOSED")
  impute_control_index <- which(bw_dt$admin_censor_est1 == "non-admin" & bw_dt$group == "CONTROL")
  bw <- data.table::copy(bw_dt)
  bw[impute_exposed_index, event_est1 := 0L]
  bw[impute_exposed_index, fup_d_est1 := general_fup_d] # exposed best: extend follow-up to the max
  bw[impute_control_index, event_est1 := 1L] # control worst: keep fup_d_est1 as is
  bw[, bw_scenario := "bw"]
  bw[, bw_id := 1] # As table 15 in table shell

  # worst exposed and best control scenario (event_est1 = 1 for exposed, 0 for control)
  wb <- data.table::copy(bw_dt)
  wb[impute_exposed_index, event_est1 := 1L] # exposed worst: keep fup_d_est1 as is
  wb[impute_control_index, event_est1 := 0L]
  wb[impute_control_index, fup_d_est1 := general_fup_d] # control best: extend follow-up to the max
  wb[, bw_scenario := "wb"]
  wb[, bw_id := 2] # As table 15 in table shell

  # Combine both scenarios
  output_dt <- data.table::rbindlist(list(bb, bw, wb, ww), use.names = TRUE)
  output_dt[, fup_length_days_est1 := as.numeric(difftime(fup_d_est1, T0, units = "days") + 1)]
  output_dt[, fup_length_pm_est1 := fup_length_days_est1 / config_values$month_length]

  picard::save(
    data = output_dt,
    file_path = dirname(out_path),
    file_name = basename(out_path)
  )

  rm(fup, bw_dt, bb, bw, wb, ww, output_dt)
  gc()
}

picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
