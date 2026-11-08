################################################################
# create_eligibility ---
# Aim:
# Build D3_ELIGIBILITY from D3_MULTIVARIATE_EPISODES by:
# 1) computing INCL_IN_ELIGIBLE_POP from composite study-variable logic,
# 2) deriving eligible_exposed and eligible_control flags using
#    SV_NIRSEVIMAB and SV_EXPOSURE_EVER_BEFORE.
#
# Input files: ---
# - configuration/config_project.yaml
# - transformations/common_configuration/RWE-BRIDGE/composite_study_variables.csv
# - data/D3_study_variables/D3_MULTIVARIATE_EPISODES.parquet
#
# Output: ---
# - data/D3_study_variables/D3_ELIGIBILITY.parquet
################################################################

# Initial setup ---
## Script logger ---

log_starter()

logger::log_info("[Eligibility] - START")
logger::log_info("Start of the create_eligibility script.")

## Config loading ---
picard::load_config()
elig_config <- config_project$create_eligibility

## Load functions ---
function_dir <- file.path(config_t3$T3$root, config_t3$T3$functions)
base::source(file.path(function_dir, "compute_eligibility.R"))

## Audit setup ---
picard::audit_start(
    file_name = "create_eligibility",
    deap_name = config_project$DEAP_configuration$name
)

# Load composite study variables metadata ---
logger::log_info("Loading composite study variables metadata from BRIDGE.")
metadata <- data.table::fread(
    file.path(config_pipeline$common$dir_bridge, "composite_study_variables.csv")
)

# Load D3_MULTIVARIATE_EPISODES ---
logger::log_info("Loading D3_MULTIVARIATE_EPISODES.")
D3_MULTIVARIATE_EPISODES <- picard::load(
    file_path = dirname(elig_config$input_path),
    file_name = basename(elig_config$input_path)
)

# Compute eligibility columns ---
# D3_MULTIVARIATE_EPISODES already contains codebook output column names
# (e.g., INCL_UNDER12M, INCL_29W_GESTAGE, EXCL_LRTI_RSV_INFECTION, etc.)
logger::log_info("Computing eligibility columns.")
compute_eligibility(D3_MULTIVARIATE_EPISODES, metadata)

# Save D3_ELIGIBILITY ---
logger::log_info("Saving D3_ELIGIBILITY.")
picard::save(
    data = D3_MULTIVARIATE_EPISODES,
    file_path = dirname(elig_config$output_path),
    file_name = basename(elig_config$output_path),
    create_plot = TRUE
)

logger::log_info("[Eligibility] - END")

## Audit end ---
picard::audit_end()
log_ender()
