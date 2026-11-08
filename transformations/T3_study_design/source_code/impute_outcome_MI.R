################################################################
# impute_outcome ---
# Aim:
# Create multiple-imputation follow-up data for estimand 1 by imputing
# event_est1 among records with non-administrative censoring.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D4_analytic_datasets/D4_StudyCohortFup_<Main>.RDS
# - data/D4_analytic_datasets/D4_StudyCohortCovariates_<Main>.RDS
#
# Output: ---
# - data/D4_analytic_datasets/D4_StudyCohort_FUP_MI.RDS
################################################################

# Initial setup ---
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("impute_outcome_MI.R")
  lm$start_capturing_prints()
}

# Config loading ---
picard::load_config()
imp_cfg <- config_project$impute_outcome

picard::audit_start(
  file_name = "impute_outcome_MI",
  deap_name = config_project$DEAP_configuration$name
)

for (mode in imp_cfg$modes) {
  logger::log_info(glue::glue("Processing mode: {mode}"))

  mode_key <- tolower(mode)
  fup_path <- imp_cfg$input$fup[[mode_key]]
  cov_path <- imp_cfg$input$cov[[mode_key]]
  out_path <- imp_cfg$output$fup_mi[[mode_key]]

  if (is.null(fup_path) || !nzchar(fup_path)) {
    stop(glue::glue("Missing config_project$impute_outcome$input$fup${mode_key}"))
  }
  if (is.null(cov_path) || !nzchar(cov_path)) {
    stop(glue::glue("Missing config_project$impute_outcome$input$cov${mode_key}"))
  }
  if (is.null(out_path) || !nzchar(out_path)) {
    stop(glue::glue("Missing config_project$impute_outcome$output$fup_mi${mode_key}"))
  }

  fup <- picard::load(
    file_path = dirname(fup_path),
    file_name = basename(fup_path)
  )
  covariates <- picard::load(
    file_path = dirname(cov_path),
    file_name = basename(cov_path)
  )

  covnames <- unique(unlist(imp_cfg$model$predictors, use.names = FALSE))

  fup_keys <- c("person_id", "T0", "group")
  cov_keep <- c(fup_keys, covnames) |> unique()
  fup_keep <- c(fup_keys, "match_id", "event_est1", "admin_censor_est1", "general_fup_d", "fup_d_est1", "fup_length_days_est1", "fup_length_pm_est1")

  mi_dt <- merge(
    fup[, ..fup_keep],
    covariates[, ..cov_keep],
    by = fup_keys,
    all.x = TRUE
  )

  available_predictors <- covnames[covnames %in% names(mi_dt)]
  missing_predictors <- setdiff(covnames, available_predictors)

  if (length(missing_predictors) > 0L) {
    logger::log_error(
      glue::glue(
        "Missing predictors dropped: {paste(missing_predictors, collapse = ', ')}"
      )
    )
  }

  if (!"event_est1" %in% names(mi_dt)) {
    logger::log_error("event_est1 is not present in the input FUP dataset.")
  }

  mi_dt[, event_est1_observed := as.integer(event_est1)]
  mi_dt[, event_est1 := as.integer(event_est1)]
  mi_dt[admin_censor_est1 == "non-admin", event_est1 := NA_integer_]

  for (col in c(covnames, "event_est1")) {
    mi_dt[, (col) := as.factor(get(col))]
  }

  model_cols <- c("event_est1", available_predictors)
  model_input <- data.table::copy(mi_dt[, ..model_cols])

  non_admin_n <- mi_dt[admin_censor_est1 == "non-admin", .N]
  logger::log_info(glue::glue("non-admin rows to impute: {non_admin_n}"))

  m <- as.integer(imp_cfg$model$n_imputations)

  if (non_admin_n == 0L) {
    logger::log_error("No non-admin rows found.")
    stop()
  }

  init <- mice::mice(model_input, maxit = 0, printFlag = FALSE)
  method <- init$method
  predictor_matrix <- init$predictorMatrix

  method[] <- ""
  method["event_est1"] <- imp_cfg$model$method

  predictor_matrix[,] <- 0
  predictor_matrix["event_est1", setdiff(colnames(model_input), "event_est1")] <- 1

  logger::log_info(
    glue::glue(
      "Imputing event_est1 using method: {imp_cfg$model$method} with {m} imputations."
    )
  )
  imp <- mice::mice(
    model_input,
    m = m,
    maxit = as.integer(imp_cfg$model$maxit),
    method = method,
    predictorMatrix = predictor_matrix,
    seed = as.integer(imp_cfg$model$seed),
    printFlag = FALSE
  )

  idx_impute <- which(mi_dt$admin_censor_est1 == "non-admin")
  out_list <- lapply(seq_len(m), function(i) {
    completed <- mice::complete(imp, action = i)
    out <- data.table::copy(mi_dt)
    # Update the event_est1 values for non-admin rows with the imputed values
    out[idx_impute, event_est1 := completed[idx_impute, "event_est1"]]

    # recompute follow up days for the imputed rows to be the general follow up days
    out[idx_impute, fup_d_est1 := general_fup_d]
    out[idx_impute, fup_length_days_est1 := as.numeric(difftime(fup_d_est1, T0, units = "days") + 1)]
    out[idx_impute, fup_length_pm_est1 := fup_length_days_est1 / config_values$month_length]

    out[, imputation_id := i]
    out
  })

  output_dt <- data.table::rbindlist(out_list, use.names = TRUE)
  picard::save(
    data = output_dt,
    file_path = dirname(out_path),
    file_name = basename(out_path)
  )

  rm(fup, covariates, mi_dt, model_input, out_list, output_dt)
  if (exists("imp")) {
    rm(imp)
  }
  gc()
}

picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
