#' Create the SV_AGE_GROUP complex concept.
#'
#' Generates three boundary rows per person from D3_SPELLS using birth_date:
#'   value = 1: ≤3.0 months; 2: >3.0–≤6.0 months; 3: >6.0 months
#' A LATEST extraction at t0 returns the age group category
#'
#' The core SQL computation is in source_code/sql/age_group.sql.
#'
#' Relies on config_project, config_t2, and config_values being present in the
#' calling environment (loaded by picard::load_config() in
#' create_complex_concepts.R).
#'
#' @param input_dir  Path to D3_CONCEPTS_parquet. Not used by this function
#'   (no concept partition needed); included for interface consistency with the
#'   orchestrator.
#' @param output_dir Path to write the output hive-partitioned parquet.
#' @param complex_concept_name Name of the output concept (used as the
#'   concept_id partition value).
#' @param sub_concept_ids Not used for this concept (NA in
#'   concept_preprocessing); included for interface consistency.
#'
#' @returns Invisibly returns a named list summarising the operation.
create_age_group <- function(
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

  # Resolve supporting paths and config values
  d3_spells_path <- config_project$create_simple_concepts$d3_spells
  # boundaries in days (floor to keep behaviour consistent with other functions)
  age_3m_days <- floor(3 * config_values$month_length)
  age_6m_days <- floor(6 * config_values$month_length)

  sql_path <- file.path(
    config_t2$T2$root,
    config_t2$T2$sql_queries,
    "age_group.sql"
  )

  # Open DuckDB connection
  con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  tryCatch(
    {
      picard::execute_sql_file(
        sql = picard::load_sql_query(
          sql_path,
          params = list(
            complex_concept_name = params$complex_concept_name,
            d3_spells_path       = d3_spells_path,
            output_dir           = params$output_dir,
            age_3m_days          = age_3m_days,
            age_6m_days          = age_6m_days
          )
        ),
        conn = con
      )
    },
    error = function(e) {
      rlang::abort(
        glue::glue(
          "DuckDB COPY failed for '{complex_concept_name}':\n
            {conditionMessage(e)}"
        ),
        class = "duckdb_copy_error"
      )
    }
  )

  # Checking rows affected
  counts <- get_counts(
    connection = con,
    complex_concept_name = params$complex_concept_name,
    output_directory = params$output_dir
  )
  logger::log_info(crayon::cyan(
    "Counts:\n",
    paste(capture.output(print(t(counts), sep = ":"))[-1], collapse = "\n")
  ))
}
