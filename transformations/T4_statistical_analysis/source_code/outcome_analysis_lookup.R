################################################################
# outcome_analysis_lookup ---
# Aim:
# Compute the D4 Cohort Analytic Lookup table by estimating incidence rates
# and risk ratios (log-binomial) per outcome table row, combining descriptive
# and comparative measures into a single lookup table for downstream reporting.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D4_analytic_datasets/D4_StudyCohort_FUP_Main.csv
# - data/D4_analytic_datasets/D4_StudyCohort_FUP_Supplement.csv
# - data/D4_analytic_datasets/D4_PS_Weights_IPTW.csv
# - data/D4_analytic_datasets/D4_PS_Weights_IPCW.csv
# - transformations/common_configuration/outcome_analysis_types.csv
#
# Output: ---
# - data/D5_results/D5_CohortAnalyticLookup.csv
################################################################

# Initial setup ---
## Script logger ---
log_starter()

logger::log_info("[Cohort Analytic Lookup] - START")

# ---------------------------------------------------------------------------
# Script body — config loading, I/O, audit (skipped when sourced for tests)
# Runs only when the picard LoggerManager (lm) is present, i.e., inside the
# pipeline runner. Sourcing from tests or interactively defines only the
# functions above.
# ---------------------------------------------------------------------------

## testing setup --
picard::load_config()
is_testing      <- isTRUE(config_pipeline$pipeline_test$testing)
# is_testing <- TRUE
if (!is_testing) {
    cfg <- config_project$outcome_analysis_lookup
    ## Audit setup ---
    picard::audit_start(
    file_name = "outcome_analysis_lookup",
    deap_name = config_project$DEAP_configuration$name
    )
    dir_d4 <- config_project$outputs$dir_d4
    dir_d5 <- config_project$outputs$dir_d5
} else {
    cfg <- config_test$T4$outcome_analysis_tables
    dir_d4 = dir_d5 <- cfg$dir_output
}
dir_metadata <- file.path(config_t4$T4$root, config_t4$T4$config)
dir_function <- file.path(config_t4$T4$root, config_t4$T4$functions)

if (!(base::exists("lm", inherits = TRUE) && base::inherits(lm, "LoggerManager")))
    stop("LoggerManager (lm) is not defined. This script should be run within the pipeline runner.")

## Load functions ---
source(file.path(dir_function, "cohort_analytic_lookup_functions.R"))
source(file.path(dir_function, "format_outcome_table_12_13.R"))

## Load metadata ---
# subset to enabled rows only
# update metadata when sensitivity analysis MI and BW are ready
outcome_analysis_types <- picard::load(
    file_path = dir_metadata,
    file_name = cfg$metadata$outcome_analysis_types
)[enabled == TRUE]

outcome_parameter_lookup <- picard::load(
    file_path = dir_metadata,
    file_name = cfg$metadata$outcome_parameter_lookup
)
## Load inputs ---
logger::log_info("Loading FUP and weight datasets.")
fup_files <-  outcome_analysis_types$source_fup |> unique()
fup_datasets <- setNames(lapply(
    fup_files,
    function(filename) {
        picard::load(
            file_path = dir_d4,
            file_name = glue::glue("{filename}.{cfg$input$ext}")
        )
    }
), fup_files)

weight_files <- outcome_analysis_types$source_weight |> unique()
weight_files <- setdiff(weight_files, "")
weight_datasets <- setNames(lapply(
    weight_files,
    function(filename) {
        picard::load(
            file_path = dir_d4,
            file_name = glue::glue("{filename}.{cfg$input$ext}")
        )
    }
), weight_files)

## Run ---
logger::log_info("Running 5 cohort analysis")
D5_CohortAnalyticLookup_list <- iter_cohort_analytic_lookup(
    fup_datasets             = fup_datasets,
    weight_datasets          = weight_datasets,
    outcome_analysis_types   = outcome_analysis_types,
    aesi_name                = cfg$aesi_name,
    aesi_label               = cfg$aesi_label,
    scale_IR                 = cfg$scale_IR
)
logger::log_success("Completed 5 cohort analytic lookup.")

## Predicted probabilities from analysis index 3
pred_prob_crude <- D5_CohortAnalyticLookup_list[[3]]$pred_prob_crude[[1]]
pred_prob_adj <- D5_CohortAnalyticLookup_list[[3]]$pred_prob_adj[[1]]

## Pooling results for multiple imputations
D5_CohortAnalyticLookup_list_pooled <- pool_cohort_analytic_lookup(
    lookup_list = D5_CohortAnalyticLookup_list,
    outcome_analysis_types = outcome_analysis_types
)

# Tag analysis_index so downstream consumers can select rows reliably even
# when an analysis (e.g. BW scenarios) expands to more than one output row.
D5_CohortAnalyticLookup_list_pooled <- Map(
    function(dt, analysis_index) {
        if (data.table::is.data.table(dt) && nrow(dt) > 0L) dt[, analysis_index := analysis_index]
        dt
    },
    D5_CohortAnalyticLookup_list_pooled,
    outcome_analysis_types$analysis_index
)

# remove pred_prob_ columns in the lookup table
D5_CohortAnalyticLookup <- data.table::rbindlist(
  Filter(
    function(x) {
      if (!data.table::is.data.table(x) || nrow(x) == 0L) return(FALSE)
      pred_prob_cols <- grep("^pred_prob_", names(x), value = TRUE)
      if (length(pred_prob_cols) > 0L) x[, (pred_prob_cols) := NULL]
      TRUE
    },
    D5_CohortAnalyticLookup_list_pooled
  ),
    fill = TRUE,
    use.names = TRUE
)

## Save output ---
cols_keep <- setdiff(names(D5_CohortAnalyticLookup), c("pred_prob_crude", "pred_prob_adj"))
picard::save(
    data      = D5_CohortAnalyticLookup[, ..cols_keep],
    file_path = dir_d5,
    file_name = glue::glue("{config_project$DEAP_configuration$name}_{cfg$output$name}.{cfg$output$ext}")
)

## Create tables ---
table12 <- create_table12(D5_CohortAnalyticLookup, outcome_parameter_lookup[1,], outcome_analysis_types)
table13_crude <- create_table13(D5_CohortAnalyticLookup, outcome_parameter_lookup[2,], outcome_analysis_types)
table13_adjusted <- create_table13(D5_CohortAnalyticLookup, outcome_parameter_lookup[3,], outcome_analysis_types)

## Create table 15 (BW scenarios; analysis index 4 from direct list output) ---
bw_lookup <- D5_CohortAnalyticLookup_list[[4]]
table15 <- create_table15(bw_lookup)

## Create table 15 (BW scenarios; analysis index 4 from direct list output) ---
bw_lookup <- D5_CohortAnalyticLookup_list[[4]]
table15 <- create_table15(bw_lookup)
table16 <- create_table16(pred_prob_crude, pred_prob_adj)

## Create table 17 (observed event counts underlying table 16, analysis index 3) ---
tv_fup_name <- outcome_analysis_types[analysis_index == 3, source_fup]
tv_weight_name <- outcome_analysis_types[analysis_index == 3, source_weight]
tv_weight_col <- outcome_analysis_types[analysis_index == 3, weight_col]
table17 <- table17_observed_count_tv(
    fup_datasets[[tv_fup_name]],
    weight_dt  = weight_datasets[[tv_weight_name]],
    weight_col = tv_weight_col
)

## Save output ---
picard::save(
    data      = table12,
    file_path = dir_d5,
    file_name = glue::glue("{config_project$DEAP_configuration$name}_{cfg$output$table12_name}.{cfg$output$ext}")
)
picard::save(
    data      = table13_crude,
    file_path = dir_d5,
    file_name = glue::glue("{config_project$DEAP_configuration$name}_{cfg$output$table13_crude_name}.{cfg$output$ext}")
)
picard::save(
    data      = table13_adjusted,
    file_path = dir_d5,
    file_name = glue::glue("{config_project$DEAP_configuration$name}_{cfg$output$table13_adjusted_name}.{cfg$output$ext}")
)
picard::save(
    data      = table15,
    file_path = dir_d5,
    file_name = glue::glue("{config_project$DEAP_configuration$name}_{cfg$output$table15_name}.{cfg$output$ext}")
)
picard::save(
    data      = table16,
    file_path = dir_d5,
    file_name = glue::glue("{config_project$DEAP_configuration$name}_{cfg$output$table16_name}.{cfg$output$ext}")
)
picard::save(
    data      = table17,
    file_path = dir_d5,
    file_name = glue::glue("{config_project$DEAP_configuration$name}_{cfg$output$table17_name}.{cfg$output$ext}")
)

## Cleanup ---
rm(
    fup_datasets, weight_datasets,
    outcome_analysis_types,
    outcome_parameter_lookup,
    D5_CohortAnalyticLookup_list,
    D5_CohortAnalyticLookup_list_pooled,
    D5_CohortAnalyticLookup,
    table12, table13_crude, table13_adjusted, table15, table16, table17,
    cfg
)
gc()

if (!is_testing) picard::audit_end()
log_ender()
