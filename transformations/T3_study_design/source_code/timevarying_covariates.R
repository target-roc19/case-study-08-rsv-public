################################################################
# timevarying_covariates ---
# Aim:
# Create D4_StudyCohort_TimeVaryingCovariates from D4_StudyCohort_FUP
# and D4_StudyVariablesAnchored by reshaping to long format (one row
# per person-month) and computing time-varying covariate counts
# categorized as 0, 1, ≥2.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D4_analytic_datasets/D4_StudyCohortFup_*.RDS
# - data/D4_analytic_datasets/D4_StudyVariablesAnchored_*_parquet
#
# Output: ---
# - data/D4_analytic_datasets/D4_StudyCohort_TimeVaryingCovariates_*.RDS
################################################################

# Initial setup ---
## Script logger ---
log_starter()

logger::log_info("[Time-Varying Covariates] - START")
logger::log_info("Start of the timevarying_covariates script.")

## Config loading ---
picard::load_config()
tv_config <- config_project$timevarying_covariates

## Audit setup ---
picard::audit_start(
  file_name = "timevarying_covariates",
  deap_name = config_project$DEAP_configuration$name
)

sv_meta <- picard::load(file.path(config_pipeline$common$dir_bridge, "study_variables.csv"))
sv_meta <- sv_meta[TV == TRUE]
sv_meta[, constructor := "GENERIC"]
sv_meta[, start_offset := -config_values$month_length]
sv_meta[, is_expected_missing := FALSE]

source(
  file.path(
    config_t3$T3$root,
    config_t3$T3$functions,
    "categorize_count.R"
  )
)

# Process each mode ---
for (mode in tv_config$modes) {
  logger::log_info(paste0("Processing mode: ", mode))

  mode_key <- tolower(mode)
  concepts_path <- tv_config$input$d3_concepts[[mode_key]]
  studycohort_path <- tv_config$input$d4_studycohort[[mode_key]]
  fup_path <- tv_config$input$d4_fup[[mode_key]]
  anchored_path <- tv_config$input$d4_anchored_path[[mode_key]]
  output_path <- tv_config$output[[mode_key]]

  if (is.null(concepts_path) || !nzchar(concepts_path)) stop(glue::glue("Missing config_project$timevarying_covariates$input$d3_concepts${mode_key}"))
  if (is.null(studycohort_path) || !nzchar(studycohort_path)) stop(glue::glue("Missing config_project$timevarying_covariates$input$d4_studycohort${mode_key}"))
  if (is.null(fup_path) || !nzchar(fup_path)) stop(glue::glue("Missing config_project$timevarying_covariates$input$d4_fup${mode_key}"))
  if (is.null(anchored_path) || !nzchar(anchored_path)) stop(glue::glue("Missing config_project$timevarying_covariates$input$d4_anchored_path${mode_key}"))
  if (is.null(output_path) || !nzchar(output_path)) stop(glue::glue("Missing config_project$timevarying_covariates$output${mode_key}"))

  # Load D4_StudyCohort_FUP ---
  d4_fup <- picard::load(
    file_path = dirname(fup_path),
    file_name = basename(fup_path)
  )
  d4_fup[, T0 := as.Date(as.character(T0))]

  # load time varying study cohort
  d4_studycohort <- picard::load(
    file_path = dirname(studycohort_path),
    file_name = basename(studycohort_path)
  )[
    group != "UNMATCHED"
  ][, T0 := as.Date(as.character(T0))]

  # Build person-month rows only up to observed follow-up (max 6 months),
  # then map month index to fixed follow-up day intervals.
  d4_studycohort_tv <- merge(
    d4_studycohort,
    d4_fup[, .(person_id, T0, group, match_id, fup_length_pm_est1)],
    by = c("person_id", "T0", "group", "match_id"),
    all.x = TRUE
  )[
    , fup_months := pmin(6L, pmax(0L, as.integer(ceiling(fup_length_pm_est1))))
  ][
    fup_months > 0L
  ][
    rep(seq_len(.N), fup_months)
  ][
    , index_months := seq_len(.N), by = .(person_id, T0)
  ][
    , followup_day_interval := factor(
      c("0-29", "30-59", "60-89", "90-119", "120-149", "150-180")[index_months],
      levels = c("0-29", "30-59", "60-89", "90-119", "120-149", "150-180")
    )
  ][
    , T1 := T0 + index_months * config_values$month_length
  ][
    , c("fup_length_pm_est1", "fup_months") := NULL
  ]

  # between T0 and T1, count SV_HC_UTI and SV_ANTIBIOTICS occurrences
  anchoR::anchor_by_variable(
    population = d4_studycohort_tv,
    metadata = sv_meta,
    concepts = concepts_path,
    anchor_col = "T1",
    anchor_hive_path = anchored_path
  ) # anchoR returns T0 despite anchor_col = T1 so Ill hack this

  tv_anchored <- anchoR::get_anchor_result(
    metadata = sv_meta,
    anchor_hive_path = anchored_path,
    impute_missing = TRUE,
    result_shape = "wide"
  )

  # clean up the anchored data
  data.table::setnames(tv_anchored, "T0", "T1")
  data.table::setnames(tv_anchored,
    new = gsub("^value_", "", names(tv_anchored))
  )

  # Keep only necessary columns: person_id, T0, and the study variable dates
  cnames <- c("person_id", "T1", sv_meta$variable_id)
  tv_anchored <- tv_anchored[, ..cnames]

  # merge with study cohort
  d4_studycohort_tv[, T1 := as.Date(as.character(T1))]
  tv_anchored[, T1 := as.Date(as.character(T1))]
  d4_anchored <- merge(
    d4_studycohort_tv[, .(person_id, T0, T1, group, match_id, index_months, followup_day_interval)],
    tv_anchored,
    by = c("person_id", "T1"),
    all.x = TRUE
  )

  # impute NA entries with 0
  d4_anchored[
  ,
  (sv_meta$variable_id) := lapply(.SD, function(x){
    x <- suppressWarnings(as.integer(x))
    x[is.na(x)] <- 0L
    x
  }),
  .SDcols = sv_meta$variable_id
]

# cumulative sum of TV variables to get counts up to T1
  data.table::setorder(d4_anchored, person_id, T0, T1)
  d4_anchored[
    ,
    (sv_meta$variable_id) := lapply(.SD, cumsum),
    by = .(person_id, T0),
    .SDcols = sv_meta$variable_id
  ]

  # Merge FUP data with anchored variables on person_id and T0 ---
  logger::log_info("Merging FUP data with anchored variables.")
  d4_tv <- merge(
    d4_anchored,
    d4_fup[, .(
      person_id, T0, group, match_id,
      admin_censor_est1,
      fup_d_est1,
      reason_censoring_est1,
      event_est1
    )],
    by = c("person_id", "T0", "group", "match_id"),
    all.x = TRUE
  )

  # Calculate fup_end_est1 (time-varying) ---
  d4_tv[, fup_end_est1 := data.table::fcase(
      !is.na(fup_d_est1) &
      T1 >= fup_d_est1 &
      data.table::shift(T1, type = "lag", fill = T0[1]) < fup_d_est1,
    1L,
    default = 0L
  ), by = .(person_id, T0)]

  # Convert subject-level follow-up fields into row-level intervals.
  d4_tv[, fup_length_days_est1 := as.numeric(difftime(T1, T0, units = "days") + 1)]
  d4_tv[, fup_length_pm_est1 := fup_length_days_est1 / config_values$month_length]

  # Keep outcome on the row where follow-up ends only.
  d4_tv[, event_est1 := as.integer(event_est1 == 1L & fup_end_est1 == 1L)]

  # response variable: non-admin censoring event (y_ipcw_est1) for IPCW model
  d4_tv[, y_ipcw_est1 := as.integer(fup_end_est1 == 1L & admin_censor_est1 == "non-admin")]


  # Calculate time-varying covariates ---
  logger::log_info("Computing time-varying covariate categories.")
  d4_tv[, SV_HC_UTI_CAT_TV := categorize_count(SV_HC_UTI_TV)]
  d4_tv[, SV_ANTIBIOTICS_CAT_TV := categorize_count(SV_ANTIBIOTICS_TV)]

  logger::log_info(paste0("Created D4_StudyCohort_TimeVaryingCovariates with ", nrow(d4_tv), " rows for mode: ", mode))

  # Save output ---
  picard::save(
    data = d4_tv,
    file_path = dirname(output_path),
    file_name = basename(output_path),
    create_plot = TRUE
  )

  logger::log_success(paste0("Successfully created D4_StudyCohort_TimeVaryingCovariates for mode: ", mode))

  rm(d4_fup, d4_anchored, d4_tv)
  gc()
}

logger::log_success("[Time-Varying Covariates] - END")

## Audit end ---
picard::audit_end()

## Script end ---
log_ender()
