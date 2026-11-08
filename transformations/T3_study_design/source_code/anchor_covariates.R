################################################################
# anchor_covariates ---
# Aim:
# Build D4_StudyVariablesAnchored by running the anchoR package
#
# Input files: ---
# - configuration/config_project.yaml
# - configuration/config_values.yaml
# - transformations/common_configuration/RWE-BRIDGE/study_variables.csv
# - data/D3_study_variables/D3_CONCEPTS_parquet (hive-partitioned parquet folder)
#
# Output: ---
# - data/D4_analytic_datasets/D4_StudyVariablesAnchored_parquet/
################################################################

# Initial setup ---
## Script logger ---
log_starter()

logger::log_info("[Study Variables Anchored] - START")
logger::log_info("Start of the anchor_covariates script.")

## Config loading ---
picard::load_config()
cov_config <- config_project$anchor_covariates
dir_d4 <- config_project$outputs$dir_d4
dir_d3 <- config_project$outputs$dir_d3
path_concepts <- file.path(dir_d3, cov_config$d3_concepts)
d3_spells_path <- file.path(dir_d3, cov_config$d3_spells)

source(
  file.path(
    config_t4$T4$root,
    config_t4$T4$functions,
    "calc_age_months.R"
  )
)

## Audit setup ---
picard::audit_start(
  file_name = "anchor_covariates",
  deap_name = config_project$DEAP_configuration$name
)

# Load censoring function
source(
  file.path(
    config_t3$T3$root,
    config_t3$T3$functions,
    "censor_fup.R"
  ))
source(
  file.path(
    config_t3$T3$root,
    config_t3$T3$functions,
    "categorize_count.R"
  ))

# Load study variables metadata ---
logger::log_info("Loading study variables metadata from BRIDGE.")
sv_meta <- data.table::fread(file.path(config_pipeline$common$dir_bridge, "study_variables.csv"))

logger::log_info("Loading D3_SPELLS for birth_date lookup.")
d3_spells <- picard::load(
  file_path = dirname(d3_spells_path),
  file_name = basename(d3_spells_path)
)

# Filter to covariate == TRUE or outcome == TRUE ---
logger::log_info("Filtering study variables to covariate == TRUE or outcome == TRUE")
sv_meta <- sv_meta[covariate == TRUE | outcome == TRUE | IE == TRUE]
logger::log_info(paste0("Number of study variables with covariate = TRUE or outcome = TRUE: ", nrow(sv_meta)))

# Preprocess look-back columns (convert to non-negative integer) ---
sv_meta[, start_offset := as.integer(start_offset)]
sv_meta[, end_offset := as.integer(end_offset)]

# add anchoR input column
sv_meta[, constructor := "GENERIC"]
sv_meta[, is_expected_missing := FALSE]

for (mode in cov_config$modes) {
  # load D4_Study_cohort
  logger::log_info(paste0("Loading D4 study cohort for mode: ", mode))
  d4_study_cohort <- picard::load(
    file_path = dir_d4,
    file_name = glue::glue("{cov_config$d4_studycohort$name}_{mode}.{cov_config$d4_studycohort$ext}")
  )
  # Drop unmatched rows
  d4_study_cohort <- d4_study_cohort[group != "UNMATCHED"]

  # Keep unique person_id + T0 combinations to anchor variables at this level,
  # but keep all columns
  person_t0 <- unique(d4_study_cohort[, .(person_id, T0)])

  logger::log_info(paste0("Running anchoR::anchor for analysis: ", mode))

  hive_path <- file.path(dir_d4, glue::glue("{cov_config$output_anchor_path}_{mode}_parquet"))

  anchoR::anchor_by_variable(
    population = person_t0,
    metadata = sv_meta,
    concepts = path_concepts,
    anchor_col = "T0",
    anchor_hive_path = hive_path
  )

  logger::log_success(paste0("Successfully anchored variables for mode: ", mode))

  # ----------------------------
  # Extract POST-EXPOSURE VARIABLES
  # ----------------------------
  logger::log_info("Extracting anchored post-exposure variables.")
  anchored_fup <- anchoR::get_anchor_result(
    metadata = sv_meta[outcome == TRUE | IE == TRUE],
    anchor_hive_path = hive_path,
    impute_missing = FALSE,
    only_date = TRUE,
    result_shape = "wide",
    population = person_t0
  )

# retain d4_study_cohort original rows
  anchored_fup <- merge(
    d4_study_cohort,
    anchored_fup,
    by = c("person_id", "T0"),
    all.x = TRUE
  )

  # apply censoring reason
  logger::log_info("Applying censoring to follow-up variables.")
  fup <- censor_fup(
    dt = anchored_fup, cfg = config_values, d3_spells_path
  )


  # Save post-exposure variables file
  picard::save(
    data = fup,
    file_path = dir_d4,
    file_name = glue::glue("{cov_config$output$fup_file}_{mode}.{cov_config$output$ext}"),
    create_plot = TRUE
  )
  rm(fup)
  gc()
  logger::log_success(paste0("Successfully created D4_StudyCohort_FUP for mode: ", mode))

  # ----------------------------
  # Extract BASELINE COVARIATES
  # ----------------------------
  logger::log_info("Extracting anchored baseline covariates.")

  anchored_cov <- anchoR::get_anchor_result(
    metadata = sv_meta[covariate == TRUE & information_source != "D3"],
    anchor_hive_path = hive_path,
    impute_missing = TRUE,
    result_shape = "wide",
    population = person_t0
  )

  logger::log_info("Cleaning and merging baseline covariates with study cohort data.")
  # remove date_ columns and rename value_ to variable_id
  covariates <- data.table::copy(anchored_cov)
  date_cols <- grep("^date_", names(covariates), value = TRUE)
  covariates[, (date_cols) := NULL]
  data.table::setnames(covariates,
    new = gsub("^value_", "", names(covariates))
  )

  # join on person_id + T0 to add group from D4_StudyCohort
  covariates <- merge(
    covariates,
    d4_study_cohort[, .(person_id, T0, group, match_id)],
    by = c("person_id", "T0"),
    all.x = TRUE,
    all.y = TRUE
  )

  # add SV_SEX directly from D3_SPELLS
  covariates <- merge(
    covariates,
    d3_spells[, .(person_id, birth_date, SV_SEX = sex_at_instance_creation)],
    by = "person_id",
    all.x = TRUE
  )

  # hot fix integer values NA -> 0
  covariates[, `:=`(
    SV_ANTIBIOTICS = ifelse(is.na(SV_ANTIBIOTICS), 0L, SV_ANTIBIOTICS),
    SV_HC_UTI = ifelse(is.na(SV_HC_UTI), 0L, SV_HC_UTI)
  )]

  covariates[, `:=`(
    SV_HC_UTI_CAT = categorize_count(SV_HC_UTI),
    SV_ANTIBIOTICS_CAT = categorize_count(SV_ANTIBIOTICS)
  )]

  covariates[, SV_AGE := calc_age_months(T0, birth_date)]

  # Save covariates file
  picard::save(
    data = covariates,
    file_path = dir_d4,
    file_name = glue::glue("{cov_config$output$baseline_cov_file}_{mode}.{cov_config$output$ext}"),
    create_plot = TRUE
  )
  rm(covariates)
  gc()
  logger::log_success(paste0("Successfully created D4_StudyCohort_Covariates for mode: ", mode))
}

## Audit end ---
picard::audit_end()

## Script end ---
log_ender()