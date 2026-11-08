#' Summarize Stabilized IPTW Weights by Group
#'
#' Creates a compact summary table of stabilized inverse probability of treatment
#' weights for each study group.
#'
#' @param p_matrix A data.table/data.frame containing at least `group` and the
#'   weight column specified in `stab_weight_col`.
#' @param groups Character vector of group names to summarize. Defaults to
#'   `c("CONTROL", "EXPOSED")`.
#' @param stab_weight_col Character scalar; name of the stabilized weight
#'   column in `p_matrix`.
#' @param custom_truncation Numeric length-2 vector with optional lower and
#'   upper truncation cutoffs to report.
#' @param digits Integer; number of decimal places for rounded output.
#'
#' @return A data.frame with summary rows (mean/sd, quartiles, median, range,
#'   p1-p99, truncation cutoffs) and two columns per group.
#' @export
describe_iptw <- function(p_matrix,
                          groups = c("CONTROL", "EXPOSED", "all"), # names of groups
                          stab_weight_col = "IPTW_full_corr", # column name stabilised weights
                          custom_truncation = c(NA, NA), # if additional truncation used, specify here
                          digits = 2) {
  for (gname in groups) {
    # calculate statistics
    if (gname == "all") {
      subset <- "TRUE"
    } else {
      subset <- glue::glue("group == '{gname}'")
    }
    mean_weight <- mean(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], na.rm = TRUE)
    median_weight <- median(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], na.rm = TRUE)
    sd_weight <- sd(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], na.rm = TRUE)
    quants <- quantile(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], c(0.01, 0.25, 0.75, 0.99), na.rm = TRUE)
    min_weight <- min(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], na.rm = TRUE)
    max_weight <- max(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], na.rm = TRUE)
    quants_custom <- quantile(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], custom_truncation, na.rm = TRUE)

    # collect into a data.frame
    gtemp <- data.frame(
      labels = c(
        "Mean (SD)",
        "Q1-Q3",
        "Median",
        "Range (Min-Max)",
        "P1-P99",
        "P5-P95"
      ),
      V1 = round(c(
        mean_weight,
        quants[2],
        median_weight,
        min_weight,
        quants[1],
        quants_custom[1]
      ), digits),
      V2 = round(c(
        sd_weight,
        quants[3],
        NA,
        max_weight,
        quants[4],
        quants_custom[2]
      ), digits)
    )

    # change row names
    colnames(gtemp)[c(2, 3)] <- paste0(gname, c("_V1", "_V2"))

    if (gname == groups[1]) {
      gout <- gtemp
    } else {
      gout <- cbind(gout, gtemp[, -1])
    }
  } # end loop over groups

  return(gout)
}
