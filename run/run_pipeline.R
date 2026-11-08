#!/usr/bin/env Rscript

# ------------------------------------------------------------
# VAC4EU Semantic Harmonization Pipeline Runner (Master)
# Orchestrates all phases using the picard::pipeline class.
# ------------------------------------------------------------
if (TRUE) {
  renv::restore()
} else { # in case renv::restore() fails, install the packages manually
  pak::pkg_install("github::UMC-Utrecht-RWE/picard@v1.2.4")
  pak::pkg_install("github::UMC-Utrecht-RWE/T2-DataManagementModel@0.2.1")
  pak::pkg_install("github::UMC-Utrecht-RWE/CohortBuilder@v0.1.0")
  pak::pkg_install("github::UMC-Utrecht-RWE/episodeR@v0.0.3")
  pak::pkg_install("github::UMC-Utrecht-RWE/DescriptiveTable@v0.3.0")
  pak::pkg_install("github::UMC-Utrecht-RWE/anchoR@448bbe1")
  pak::pkg_install("github::UMC-Utrecht-RWE/CohortAnalytics@e5225eb")
}

# --- Setup the environment ---
source("run/run_logger.R")

lm <- picard:::LoggerManager$new()
# picard::track_file_changes(path = "logs") # nolint
lm$configure(verbose = "Normal") # Low or High
logger::log_info("Loading master pipeline")

# ---- Instantiate master pipeline ----
logger::log_debug("Instantiating master pipeline class")
pipeline <- picard::pipeline$new(
  config_pipeline = "configuration/config_pipeline.yaml"
)
###############################################

# TO BE DELETED FOR DEPLOYMENT
# ensure common config_project.yaml depending on input
# Write the content to the output YAML file (overwrite if exists)
# Set configuration template manually (developer choice):
input_file <- "configuration/config_project_sequential.yaml"
# input_file <- "configuration/config_test.yaml"

output_file <- "configuration/config_project.yaml"

if (!file.exists(input_file)) {
  stop(glue::glue("Selected config template does not exist: '{input_file}'"))
}

yaml_content <- yaml::read_yaml(input_file)
yaml::write_yaml(yaml_content, output_file)

###############################################

picard::load_config()
logger::log_debug("Running master pipeline")
pipeline$run()
