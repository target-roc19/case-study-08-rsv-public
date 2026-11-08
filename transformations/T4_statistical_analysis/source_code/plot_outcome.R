log_starter()

logger::log_info("Load configuration and inputs")
## Load configuration ---
picard::load_config()
dir_metadata <- file.path(config_t4$T4$root, config_t4$T4$config)
dir_function <- file.path(config_t4$T4$root, config_t4$T4$functions)
cfg <- config_project$plot_outcome

## Load functions ---
source(file.path(dir_function, "fn_plot_outcome.R"))

## Load metadata ---
outcome_analysis_types <- picard::load(
    file_path = dir_metadata,
    file_name = cfg$metadata$outcome_analysis_types
)

## Load inputs ---
d5_cohort_lookup <- picard::load(
    file_path = config_project$outputs$dir_d5,
    file_name = glue::glue("{config_project$DEAP_configuration$name}_{cfg$input$cohort_lookup}.{cfg$input$file_ext}")
)
d5_cohort_lookup <- data.table::as.data.table(d5_cohort_lookup)
d5_cohort_lookup <- merge(
    outcome_analysis_types[, .(analysis_index, analysis_description, estimand)],
    d5_cohort_lookup,
    by = "analysis_index"
)
# Analysis 4 (BW scenarios) has no single primary scenario; label each
# bw_scenario (bb/bw/wb/ww) separately so the forest plot shows all 4.
if ("bw_scenario" %in% names(d5_cohort_lookup)) {
    d5_cohort_lookup[
        !is.na(bw_scenario),
        analysis_description := paste0(analysis_description, " (", bw_scenario, ")")
    ]
}

## Figure 6: Forest plot for main analysis, sensitivity, supplement estimates ---
logger::log_info("Generate forest plot for main analysis, sensitivity, supplement estimates")
forest_plot <- plot_forest(
    forest_data = d5_cohort_lookup[estimand == 1])
ggplot2::ggsave(
  filename = paste0(config_project$DEAP_configuration$name, "_Figure6_Forest_plot.png"),
  path = config_project$outputs$dir_d5,
  plot = forest_plot,
  width = 30,
  height = 12,
  dpi = 300,
  units = "cm"
)
logger::log_success("Forest plot saved to D5_results directory")

fup_files <- unique(outcome_analysis_types$source_fup)
fup_datasets <- setNames(lapply(
    fup_files,
    function(file_name) {
        picard::load(
            file_path = config_project$outputs$dir_d4,
            file_name = glue::glue("{file_name}.{config_project$outcome_analysis_lookup$input$ext}")
        )
    }
), fup_files)

weight_files <- unique(outcome_analysis_types$source_weight)
weight_files <- weight_files[!is.na(weight_files) & nzchar(trimws(weight_files))]
weight_datasets <- setNames(lapply(
    weight_files,
    function(file_name) {
        picard::load(
            file_path = config_project$outputs$dir_d4,
            file_name = glue::glue("{file_name}.{config_project$outcome_analysis_lookup$input$ext}")
        )
    }
), weight_files)

## Figure 7: Schoenfeld residuals
schoenfeld_enabled <- TRUE
if (!is.null(cfg$diagnostics) && !is.null(cfg$diagnostics$schoenfeld)) {
    schoenfeld_enabled <- isTRUE(cfg$diagnostics$schoenfeld$enabled)
}

if (schoenfeld_enabled) {
    logger::log_info("Generate Schoenfeld residuals plot")

    schoenfeld_plots <- plot_schoenfeld_by_analysis(
        outcome_analysis_types = outcome_analysis_types,
        fup_datasets = fup_datasets,
        weight_datasets = weight_datasets,
        days_per_month = config_values$month_length
    )

    for (obj in schoenfeld_plots) {
        ggplot2::ggsave(
            filename = paste0(
                config_project$DEAP_configuration$name,
                "_Figure7_Schoenfeld_residuals_analysis",
                obj$analysis_index,
                ".png"
            ),
            path = config_project$outputs$dir_d5,
            plot = obj$plot,
            width = 20,
            height = 14,
            dpi = 300,
            units = "cm"
        )
    }
    if (length(schoenfeld_plots) > 0) {
        logger::log_success("Schoenfeld residuals plots saved to D5_results directory")
    } else {
        logger::log_warn("No Schoenfeld residuals plots generated.")
    }
} else {
    logger::log_info("Schoenfeld residuals plotting disabled by config.")
}

## Figure 8: Log(-log) survival plot
loglog_enabled <- TRUE
if (!is.null(cfg$diagnostics) && !is.null(cfg$diagnostics$loglog)) {
    loglog_enabled <- isTRUE(cfg$diagnostics$loglog$enabled)
}

if (loglog_enabled) {
    logger::log_info("Generate Log(-log) survival plot")
    loglog_plots <- plot_loglog_by_analysis(
        outcome_analysis_types = outcome_analysis_types,
        fup_datasets = fup_datasets,
        weight_datasets = weight_datasets
    )

    for (obj in loglog_plots) {
        ggplot2::ggsave(
            filename = paste0(
                config_project$DEAP_configuration$name,
                "_Figure8_Loglog_survival_plot_analysis",
                obj$analysis_index,
                ".png"
            ),
            path = config_project$outputs$dir_d5,
            plot = obj$plot,
            width = 20,
            height = 14,
            dpi = 300,
            units = "cm"
        )
    }
    if (length(loglog_plots) > 0) {
        logger::log_success("Log(-log) survival plots saved to D5_results directory")
    } else {
        logger::log_warn("No Log(-log) survival plots generated.")
    }
} else {
    logger::log_info("Log(-log) survival plotting disabled by config.")
}

## Figure 9: Tipping point analysis
## Elisa will do it - reformat from table 15
log_ender()