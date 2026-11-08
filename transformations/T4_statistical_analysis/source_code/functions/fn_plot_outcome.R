#' Forest plot of crude and adjusted subgroup hazard ratios.
plot_forest <- function(forest_data) {
  pd <- data.table::as.data.table(forest_data)[
    , .(
      analysis_description,
      hr = rr_est_crude,
      lb = rr_lb_crude,
      ub = rr_ub_crude,
      hr_adj = rr_est_adj,
      lb_adj = rr_lb_adj,
      ub_adj = rr_ub_adj
    )
  ]

  analysis_levels <- rev(unique(pd$analysis_description))
  plot_data <- data.table::rbindlist(list(
    pd[, .(
      Analysis = factor(analysis_description, levels = analysis_levels),
      Model = "Crude HR",
      hr = hr,
      lb = lb,
      ub = ub
    )],
    pd[, .(
      Analysis = factor(analysis_description, levels = analysis_levels),
      Model = "Adjusted HR",
      hr = hr_adj,
      lb = lb_adj,
      ub = ub_adj
    )]
  ))

  plot_data <- plot_data[!is.na(hr) & !is.na(lb) & !is.na(ub)]

  ggplot2::ggplot(plot_data, ggplot2::aes(x = hr, y = Analysis, color = Model)) +
    ggplot2::geom_vline(xintercept = 1, linetype = "dashed", color = "grey40") +
    ggplot2::geom_linerange(
      ggplot2::aes(xmin = lb, xmax = ub),
      position = ggplot2::position_dodge(width = 0.6)
    ) +
    ggplot2::geom_point(
      size = 2.5,
      position = ggplot2::position_dodge(width = 0.6)
    ) +
    ggplot2::scale_x_log10() +
    ggplot2::scale_color_manual(
      values = c("Crude HR" = "#1B9E77", "Adjusted HR" = "#D95F02"),
      name = "Estimate"
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      axis.text = ggplot2::element_text(size = 10),
      axis.title = ggplot2::element_text(size = 10),
      legend.position = "right",
      legend.title = ggplot2::element_text(size = 10),
      legend.text = ggplot2::element_text(size = 9)
    ) +
    ggplot2::labs(
      x = "Figure 6: Forest plot for main analysis, sensitivity, supplementary estimates",
      y = NULL
    )
}

# ---- Shared helpers -------------------------------------------------------

# Return TRUE when a scalar configuration value is present and non-empty.
.has_value <- function(x) {
  !is.null(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(as.character(x)))
}

# Extract a scalar value from a one-row data.table used as an analysis specification.
.row_value <- function(dt_row, col_name) {
  dt_row[[col_name]][[1]]
}

# Analyses 1 and 5 are multiply imputed and therefore require curve pooling.
.analysis_needs_pooling <- function(analysis_index) {
  as.integer(analysis_index) %in% c(1L, 5L)
}

# Check that an intermediate data set contains all columns needed by the next step.
.require_columns <- function(dt, required_cols, context_label) {
  missing_cols <- setdiff(required_cols, names(dt))
  if (length(missing_cols) > 0L) {
    logger::log_error(glue::glue(
      "[{context_label}] Missing required columns: {paste(missing_cols, collapse = ', ')}"
    ))
    return(FALSE)
  }
  TRUE
}

# Return a copy with CONTROL set as the Cox/survival-model reference group.
.group_factor <- function(dt) {
  data.table::copy(dt)[, group := relevel(factor(group), ref = "CONTROL")]
}

# Create display labels and enforce Exposed-before-Control legend order.
.group_label_factor <- function(group) {
  factor(
    group,
    levels = c("EXPOSED", "CONTROL"),
    labels = c("Exposed group", "Control group")
  )
}

# Convert survfit strata to long format and retain the cumulative-hazard standard error.
.tidy_survfit <- function(fit) {
  strata <- rep(names(fit$strata), fit$strata)
  cumhaz_se <- if (is.null(fit$std.err)) {
    rep(NA_real_, length(fit$time))
  } else {
    as.numeric(fit$std.err)
  }

  dt <- data.table::data.table(
    time = as.numeric(fit$time),
    surv = as.numeric(fit$surv),
    cumhaz_se = cumhaz_se,
    group = sub("^group=", "", strata)
  )
  anchor <- dt[, .(time = 0, surv = 1, cumhaz_se = 0), by = group]
  data.table::rbindlist(list(anchor, dt), use.names = TRUE)[order(group, time)]
}

# Add pointwise normal confidence limits from an estimate and its variance.
.add_pointwise_limits <- function(dt, estimate_col, variance_col) {
  if (!.require_columns(dt, c(estimate_col, variance_col), "pointwise confidence limits")) {
    return(data.table::data.table())
  }

  out <- data.table::copy(dt)[
    is.finite(get(estimate_col)) &
      is.finite(get(variance_col)) &
      get(variance_col) >= 0
  ]
  if (nrow(out) == 0L) {
    return(data.table::data.table())
  }

  z_value <- stats::qnorm(0.975)
  out[, `:=`(
    lb = get(estimate_col) - z_value * sqrt(get(variance_col)),
    ub = get(estimate_col) + z_value * sqrt(get(variance_col))
  )]
  out[is.finite(lb) & is.finite(ub)]
}

# Pool pointwise estimates and within-imputation variances using Rubin's rule.
.pool_pointwise_rubin <- function(
  dt,
  by_cols,
  estimate_col,
  variance_col,
  context_label
) {
  required_cols <- c(by_cols, estimate_col, variance_col)
  if (!.require_columns(dt, required_cols, context_label)) {
    return(data.table::data.table())
  }

  valid <- data.table::copy(dt)[
    is.finite(get(estimate_col)) &
      is.finite(get(variance_col)) &
      get(variance_col) >= 0
  ]
  if (nrow(valid) == 0L) {
    logger::log_warn(glue::glue("[{context_label}] No finite estimates available for pooling."))
    return(data.table::data.table())
  }

  pooled <- valid[
    , {
      estimates <- get(estimate_col)
      variances <- get(variance_col)
      m <- length(estimates)
      q_bar <- mean(estimates)
      u_bar <- mean(variances)
      b_var <- if (m > 1L) stats::var(estimates) else 0
      total_var <- u_bar + (1 + 1 / m) * b_var

      list(
        pooled_estimate = q_bar,
        within_var = u_bar,
        between_var = b_var,
        total_var = total_var,
        n_imputations = m
      )
    },
    by = by_cols
  ]

  data.table::setnames(pooled, "pooled_estimate", estimate_col)
  .add_pointwise_limits(pooled, estimate_col = estimate_col, variance_col = "total_var")
}

# Fit the same diagnostic separately within each imputation and combine the results.
.fit_by_imputation <- function(dt, fit_fun, analysis_index, diagnostic_label) {
  imputation_data <- split(data.table::copy(dt), by = "imputation_id", keep.by = TRUE)
  fitted <- lapply(imputation_data, function(one_imp) {
    imputation_id <- one_imp$imputation_id[[1]]
    fit_dt <- tryCatch(
      fit_fun(one_imp),
      error = function(e) {
        logger::log_error(glue::glue(
          "{diagnostic_label} fit failed for analysis index {analysis_index}, ",
          "imputation {imputation_id}: {conditionMessage(e)}"
        ))
        NULL
      }
    )

    if (is.null(fit_dt) || nrow(fit_dt) == 0L) {
      return(NULL)
    }

    fit_dt[, imputation_id := imputation_id]
    fit_dt
  })
  fitted <- Filter(Negate(is.null), fitted)

  if (length(fitted) == 0L) {
    return(data.table::data.table())
  }
  data.table::rbindlist(fitted, fill = TRUE)
}

# Load, standardize, weight, trim, and filter the data for one analysis specification.
.prepare_analysis_survival_data <- function(analysis_row, fup_datasets, weight_datasets) {
  analysis_index <- as.integer(.row_value(analysis_row, "analysis_index"))
  estimand <- as.integer(.row_value(analysis_row, "estimand"))
  source_fup <- as.character(.row_value(analysis_row, "source_fup"))

  fup_dt <- data.table::copy(fup_datasets[[source_fup]])
  if (is.null(fup_dt)) {
    logger::log_error(glue::glue("Missing follow-up dataset: {source_fup}"))
    return(NULL)
  }

  fup_col <- paste0("fup_length_days_est", estimand)
  event_col <- paste0("event_est", estimand)
  missing_cols <- setdiff(c(fup_col, event_col), names(fup_dt))
  if (length(missing_cols) > 0L) {
    logger::log_error(glue::glue(
      "Missing required columns in {source_fup}: {paste(missing_cols, collapse = ', ')}"
    ))
    return(NULL)
  }

  data.table::setnames(fup_dt, c(fup_col, event_col), c("fup_days", "event"))

  keep_cols <- intersect(
    c(
      "person_id", "T0", "T1", "group", "match_id", "imputation_id",
      "bw_scenario", "fup_days", "event"
    ),
    names(fup_dt)
  )
  dt <- fup_dt[, ..keep_cols]
  if (!.require_columns(dt, c("person_id", "T0", "T1", "group", "fup_days", "event"), "follow-up")) {
    return(NULL)
  }

  source_weight <- as.character(.row_value(analysis_row, "source_weight"))
  weight_col <- as.character(.row_value(analysis_row, "weight_col"))

  if (.has_value(source_weight) && .has_value(weight_col)) {
    wt <- data.table::copy(weight_datasets[[source_weight]])
    if (is.null(wt)) {
      logger::log_error(glue::glue("Missing weight dataset: {source_weight}"))
      return(NULL)
    }
    if (!(weight_col %in% names(wt))) {
      logger::log_error(glue::glue("Weight column {weight_col} not found in {source_weight}"))
      return(NULL)
    }

    data.table::setnames(wt, weight_col, "ip_weight")
    wt_cols <- intersect(
      c(
        "person_id", "T0", "T1", "group", "match_id", "imputation_id",
        "include_after_trimming", "ip_weight"
      ),
      names(wt)
    )
    wt <- wt[, ..wt_cols]

    join_keys <- intersect(
      c("person_id", "T0", "T1", "group", "match_id", "imputation_id"),
      intersect(names(dt), names(wt))
    )
    if (length(join_keys) == 0L) {
      logger::log_error(glue::glue(
        "No common join keys between {source_fup} and {source_weight}"
      ))
      return(NULL)
    }

    dt <- data.table::merge.data.table(
      dt,
      wt,
      by = join_keys,
      all.x = TRUE,
      all.y = FALSE
    )
  } else {
    dt[, `:=`(ip_weight = 1, include_after_trimming = TRUE)]
  }

  if (!.require_columns(dt, c("include_after_trimming", "ip_weight"), "weights")) {
    return(NULL)
  }

  if (!("imputation_id" %in% names(dt))) {
    if (.analysis_needs_pooling(analysis_index)) {
      logger::log_error(glue::glue(
        "imputation_id is required for multiply imputed analysis index {analysis_index}."
      ))
      return(NULL)
    }
    dt[, imputation_id := 1L]
  }

  # Analysis 4 represents the BW tipping-point scenario used in the main figures.
  if (analysis_index == 4L) {
    if (!("bw_scenario" %in% names(dt))) {
      logger::log_error("bw_scenario is required for analysis index 4.")
      return(NULL)
    }
    dt <- dt[bw_scenario == "bw"]
  }

  dt <- dt[
    include_after_trimming %in% TRUE &
      !is.na(fup_days) &
      !is.na(event) &
      !is.na(group) &
      !is.na(ip_weight)
  ]
  dt[, event := as.integer(event)]

  dt[, `:=`(
    analysis_index = analysis_index,
    analysis_description = as.character(.row_value(analysis_row, "analysis_description"))
  )]

  dt
}

# ---- Schoenfeld helpers ---------------------------------------------------

# Fit the weighted Cox model and return its scaled Schoenfeld residual observations.
.fit_schoenfeld_data <- function(dt, days_per_month) {
  fit <- survival::coxph(
    survival::Surv(fup_days, event) ~ group,
    data = .group_factor(dt),
    weights = ip_weight,
    cluster = person_id,
    robust = TRUE
  )
  zph <- survival::cox.zph(fit)

  data.table::data.table(
    time_months = as.numeric(zph$time) / days_per_month,
    residual = as.numeric(zph$y[, 1])
  )[is.finite(time_months) & is.finite(residual)]
}

# Fit the original loess smoother and predict its estimate and variance on a supplied grid.
.predict_schoenfeld_loess <- function(dt, grid, context_label) {
  loess_fit <- tryCatch(
    stats::loess(residual ~ time_months, data = dt),
    error = function(e) {
      logger::log_error(glue::glue(
        "Schoenfeld loess fit failed for {context_label}: {conditionMessage(e)}"
      ))
      NULL
    }
  )
  if (is.null(loess_fit)) {
    return(data.table::data.table())
  }

  pred <- tryCatch(
    stats::predict(
      loess_fit,
      newdata = data.frame(time_months = grid),
      se = TRUE
    ),
    error = function(e) {
      logger::log_error(glue::glue(
        "Schoenfeld loess prediction failed for {context_label}: {conditionMessage(e)}"
      ))
      NULL
    }
  )
  if (is.null(pred)) {
    return(data.table::data.table())
  }

  data.table::data.table(
    time_months = grid,
    estimate = as.numeric(pred$fit),
    within_var = as.numeric(pred$se.fit)^2
  )[is.finite(estimate) & is.finite(within_var)]
}

# Build one loess curve and its pointwise confidence limits for a non-imputed analysis.
.fit_schoenfeld_loess_curve <- function(dt, n_points = 120L) {
  valid <- data.table::copy(dt)[is.finite(time_months) & is.finite(residual)]
  if (nrow(valid) < 3L) {
    return(data.table::data.table())
  }

  lower_time <- min(valid$time_months)
  upper_time <- max(valid$time_months)
  if (!is.finite(lower_time) || !is.finite(upper_time) || lower_time >= upper_time) {
    return(data.table::data.table())
  }

  grid <- seq(lower_time, upper_time, length.out = n_points)
  pred <- .predict_schoenfeld_loess(valid, grid, context_label = "single analysis")
  if (nrow(pred) == 0L) {
    return(data.table::data.table())
  }

  pred <- .add_pointwise_limits(
    pred,
    estimate_col = "estimate",
    variance_col = "within_var"
  )
  pred[, .(time_months, residual = estimate, lb, ub)]
}

# Pool imputation-specific loess estimates and variances pointwise using Rubin's rule.
.pool_schoenfeld_loess <- function(dt, n_points = 120L) {
  required_cols <- c("imputation_id", "time_months", "residual")
  if (!.require_columns(dt, required_cols, "Schoenfeld pooling")) {
    return(data.table::data.table())
  }

  imputation_data <- split(
    data.table::copy(dt)[is.finite(time_months) & is.finite(residual)],
    by = "imputation_id",
    keep.by = TRUE
  )
  imputation_data <- Filter(function(x) nrow(x) >= 3L, imputation_data)
  if (length(imputation_data) == 0L) {
    return(data.table::data.table())
  }

  # Pool only where every imputation has observed residual times.
  lower_time <- max(vapply(imputation_data, function(x) min(x$time_months), numeric(1)))
  upper_time <- min(vapply(imputation_data, function(x) max(x$time_months), numeric(1)))
  if (!is.finite(lower_time) || !is.finite(upper_time) || lower_time >= upper_time) {
    logger::log_error("No common follow-up-time range across imputations for Schoenfeld pooling.")
    return(data.table::data.table())
  }

  grid <- seq(lower_time, upper_time, length.out = n_points)
  predictions <- lapply(imputation_data, function(one_imp) {
    imputation_id <- one_imp$imputation_id[[1]]
    pred <- .predict_schoenfeld_loess(
      one_imp,
      grid,
      context_label = glue::glue("imputation {imputation_id}")
    )
    if (nrow(pred) == 0L) {
      return(NULL)
    }
    pred[, imputation_id := imputation_id]
    pred
  })
  predictions <- Filter(Negate(is.null), predictions)
  if (length(predictions) == 0L) {
    return(data.table::data.table())
  }

  prediction_dt <- data.table::rbindlist(predictions)
  pooled <- .pool_pointwise_rubin(
    prediction_dt,
    by_cols = "time_months",
    estimate_col = "estimate",
    variance_col = "within_var",
    context_label = "Schoenfeld pooling"
  )
  if (nrow(pooled) == 0L) {
    return(data.table::data.table())
  }

  pooled[, .(time_months, residual = estimate, lb, ub)]
}

# ---- Log-log helpers ------------------------------------------------------

# Fit a weighted survival curve and derive log(-log(S)) estimates and variances.
.fit_loglog_data <- function(dt) {
  fit <- survival::survfit(
    survival::Surv(fup_days, event) ~ group,
    data = .group_factor(dt),
    weights = ip_weight,
    se.fit = TRUE
  )

  ll <- .tidy_survfit(fit)
  ll <- ll[
    time > 0 &
      surv > 0 &
      surv < 1 &
      is.finite(cumhaz_se) &
      cumhaz_se >= 0
  ]
  ll[, cumulative_hazard := -log(surv)]
  ll <- ll[is.finite(cumulative_hazard) & cumulative_hazard > 0]
  ll[, `:=`(
    log_time = log(time),
    cloglog = log(cumulative_hazard),
    # Delta method: Var(log(H)) = Var(H) / H^2, where H = -log(S).
    within_var = (cumhaz_se / cumulative_hazard)^2,
    group_label = .group_label_factor(group)
  )]
  ll[
    is.finite(log_time) &
      is.finite(cloglog) &
      is.finite(within_var) &
      within_var >= 0
  ]
}

# Evaluate a right-continuous step curve and several value columns on one grid.
.predict_step_curve <- function(dt, grid, value_cols) {
  required_cols <- c("log_time", value_cols)
  if (!.require_columns(dt, required_cols, "step-curve prediction")) {
    return(data.table::data.table())
  }

  ordered <- data.table::copy(dt)[order(log_time)]
  # Keep the final value at duplicated event times to preserve the post-event step.
  ordered <- ordered[, lapply(.SD, function(x) x[[length(x)]]), by = log_time, .SDcols = value_cols]
  if (nrow(ordered) == 0L) {
    return(data.table::data.table())
  }

  step_index <- findInterval(grid, ordered$log_time)
  valid <- step_index > 0L & step_index <= nrow(ordered)
  if (!any(valid)) {
    return(data.table::data.table())
  }

  out <- data.table::data.table(log_time = grid[valid])
  for (value_col in value_cols) {
    out[, (value_col) := ordered[[value_col]][step_index[valid]]]
  }
  out
}

# Add native pointwise uncertainty limits to a single log-log survival curve.
.fit_loglog_curve <- function(dt) {
  limited <- .add_pointwise_limits(
    dt,
    estimate_col = "cloglog",
    variance_col = "within_var"
  )
  limited[, .(group_label, log_time, cloglog, lb, ub)]
}

# Pool imputation-specific log-log estimates and variances pointwise using Rubin's rule.
.pool_loglog_curves <- function(dt, n_points = 120L, context_label = "log-log pooling") {
  required_cols <- c(
    "imputation_id", "group_label", "log_time", "cloglog", "within_var"
  )
  if (!.require_columns(dt, required_cols, context_label)) {
    return(data.table::data.table())
  }

  group_data <- split(data.table::copy(dt), by = "group_label", keep.by = TRUE)
  pooled_groups <- lapply(group_data, function(one_group) {
    group_name <- as.character(one_group$group_label[[1]])
    valid <- one_group[
      is.finite(log_time) &
        is.finite(cloglog) &
        is.finite(within_var) &
        within_var >= 0
    ]
    imputation_data <- split(valid, by = "imputation_id", keep.by = TRUE)
    imputation_data <- Filter(function(x) nrow(x) >= 2L, imputation_data)
    if (length(imputation_data) == 0L) {
      logger::log_warn(glue::glue(
        "[{context_label}] No valid imputation curves for {group_name}."
      ))
      return(NULL)
    }

    # Pool only over the follow-up range observed in every retained imputation.
    lower_time <- max(vapply(imputation_data, function(x) min(x$log_time), numeric(1)))
    upper_time <- min(vapply(imputation_data, function(x) max(x$log_time), numeric(1)))
    if (!is.finite(lower_time) || !is.finite(upper_time) || lower_time >= upper_time) {
      logger::log_warn(glue::glue(
        "[{context_label}] No common follow-up-time range across imputations for {group_name}."
      ))
      return(NULL)
    }

    grid <- seq(lower_time, upper_time, length.out = n_points)
    predictions <- lapply(imputation_data, function(one_imp) {
      imputation_id <- one_imp$imputation_id[[1]]
      pred <- .predict_step_curve(
        one_imp,
        grid = grid,
        value_cols = c("cloglog", "within_var")
      )
      if (nrow(pred) == 0L) {
        return(NULL)
      }
      pred[, imputation_id := imputation_id]
      pred
    })
    predictions <- Filter(Negate(is.null), predictions)
    if (length(predictions) == 0L) {
      return(NULL)
    }

    pooled <- .pool_pointwise_rubin(
      data.table::rbindlist(predictions),
      by_cols = "log_time",
      estimate_col = "cloglog",
      variance_col = "within_var",
      context_label = glue::glue("{context_label}: {group_name}")
    )
    if (nrow(pooled) == 0L) {
      return(NULL)
    }

    pooled[, group_label := group_name]
    pooled[, .(group_label, log_time, cloglog, lb, ub)]
  })
  pooled_groups <- Filter(Negate(is.null), pooled_groups)
  if (length(pooled_groups) == 0L) {
    return(data.table::data.table())
  }

  pooled <- data.table::rbindlist(pooled_groups)
  pooled[, group_label := factor(
    group_label,
    levels = c("Exposed group", "Control group")
  )]
  pooled[]
}

# ---- Data collection helpers --------------------------------------------

# Fit and prepare one Schoenfeld curve per analysis, pooling analyses 1 and 5.
.collect_schoenfeld_data <- function(outcome_analysis_types, fup_datasets, weight_datasets, days_per_month) {
  analysis_types <- data.table::as.data.table(outcome_analysis_types)

  out <- lapply(seq_len(nrow(analysis_types)), function(i) {
    analysis_row <- analysis_types[i]
    analysis_index <- as.integer(.row_value(analysis_row, "analysis_index"))
    logger::log_info(glue::glue(
      "Processing Schoenfeld residuals for analysis index {analysis_index}"
    ))

    dt <- .prepare_analysis_survival_data(analysis_row, fup_datasets, weight_datasets)
    if (is.null(dt) || nrow(dt) == 0L) {
      logger::log_warn(glue::glue(
        "No survival rows available for Schoenfeld analysis index {analysis_index}."
      ))
      return(NULL)
    }

    plot_dt <- .fit_by_imputation(
      dt,
      fit_fun = function(one_imp) {
        .fit_schoenfeld_data(one_imp, days_per_month = days_per_month)
      },
      analysis_index = analysis_index,
      diagnostic_label = "Schoenfeld"
    )
    if (nrow(plot_dt) == 0L) {
      return(NULL)
    }

    if (.analysis_needs_pooling(analysis_index)) {
      plot_dt <- .pool_schoenfeld_loess(plot_dt, n_points = 120L)
    } else {
      # Match geom_smooth(method = "loess", se = TRUE) while returning explicit limits.
      plot_dt <- .fit_schoenfeld_loess_curve(plot_dt, n_points = 120L)
    }

    if (nrow(plot_dt) == 0L) {
      return(NULL)
    }

    plot_dt[, `:=`(
      analysis_index = analysis_index,
      analysis_description = as.character(.row_value(analysis_row, "analysis_description"))
    )]
    plot_dt
  })

  data.table::rbindlist(out, fill = TRUE)
}

# Fit and prepare one log-log curve per analysis, pooling analyses 1 and 5.
.collect_loglog_data <- function(outcome_analysis_types, fup_datasets, weight_datasets) {
  analysis_types <- data.table::as.data.table(outcome_analysis_types)

  out <- lapply(seq_len(nrow(analysis_types)), function(i) {
    analysis_row <- analysis_types[i]
    analysis_index <- as.integer(.row_value(analysis_row, "analysis_index"))
    logger::log_info(glue::glue(
      "Processing log-log survival curves for analysis index {analysis_index}"
    ))

    dt <- .prepare_analysis_survival_data(analysis_row, fup_datasets, weight_datasets)
    if (is.null(dt) || nrow(dt) == 0L) {
      logger::log_warn(glue::glue(
        "No survival rows available for log-log analysis index {analysis_index}."
      ))
      return(NULL)
    }

    plot_dt <- .fit_by_imputation(
      dt,
      fit_fun = .fit_loglog_data,
      analysis_index = analysis_index,
      diagnostic_label = "Log-log"
    )
    if (nrow(plot_dt) == 0L) {
      return(NULL)
    }

    if (.analysis_needs_pooling(analysis_index)) {
      plot_dt <- .pool_loglog_curves(
        plot_dt,
        n_points = 120L,
        context_label = glue::glue("log-log pooling, analysis index {analysis_index}")
      )
    } else {
      plot_dt <- .fit_loglog_curve(plot_dt)
    }

    if (nrow(plot_dt) == 0L) {
      return(NULL)
    }

    plot_dt[, `:=`(
      analysis_index = analysis_index,
      analysis_description = as.character(.row_value(analysis_row, "analysis_description"))
    )]
    plot_dt
  })

  data.table::rbindlist(out, fill = TRUE)
}

# Draw one Schoenfeld panel with a solid estimate and dashed uncertainty limits.
.plot_schoenfeld_one <- function(plot_dt, analysis_label) {
  ggplot2::ggplot(
    plot_dt,
    ggplot2::aes(x = time_months, y = residual)
  ) +
    ggplot2::geom_hline(
      yintercept = 0,
      linetype = "dashed",
      color = "grey40"
    ) +
    ggplot2::geom_line(
      ggplot2::aes(y = lb),
      linetype = "dashed",
      color = "black"
    ) +
    ggplot2::geom_line(
      ggplot2::aes(y = ub),
      linetype = "dashed",
      color = "black"
    ) +
    ggplot2::geom_line(
      linewidth = 0.8,
      color = "black"
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(legend.position = "none") +
    ggplot2::labs(
      title = analysis_label,
      x = "Follow-up time (months)",
      y = "Scaled Schoenfeld residual (group)"
    )
}

# Draw one log-log panel with pointwise uncertainty ribbons and step estimates.
.plot_loglog_one <- function(plot_dt, analysis_label) {
  group_colors <- c("Exposed group" = "darkred", "Control group" = "darkblue")

  ggplot2::ggplot(
    plot_dt,
    ggplot2::aes(x = log_time, group = group_label)
  ) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = lb, ymax = ub, fill = group_label),
      alpha = 0.18,
      color = NA,
      na.rm = TRUE
    ) +
    ggplot2::geom_step(
      ggplot2::aes(y = cloglog, color = group_label),
      linewidth = 0.8,
      na.rm = TRUE
    ) +
    ggplot2::scale_color_manual(
      values = group_colors,
      breaks = c("Exposed group", "Control group")
    ) +
    ggplot2::scale_fill_manual(
      values = group_colors,
      breaks = c("Exposed group", "Control group")
    ) +
    ggplot2::guides(fill = "none") +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      legend.title = ggplot2::element_blank(),
      legend.position = "right"
    ) +
    ggplot2::labs(
      title = analysis_label,
      x = "log(follow-up time in days)",
      y = "log(-log(survival probability))"
    )
}

# Build the standard list output for one plot per analysis index.
.build_analysis_plot_list <- function(plot_dt, plot_fun) {
  split_data <- split(plot_dt, plot_dt$analysis_index)
  split_data <- split_data[order(as.integer(names(split_data)))]

  lapply(names(split_data), function(idx) {
    one_dt <- split_data[[idx]]
    label <- unique(one_dt$analysis_description)
    list(
      analysis_index = as.integer(idx),
      analysis_description = label[[1]],
      plot = plot_fun(one_dt, analysis_label = label[[1]])
    )
  })
}

#' Build one Schoenfeld residual plot per analysis index
plot_schoenfeld_by_analysis <- function(
  outcome_analysis_types,
  fup_datasets,
  weight_datasets = list(),
  days_per_month
) {
  if (
    missing(days_per_month) ||
      !is.numeric(days_per_month) ||
      length(days_per_month) != 1L ||
      !is.finite(days_per_month) ||
      days_per_month <= 0
  ) {
    logger::log_error("days_per_month must be one finite, positive numeric value.")
    return(list())
  }

  plot_dt <- .collect_schoenfeld_data(
    outcome_analysis_types = outcome_analysis_types,
    fup_datasets = fup_datasets,
    weight_datasets = weight_datasets,
    days_per_month = days_per_month
  )

  if (nrow(plot_dt) == 0L) {
    logger::log_error("No Schoenfeld data available after analysis filtering.")
    return(list())
  }

  .build_analysis_plot_list(plot_dt, plot_fun = .plot_schoenfeld_one)
}

#' Build one log-log survival plot per analysis index
plot_loglog_by_analysis <- function(outcome_analysis_types, fup_datasets, weight_datasets = list()) {
  plot_dt <- .collect_loglog_data(
    outcome_analysis_types = outcome_analysis_types,
    fup_datasets = fup_datasets,
    weight_datasets = weight_datasets
  )

  if (nrow(plot_dt) == 0L) {
    logger::log_error("No log-log data available after analysis filtering.")
    return(list())
  }

  .build_analysis_plot_list(plot_dt, plot_fun = .plot_loglog_one)
}
