# ---------------------------------------------------------------
# Step: create_iptw_ipcw_tables
#
# The actual diagnostics are controlled by
# config_project$diagnosis_IPTW_IPCW.
#
# The main script only:
#   - loads config
#   - sources helper functions
#   - iterates over configured methods and modes
#   - dispatches enabled diagnostics
# ---------------------------------------------------------------

if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("create_iptw_ipcw_tables.R")
  lm$start_capturing_prints()
}

library(ggplot2)

logger::log_info("[create_iptw_ipcw_tables] - START")

# --- Configuration ------------------------------------------------
picard::load_config()

deap_name <- config_project$DEAP_configuration$name

if (!isTRUE(config_pipeline$pipeline_test$testing)) {
  diagnosis_cfg <- config_project$diagnosis_IPTW_IPCW
  dir_d4 <- config_project$outputs$dir_d4
  dir_d5 <- config_project$outputs$dir_d5
} else {
  diagnosis_cfg <- config_test$T4$diagnosis_IPTW_IPCW
  dir_d4 <- diagnosis_cfg$dir_d4
  dir_d5 <- diagnosis_cfg$dir_d5
}

common_cfg <- diagnosis_cfg$common

source(file.path(common_cfg$ps_fn_dir, "describe_iptw.R"))
source(file.path(config_t4$T4$root, config_t4$T4$functions, "diagnosis_iptw_ipcw_helpers.R"))

weight_methods <- common_cfg$method_weights %||% setdiff(names(diagnosis_cfg), "common")

# --- Lazy shared metadata -----------------------------------------

load_ps_variables_once <- local({
  ps_variables_cache <- NULL

  function() {
    if (is.null(ps_variables_cache)) {
      ps_variables_cache <<- picard::load(
        file.path(
          config_t4$T4$root,
          config_t4$T4$config,
          common_cfg$ps_variables
        )
      )
      data.table::setDT(ps_variables_cache)
    }

    ps_variables_cache
  }
})

# --- Iterate over configured weighting methods and modes -----------

for (method_name in weight_methods) {
  method_cfg <- diagnosis_cfg[[method_name]]

  if (is.null(method_cfg)) {
    stop(
      "Configured method_weights includes '",
      method_name,
      "', but diagnosis_cfg$",
      method_name,
      " is missing."
    )
  }

  if (!isTRUE(method_cfg$enabled %||% TRUE)) {
    next
  }

  for (mode in method_cfg$modes) {
    logger::log_info(
      glue::glue("Processing {method_cfg$label}, mode: {mode}")
    )

    weight_data <- load_mode_file(
      file_cfg = method_cfg$d4_weights,
      directory = dir_d4,
      mode = mode
    )
    data.table::setDT(weight_data)

    d4_covariates <- NULL
    ps_variables <- NULL

    if (diagnostic_enabled(method_cfg, "asd", mode)) {
      d4_covariates <- load_mode_file(
        file_cfg = common_cfg$d4_covariates,
        directory = dir_d4,
        mode = mode
      )
      data.table::setDT(d4_covariates)

      ps_variables <- load_ps_variables_once()
    }

    if (diagnostic_enabled(method_cfg, "propensity_score", mode)) {
      create_propensity_score_diagnostics(
        weight_data = weight_data,
        method_cfg = method_cfg,
        mode = mode,
        dir_d5 = dir_d5,
        deap_name = deap_name
      )
    }

    if (diagnostic_enabled(method_cfg, "model_table", mode)) {
      create_model_table(
        method_cfg = method_cfg,
        mode = mode,
        dir_d5 = dir_d5,
        deap_name = deap_name,
        common_cfg = common_cfg
      )
    }

    run_weight_diagnostics(
      weight_data = weight_data,
      d4_covariates = d4_covariates,
      ps_variables = ps_variables,
      method_cfg = method_cfg,
      mode = mode,
      dir_d5 = dir_d5,
      deap_name = deap_name
    )

    rm(weight_data, d4_covariates, ps_variables)
  }
}

logger::log_info("[create_iptw_ipcw_tables] - SUCCEED")

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
