#' Create follow-up/intercurrent-event/end-of-follow-up summary table
#'
#' Builds a 3-column summary table for one analysis group. Optionally, rows can
#' be split by a status variable (e.g., observed vs imputed) and stacked.
#'
#' @param d A data.frame/data.table with person-level data.
#' @param fup_time Character column name for follow-up time.
#' @param reas_cens Character column name for end-of-follow-up reason.
#' @param header Header text for the value column.
#' @param ie_vars Character vector with IE column names.
#' @param ie_labels Character vector with IE labels.
#' @param eof_vars Character vector/list with reason codes to count.
#' @param eof_labels Character vector with labels for eof_vars.
#' @param cens_vars List of reason-code vectors for censoring section.
#' @param cens_labels Character vector with labels for cens_vars.
#' @param row_structure Order of sections to render.
#' @param section_labels Named list with section titles.
#' @param cens_fup Logical. If TRUE, add follow-up summary for each censoring row.
#' @param n_dec Number of decimals for percentages/statistics.
#' @param split_var Optional column name used to split and stack summaries, such as imputed vs observed. If NULL, no split is performed.
#' @param split_levels Optional values of split_var in output order.
#' @param split_labels Optional display labels for split_levels.
fup_ie_cens_tab <- function(d,
                            fup_time,
                            reas_cens,
                            header,
                            ie_vars,
                            ie_labels,
                            eof_vars,
                            eof_labels,
                            cens_vars,
                            cens_labels,
                            row_structure = c("header", "fup", "ie", "eof", "cens"),
                            section_labels = list(
                              fup  = "Person-months of follow-up",
                              ie   = "Occurrence of Intercurrent Events during follow-up, n (%)",
                              eof  = "Reason for end of follow-up, n (%)",
                              cens = "Reason for censoring, n (%)"
                            ),
                            cens_fup = FALSE,
                            n_dec = 1,
                            split_var = NULL,
                            split_levels = NULL,
                            split_labels = NULL) {
  if (length(ie_vars) != length(ie_labels)) {
    stop("ie_vars and ie_labels must have the same length")
  }
  if (length(eof_vars) != length(eof_labels)) {
    stop("eof_vars and eof_labels must have the same length")
  }
  if (length(cens_vars) != length(cens_labels)) {
    stop("cens_vars and cens_labels must have the same length")
  }
  if (!fup_time %in% names(d)) {
    stop("fup_time not found in d")
  }
  if (!reas_cens %in% names(d)) {
    stop("reas_cens not found in d")
  }
  if (!all(ie_vars %in% names(d))) {
    stop("Some ie_vars not found in d")
  }

  if (is.null(split_var)) {
    return(build_single_table(
      d_sub = d,
      header_sub = header,
      fup_time = fup_time,
      reas_cens = reas_cens,
      ie_vars = ie_vars,
      ie_labels = ie_labels,
      eof_vars = eof_vars,
      eof_labels = eof_labels,
      cens_vars = cens_vars,
      cens_labels = cens_labels,
      row_structure = row_structure,
      section_labels = section_labels,
      cens_fup = cens_fup,
      n_dec = n_dec
    ))
  }

  if (!split_var %in% names(d)) {
    stop("split_var not found in d")
  }

  split_vec <- as.character(d[[split_var]])
  if (is.null(split_levels)) {
    split_levels <- unique(split_vec)
    split_levels <- split_levels[!is.na(split_levels)]
  } else {
    split_levels <- as.character(split_levels)
  }

  if (is.null(split_labels)) {
    split_labels <- split_levels
  }

  if (length(split_levels) != length(split_labels)) {
    stop("split_levels and split_labels must have the same length")
  }

  out_list <- vector("list", length(split_levels))
  for (i in seq_along(split_levels)) {
    level_i <- split_levels[i]
    d_i <- d[split_vec == level_i, , drop = FALSE]
    header_i <- paste0(header, " - ", split_labels[i])
    out_list[[i]] <- build_single_table(
      d_sub = d_i,
      header_sub = header_i,
      fup_time = fup_time,
      reas_cens = reas_cens,
      ie_vars = ie_vars,
      ie_labels = ie_labels,
      eof_vars = eof_vars,
      eof_labels = eof_labels,
      cens_vars = cens_vars,
      cens_labels = cens_labels,
      row_structure = row_structure,
      section_labels = section_labels,
      cens_fup = cens_fup,
      n_dec = n_dec
    )
  }

  out <- do.call(rbind, out_list)
  rownames(out) <- NULL
  out
}

#' Driver function to summarise fup
build_single_table <- function(d_sub,
                               header_sub,
                               fup_time,
                               reas_cens,
                               ie_vars,
                               ie_labels,
                               eof_vars,
                               eof_labels,
                               cens_vars,
                               cens_labels,
                               row_structure,
                               section_labels,
                               cens_fup,
                               n_dec) {
    fup_vec <- d_sub[[fup_time]]
    cens_vec <- d_sub[[reas_cens]]
    n_total <- nrow(d_sub)

    if (n_total == 0L) {
      warning(paste0("No rows available for header: ", header_sub))
    }

    if (!all(unlist(eof_vars) %in% unique(cens_vec))) {
      warning("Some eof_vars values not found in reas_cens")
    }
    if (!all(unlist(cens_vars) %in% unique(cens_vec))) {
      warning("Some cens_vars values not found in reas_cens")
    }

    fup_stats <- summ_fun(fup_vec, n_dec)

    n_ie <- vapply(ie_vars, function(v) sum(!is.na(d_sub[[v]])), numeric(1))
    p_ie <- if (n_total > 0) round(100 * n_ie / n_total, n_dec) else rep(0, length(n_ie))

    n_eof <- vapply(eof_vars, function(v) sum(cens_vec %in% v, na.rm = TRUE), numeric(1))
    p_eof <- if (n_total > 0) round(100 * n_eof / n_total, n_dec) else rep(0, length(n_eof))

    ie_col1 <- paste0("   ", ie_labels)
    ie_col2 <- as.character(n_ie)
    ie_col3 <- paste0(p_ie, "%")

    eof_col1 <- paste0("   ", eof_labels)
    eof_col2 <- as.character(n_eof)
    eof_col3 <- paste0(p_eof, "%")

    col1 <- c()
    col2 <- c()
    col3 <- c()

    for (section in row_structure) {
      if (section == "header") {
        col1 <- c(col1, "")
        col2 <- c(col2, paste0(header_sub, " (N = ", n_total, ")"))
        col3 <- c(col3, "")
      }

      if (section == "fup") {
        col1 <- c(
          col1,
          section_labels$fup,
          "   Median (Q1 - Q3)",
          "   Min - Max"
        )
        col2 <- c(
          col2,
          "",
          as.character(fup_stats["med"]),
          as.character(fup_stats["min"])
        )
        col3 <- c(
          col3,
          "",
          sprintf("(%s - %s)", fup_stats["q1"], fup_stats["q3"]),
          as.character(fup_stats["max"])
        )
      }

      if (section == "ie") {
        col1 <- c(col1, section_labels$ie, ie_col1)
        col2 <- c(col2, "", ie_col2)
        col3 <- c(col3, "", ie_col3)
      }

      if (section == "eof") {
        col1 <- c(col1, section_labels$eof, eof_col1)
        col2 <- c(col2, "", eof_col2)
        col3 <- c(col3, "", eof_col3)
      }

      if (section == "cens") {
        col1 <- c(col1, section_labels$cens)
        col2 <- c(col2, "")
        col3 <- c(col3, "")

        for (i in seq_along(cens_vars)) {
          idx <- cens_vec %in% cens_vars[[i]]
          n_i <- sum(idx, na.rm = TRUE)
          p_i <- if (n_total > 0) round(100 * n_i / n_total, n_dec) else 0

          col1 <- c(col1, paste0("   ", cens_labels[i]))
          col2 <- c(col2, as.character(n_i))
          col3 <- c(col3, paste0(p_i, "%"))

          if (cens_fup) {
            fup_i <- summ_fun_by_group(fup_vec, cens_vec, cens_vars[[i]], n_dec)

            col1 <- c(col1, "      Median (Q1 - Q3)", "      Min - Max")
            if (!is.null(fup_i)) {
              col2 <- c(col2, as.character(fup_i["med"]), as.character(fup_i["min"]))
              col3 <- c(col3, sprintf("(%s - %s)", fup_i["q1"], fup_i["q3"]), as.character(fup_i["max"]))
            } else {
              col2 <- c(col2, "", "")
              col3 <- c(col3, "", "")
            }
          }
        }
      }
    }

    data.frame(col1 = col1, col2 = col2, col3 = col3, stringsAsFactors = FALSE)
  }

#' Create summary statistics for a numeric vector
#'
#' @param x Numeric vector.
#' @param n_dec Number of decimals for rounding.
summ_fun <- function(x, n_dec = 1) {
  x <- as.numeric(x)
  x <- x[!is.na(x)]

  if (length(x) == 0L) {
    return(c(med = NA, q1 = NA, q3 = NA, min = NA, max = NA))
  }

  stats <- c(
    med = median(x),
    q1  = unname(quantile(x, 0.25)),
    q3  = unname(quantile(x, 0.75)),
    min = min(x),
    max = max(x)
  )

  round(stats, n_dec)
}

#' Create summary statistics for a numeric vector within groups.
#'
#' @param num_vec Numeric vector.
#' @param group_vec Grouping vector.
#' @param group_values Values in group_vec used to subset.
#' @param n_dec Number of decimals for rounding.
summ_fun_by_group <- function(num_vec,
                              group_vec,
                              group_values,
                              n_dec = 1) {
  idx <- group_vec %in% group_values
  if (!any(idx, na.rm = TRUE)) {
    return(NULL)
  }
  summ_fun(num_vec[idx], n_dec)
}
