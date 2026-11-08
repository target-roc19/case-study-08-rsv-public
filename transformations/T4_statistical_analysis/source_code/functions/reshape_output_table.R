# reshape descriptive table output to match expected format for reporting

reshape_output_table <- function(table) {
    cols <- colnames(table)
    colnames(table) <- stringr::str_replace_all(cols, c("V1" = "N", "V2" = "perc", "V3" = "aux"))
    all_groups <- stringr::str_extract(cols, "V\\d+_([^\\s]+)") |>
        stringr::str_replace("V\\d+_", "") |>
        unique() |>
        na.omit()

    asd_cols <- grep("^asd(_.*)?$", names(table), value = TRUE)
    if (length(asd_cols) > 0L && !"asd" %in% names(table)) {
        data.table::setnames(table, asd_cols[1L], "asd")
    }

    # percentages and descriptive statistics (mean/SD, median/Q1/Q3) to 1 decimal;
    # asd is left at its computed precision, it is not a percentage or a plain descriptive statistic.
    value_cols <- grep("^(N|perc|aux)_", names(table), value = TRUE)
    table[, (value_cols) := lapply(.SD, function(x) round(as.numeric(x), 1)), .SDcols = value_cols]

    median_rows <- !is.na(table$label) & table$label == "Median (Q1, Q3)"
    for (group_name in all_groups) {
        perc_col <- paste0("perc_", group_name)
        aux_col  <- paste0("aux_", group_name)

        if (all(c(perc_col, aux_col) %in% names(table)) && any(median_rows)) {
            table[, (perc_col) := as.character(get(perc_col))]
            table[median_rows, (perc_col) := ifelse(
                is.na(get(perc_col)) & is.na(get(aux_col)),
                NA_character_,
                sprintf("(%s - %s)", get(perc_col), get(aux_col))
            )]
        }
    }
    table$label[median_rows] <- "Median (Q1 - Q3)"

    drop_cols <- intersect(c(paste0("aux_", all_groups)), names(table))
    if (length(drop_cols) > 0L) {
        table[, (drop_cols) := NULL]
    }

    desired_cols <- c(
        "label", "var", "cat",
        paste0(
            rep(c("N_", "perc_"), each = length(all_groups)),
            all_groups
        ),
        "asd"
    )
    output_cols <- intersect(desired_cols, names(table))
    table[, ..output_cols]
}
