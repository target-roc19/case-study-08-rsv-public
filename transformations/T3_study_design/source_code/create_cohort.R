################################################################
# create_cohort ---
# Aim:
# Create the D4 study cohort by running the matching pipeline on D3 eligibility
# data, producing main and supplementary cohort outputs for downstream analysis.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D3_study_variables/D3_ELIGIBILITY.parquet
#
# Output: ---
# - data/D4_analytic_datasets/D4_StudyCohort_Main.parquet
# - data/D4_analytic_datasets/D4_StudyCohort_Supplement.parquet
# - matching log files and optional intermediate matching outputs
################################################################

# Initial setup ---
## Script logger ---
log_starter()

logger::log_info("[Cohort creation] - START")
logger::log_info("Start of the create_cohort script.")

## Config loading ---
picard::load_config()
create_cohort_config <- config_project$create_cohort
dir_d3 <- config_project$outputs$dir_d3

## Audit setup ---
picard::audit_start(
    file_name = "create_cohort",
    deap_name = config_project$DEAP_configuration$name
)

# Extract matching modes
matching_modes <- unlist(create_cohort_config$matching$modes, use.names = FALSE)

## Load D3 eligibility data ---
logger::log_info("Loading D3 eligibility data from parquet file.")
D3_ELIGIBILITY <- picard::load(
    file_path = dir_d3,
    file_name = create_cohort_config$input$input_file_name
)

## Add year_birth column ---
# CohortBuilder uses year_birth as col_age_iterator to build a year-of-birth
# eligibility window (ctrl BETWEEN exp-1 AND exp+1). Assigning alternating
# values {1, 2} neutralises this window (|1-2|=1 satisfies the window for every
# pair) while providing a range of at least two distinct values, which is
# required by CohortBuilder's internal year-loop progress calculation.
logger::log_info("Setting year_birth to alternating 1/2 (neutralises CohortBuilder age window).")
data.table::setDT(D3_ELIGIBILITY)
D3_ELIGIBILITY[, year_birth := (.I - 1L) %% 2L + 1L]

## Run the matching pipeline for each specified matching mode ---
logger::log_info("Running the matching pipeline.")

set.seed(123456)

for (matching_mode in matching_modes) {
    logger::log_info(paste0("Running the matching pipeline with matching mode: ", matching_mode))

    mode_is_without_replacement <- matching_mode == "without_replacement"
    log_prefix <- ifelse(
        mode_is_without_replacement,
        "matching_log_main",
        "matching_log_supp"
    )
    mode_suffix <- ifelse(mode_is_without_replacement, "Main", "Supplement")

    log_file_name <- paste0(log_prefix, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    output_file_name <- paste0(create_cohort_config$output$output_file_name, "_", mode_suffix)

    profile_table_name <- paste0(create_cohort_config$intermediate_output$profile_table_name, "_", mode_suffix)
    matching_pop_name <- paste0(create_cohort_config$intermediate_output$matching_pop_name, "_", mode_suffix)

    d4_msc <- CohortBuilder::build_study_cohort(
        eligible_pop = D3_ELIGIBILITY,
        matching_vars = unlist(create_cohort_config$matching$vars, use.names = FALSE),
        dir_matching_db = create_cohort_config$matching$dir_matching_db,
        n_cores = create_cohort_config$matching$n_cores,
        log_name = log_file_name,
        output_pars = list(
            save_output = create_cohort_config$output$save_output,
            dir_output = create_cohort_config$output$dir_d4,
            output_file_name = output_file_name
        ),
        intermediate_output_pars = list(
            save_intermediate_outputs = create_cohort_config$intermediate_output$save_intermediate_outputs,
            dir_intermediate_outputs = create_cohort_config$intermediate_output$dir_intermediate_outputs,
            profile_table_name = profile_table_name,
            matching_pop_name = matching_pop_name
        ),
        bootstrap_pars = list(
            with_bootstrap = create_cohort_config$bootstrap$with_bootstrap,
            n_bootstraps = create_cohort_config$bootstrap$n_bootstraps,
            dir_bootstrap = create_cohort_config$bootstrap$dir_bootstrap,
            start_seed = create_cohort_config$matching$start_seed
        ),
        input_column_names = list(
            col_person_id = "person_id",
            col_eligible_exposed = "eligible_exposed",
            col_eligible_control = "eligible_control",
            col_matching_status_start = "start_episode",
            col_matching_status_end = "end_episode",
            col_age_iterator = "year_birth"
        ),
        output_column_names = list(
            col_person_id = "person_id",
            col_match_id = "match_id",
            col_treatment_group = "group",
            col_T0 = "T0"
        ),
        matching_mode = matching_mode
    )

    # special case: control T0 > end_episode, set T0 to end_episode
    d4_msc[group == "CONTROL", T0 := pmin(T0, end_episode)]

    # save
    picard::save(
        data = d4_msc,
        file_path = create_cohort_config$output$dir_d4,
        file_name = glue::glue("{output_file_name}.{create_cohort_config$output$ext}")
    )
    rm(d4_msc)
}

# Clean the environment
rm(
    D3_ELIGIBILITY, output_file_name, profile_table_name, matching_pop_name,
    log_file_name, mode_suffix, log_prefix, mode_is_without_replacement,
    matching_mode, matching_modes
)
gc()

# Close logs
picard::audit_end()
logger::log_info("[Cohort creation] - SUCCEED")

log_ender()