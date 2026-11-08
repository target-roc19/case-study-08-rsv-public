# Applies eligibility logic to a data.table given composite study variable
# metadata. Computes INCL_IN_ELIGIBLE_POP from the combination rules, then
# derives eligible_exposed and eligible_control flags.
#
# @param dt       data.table containing D3_MULTIVARIATE_EPISODES columns.
# @param metadata data.table with columns sub_variable_id and combination_rule
#                 (from composite_study_variables.csv).
# @return dt, modified in place with INCL_IN_ELIGIBLE_POP, eligible_exposed,
#         and eligible_control columns added.
compute_eligibility <- function(dt, metadata) {
  rule_eligible <- paste0(
    metadata$sub_variable_id[1],
    paste0(
      " ",
      metadata$combination_rule[-1],
      " ",
      metadata$sub_variable_id[-1],
      collapse = ""
    )
  )
  cols_logical <- c(metadata$sub_variable_id, "SV_NIRSEVIMAB", "SV_EXPOSURE_EVER_BEFORE")
  dt[, (cols_logical) := lapply(.SD, as.logical), .SDcols = cols_logical]
  dt[, INCL_IN_ELIGIBLE_POP := eval(parse(text = rule_eligible))]
  dt[
    ,
    `:=`(
      eligible_exposed = INCL_IN_ELIGIBLE_POP & SV_NIRSEVIMAB &
        !SV_EXPOSURE_EVER_BEFORE,
      eligible_control = INCL_IN_ELIGIBLE_POP & !SV_NIRSEVIMAB &
        !SV_EXPOSURE_EVER_BEFORE
    )
  ]
}
