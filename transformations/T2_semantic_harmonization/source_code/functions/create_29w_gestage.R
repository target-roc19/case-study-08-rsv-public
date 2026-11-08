#' Create the CC_29W_GESTAGE complex concept.
#'
#' Identifies persons born at >= 29 weeks gestational age. Reads the GEST_AGE
#' simple concept from D3_CONCEPTS_parquet (value = gestational age in weeks as
#' a numeric string). The output value is TRUE when GEST_AGE >= 29 weeks,
#' FALSE otherwise. The date column is the GEST_AGE event date.
#'
#' The core SQL computation is shared via
#' source_code/sql/gest_age_condition.sql and loaded at runtime.
#'
#' Relies on config_project and config_t2 being present in the calling
#' environment (loaded by picard::load_config() in create_complex_concepts.R).
#'
#' @param input_dir  Path to D3_CONCEPTS_parquet (hive-partitioned).
#'   Must contain a sub-directory concept_id=<gest_age_concept_id>.
#' @param output_dir Path to write the output hive-partitioned parquet.
#' @param complex_concept_name Name of the output concept (used as the
#'   concept_id partition value).
#' @param sub_concept_ids Character vector whose first element is the
#'   concept_id of the gestational age simple concept (e.g. "GEST_AGE").
#'
#' @returns Invisibly returns a named list summarising the operation.
create_29w_gestage <- function(
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
    "gest_age_condition.sql"
  )

  d3_spells_path <- config_project$create_simple_concepts$d3_spells

  # Open DuckDB connection
  con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(
    con,
    glue::glue(
      "CREATE OR REPLACE VIEW {params$complex_concept_name} AS
        SELECT *
        FROM read_parquet(
          ['{params$input_dir}/**/*.parquet'],
          hive_partitioning = true,
          union_by_name     = true
          )
        WHERE concept_id IN ({partitions})",
      partitions = paste0("'", existing_sub_concepts, "'", collapse = ", ")
    )
  )

  tryCatch(
    {
      picard::execute_sql_file(
        sql = picard::load_sql_query(
          sql_path,
          params = list(
            complex_concept_name = params$complex_concept_name,
            d3_spells_path       = d3_spells_path,
            output_dir           = params$output_dir,
            condition            = ">= 29"
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
