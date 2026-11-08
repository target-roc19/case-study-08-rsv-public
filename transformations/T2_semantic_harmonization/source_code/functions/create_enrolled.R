# This function defines record of start and end of enrollement within a database.
# When value = TRUE we have a start of enrollmenet and when value FALSE we have end.
# Input: D3_SPELLS

create_enrolled <- function(
  input_dir,
  output_dir,
  complex_concept_name = NULL,
  sub_concept_ids = NULL
) {
  # Normalise inputs
  params <- normalise_inputs(
    input_dir = input_dir,
    output_dir = output_dir,
    complex_concept_name = complex_concept_name,
    sub_concept_ids = sub_concept_ids
  )
  # Validate inputs
  validate_inputs(
    input_dir = params$input_dir,
    complex_concept_name = params$complex_concept_name,
    sub_concept_ids = params$sub_concept_ids
  )
  # Clean output directory
  ensure_clean_output_directory(params$output_dir, params$complex_concept_name)

  d3_spells <- picard::load(
    config_project$create_complex_concepts$d3_spells)

  results <- calculate_enrollement(d3_spells)
  results <- data.table::as.data.table(results)
  results[, concept_id := complex_concept_name]

  # Add missing columns
  required_cols_d3_concept <- config_project$create_complex_concepts$required_cols_d3_concept
  missing_cols <- required_cols_d3_concept[!required_cols_d3_concept %in% names(results)]
  lapply(missing_cols , function(x) results[, eval(x) := NA])

  arrow::write_dataset(
    results[, ..required_cols_d3_concept],
    path = output_dir,
    format = "parquet",
    partitioning = "concept_id"
  )

}


calculate_enrollement <- function(d3_spells) {
  results <- data.table::copy(d3_spells)
  results[, end_spell := end_spell + 1]
  results[, start_value := TRUE][, end_value := FALSE]

  results <- data.table::melt(
    results[, c("person_id", "start_spell", "end_spell", "start_value", "end_value")],
    id.vars = "person_id",
    measure.vars = list(c("start_spell", "end_spell"), c("start_value", "end_value")),
    variable.name = "concept_id",
    value.name = c("date", "value"),
    na.rm = TRUE
  )
  return(results)
}
