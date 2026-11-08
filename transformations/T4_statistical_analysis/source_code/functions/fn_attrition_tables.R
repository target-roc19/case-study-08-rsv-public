################################################################
# fn_attrition_tables ---
# Aim:
# Build attrition and matching statistics tables for CS08-RSV.
#
# Tables:
# - Table 1: attrition for entry into the eligible cohort
# - Table 2: matched cohort main analysis (without replacement)
# - Table 3: matched cohort supplementary analysis (with replacement)
#
# D3_ELIGIBILITY columns used:
#   person_id, SV_NIRSEVIMAB, SV_EXPOSURE_EVER_BEFORE,
#   INCL_UNDER12M, INCL_29W_GESTAGE, INCL_ENROLLED,
#   EXCL_LRTI_RSV_INFECTION, EXCL_NIVERSIMAB_MOTHER,
#   EXCL_IMMUNODEF, EXCL_LUNGDIS, EXCL_HEARTDIS,
#   EXCL_CYSTICFRIBROSIS, EXCL_NEUROMUSCULARDIS,
#   EXCL_CRANCONANOM, EXCL_GESTAGE_AGESEAS, EXCL_HEARTTRANS,
#   INCL_IN_ELIGIBLE_POP, eligible_exposed, eligible_control
################################################################

.as_logical <- function(x) {
    if (is.logical(x)) {
        return(x)
    }
    if (is.numeric(x) || is.integer(x)) {
        return(x != 0)
    }
    if (is.character(x)) {
        return(toupper(trimws(x)) %in% c("TRUE", "T", "1", "YES", "Y"))
    }
    as.logical(x)
}

.assert_required_cols <- function(dt, required_cols, table_name) {
    missing_cols <- setdiff(required_cols, names(dt))
    if (length(missing_cols) > 0) {
        stop(sprintf(
            "%s is missing required columns: %s",
            table_name, paste(missing_cols, collapse = ", ")
        ))
    }
}

.pct <- function(numerator, denominator, digits = 1) {
    if (is.na(denominator) || denominator == 0) {
        return(NA_character_)
    }
    format(round((numerator / denominator) * 100, digits), nsmall = digits)
}

.format_count <- function(x) {
    if (is.na(x)) {
        return(NA_character_)
    }
    format(x, scientific = FALSE, trim = TRUE)
}

.finalize_attrition_table <- function(dt, return_na = FALSE) {
    out <- data.table::copy(dt)
    if (!return_na) {
        out[is.na(N), N := ""]
        out[is.na(Percentage), Percentage := ""]
        if ("Aux" %in% names(out)) out[is.na(Aux), Aux := ""]
    }
    out[]
}

# Harmonize all flag columns used in eligibility logic.
.coerce_eligibility_flags <- function(dt) {
    flag_cols <- c(
        "SV_NIRSEVIMAB", "SV_EXPOSURE_EVER_BEFORE",
        "INCL_UNDER12M", "INCL_29W_GESTAGE", "INCL_ENROLLED",
        "EXCL_LRTI_RSV_INFECTION", "EXCL_NIVERSIMAB_MOTHER",
        "EXCL_IMMUNODEF", "EXCL_LUNGDIS", "EXCL_HEARTDIS",
        "EXCL_CYSTICFRIBROSIS", "EXCL_NEUROMUSCULARDIS",
        "EXCL_CRANCONANOM", "EXCL_GESTAGE_AGESEAS", "EXCL_HEARTTRANS",
        "INCL_IN_ELIGIBLE_POP", "eligible_exposed", "eligible_control"
    )
    for (col in intersect(flag_cols, names(dt))) {
        data.table::set(dt, j = col, value = .as_logical(dt[[col]]))
    }
    invisible(dt)
}


#' Table 1: Attrition table for entry into the eligible cohort.
#'
#' @param d3_eligibility  D3_ELIGIBILITY dataset.
#' @param study_period    Display string for the study period
#'   (start_study_date to end_study_date, used in row labels).
#' @param exposure_name   Display name of the exposure.
#' @param digits          Decimal places for percentages.
#' @param return_na       Keep NA cells when TRUE; replace with "" when FALSE.
#'
#' @return data.table with columns Label, N, Percentage, Aux.
create_table_1 <- function(
  d3_eligibility,
  study_period,
  exposure_name,
  digits = 1,
  return_na = FALSE
) {
    dt <- data.table::as.data.table(data.table::copy(d3_eligibility))

    .assert_required_cols(dt, c(
        "person_id", "SV_NIRSEVIMAB", "SV_EXPOSURE_EVER_BEFORE",
        "INCL_UNDER12M", "INCL_29W_GESTAGE", "INCL_ENROLLED",
        "EXCL_LRTI_RSV_INFECTION", "EXCL_NIVERSIMAB_MOTHER",
        "EXCL_IMMUNODEF", "EXCL_LUNGDIS", "EXCL_HEARTDIS",
        "EXCL_CYSTICFRIBROSIS", "EXCL_NEUROMUSCULARDIS",
        "EXCL_CRANCONANOM", "EXCL_GESTAGE_AGESEAS", "EXCL_HEARTTRANS",
        "INCL_IN_ELIGIBLE_POP", "eligible_exposed", "eligible_control"
    ), "d3_eligibility")

    .coerce_eligibility_flags(dt)

    # ------------------------------------------------------------
    # Palivizumab eligibility composite
    # TRUE = infant is NOT eligible to receive palivizumab.
    # ------------------------------------------------------------
    dt[, NOT_PALIVIZUMAB_ELIGIBLE :=
        !EXCL_IMMUNODEF &
        !EXCL_LUNGDIS &
        !EXCL_HEARTDIS &
        !EXCL_CYSTICFRIBROSIS &
        !EXCL_NEUROMUSCULARDIS &
        !EXCL_CRANCONANOM &
        !EXCL_GESTAGE_AGESEAS &
        !EXCL_HEARTTRANS
    ]

    # ------------------------------------------------------------
    # Cumulative attrition sequence
    # ------------------------------------------------------------

    # 0. All individuals registered in the healthcare data source.
    stage_0 <- dt
    n0 <- stage_0[, data.table::uniqueN(person_id)]

    # 1. Born >=29 weeks gestational age.
    stage_1 <- stage_0[INCL_29W_GESTAGE == TRUE]
    n1 <- stage_1[, data.table::uniqueN(person_id)]

    # 2. No ongoing lower respiratory tract infection or RSV infection.
    stage_2 <- stage_1[EXCL_LRTI_RSV_INFECTION == FALSE]
    n2 <- stage_2[, data.table::uniqueN(person_id)]

    # 3. Mother did NOT receive RSV vaccine during pregnancy.
    stage_3 <- stage_2[EXCL_NIVERSIMAB_MOTHER == FALSE]
    n3 <- stage_3[, data.table::uniqueN(person_id)]

    # 4. Infant is NOT eligible to receive palivizumab.
    stage_4 <- stage_3[NOT_PALIVIZUMAB_ELIGIBLE == TRUE]
    n4 <- stage_4[, data.table::uniqueN(person_id)]

    # 5. Received Nirsevimab during the enrolment period.
    # INCL_ENROLLED is included here because it is an explicit component
    # of INCL_IN_ELIGIBLE_POP.
    stage_5 <- stage_4[
        INCL_ENROLLED == TRUE &
        SV_NIRSEVIMAB == TRUE
    ]
    n5 <- stage_5[, data.table::uniqueN(person_id)]

    # 6. Never received Nirsevimab ever before.
    stage_6 <- stage_5[SV_EXPOSURE_EVER_BEFORE == FALSE]
    n6 <- stage_6[, data.table::uniqueN(person_id)]

    # 7. <=12 months of age at first exposure to Nirsevimab.
    stage_7 <- stage_6[INCL_UNDER12M == TRUE]
    n7 <- stage_7[, data.table::uniqueN(person_id)]

    # ------------------------------------------------------------
    # Final cohort rows
    #
    # Total Eligible Cohort is defined by INCL_IN_ELIGIBLE_POP.
    # The final cumulative attrition stage above is exposure-specific,
    # so it is expected to align with Eligible Exposed, not Total Eligible Cohort.
    # ------------------------------------------------------------
    n_cohort <- dt[
        INCL_IN_ELIGIBLE_POP == TRUE,
        data.table::uniqueN(person_id)
    ]
    n_exp <- dt[
        eligible_exposed == TRUE,
        data.table::uniqueN(person_id)
    ]
    n_control <- dt[
        eligible_control == TRUE,
        data.table::uniqueN(person_id)
    ]

    table_1 <- data.table::data.table(
        Label = c(
            paste0("All individuals registered in the healthcare data source at any time between ", study_period),
            "  AND are born \u226529 weeks of gestational age",
            "  AND do NOT have an ongoing lower respiratory tract infection or RSV infection",
            "  AND the mother has NOT received RSV vaccine during the pregnancy",
            "  AND the infant is NOT eligible to receive palivizumab",
            paste0("  AND received ", exposure_name, " during the enrolment period ", study_period),
            paste0("  AND never received ", exposure_name, " ever before"),
            paste0("  AND are \u226412 months of age at first exposure to ", exposure_name),
            "    Total Eligible Cohort",
            "      Eligible Exposed",
            "      Eligible Control"
        ),
        N = c(
            .format_count(n0),
            .format_count(n1),
            .format_count(n2),
            .format_count(n3),
            .format_count(n4),
            .format_count(n5),
            .format_count(n6),
            .format_count(n7),
            .format_count(n_cohort),
            .format_count(n_exp),
            .format_count(n_control)
        ),
        Percentage = c(
            NA_character_,
            .pct(n1, n0, digits),
            .pct(n2, n0, digits),
            .pct(n3, n0, digits),
            .pct(n4, n0, digits),
            .pct(n5, n0, digits),
            .pct(n6, n0, digits),
            .pct(n7, n0, digits),
            .pct(n_cohort, n0, digits),
            .pct(n_exp, n_cohort, digits),
            .pct(n_control, n_cohort, digits)
        ),
        Aux = NA_character_
    )

    .finalize_attrition_table(table_1, return_na = return_na)
}


#' Table 2: Matching statistics for the main analysis (matching without replacement).
#'
#' @param d3_eligibility   D3_ELIGIBILITY dataset (used for n_cohort denominator).
#' @param d4_main          D4_StudyCohort_Main dataset.
#' @param digits  Decimal places for percentages.
#' @param return_na  Keep NA cells when TRUE; replace with "" when FALSE.
#'
#' @return data.table with columns Label, N, Percentage, Aux.
create_table_2 <- function(
  d4_main,
  digits = 1,
  return_na = FALSE
) {
    d4 <- data.table::as.data.table(data.table::copy(d4_main))

    .assert_required_cols(d4, c("person_id", "group"), "d4_main")

    d4[, group := as.character(group)]

    # Total eligible persons (exposed + control combined) as common denominator.
    n_cohort <- d4[, .N]
    n_matched_exp <- d4[group == "EXPOSED", .N]
    n_matched_con <- d4[group == "CONTROL", .N]
    n_unmatched <- d4[group == "UNMATCHED", .N]
    n_matched <- n_matched_exp + n_matched_con

    table_2 <- data.table::data.table(
        Label = c(
            "Matched cohort",
            "  Exposed unmatched",
            "  Exposed matched",
            "  Control matched individuals in the cohort"
        ),
        N = c(
            .format_count(n_matched),
            .format_count(n_unmatched),
            .format_count(n_matched_exp),
            .format_count(n_matched_con)
        ),
        Percentage = c(
            .pct(n_matched, n_cohort, digits),
            .pct(n_unmatched, n_cohort, digits),
            .pct(n_matched_exp, n_cohort, digits),
            .pct(n_matched_con, n_cohort, digits)
        )
    )

    .finalize_attrition_table(table_2, return_na = return_na)
}


#' Table 3: Matching statistics for the supplementary analysis (matching with replacement).
#'
#' @param d3_eligibility      D3_ELIGIBILITY dataset (used for n_cohort and n_control denominators).
#' @param d4_supplementary    D4_StudyCohort_Supplement dataset.
#' @param digits  Decimal places for percentages.
#' @param return_na  Keep NA cells when TRUE; replace with "" when FALSE.
#'
#' @return data.table with columns Label, N, Percentage, Aux.
create_table_3 <- function(
  d4_supplementary,
  digits = 1,
  return_na = FALSE
) {
    d4 <- data.table::as.data.table(data.table::copy(d4_supplementary))

    .assert_required_cols(d4, c("person_id", "group"), "d4_supplementary")

    d4[, group := as.character(group)]

    n_cohort <- d4[, .N]

    n_matched_exp <- d4[group == "EXPOSED", .N]
    n_matched_con <- d4[group == "CONTROL", .N]
    n_unmatched <- d4[group == "UNMATCHED", .N]
    n_matched <- n_matched_exp + n_matched_con

    # Persons who appear as EXPOSED and were also reused as a CONTROL (served as control before exposure).
    exp_ids <- unique(d4[group == "EXPOSED", person_id])
    control_ids <- unique(d4[group == "CONTROL", person_id])
    n_exp_as_control <- length(intersect(exp_ids, control_ids))

    # Distribution of how many times each control individual was selected.
    control_counts <- d4[group == "CONTROL", .(times_selected = .N), by = person_id]
    n_unique_control <- nrow(control_counts)

    if (n_unique_control == 0L) {
        median_n <- q1_n <- q3_n <- min_n <- max_n <- NA_real_
        freq_1 <- freq_2 <- freq_3 <- freq_4 <- freq_5p <- 0L
    } else {
        ts <- control_counts$times_selected
        median_n <- stats::median(ts)
        q1_n <- stats::quantile(ts, 0.25, names = FALSE)
        q3_n <- stats::quantile(ts, 0.75, names = FALSE)
        min_n <- min(ts)
        max_n <- max(ts)
        # tabulate with pmin caps all values >=5 into bin 5.
        freqs <- tabulate(pmin(ts, 5L), nbins = 5L)
        freq_1 <- freqs[1L]
        freq_2 <- freqs[2L]
        freq_3 <- freqs[3L]
        freq_4 <- freqs[4L]
        freq_5p <- freqs[5L]
    }

    median_str <- if (is.na(median_n)) {
        NA_character_
    } else {
        sprintf("%.1f (%.1f, %.1f)", median_n, q1_n, q3_n)
    }
    range_str <- if (is.na(min_n)) {
        NA_character_
    } else {
        sprintf("(%s - %s)", .format_count(min_n), .format_count(max_n))
    }

    table_3 <- data.table::data.table(
        Label = c(
            "Matched cohort",
            "  Exposed unmatched",
            "  Exposed matched",
            "    Served as control before exposure",
            "  Control matched individuals in the cohort",
            "    Number of distinct control individuals matched",
            "    Number of times comparator selected for matching",
            "      Median (Q1 - Q3)",
            "      Min - Max",
            "      1 time - n (%)",
            "      2 times - n (%)",
            "      3 times - n (%)",
            "      4 times - n (%)",
            "      5 times or more - n (%)"
        ),
        N = c(
            .format_count(n_matched),
            .format_count(n_unmatched),
            .format_count(n_matched_exp),
            .format_count(n_exp_as_control),
            .format_count(n_matched_con),
            .format_count(n_unique_control),
            NA_character_,
            median_str,
            range_str,
            .format_count(freq_1),
            .format_count(freq_2),
            .format_count(freq_3),
            .format_count(freq_4),
            .format_count(freq_5p)
        ),
        Percentage = c(
            .pct(n_matched, n_cohort, digits),
            .pct(n_unmatched, n_cohort, digits),
            .pct(n_matched_exp, n_cohort, digits),
            .pct(n_exp_as_control, n_cohort, digits),
            .pct(n_matched_con, n_cohort, digits),
            .pct(n_unique_control, n_matched_con, digits),
            NA_character_,
            NA_character_,
            NA_character_,
            .pct(freq_1, n_unique_control, digits),
            .pct(freq_2, n_unique_control, digits),
            .pct(freq_3, n_unique_control, digits),
            .pct(freq_4, n_unique_control, digits),
            .pct(freq_5p, n_unique_control, digits)
        )
    )

    .finalize_attrition_table(table_3, return_na = return_na)
}
