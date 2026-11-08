# Format outcome table 12 and 13 based on D5_CohortAnalyticLookup and outcome_parameter_lookup

# Fixed row design ---------------------------------------------------------
# One row per analysis_index (label/section from outcome_analysis_types.csv),
# except analysis 4 (BW scenarios) which has no single primary scenario and
# contributes one row per bw_scenario (bb/bw/wb/ww).

section_titles <- c(
  main        = "Main Analyses",
  sensitivity = "Sensitivity Analyses",
  supplement  = "Supplement Analyses"
)

# Join D5_CohortAnalyticLookup with its analysis metadata and label BW rows
# with their bw_scenario (bb/bw/wb/ww) since analysis 4 has no primary row.
join_analysis_metadata <- function(D5_CohortAnalyticLookup, outcome_analysis_types) {
  x <- data.table::as.data.table(D5_CohortAnalyticLookup)
  meta <- data.table::as.data.table(outcome_analysis_types)[
    , .(analysis_index, analysis_description, analysis_type)
  ]

  x <- merge(meta, x, by = "analysis_index", sort = FALSE)
  if ("bw_scenario" %in% names(x)) {
    x[
      !is.na(bw_scenario),
      analysis_description := paste0(analysis_description, " (", bw_scenario, ")")
    ]
  }

  order_cols <- intersect(c("analysis_index", "bw_scenario"), names(x))
  data.table::setorderv(x, order_cols)
  x
}

# Insert a section header row before each contiguous run of analysis_type
# sharing the same section; dt must already be ordered by analysis_index.
add_analysis_sections <- function(dt) {
  section <- section_titles[dt$analysis_type]
  runs <- rle(section)

  pieces <- list()
  pos <- 1L
  for (i in seq_along(runs$lengths)) {
    len <- runs$lengths[[i]]
    pieces[[length(pieces) + 1L]] <- data.table::data.table(Description = runs$values[[i]])
    pieces[[length(pieces) + 1L]] <- dt[pos:(pos + len - 1L)]
    pos <- pos + len
  }

  out <- data.table::rbindlist(pieces, fill = TRUE)
  out[, analysis_type := NULL]
  out
}

# Formatting helpers ------------------------------------------------------

fmt_num <- function(x, digits = 2) {
  x <- suppressWarnings(as.numeric(x))

  data.table::fifelse(
    is.na(x) | x %in% c(-99, -88),
    "",
    formatC(x, digits = digits, format = "f", big.mark = ",")
  )
}

fmt_ci <- function(lb, ub, digits = 2, style = c("lbub", "dash")) {
  style <- match.arg(style)

  lb <- fmt_num(lb, digits)
  ub <- fmt_num(ub, digits)

  data.table::fifelse(
    lb == "" | ub == "",
    "",
    if (style == "lbub") {
      paste0("Lb, ub: ", lb, ", ", ub)
    } else {
      paste0(lb, "-", ub)
    }
  )
}

add_table_attrs <- function(dt, params) {
  attr(dt, "title") <- params$Description
  attr(dt, "tab_group") <- params$tab_group
  dt
}

# Table 12/13 have one row per analysis_index, except analysis 4 (BW
# scenarios) which contributes one row per bw_scenario — there is no single
# primary BW scenario.
create_table12 <- function(D5_CohortAnalyticLookup, outcome_parameter, outcome_analysis_types) {
  x <- join_analysis_metadata(D5_CohortAnalyticLookup, outcome_analysis_types)
  p <- as.list(outcome_parameter[1, ])

  dt <- data.table::data.table(
    analysis_type = x$analysis_type,
    Description = x$analysis_description,

    `Exposed: N individuals` = fmt_num(x$n_pat_exp, 0),
    `Exposed: N events` = fmt_num(x$n_out_exp, 1),
    `Exposed: Person-Months` = fmt_num(x$py_exp, 1),
    `Exposed: IR per 100,000 person-months` = fmt_num(x$ir_est_exp, 1),
    `Exposed: 95% CI` = fmt_ci(x$ir_lb_exp, x$ir_ub_exp, 1, "dash"),

    `Control: N individuals` = fmt_num(x$n_pat_con, 0),
    `Control: N events` = fmt_num(x$n_out_con, 1),
    `Control: Person-Months` = fmt_num(x$py_con, 1),
    `Control: IR per 100,000 person-months` = fmt_num(x$ir_est_con, 1),
    `Control: 95% CI` = fmt_ci(x$ir_lb_con, x$ir_ub_con, 1, "dash")
  )

  dt <- add_analysis_sections(dt)
  add_table_attrs(dt, p)
}

create_table13 <- function(D5_CohortAnalyticLookup, outcome_parameter, outcome_analysis_types) {
  x <- join_analysis_metadata(D5_CohortAnalyticLookup, outcome_analysis_types)
  p <- as.list(outcome_parameter[1, ])

  is_crude <- p$rr_est_crude == 1

  if (is_crude) {
    rr_est <- x$rr_est_crude
    rr_lb  <- x$rr_lb_crude
    rr_ub  <- x$rr_ub_crude
    rr_type <- "crude"
  } else {
    rr_est <- x$rr_est_adj
    rr_lb  <- x$rr_lb_adj
    rr_ub  <- x$rr_ub_adj
    rr_type <- "adjusted"
  }

  dt <- data.table::data.table(
    analysis_type = x$analysis_type,
    Description = x$analysis_description,
    `Risk Ratio` = fmt_num(rr_est, 2),
    `95%CI` = fmt_ci(rr_lb, rr_ub, 2, "dash")
  )

  dt <- add_analysis_sections(dt)

  attr(dt, "rr_type") <- rr_type
  add_table_attrs(dt, p)
}

create_table15 <- function(D5_CohortAnalyticLookup_bw) {
  x <- data.table::as.data.table(D5_CohortAnalyticLookup_bw)
  x <- x[order(as.integer(bw_id))]

  scenario_lookup <- data.table::data.table(
    bw_id = 1:4,
    Scenario = as.character(1:4),
    `Exposed Group` = c(
      "Best case (lowest event rate)",
      "Worst case (highest event rate)",
      "Best case",
      "Worst case"
    ),
    `Unexposed Group` = c(
      "Worst case (highest event rate)",
      "Best case (lowest event rate)",
      "Best case",
      "Worst case"
    ),
    Interpretation = c(
      "Maximally favors intervention",
      "Maximally favors control",
      "Optimistic for both groups (primary analysis)",
      "Pessimistic for both groups"
    )
  )

  dt <- data.table::merge.data.table(
    scenario_lookup,
    x,
    by = "bw_id",
    all.x = TRUE,
    sort = FALSE
  )

  dt[, `Effect Estimate` := fmt_num(rr_est_adj, 2)]
  dt[, `95% CI` := fmt_ci(rr_lb_adj, rr_ub_adj, 2, "dash")]

  dt[, .(
    Scenario,
    `Exposed Group`,
    `Unexposed Group`,
    Interpretation,
    `Effect Estimate`,
    `95% CI`
  )]
}


format_probability <- function(mean, lb, ub) {
  paste0(
    fmt_num(100 * mean, 1), "% (",
    fmt_num(100 * lb, 1), "%, ",
    fmt_num(100 * ub, 1), "%)"
  )
}

create_table16 <- function(
    pred_prob_crude,
    pred_prob_adj,
    time_var = "index_months",
    group_col = "group",
    treated_group = "EXPOSED",
    untreated_group = "CONTROL") {

  crude <- data.table::as.data.table(pred_prob_crude)
  adj   <- data.table::as.data.table(pred_prob_adj)

  crude[, prediction_type := "Crude"]
  adj[, prediction_type := "Weighted"]

  x <- data.table::rbindlist(
    list(crude, adj),
    use.names = TRUE
  )

  x[, probability_ci := format_probability(
    mean,
    ci_lb,
    ci_ub
  )]

  out <- data.table::dcast(
    x,
    stats::as.formula(
      paste0(time_var, " ~ prediction_type + ", group_col)
    ),
    value.var = "probability_ci"
  )

  data.table::setnames(
    out,
    old = c(
      time_var,
      paste0("Crude_", treated_group),
      paste0("Crude_", untreated_group),
      paste0("Weighted_", treated_group),
      paste0("Weighted_", untreated_group)
    ),
    new = c(
      "Follow-up month",
      "Nirsevimab predicted probability (95% CI)",
      "No treatment predicted probability (95% CI)",
      "Weighted Nirsevimab predicted probability (95% CI)",
      "Weighted no treatment predicted probability (95% CI)"
    )
  )

  out[]
}

# Table 17: cumulative observed (non model-based) event counts per follow-up month and
# treatment group, computed directly from the time-varying FUP dataset used
# for the Table 16 predicted probabilities (analysis index 3). Also reports a
# weighted (IPCW) cumulative event rate, applying D4_PS_Weights_IPCW_Main.
table17_observed_count_tv <- function(fup_dt, weight_dt = NULL, weight_col = "trunc_iptw_ipcw", estimand_n = 1) {
  x <- data.table::as.data.table(fup_dt)
  event_col <- paste0("event_est", estimand_n)

  x[, eventCount := as.integer(as.character(get(event_col)))]
  x[, group := factor(group, levels = c("EXPOSED", "CONTROL"))]

  if (!is.null(weight_dt)) {
    wt <- data.table::copy(data.table::as.data.table(weight_dt))
    if (!(weight_col %in% names(wt))) {
      stop(glue::glue("Weight column '{weight_col}' was not found in weight data."))
    }
    data.table::setnames(wt, weight_col, "weight")
    keys <- intersect(
      intersect(colnames(x), colnames(wt)),
      c("person_id", "T0", "group", "match_id", "index_months")
    )
    wt <- wt[, c(keys, "weight"), with = FALSE]
    x <- data.table::merge.data.table(x, wt, by = keys, all.x = TRUE, all.y = FALSE)
  } else {
    x[, weight := 1.0]
  }

  summary_dt <- x[, .(
    n_ind   = data.table::uniqueN(person_id),
    n_event = sum(eventCount, na.rm = TRUE),
    w_event = sum(weight * eventCount, na.rm = TRUE) /
              sum(weight, na.rm = TRUE) *
              .N
  ), by = .(index_months, group)]
  data.table::setorder(summary_dt, group, index_months)
  summary_dt[, n_event_cum := cumsum(n_event), by = group]
  summary_dt[, w_event_cum := cumsum(w_event), by = group]

  wide <- data.table::dcast(
    summary_dt,
    index_months ~ group,
    value.var = c("n_event_cum", "w_event_cum"),
    drop = FALSE
  )
  data.table::setorder(wide, index_months)

  data.table::data.table(
    `Follow-up month` = wide$index_months,
    `Exposed cumulative N events` = fmt_num(wide$n_event_cum_EXPOSED, 0),
    `Control cumulative N events` = fmt_num(wide$n_event_cum_CONTROL, 0),
    `Exposed weighted cumulative events` = fmt_num(wide$w_event_cum_EXPOSED, 1),
    `Control weighted cumulative events` = fmt_num(wide$w_event_cum_CONTROL, 1)
  )
}

