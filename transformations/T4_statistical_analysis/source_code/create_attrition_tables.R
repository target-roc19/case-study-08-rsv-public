################################################################
# create_attrition_tables ---
# Aim:
# Create attrition and matching statistics tables using D3 eligibility
# and D4 matched cohort outputs (Tables 1, 2, 3).
#
# Input files:
# - configuration/config_project.yaml
# - configuration/config_T4.yaml
# - data/D3_study_variables/D3_ELIGIBILITY.parquet
# - data/D4_analytic_datasets/D4_StudyCohort_Main.parquet
# - data/D4_analytic_datasets/D4_StudyCohort_Supplement.parquet
# - transformations/T4_statistical_analysis/source_code/functions/fn_attrition_tables.R
#
# Output:
# - data/D5_results/<DEAP>_Table1_Attrition.csv
# - data/D5_results/<DEAP>_Table2_MatchMain.csv
# - data/D5_results/<DEAP>_Table3_MatchSupplement.csv
################################################################

# Initial setup ---
log_starter()
logger::log_info("[Attrition Tables] - START")

## Config loading ---
picard::load_config()

## Audit setup ---
picard::audit_start(
    file_name = "create_attrition_tables",
    deap_name = config_project$DEAP_configuration$name
)

## Resolve paths from config ---
dir_d3 <- config_project$create_cohort$input$dir_d3
d3_file <- config_project$create_cohort$input$input_file_name

dir_d4 <- config_project$outputs$dir_d4
d4_base_name <- config_project$create_cohort$output$output_file_name
dir_d5 <- config_project$outputs$dir_d5

## Derive reporting labels from config_values ---
start_d <- as.Date(config_values$start_study_d)
end_d <- as.Date(config_values$end_study_d)
study_period <- paste(format(start_d, "%d %B %Y"), "-", format(end_d, "%d %B %Y"))
exposure_name <- config_values$exposure_name

## Data loading ---
D3_Eligibility <- picard::load(
    file_path = dir_d3,
    file_name = d3_file
)
D4_StudyCohort_Main <- picard::load(
    file_path = dir_d4,
    file_name = paste0(d4_base_name, "_Main.parquet")
)
D4_StudyCohort_Supplement <- picard::load(
    file_path = dir_d4,
    file_name = paste0(d4_base_name, "_Supplement.parquet")
)

## Source functions ---
source(
    file.path(
        config_t4$T4$root,
        config_t4$T4$functions,
        "fn_attrition_tables.R"
    )
)

## Output setup ---
dir.create(dir_d5, recursive = TRUE, showWarnings = FALSE)
deap_name <- trimws(config_project$DEAP_configuration$name %||% "")
prefix <- if (nzchar(deap_name)) paste0(deap_name, "_") else ""

#--------------------------------------------------#
# Create tables
#--------------------------------------------------#

## Table 1: Attrition for entry into the eligible cohort ---
table_1 <- create_table_1(
    d3_eligibility = D3_Eligibility,
    study_period   = study_period,
    exposure_name  = exposure_name
)
out_table_1 <- file.path(dir_d5, paste0(prefix, "Table1_Attrition.csv"))
data.table::fwrite(table_1, out_table_1, na = "")
logger::log_info(paste("Saved Table 1 (attrition) to:", out_table_1))

## Table 2: Matching statistics, main analysis (without replacement) ---
table_2 <- create_table_2(
    d4_main        = D4_StudyCohort_Main
)
out_table_2 <- file.path(dir_d5, paste0(prefix, "Table2_MatchMain.csv"))
data.table::fwrite(table_2, out_table_2, na = "")
logger::log_info(paste("Saved Table 2 (matching main) to:", out_table_2))

## Table 3: Matching statistics, supplementary analysis (with replacement) ---
table_3 <- create_table_3(
    d4_supplementary = D4_StudyCohort_Supplement
)
out_table_3 <- file.path(dir_d5, paste0(prefix, "Table3_MatchSupplement.csv"))
data.table::fwrite(table_3, out_table_3, na = "")
logger::log_info(paste("Saved Table 3 (matching supplement) to:", out_table_3))

# Clean up ---
rm(list = intersect(
    c(
        "D3_Eligibility", "D4_StudyCohort_Main", "D4_StudyCohort_Supplement",
        "table_1", "table_2", "table_3",
        "dir_d3", "d3_file", "dir_d4", "d4_base_name", "dir_d5",
        "start_d", "end_d", "study_period", "exposure_name",
        "deap_name", "prefix",
        "out_table_1", "out_table_2", "out_table_3"
    ),
    ls()
))
gc()

picard::audit_end()
log_ender()