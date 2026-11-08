################################################################
# create_baseline_tables ---
# Aim:
# Create baseline descriptive tables (Tables 4 and 5) for the
# main and supplementary matched cohorts.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D4_analytic_datasets/D4_StudyCohort_Covariates_{Main,Supplementary}.parquet
# - transformations/T4_statistical_analysis/table_metadata/BaselineDescriptives_Metadata.csv
# - transformations/T4_statistical_analysis/table_metadata/table_scenarios.csv
#
# Output: ---
# - data/D5_results/{deap_name}_Table{4a,5a}_Baseline.csv
################################################################

# Initial setup ---
## Script logger ---
log_starter()
logger::log_info("[Baseline tables] - START")

## Config loading ---
picard::load_config()
bl_config <- config_project$create_baseline_tables
dir_d5 <- bl_config$output$dir_d5

## Audit setup ---
picard::audit_start(
    file_name = "create_baseline_tables",
    deap_name = config_project$DEAP_configuration$name
)

## Extract config parameters ---
deap_name    <- config_project$DEAP_configuration$name
file_ext     <- bl_config$input$file_ext

## Load scenario and variable metadata ---
table_scenarios <- picard::load(
    file_path = dirname(bl_config$input$table_scenarios_path),
    file_name = basename(bl_config$input$table_scenarios_path)
)
baseline_metadata <- picard::load(
    file_path = dirname(bl_config$input$baseline_metadata_path),
    file_name = basename(bl_config$input$baseline_metadata_path)
)
baseline_label_lookup <- picard::load(
    file_path = dirname(bl_config$input$baseline_label_lookup_path),
    file_name = basename(bl_config$input$baseline_label_lookup_path)
)
baseline_metadata[, expectedCat := as.character(expectedCat)]
baseline_label_lookup[, integerVal := as.character(integerVal)]
source(file.path(
    config_t4$T4$root,
    config_t4$T4$functions,
    "reshape_output_table.R"
))

# Restrict to enabled scenarios only
table_scenarios <- table_scenarios[table_type == "baseline" & enabled == TRUE]
if (!is.null(bl_config$table_ids) && length(bl_config$table_ids) > 0L) {
    table_scenarios <- table_scenarios[table_id %in% bl_config$table_ids]
}

# ============================================================
# Main loop: iterate over enabled scenarios
# ============================================================
for (i in seq_len(nrow(table_scenarios))) {
    scenario <- table_scenarios[i]

    logger::log_info(paste0(
        "[Baseline tables] Scenario ", scenario$table_id,
        ": cohort=", scenario$cohort,
        ", weighted=", scenario$weighted
    ))

    # Load covariate data for this cohort ---
    cohort_key <- tolower(as.character(scenario$cohort))
    cov_path <- bl_config$input$cov[[cohort_key]]
    d4_data <-  picard::load(file_path = dirname(cov_path), file_name = basename(cov_path))

    # for table 14, add censor_nonadmin_ipcw_est1 to the covariate data
    if (scenario$table_id %in% c("14a", "14b")) {
        fup_path <- bl_config$input$fup[[cohort_key]]
        d4_fup <- picard::load(file_path = dirname(fup_path), file_name = basename(fup_path))
        cols <- c("person_id", "T0", scenario$group_col)
        d4_data <- merge(
            d4_data,
            d4_fup[, ..cols],
            by = c("person_id", "T0"),
            all.x = TRUE
        )
    }

    # filter to subset as in table scenario metadata
    if (!is.na(scenario$subset) && scenario$subset != "") {
        d4_data <- d4_data[eval(parse(text = scenario$subset))]
    }

    if (nrow(d4_data) == 0L) {
        logger::log_warn(paste0(
            "[Baseline tables] Scenario ", scenario$table_id,
            " produced 0 rows after filtering; skipping."
        ))
        next
    }

    # Join weight data if this is a weighted scenario ---
    # NOTE: confirm the weight column name in the weight file before enabling.
    weight_col <- NULL
    if (isTRUE(scenario$weighted) && !is.na(scenario$weight_file)) {
        dir_d4 <- dirname(cov_path)
        d4_weights <- data.table::as.data.table(
            picard::load(file_path = dir_d4, file_name = scenario$weight_file)
        )
        merge_keys <- intersect(
            c("person_id", "T0", scenario$group_col, "match_id"),
            intersect(names(d4_data), names(d4_weights))
        )
        d4_data    <- merge(d4_data, d4_weights, by = merge_keys)
        weight_col <- "stabilized_trunc_iptw"  # TODO: confirm column name in weight file
        rm(d4_weights)
    }

    # Select relevant columns ---
    meta_vars    <- baseline_metadata$var
    missing_vars <- setdiff(meta_vars, names(d4_data))
    if (length(missing_vars) > 0L) {
        logger::log_warn(paste0(
            "[Baseline tables] Variables absent from data and skipped: ",
            paste(missing_vars, collapse = ", ")
        ))
    }
    keep_cols  <- c(scenario$group_col, intersect(meta_vars, names(d4_data)))
    if (!is.null(weight_col)) keep_cols <- c(keep_cols, weight_col)
    d4_input   <- d4_data[, ..keep_cols]
    table_meta <- baseline_metadata[var %in% names(d4_input)]

  # Coerce column types to match metadata specification ---
    for (j in seq_len(nrow(table_meta))) {
        col  <- table_meta$var[j]
        type <- table_meta$type[j]
        if (!col %in% names(d4_input)) next
        if (type == "NUM1") {
            d4_input[, (col) := as.numeric(get(col))]
        } else if (type == "CAT") {
            d4_input[, (col) := toupper(as.character(get(col)))]
        } else if (type == "TF") {
            d4_input[, (col) := as.logical(get(col))]
        }
    }

    # Build and call DescriptivesTable ---
    label_lookup <- baseline_label_lookup[VarName %in% table_meta$var]

    # assign group column to "group" for DescriptiveTable processing
    d4_input[, group := get(scenario$group_col)]

    logger::log_info(paste0(
        "[Baseline tables] Scenario ", scenario$table_id,
        ": calling DescriptiveTable::DescriptivesTable()"
    ))
    tableout <- DescriptiveTable::DescriptivesTable(
        popdf          = d4_input,
        table_metadata = table_meta,
        groupcol       = "group",
        output_format  = "processed",
        calculate_asd  = TRUE,
        keep_varinfo   = FALSE,
        label_lookup   = label_lookup,
        control_types  = FALSE,
        missing_vars   = character(0),
        missing_flag   = -99,
        round_decimals = 3,
        use_weights    = if (!is.null(weight_col)) weight_col else FALSE,
        weighted_stats = !is.null(weight_col),
        output_asd     = TRUE
    )
    table_by_group <- reshape_output_table(tableout$table)

    # EMA feedback: add overall stats
    d4_overall <- data.table::copy(d4_input[, group := "Overall"])
    table_overall <- DescriptiveTable::DescriptivesTable(
        popdf          = d4_overall,
        table_metadata = table_meta,
        groupcol       = "group",
        output_format  = "processed",
        calculate_asd  = FALSE,
        keep_varinfo   = TRUE,
        label_lookup   = label_lookup,
        control_types  = FALSE,
        missing_vars   = character(0),
        missing_flag   = -99,
        round_decimals = 3,
        use_weights    = if (!is.null(weight_col)) weight_col else FALSE,
        weighted_stats = !is.null(weight_col),
        output_asd     = FALSE
    )
    table_overall <- reshape_output_table(table_overall)

    # Combine overall stats with group-specific stats
    table_descriptives <- merge.data.table(
        table_by_group,
        table_overall,
        by = c("label"),
        sort = FALSE,
        all = TRUE
    )
    # shift ASD column to the rightmost position
    setcolorder(table_descriptives, c(setdiff(names(table_descriptives), c("asd", "var", "cat")), "asd"))

    # Save table ---
    out_file <- paste0(deap_name, "_Table", scenario$table_id, "_Baseline.csv")
    logger::log_info(paste0("[Baseline tables] Saving ", out_file, " to ", dir_d5))
    picard::save(
        data = table_descriptives,
        file_path = dir_d5,
        file_name = out_file,
        create_plot = FALSE
    )

       # overall population summary - needed for propensity score table 9
    if (i == 1) {

    picard::save(
        data = table_overall,
        file_path = dir_d5,
        file_name = "BaselineDescriptives_Overall.csv"
    )
    }

    rm(d4_data, d4_input, tableout)
    if (exists("d4_fup")) rm(d4_fup)
    gc()
}

logger::log_info("[Baseline tables] - SUCCESS")

## Audit end ---
picard::audit_end()

## Logger cleanup ---
log_ender()
