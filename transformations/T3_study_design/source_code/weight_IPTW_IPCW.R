# ---------------------------------------------------------------
# Step: compute_d4_PS_Weights_IPTW_IPCW
#
# Input:  D4_StudyCohort_Covariates
#         D4_StudyCohort_TimeVaryingCovariates
#         psmodel_variables.csv
#
# Output: D4_PS_Weights_IPTW
#         D4_StudyCohort_IPCW (person-level: IPCW and combined IPTW×IPCW weights)
#         <DEAP>_D5_PS_Coef.csv
#         <DEAP>_D5_PS_ModelBuilding.csv
#
# Orchestrator script to generate a propensity score model and compute IPTW,
# then fit censoring models on time-varying data and compute IPCW,
# finally combine IPTW × IPCW for the final analysis weights.
# ---------------------------------------------------------------

# --- Initial setup of the environment ----
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("weight_IPTW_IPCW.R")
  lm$start_capturing_prints()
}

logger::log_info("[weight_IPTW_IPCW] - START")

# --- Config loading ---
picard::load_config()

deap_name <- config_project$DEAP_configuration$name

is_testing <- isTRUE(config_pipeline$pipeline_test$testing)
# testing mode: is_testing <- TRUE
if (is_testing) {
  cfg <- config_test$T4$iptw_ipcw
  dir_d4 <- cfg$dir_d4
  dir_d5 <- cfg$dir_d5
} else {
  cfg <- config_project$weight_IPTW_IPCW
  dir_d4 <- config_project$outputs$dir_d4
  dir_d5 <- config_project$outputs$dir_d5
}

source(file.path(cfg$ps_fn_dir, "fit_ps_model.R"))

source(file.path(
  config_t3$T3$root,
  config_t3$T3$functions,
  "fn_weight_IPTW.R"
))

baseline_metadata <- picard::load(
  file.path(
    config_t4$T4$root,
    config_t4$T4$config,
    cfg$ps_variables
  )
)

ps_variables <- baseline_metadata[include_ps == TRUE, ]

# mode <- "Main"
for(mode in cfg$modes) {
  logger::log_info(paste("Processing mode:", mode))

  # ---------------------------------------------------------------
  # PART 1: IPTW Computation
  # ---------------------------------------------------------------
  
# --- Read baseline covariates ---
  d4_covariates_path <- file.path(
  dir_d4,
  glue::glue("{cfg$d4_covariates$name}_{mode}.{cfg$d4_covariates$ext}")
  )
  d4_covariates <- picard::load(d4_covariates_path)

  # --- Compute IPTW ---
  results_iptw <- fn_weight_iptw(
    d4_covariates = d4_covariates,
    ps_variables = ps_variables,
    iptw_trunc_bounds = cfg$iptw_trunc_bounds,
    se_threshold = cfg$se_threshold
  )

  # --- Save IPTW outputs ---
  # D4 (analytic dataset): no DEAP prefix; each DAP owns its D4 directory
  results_iptw$D4_PS_Weights_IPTW[,
    T0 := as.Date(T0)]
  picard::save(
    data = results_iptw$D4_PS_Weights_IPTW,
    file_path = dir_d4,
    file_name = glue::glue(
      "{cfg$d4_iptw$name}_{mode}.{cfg$d4_iptw$ext}")
  )

  # D5 (per-DAP results): prefixed with DEAP name for the central meta-analysis
  picard::save(
    data = results_iptw$D5_PS_Coef,
    file_path = dir_d5,
      file_name = glue::glue(
        "{deap_name}_{cfg$d5_ps_coef$name}_{mode}.{cfg$d5_ps_coef$ext}")
  )

  picard::save(
    data = results_iptw$D5_PS_ModelBuilding,
    file_path = dir_d5,
    file_name = glue::glue(
      "{deap_name}_{cfg$d5_ps_model_building$name}_{mode}.{cfg$d5_ps_model_building$ext}")
  )

  logger::log_info(
    glue::glue(
      "D4_PS_Weights_IPTW: {nrow(results_iptw$D4_PS_Weights_IPTW)} rows"
    )
  )

  # ---------------------------------------------------------------
  # PART 2: IPCW Computation
  # ---------------------------------------------------------------

  if(mode != "Main")
    next # IPCW is only computed for the Main mode

  logger::log_info("Computing IPCW weights...")

  # Load time-varying covariates dataset ---
  d4_tv_path <- file.path(
    dir_d4,
    glue::glue("{cfg$d4_timevarying$name}_{mode}.{cfg$d4_timevarying$ext}")
  )
  d4_tv <- picard::load(d4_tv_path)

  # Load baseline matching variables from covariates for IPCW denominator model ---
  ipcw_vars <- baseline_metadata[include_ipcw == TRUE, unique(var)]

  d4_baseline <- d4_covariates[, c("person_id", "T0", ipcw_vars), with = FALSE]
  d4_baseline <- unique(d4_baseline, by = c("person_id", "T0"))

  # Merge baseline vars with time-varying data ---
  d4_tv <- merge(
    d4_tv,
    d4_baseline,
    by = c("person_id", "T0"),
    all.x = TRUE
  )
  d4_tv[, T0 := as.Date(T0)]

  # Fit censoring model using pooled logistic regression ---
  logger::log_info("Fitting IPCW censoring model: y_ipcw_est1 (non-admin censoring) ~ group + followup_day_interval + baseline vars + time-varying vars")

  # Fit single model: group + follow-up day interval + all baseline and time-varying covariates
  ipcw_terms <- c(
    "group",
    "followup_day_interval",
    ipcw_vars,
    "SV_HC_UTI_CAT_TV",
    "SV_ANTIBIOTICS_CAT_TV"
  )
  d4_tv[
    ,
    (ipcw_terms) := lapply(.SD, as.factor),
    .SDcols = ipcw_terms
  ]

  # Fit single model: group + follow-up day interval + all baseline and time-varying covariates
  model_censor <- glm(
    stats::reformulate(ipcw_terms, response = "y_ipcw_est1"),
    data = d4_tv,
    family = binomial(link = "logit")
  )

  # Get predicted probability of censoring and convert to P(uncensored)
  d4_tv[, prob_censoring := predict(model_censor, newdata = d4_tv, type = "response")]
  d4_tv[, prob_uncensored := 1 - prob_censoring]

  # Calculate IPCW weights as inverse probability: IPCW = 1 / P(uncensored)
  d4_tv[, ipcw_raw := 1 / prob_uncensored]

  # Stabilize IPCW in the same style as IPTW: marginal / conditional probability
  p_uncensored_marginal <- mean(d4_tv$prob_uncensored, na.rm = TRUE)
  d4_tv[, ipcw_stabilized := p_uncensored_marginal * ipcw_raw]

  # Truncate stabilized IPCW at configured empirical quantiles
  ipcw_trunc_bounds <- cfg$ipcw_trunc_bounds

  ipcw_cutoffs <- stats::quantile(
    d4_tv$ipcw_stabilized,
    probs = ipcw_trunc_bounds,
    na.rm = TRUE,
    names = FALSE,
    type = 7
  )

  d4_tv[, ipcw_trunc := pmin(pmax(ipcw_stabilized, ipcw_cutoffs[1]), ipcw_cutoffs[2])]

  # Cumulative IPCW by person across ordered follow-up intervals
  data.table::setorder(d4_tv, person_id, T0, index_months)
  d4_tv[, ipcw_stabilized_cum := cumprod(ipcw_stabilized), by = .(person_id, T0)]
  d4_tv[, ipcw_trunc_cum := cumprod(ipcw_trunc), by = .(person_id, T0)]

  logger::log_info(glue::glue(
    "IPCW stabilization applied with marginal P(uncensored) = {round(p_uncensored_marginal, 4)}"
  ))

  logger::log_info(glue::glue(
    "IPCW truncation applied at quantiles [{round(ipcw_trunc_bounds[1], 3)}, {round(ipcw_trunc_bounds[2], 3)}] with cutoffs [{round(ipcw_cutoffs[1], 4)}, {round(ipcw_cutoffs[2], 4)}]"
  ))

  # ---------------------------------------------------------------
  # PART 3: Combine IPTW and IPCW
  # ---------------------------------------------------------------
  
  # Merge IPTW with IPCW ---
  weights_ipcw <- merge(
    results_iptw$D4_PS_Weights_IPTW,
    d4_tv,
    by = c("person_id", "T0", "group","match_id"),
    all = TRUE
  )

  # Create final combined weight ---
  weights_ipcw[, iptw_ipcw := stabilized_iptw * ipcw_stabilized_cum]
  # truncated version of combined weight is calculated by
  # multiplying the truncated IPTW and truncated IPCW weights
  weights_ipcw[, trunc_iptw_ipcw := stabilized_trunc_iptw * ipcw_trunc_cum]

  logger::log_info("Created combined IPTW×IPCW weights")

  # Save D4_StudyCohort_IPCW ---
  picard::save(
    data = weights_ipcw,
    file_path = dir_d4,
    file_name = glue::glue(
      "{cfg$d4_ipcw$name}_{mode}.{cfg$d4_ipcw$ext}")
  )
  
  # --- Cleanup ---
  rm(d4_covariates, d4_tv, d4_tv_final, d4_baseline, results_iptw)
  rm(model_censor)
  gc()
}

logger::log_success("Compute D4_PS_Weights_IPTW_IPCW SUCCEED")

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
