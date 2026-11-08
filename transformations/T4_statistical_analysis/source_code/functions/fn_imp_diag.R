#' Create Imputation Diagnostics Table
#' https://github.com/target-roc19/case-study-07-valproate/blob/main/transformations/T4_statistical_analysis/source_code/functions/fn_imputation_diagnostics.R
#' 
#' @param data A data.table with one row per person (single imputation copy)
#' @param missing_col Logical column indicating missing outcomes
#' @param observed_col Observed outcome column (0/1)
#' @param imputed_col Imputed outcome column (0/1)
#' @param impute_id Column indicating imputation set (for averaging across sets)
#' @param group_col Treatment group column
#' @param exposed_val Exposed group value
#' @param control_val Control group value
#' @param digits Decimal places for percentages
#'
#' @return data.table with exposed/control/overall diagnostics

fn_imp_diag <- function(
  data,
  missing_col = "outcome_missing_estimand1",
  observed_col = "event_est1_observed",
  imputed_col = "event_est1",
  impute_id = "impute_id",
  group_col = "group",
  exposed_val = "EXPOSED",
  control_val = "CONTROL",
  digits = 1
) {
  data <- data.table::as.data.table(data)

  # imutation sets
  if (!impute_id %in% names(data)) {
    logger::log_error(glue::glue("impute_id column '{impute_id}' not found in data"))
  }
  n_impute <- length(unique(data[[impute_id]]))

  # Overall
  n_total <- nrow(data) / n_impute
  n_observed_total <- data[get(missing_col) == FALSE, .N] / n_impute
  n_imputed_total <- data[get(missing_col) == TRUE, .N] / n_impute

  n_missing_overall <- data[get(missing_col) == TRUE, .N] / n_impute
  n_obs_event1 <- data[get(observed_col) == 1L & get(missing_col) == FALSE, .N] / n_impute
  n_imp_event1 <- data[get(imputed_col) == 1L & get(missing_col) == TRUE, .N] / n_impute

  # Exposed
  d_exp <- data[get(group_col) == exposed_val]
  n_exposed <- nrow(d_exp) / n_impute
  n_observed_exposed <- d_exp[get(missing_col) == FALSE, .N] / n_impute
  n_imputed_exposed <- d_exp[get(missing_col) == TRUE, .N] / n_impute

  n_missing_exposed <- d_exp[get(missing_col) == TRUE, .N] / n_impute
  n_obs_event1_exposed <- d_exp[get(observed_col) == 1L & get(missing_col) == FALSE, .N] / n_impute
  n_imp_event1_exposed <- d_exp[get(imputed_col) == 1L & get(missing_col) == TRUE, .N] / n_impute

  # Control
  d_con <- data[get(group_col) == control_val]
  n_control <- nrow(d_con) / n_impute
  n_observed_control <- d_con[get(missing_col) == FALSE, .N] / n_impute
  n_imputed_control <- d_con[get(missing_col) == TRUE, .N] / n_impute

  n_missing_control <- d_con[get(missing_col) == TRUE, .N] / n_impute
  n_obs_event1_control <- d_con[get(observed_col) == 1L & get(missing_col) == FALSE, .N] / n_impute
  n_imp_event1_control <- d_con[get(imputed_col) == 1L & get(missing_col) == TRUE, .N] / n_impute

  # Range of imputed outcomes
  imp_all <- data[get(missing_col) == TRUE, get(imputed_col)]
  imp_exp <- d_exp[get(missing_col) == TRUE, get(imputed_col)]
  imp_con <- d_con[get(missing_col) == TRUE, get(imputed_col)]

  
  data.table::data.table(
    Outcome = c(exposed_val, control_val, "Overall"),
    `Outcome missing (%)` = c(
      fmt_npct(n_missing_exposed, n_exposed, digits),
      fmt_npct(n_missing_control, n_control, digits),
      fmt_npct(n_missing_overall, n_total, digits)
    ),
    `Outcome distribution of observed outcomes (%)` = c(
      fmt_npct(n_obs_event1_exposed, n_observed_exposed, digits),
      fmt_npct(n_obs_event1_control, n_observed_control, digits),
      fmt_npct(n_obs_event1, n_observed_total, digits)
    ),
    `Outcome distribution of imputed outcomes (%)` = c(
      fmt_npct(n_imp_event1_exposed, n_imputed_exposed, digits),
      fmt_npct(n_imp_event1_control, n_imputed_control, digits),
      fmt_npct(n_imp_event1, n_imputed_total, digits)
    ),
    `Range of imputed outcomes` = c(
      fmt_range(imp_exp),
      fmt_range(imp_con),
      fmt_range(imp_all)
    )
  )
}

fmt_npct <- function(n, d, digits = 1) {
  if (is.na(d) || d <= 0) {
    return(glue::glue("{n} / {d} (0.{strrep('0', digits)}%)"))
  }
  glue::glue("{n} / {d} ({round(100 * n / d, digits)}%)")
}
fmt_range <- function(x) {
    x <- x[!is.na(x)]
    if (length(x) == 0L) {
      return("(NA, NA)")
    }
    glue::glue("({as.integer(min(x))}, {as.integer(max(x))})")
  }
