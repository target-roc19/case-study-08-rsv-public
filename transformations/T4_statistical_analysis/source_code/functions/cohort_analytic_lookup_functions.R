# ---------------------------------------------------------------------------
# cohort_analytic_lookup_functions.R
# Helper functions for create_cohort_analytic_lookup
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# prepare_aesifup: reshape one FUP data.table for a given estimand and merge
# weights. Converts person-years to person-months so that incidence rates are
# reported per 100,000 person-months.
# output is divided into lists, listed by parameter 'listed_by'
# ---------------------------------------------------------------------------
prepare_aesifup <- function(fup_dt, estimand_n, weight_dt = NULL, weight_col = NULL, timeVar = NULL, listed_by = NULL) {
    dt <- data.table::copy(fup_dt)
    listed_by_col <- if (!is.null(listed_by) && nzchar(trimws(listed_by))) listed_by else NULL

    data.table::setnames(dt, paste0("fup_length_days_est", estimand_n), "fup")
    data.table::setnames(dt, paste0("fup_length_pm_est",  estimand_n), "pm")
    data.table::setnames(dt, paste0("event_est", estimand_n), "eventCount")
    dt[, eventCount := as.integer(as.character(eventCount))]

    keys <- intersect(
        colnames(dt),
        c("person_id", "T0", "T1", "group", "match_id")
    )
    dt[, id := match_id]

    if (!is.null(weight_dt) && !is.null(weight_col) && nzchar(trimws(weight_col))) {
        wt <- data.table::copy(weight_dt)
        if (!(weight_col %in% names(wt))) {
            stop(glue::glue("Weight column '{weight_col}' was not found in weight data."))
        }
        data.table::setnames(wt, weight_col, "ip_weight")
        cols_wt <- c(keys, "ip_weight")
        wt <- wt[, ..cols_wt]
        dt <- data.table::merge.data.table(dt, wt, by = keys, all.x = TRUE, all.y = FALSE)
    } else {
        dt[, ip_weight := 1.0]
    }

    dt[, group := factor(group, levels = c("CONTROL", "EXPOSED"))]
    dt[, person_id_num := as.numeric(as.factor(person_id))]
    data.table::setorder(dt, person_id_num)
    dt[pm >  0, pm_offset := log(pm)]
    if(nrow(dt[pm ==0]) > 0)
        logger::log_warn(glue::glue("Detected {nrow(dt[pm ==0])} individuals with 0 follow up time, check follow up calculations"))
    dt[pm == 0, pm_offset := -Inf]
    if (!is.null(timeVar)) {
      data.table::set(dt, j = timeVar, value = as.factor(dt[[timeVar]]))
    }
    if (!is.null(listed_by_col)) {
        split_idx <- dt[, .(row_id = list(.I)), by = listed_by_col]
        split_list <- lapply(split_idx$row_id, function(idx) {
            dt[idx]
        })
        split_names <- as.character(split_idx[[listed_by_col]])
        split_names[is.na(split_names)] <- "NA"
        names(split_list) <- split_names
        return(split_list)
    }

    list(all = dt)
}

# ---------------------------------------------------------------------------
# iter_cohort_analytic_lookup: iterate over all unique combinations of
# (source_D4, estimand, source_weight) defined in outcome_tables, compute
# incidence rates and log-binomial risk ratios via CohortAnalytics, and
# assemble one output row per outcome_tables entry.
# ---------------------------------------------------------------------------
iter_cohort_analytic_lookup <- function(fup_datasets,
                                        weight_datasets,
                                        outcome_analysis_types,
                                        aesi_name,
                                        aesi_label,
                                        scale_IR = 100000
                                        ) {

    outcome_analysis_types <- data.table::as.data.table(outcome_analysis_types)
    results_by_analysis <- vector("list", nrow(outcome_analysis_types))
    names(results_by_analysis) <- as.character(outcome_analysis_types$analysis_index)

    for (i in seq_len(nrow(outcome_analysis_types))) {
        combo <- outcome_analysis_types[i]
        analysis_results <- list()
        analysis_out_idx <- 1L
        logger::log_info(glue::glue("Computing: {combo$analysis_type} analysis, estimand {combo$estimand} with {combo$source_fup}"))

        fup_dt  <- data.table::copy(fup_datasets[[combo$source_fup]])
        listed_by_col <- if (!is.null(combo$listed_by) && nzchar(trimws(combo$listed_by)) && !is.na(combo$listed_by)) combo$listed_by else NULL
        has_weight <- !is.null(combo$source_weight) && nzchar(trimws(combo$source_weight))
        wt_dt <- if (has_weight) data.table::copy(weight_datasets[[combo$source_weight]]) else NULL

        aesifup_list <- prepare_aesifup(
            fup_dt, estimand_n = combo$estimand,
            weight_dt = wt_dt, weight_col = combo$weight_col,
            listed_by = listed_by_col)

        split_names <- names(aesifup_list)
        for (j in seq_along(aesifup_list)) {
            aesifup <- aesifup_list[[j]]
            split_name <- split_names[[j]]

            logger::log_info(glue::glue(
                "Running analysis_index={combo$analysis_index} {ifelse(is.null(listed_by_col), '', paste0('for ', listed_by_col, '=', split_name))}"
            ))

            res <- tryCatch(
                CohortAnalytics::compute_rates_cohort(
                    aesifup_input                 = aesifup,
                    fupCol                        = "fup",
                    pyrCol                        = "pm",
                    pyr_offset                    = "pm_offset",
                    eventCol                      = "eventCount",
                    iptw                          = "ip_weight",
                    idCol                       = "person_id_num",
                    timeVar                     = combo$timeVar,
                    incidence_model             = combo$incidence_model,
                    target_aesi                   = aesi_name,
                    type                          = "incidence",
                    CImethod                      = "wilson",
                    risk_type                     = "incidence",
                    CumulativeInc                 = FALSE,
                    comparison_measures           = TRUE,
                    scale_IR                      = scale_IR,
                    model_based_control           = FALSE,
                    weighted_IR                   = FALSE,
                    end_risk                      = NULL,
                    output_format                 = "data.frame",
                    minimum_count_for_comparative = 3
                ),
                error = function(e) {
                    logger::log_error(glue::glue(
                        "Error for analysis index {combo$analysis_index}{ifelse(is.null(listed_by_col), '', paste0(' (', listed_by_col, '=', split_name, ')'))}: {conditionMessage(e)}"
                    ))
                    NULL
                }
            )

            if (is.null(res)) {
                next
            }

            res_dt <- data.table::as.data.table(res)
            if (!is.null(listed_by_col) && listed_by_col %in% names(aesifup)) {
                res_dt[, (listed_by_col) := aesifup[[listed_by_col]][1]]
            }
            if ("bw_scenario" %in% names(aesifup)) {
                res_dt[, bw_scenario := aesifup[["bw_scenario"]][1]]
            }

            analysis_results[[analysis_out_idx]] <- res_dt
            analysis_out_idx <- analysis_out_idx + 1L
        }

        results_by_analysis[[i]] <- if (length(analysis_results) == 0L) {
            data.table::data.table()
        } else {
            data.table::rbindlist(analysis_results, fill = TRUE, use.names = TRUE)
        }
    }
    results_by_analysis
}

# ---------------------------------------------------------------------------
# pool_cohort_analytic_lookup: apply metadata-driven pooling rules per
# analysis list element.
# - pooling_method == "rubin": Rubin pooling across split rows (MI analyses)
# - pooling_method == "subset": keep rows matching pooling_condition
# ---------------------------------------------------------------------------
pool_cohort_analytic_lookup <- function(lookup_list, outcome_analysis_types) {
    meta <- data.table::as.data.table(data.table::copy(outcome_analysis_types))

    if (length(lookup_list) == 0L) {
        return(list())
    }

    pool_metric <- function(est, lb, ub, log_scale = FALSE) {
        ok <- is.finite(est) & is.finite(lb) & is.finite(ub)
        if (!any(ok)) {
            return(c(est = NA_real_, lb = NA_real_, ub = NA_real_))
        }

        est <- est[ok]
        lb <- lb[ok]
        ub <- ub[ok]
        if (length(est) == 1L) {
            return(c(est = est[1], lb = lb[1], ub = ub[1]))
        }

        if (log_scale && any(est <= 0 | lb <= 0 | ub <= 0)) {
            log_scale <- FALSE
        }

        q <- if (log_scale) log(est) else est
        se <- if (log_scale) {
            (log(ub) - log(lb)) / (2 * stats::qnorm(0.975))
        } else {
            (ub - lb) / (2 * stats::qnorm(0.975))
        }

        keep <- is.finite(q) & is.finite(se)
        if (!any(keep)) {
            return(c(est = NA_real_, lb = NA_real_, ub = NA_real_))
        }

        pooled <- mice::pool.scalar(Q = q[keep], U = se[keep]^2, n = Inf, k = 1)
        crit <- if (is.finite(pooled$df)) stats::qt(0.975, pooled$df) else stats::qnorm(0.975)
        lo <- pooled$qbar - crit * sqrt(pooled$t)
        hi <- pooled$qbar + crit * sqrt(pooled$t)

        if (log_scale) {
            c(est = exp(pooled$qbar), lb = exp(lo), ub = exp(hi))
        } else {
            c(est = pooled$qbar, lb = lo, ub = hi)
        }
    }

    pool_analysis_rubin <- function(dt) {
        out <- data.table::copy(dt[1])
        est_cols <- grep("_est_", names(dt), value = TRUE)

        for (est_col in est_cols) {
            lb_col <- sub("_est_", "_lb_", est_col)
            ub_col <- sub("_est_", "_ub_", est_col)
            if (!(lb_col %in% names(dt) && ub_col %in% names(dt))) {
                next
            }

            log_scale <- sub("_est_.*$", "", est_col) %in% c("rr", "ir")
            pooled <- pool_metric(dt[[est_col]], dt[[lb_col]], dt[[ub_col]], log_scale)
            out[[est_col]] <- pooled[["est"]]
            out[[lb_col]] <- pooled[["lb"]]
            out[[ub_col]] <- pooled[["ub"]]
        }

        numeric_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
        pooled_cols <- unique(c(est_cols, sub("_est_", "_lb_", est_cols), sub("_est_", "_ub_", est_cols)))
        mean_cols <- setdiff(numeric_cols, pooled_cols)
        for (col in mean_cols) {
            vals <- dt[[col]]
            out[[col]] <- if (all(is.na(vals))) NA_real_ else mean(vals, na.rm = TRUE)
        }

        if ("imputation_id" %in% names(out)) {
            out[, imputation_id := NA_integer_]
        }
        out
    }

    apply_subset_condition <- function(dt, condition_text) {
        cond <- if (is.null(condition_text)) "" else trimws(condition_text)
        if (!nzchar(cond)) {
            return(data.table::copy(dt))
        }

        tryCatch(
            dt[eval(parse(text = cond))],
            error = function(e) {
                logger::log_warn(glue::glue("Invalid pooling_condition '{cond}', keeping unfiltered rows: {conditionMessage(e)}"))
                data.table::copy(dt)
            }
        )
    }

    n_items <- nrow(meta)
    out_list <- vector("list", n_items)

    for (i in seq_len(n_items)) {
        dt <- lookup_list[[i]]
        if (!data.table::is.data.table(dt) || nrow(dt) == 0L) {
            out_list[[i]] <- data.table::data.table()
            next
        }

        combo <- meta[i]
        method <- if ("pooling_method" %in% names(combo)) as.character(combo$pooling_method[[1]]) else ""
        method <- trimws(ifelse(is.na(method), "", method))

        if (identical(method, "rubin")) {
            out_list[[i]] <- pool_analysis_rubin(data.table::copy(dt))
        } else if (identical(method, "subset")) {
            cond <- if ("pooling_condition" %in% names(combo)) as.character(combo$pooling_condition[[1]]) else ""
            out_list[[i]] <- apply_subset_condition(data.table::copy(dt), cond)
        } else {
            out_list[[i]] <- data.table::copy(dt)
        }
    }

    out_list
}