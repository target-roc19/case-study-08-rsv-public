# Applies censoring reason to follow up outcomes
#
# @param dt       data.table containing anchored study variables outcome columns
# @param cfg      config with study dates
# @param d3_spells
# @return dt, modified in place with censored dates and reasons, for 2 estimands
censor_fup <- function(dt, cfg, d3_spells_path) {
  dt[, SV_HOSP_RSV_LRTI_d := SV_HOSP_RSV_LRTI]

  # join on person_id to add end_spell and death_date from D3_Spells
  d3_spells <- picard::load(file_path = d3_spells_path)
  dt <- merge(
    dt,
    d3_spells[, .(person_id, death_d = death_date, end_spell_d = end_spell)],
    by = "person_id", all.x = TRUE
  )

  # add general censoring dates from configuration
  event_cols_est1 <- c(
    "SV_HOSP_RSV_LRTI_d", "death_d", "end_spell_d",
    "general_fup_d", "end_study_d", "end_control_d"
  )
  event_cols_est2 <- c(
    "SV_HOSP_RSV_LRTI_d", "death_d", "end_spell_d",
    "general_fup_d", "end_study_d"
  )

  # Step 1: Calculate the derived time columns
  end_study_date <- as.Date(cfg$end_study_d)
  dt[, `:=`(
    general_fup_d = T0 + cfg$general_fup_d,
    end_study_d = end_study_date,
    end_control_d = data.table::fifelse(
      group == "CONTROL", as.Date(SV_NIRSEVIMAB_IE), as.Date(NA)
    )
  )]

  # Step 2: Calculate est1 columns
  # Single step for both est1 and est2
  for (est in c("est1", "est2")) {
    cols <- get(paste0("event_cols_", est))
    dt[, (cols) := lapply(
      .SD, data.table::fcoalesce, as.Date("2099-01-01")
    ), .SDcols = cols]

    # Calculate fup_d
    dt[,
      paste0("fup_d_", est) := do.call(
        pmin, c(.SD, list(na.rm = TRUE))
      ),
      .SDcols = cols
    ]

    # Calculate reason_censoring
    # Convert to numeric matrix
    mat_num <- as.matrix(dt[, lapply(.SD, as.numeric), .SDcols = cols])

    # Find column with minimum (handling NAs by treating them as large values)
    dt[, paste0("reason_censoring_", est) := max.col(
      -mat_num,
      ties.method = "first"
    )]

    # censoring reason corresponding to the column names
    dt[, paste0("reason_censoring_col_", est) :=
      event_cols_est1[as.numeric(get(paste0("reason_censoring_", est)))]]

    # calculate follow up days
    dt[
      ,
      paste0("fup_length_days_", est) :=
        as.numeric(difftime(get(paste0("fup_d_", est)), T0, units = "days") + 1)
    ]
    dt[
      ,
      paste0("fup_length_pm_", est) :=
        get(paste0("fup_length_days_", est)) / cfg$month_length
    ]
    dt[
      ,
      paste0("event_", est) := ifelse(
        SV_HOSP_RSV_LRTI_d ==
          get(paste0("fup_d_", est)), 1L, 0L
      )
    ]
  }
  dt[
    ,
    admin_censor_est1 := data.table::fcase(
      reason_censoring_est1 == 1, "uncensored", # event occurr, no censoring
      reason_censoring_est1 %in% c(6, 3), "non-admin", # non-admin censoring (hypothetical strategy - end control, end_spell)
      reason_censoring_est1 %in% c(2, 4, 5), "admin" # admin censoring (death, general fup, end study)
    )]
  # reverse large date back to NA_date
dt[, (names(dt)[stringr::str_detect(names(dt), "_d")]) :=
   lapply(.SD, function(x) data.table::fifelse(x == "2099-01-01", NA, x)),
   .SDcols = patterns("_d")]
}
