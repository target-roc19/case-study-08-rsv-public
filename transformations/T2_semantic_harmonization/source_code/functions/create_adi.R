#' Create the PP_ADI complex concept.
#'
#' replace concept date by birth date
#'
#' Relies on config_project and config_t2 being present in the calling
#' environment (loaded by picard::load_config() in create_complex_concepts.R).
#'
#' @param input_dir  Path to D3_CONCEPTS_parquet (hive-partitioned).
#' @param output_dir Path to write the output hive-partitioned parquet.
#' @param complex_concept_name Name of the output concept (used as the
#'   concept_id partition value).
#' @param sub_concept_ids Character vector whose first element is the
#'   concept_id of the gestational age simple concept
#'
#' @returns Invisibly returns a named list summarising the operation.
create_adi <- function(
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

  # Getting existing sub_concept_ids
  existing_sub_concepts <- prepare_sub_concept_ids(
    sub_concept_ids = params$sub_concept_ids,
    input_directory = params$input_dir
  )

  sql_path <- file.path(
    config_t2$T2$root,
    config_t2$T2$sql_queries,
    "adi_date.sql"
  )

  d3_spells_path <- config_project$create_simple_concepts$d3_spells

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
            sub_concept_ids = existing_sub_concepts,
            d3_spells_path       = d3_spells_path,
            input_dir            = params$input_dir,
            output_dir           = params$output_dir
          )
        ),
        conn = con
      )
    },
    error = function(e) {
      rlang::abort(
        glue::glue(
          "DuckDB COPY failed for '{params$complex_concept_name}':\n
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
