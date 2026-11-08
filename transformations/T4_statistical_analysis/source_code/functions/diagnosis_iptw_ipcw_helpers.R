# --- Helpers ------------------------------------------------------

load_mode_file <- function(file_cfg, directory, mode, prefix = NULL) {
  file_stem <- file_cfg$name
  if (!is.null(prefix)) {
    file_stem <- glue::glue("{prefix}_{file_stem}")
  }

  picard::load(
    file.path(
      directory,
      glue::glue("{file_stem}_{mode}.{file_cfg$ext}")
    )
  )
}

resolve_output_name <- function(name_cfg, mode, field_name, default = NULL) {
  if (is.null(name_cfg)) {
    if (!is.null(default)) {
      return(default)
    }
    stop("Missing output-name config field: ", field_name)
  }

  if (is.character(name_cfg) && length(name_cfg) == 1L) {
    return(name_cfg)
  }

  if (!is.null(names(name_cfg)) && mode %in% names(name_cfg)) {
    return(name_cfg[[mode]])
  }

  if (!is.null(name_cfg$default)) {
    return(name_cfg$default)
  }

  if (!is.null(default)) {
    return(default)
  }

  stop(
    "No output name configured for field '",
    field_name,
    "' and mode '",
    mode,
    "'."
  )
}

diagnostic_enabled <- function(method_cfg, diagnostic_name, mode) {
  diagnostic_cfg <- method_cfg$diagnostics[[diagnostic_name]]

  if (is.logical(diagnostic_cfg)) {
    return(isTRUE(diagnostic_cfg))
  }

  if (is.character(diagnostic_cfg)) {
    return(mode %in% diagnostic_cfg)
  }

  if (is.list(diagnostic_cfg)) {
    enabled <- diagnostic_cfg$enabled
    modes <- diagnostic_cfg$modes

    if (!isTRUE(enabled)) {
      return(FALSE)
    }

    if (is.null(modes)) {
      return(TRUE)
    }

    return(mode %in% unlist(modes))
  }

  FALSE
}

any_diagnostic_enabled <- function(method_cfg, diagnostic_names, mode) {
  any(vapply(
    diagnostic_names,
    diagnostic_enabled,
    logical(1),
    method_cfg = method_cfg,
    mode = mode
  ))
}

select_diagnostic_population <- function(weight_data, method_cfg) {
  include_col <- method_cfg$include_col

  if (is.null(include_col)) {
    return(data.table::copy(weight_data))
  }

  if (!include_col %in% names(weight_data)) {
    stop(
      "Configured include_col '", include_col,
      "' is missing from ", method_cfg$label, " data."
    )
  }

  include_value <- method_cfg$include_value
  weight_data[get(include_col) %in% include_value]
}

resolve_truncation_bounds <- function(method_cfg, project_cfg = NULL) {
  if (is.null(project_cfg)) {
    project_cfg <- get0("config_project", ifnotfound = NULL)
  }

  if (!is.null(project_cfg$weight_IPTW_IPCW)) {
    method_label <- tolower(method_cfg$label)

    if (method_label == "iptw") {
      return(project_cfg$weight_IPTW_IPCW$iptw_trunc_bounds)
    }

    if (method_label == "ipcw") {
      return(project_cfg$weight_IPTW_IPCW$ipcw_trunc_bounds)
    }
  }

  method_cfg$trunc_bounds
}

validate_columns <- function(data, required_cols, context) {
  missing_cols <- setdiff(required_cols, names(data))

  if (length(missing_cols) > 0L) {
    stop(
      "Missing ", context, " column(s): ",
      paste(missing_cols, collapse = ", ")
    )
  }
}

validate_weight_columns <- function(weight_data, method_cfg) {
  validate_columns(
    data = weight_data,
    required_cols = c(
      "person_id",
      method_cfg$weight_col,
      method_cfg$trunc_weight_col
    ),
    context = method_cfg$label
  )
}

get_groups <- function(weight_data) {
  if ("group" %in% names(weight_data)) {
    return(c("CONTROL", "EXPOSED", "all"))
  }

  "all"
}

create_propensity_score_diagnostics <- function(
  weight_data,
  method_cfg,
  mode,
  dir_d5,
  deap_name
) {
  logger::log_info(
    glue::glue("Creating {method_cfg$label} propensity-score diagnostics")
  )

  ps_score_col <- method_cfg$ps_score_col
  include_col <- method_cfg$include_col
  include_value <- method_cfg$include_value
  trim_bounds <- method_cfg$trim_bounds

  validate_columns(
    data = weight_data,
    required_cols = c(ps_score_col, include_col, "group"),
    context = glue::glue("{method_cfg$label} propensity-score diagnostic")
  )

  ps_plot_data <- data.table::copy(weight_data)[
    !is.na(get(ps_score_col))
  ]

  ps_plot_data[
    ,
    group_label := factor(
      group,
      levels = c("CONTROL", "EXPOSED"),
      labels = c("Control", "Exposed")
    )
  ]

  fig_ps_density <- ggplot(
    ps_plot_data,
    aes(x = get(ps_score_col))
  ) +
    geom_density(
      aes(color = group_label, fill = group_label),
      linewidth = 0.8,
      alpha = 0.1
    ) +
    scale_fill_manual(values = c("darkblue", "darkred")) +
    scale_color_manual(values = c("darkblue", "darkred")) +
    scale_x_continuous(breaks = seq(0, 1, 0.2)) +
    theme_minimal() +
    theme(
      legend.title = element_blank(),
      legend.position = "bottom",
      legend.text = element_text(size = 10),
      axis.text = element_text(size = 10),
      axis.title = element_text(size = 10)
    ) +
    labs(x = "Propensity Score", y = "Density")

  ggsave(
    filename = glue::glue(
      "{deap_name}_{resolve_output_name(method_cfg$ps_plot_name, mode, 'ps_plot_name')}_{mode}.png"
    ),
    path = dir_d5,
    plot = fig_ps_density,
    width = 18,
    height = 18,
    dpi = 300,
    units = "cm"
  )

  selected_weights <- select_diagnostic_population(
    weight_data,
    method_cfg
  )

  weight_description <- describe_iptw(
    p_matrix = selected_weights,
    groups = get_groups(selected_weights),
    stab_weight_col = method_cfg$weight_col,
    custom_truncation = c(0.05, 0.95),
    digits = 1
  )

  ps_description <- describe_iptw(
    p_matrix = weight_data[!is.na(get(ps_score_col))],
    groups = get_groups(weight_data),
    stab_weight_col = ps_score_col,
    custom_truncation = c(0.05, 0.95),
    digits = 1
  )

  combined_table <- rbind(
    t(c("Propensity score", rep("", 6))),
    as.matrix(ps_description),
    t(c(method_cfg$label, rep("", 6))),
    as.matrix(weight_description)
  )

  legacy_table_name <- ifelse(
    mode == "Main",
    "Table10_PS_IPTW",
    "Table11_PS_IPTW"
  )

  picard::save(
    data = combined_table,
    file_path = dir_d5,
    file_name = glue::glue(
      "{deap_name}_{resolve_output_name(method_cfg$ps_weight_table_name, mode, 'ps_weight_table_name', legacy_table_name)}_{mode}.csv"
    )
  )
}

create_model_table <- function(
  method_cfg,
  mode,
  dir_d5,
  deap_name,
  common_cfg
) {
  logger::log_info(
    glue::glue("Creating {method_cfg$label} model table")
  )

  d5_ps_coef <- load_mode_file(
    file_cfg = method_cfg$d5_ps_coef,
    directory = dir_d5,
    mode = mode,
    prefix = deap_name
  )
  data.table::setDT(d5_ps_coef)

  prevalence_table <- picard::load(
    file_path = dir_d5,
    file_name = common_cfg$descriptive_overall
  )
  data.table::setDT(prevalence_table)

  table_pre <- prevalence_table[-1, ]
  table_pre[, Prevalence := data.table::fcase(
    label == "Mean (SD)",
    sprintf("%.1f (%s)", N_Overall, perc_Overall),
    label == "Median (Q1 - Q3)",
    sprintf("%.1f %s", N_Overall, perc_Overall),
    is.na(N_Overall),
    NA_character_,
    default = sprintf("%.0f (%s%%)", N_Overall, perc_Overall)
  )]
  table_pre <- table_pre[
    ,
    .(
      label,
      coefficient = ifelse(
        !is.na(var),
        paste0(var, cat),
        NA_character_
      ),
      Prevalence
    )
  ]

  excluded_coefficients <- method_cfg$model_exclude_coefficients

  exp_estimate_table <- data.table::copy(
    d5_ps_coef[
      !coefficient %in% excluded_coefficients
    ]
  )
  exp_estimate_table[
    ,
    exp_estimate_lower :=
      exp(estimate + qnorm(0.025) * std_error)
  ]
  exp_estimate_table[
    ,
    exp_estimate_upper :=
      exp(estimate + qnorm(0.975) * std_error)
  ]
  exp_estimate_table[
    ,
    OR_ci := sprintf(
      "%.2f (%.2f-%.2f)",
      round(exp_estimate, 2),
      round(exp_estimate_lower, 2),
      round(exp_estimate_upper, 2)
    )
  ]

  table_or <- exp_estimate_table[
    ,
    .(coefficient, `Propensity score model` = OR_ci)
  ]

  output_table <- data.table::merge.data.table(
    table_pre,
    table_or,
    by = "coefficient",
    all.x = TRUE,
    sort = FALSE
  )

  picard::save(
    data = output_table[
      ,
      .(label, Prevalence, `Propensity score model`)
    ],
    file_path = dir_d5,
    file_name = glue::glue(
      "{deap_name}_{resolve_output_name(method_cfg$model_table_name, mode, 'model_table_name')}_{mode}.csv"
    )
  )
}

create_weight_description <- function(
  weight_data,
  method_cfg,
  mode,
  dir_d5,
  deap_name
) {
  logger::log_info(
    glue::glue("Creating {method_cfg$label} weight description table")
  )

  selected_weights <- select_diagnostic_population(weight_data, method_cfg)
  truncation_bounds <- resolve_truncation_bounds(method_cfg)

  weight_table <- describe_iptw(
    p_matrix = selected_weights,
    groups = get_groups(selected_weights),
    stab_weight_col = method_cfg$weight_col,
    custom_truncation = truncation_bounds,
    digits = 1
  )

  picard::save(
    data = weight_table,
    file_path = dir_d5,
    file_name = glue::glue(
      "{deap_name}_{resolve_output_name(method_cfg$table_name, mode, 'table_name')}_{mode}.csv"
    )
  )

  invisible(weight_table)
}

create_asd_diagnostics <- function(
  weight_data,
  d4_covariates,
  ps_variables,
  method_cfg,
  mode,
  dir_d5,
  deap_name
) {
  logger::log_info(
    glue::glue("Computing {method_cfg$label} weighted ASDs")
  )

  if (is.null(d4_covariates) || is.null(ps_variables)) {
    stop(
      "ASD diagnostics require d4_covariates and ps_variables for ",
      method_cfg$label,
      " ",
      mode,
      "."
    )
  }

  selected_weights <- select_diagnostic_population(weight_data, method_cfg)

   weight_subset <- selected_weights[
    ,
    c("person_id", method_cfg$trunc_weight_col),
    with = FALSE
  ]

  cov_with_weights <- merge(
    d4_covariates,
    weight_subset,
    by = "person_id"
  )

  asd_unweighted <- DescriptiveTable::compute_asd(
    CovariatesInformation = cov_with_weights,
    metadata = ps_variables,
    referenceExtension = "unweighted",
    use_weights = FALSE
  )

  asd_weighted <- DescriptiveTable::compute_asd(
    CovariatesInformation = cov_with_weights,
    metadata = ps_variables,
    referenceExtension = "weighted",
    use_weights = method_cfg$trunc_weight_col
  )

  asd_combined <- merge(
    asd_unweighted,
    asd_weighted[, .(var, asd_weighted)],
    by = "var"
  )
  asd_combined <- merge(
    asd_combined,
    ps_variables[, .(var, label)],
    by = "var",
    all.x = TRUE
  )

  picard::save(
    data = asd_combined,
    file_path = dir_d5,
    file_name = glue::glue(
      "{deap_name}_{resolve_output_name(method_cfg$asd_table_name, mode, 'asd_table_name')}_{mode}.csv"
    )
  )

  asd_plot_data <- data.table::melt(
    asd_combined,
    id.vars = c("var", "type", "label"),
    measure.vars = c("asd_unweighted", "asd_weighted"),
    variable.name = "diagnostic_stage",
    value.name = "asd"
  )
  asd_plot_data[, asd := as.numeric(asd)]
  asd_plot_data[
    ,
    diagnostic_stage := factor(
      diagnostic_stage,
      levels = c("asd_unweighted", "asd_weighted"),
      labels = c("Before weighting", "After weighting")
    )
  ]
  asd_plot_data[
    ,
    label := data.table::fifelse(is.na(label), var, label)
  ]

  var_order <- asd_plot_data[
    diagnostic_stage == "Before weighting"
  ][order(asd), label]
  asd_plot_data[, label := factor(label, levels = var_order)]

  fig_asd <- ggplot(
    asd_plot_data[!is.na(asd)],
    aes(
      x = label,
      y = asd,
      color = diagnostic_stage,
      shape = diagnostic_stage,
      group = diagnostic_stage
    )
  ) +
    geom_point(size = 3) +
    geom_line(linewidth = 0.5) +
    geom_hline(
      yintercept = 0.1,
      linetype = "dashed",
      color = "black",
      linewidth = 0.5
    ) +
    coord_flip() +
    scale_shape_manual(values = c(1, 1)) +
    scale_color_manual(values = c("darkred", "darkblue")) +
    theme_minimal() +
    theme(
      legend.position = "right",
      legend.title = element_blank(),
      legend.text = element_text(size = 10),
      axis.text = element_text(size = 10),
      axis.title = element_text(size = 10)
    ) +
    labs(
      x = NULL,
      y = "Absolute Standardised Difference"
    )

  ggsave(
    filename = glue::glue(
      "{deap_name}_{resolve_output_name(method_cfg$asd_plot_name, mode, 'asd_plot_name')}_{mode}.png"
    ),
    path = dir_d5,
    plot = fig_asd,
    width = 20,
    height = 14,
    dpi = 300,
    units = "cm"
  )
}

create_weight_distribution <- function(
  weight_data,
  method_cfg,
  mode,
  dir_d5,
  deap_name
) {
  logger::log_info(
    glue::glue("Creating {method_cfg$label} weight distribution plot")
  )

  selected_weights <- select_diagnostic_population(weight_data, method_cfg)

  id_vars <- intersect(
    c("person_id", "group", "time", "follow_up_time"),
    names(selected_weights)
  )

  plot_data <- data.table::melt(
    selected_weights,
    id.vars = id_vars,
    measure.vars = c(
      method_cfg$weight_col,
      method_cfg$trunc_weight_col
    ),
    variable.name = "diagnostic_stage",
    value.name = "weight",
    variable.factor = FALSE
  )
  plot_data <- plot_data[is.finite(weight)]

  truncation_bounds <- resolve_truncation_bounds(method_cfg)
  truncation_label <- sprintf(
    "After truncation at P%d/P%d",
    round(100 * truncation_bounds[1]),
    round(100 * truncation_bounds[2])
  )

  plot_data[
    ,
    diagnostic_stage := factor(
      diagnostic_stage,
      levels = c(
        method_cfg$weight_col,
        method_cfg$trunc_weight_col
      ),
      labels = c("Before truncation", truncation_label)
    )
  ]

  if ("group" %in% names(plot_data)) {
    plot_data[
      ,
      group_label := factor(
        group,
        levels = c("CONTROL", "EXPOSED"),
        labels = c("Control", "Exposed")
      )
    ]

    fig_weight <- ggplot(plot_data, aes(x = weight)) +
      geom_histogram(
        aes(color = group_label, fill = group_label),
        bins = 30,
        position = "identity",
        alpha = 0.4
      ) +
      scale_fill_manual(
        values = c("darkblue", "darkred"),
        na.translate = FALSE
      ) +
      scale_color_manual(
        values = c("darkblue", "darkred"),
        na.translate = FALSE
      )
  } else {
    fig_weight <- ggplot(plot_data, aes(x = weight)) +
      geom_histogram(bins = 30)
  }

  fig_weight <- fig_weight +
    facet_wrap(~diagnostic_stage, ncol = 1, scales = "free") +
    theme_minimal() +
    theme(
      legend.title = element_blank(),
      legend.position = "bottom",
      legend.text = element_text(size = 10),
      axis.text = element_text(size = 10),
      axis.title = element_text(size = 10)
    ) +
    labs(
      x = glue::glue("Stabilized {method_cfg$axis_label} weight"),
      y = "Frequency"
    )

  ggsave(
    filename = glue::glue(
      "{deap_name}_{resolve_output_name(method_cfg$distribution_plot_name, mode, 'distribution_plot_name')}_{mode}.png"
    ),
    path = dir_d5,
    plot = fig_weight,
    width = 18,
    height = 18,
    dpi = 300,
    units = "cm"
  )
}

run_weight_diagnostics <- function(
  weight_data,
  d4_covariates,
  ps_variables,
  method_cfg,
  mode,
  dir_d5,
  deap_name
) {
  weight_diagnostics <- c(
    "weight_description",
    "asd",
    "weight_distribution"
  )

  if (!any_diagnostic_enabled(method_cfg, weight_diagnostics, mode)) {
    return(invisible(NULL))
  }

  validate_weight_columns(weight_data, method_cfg)

  if (diagnostic_enabled(method_cfg, "weight_description", mode)) {
    create_weight_description(
      weight_data = weight_data,
      method_cfg = method_cfg,
      mode = mode,
      dir_d5 = dir_d5,
      deap_name = deap_name
    )
  }

  if (diagnostic_enabled(method_cfg, "asd", mode)) {
    create_asd_diagnostics(
      weight_data = weight_data,
      d4_covariates = d4_covariates,
      ps_variables = ps_variables,
      method_cfg = method_cfg,
      mode = mode,
      dir_d5 = dir_d5,
      deap_name = deap_name
    )
  }

  if (diagnostic_enabled(method_cfg, "weight_distribution", mode)) {
    create_weight_distribution(
      weight_data = weight_data,
      method_cfg = method_cfg,
      mode = mode,
      dir_d5 = dir_d5,
      deap_name = deap_name
    )
  }

  invisible(NULL)
}
