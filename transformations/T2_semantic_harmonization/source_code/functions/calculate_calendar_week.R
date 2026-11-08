calculate_calendar_week <- function(
    input_dir,
    output_dir,
    complex_concept_name = NULL,
    sub_concept_ids = NULL) {
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

  # Open DuckDB connection
  picard::load_config()
  # Resolve paths and config
  d3_spells_path <- config_project$create_simple_concepts$d3_spells
  end_study_date <- config_values$end_study_d

  con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(
    con,
    glue::glue(
      "CREATE OR REPLACE VIEW {params$complex_concept_name} AS
        SELECT *
        FROM read_parquet(
          ['{input_dir}/**/*.parquet'],
          hive_partitioning = true,
          union_by_name     = true
          )
        WHERE concept_id IN ({partitions})",
      partitions = paste0("'", existing_sub_concepts, "'", collapse = ", ")
    )
  )
  query <- picard::load_sql_query(
    file.path(
      config_t2$T2$root,
      config_t2$T2$sql_queries,
      "calendar_week_time.sql"
    ),
    params = list(
      complex_concept_name = params$complex_concept_name,
      d3_spells_path = d3_spells_path,
      end_study_date = end_study_date
    )
  )

  tryCatch(
    {
      DBI::dbExecute(
        con,
        glue::glue(
          "COPY (
            {query}
          ) TO '{params$output_dir}'
          (FORMAT PARQUET,  PARTITION_BY (concept_id), APPEND)"
        )
      )
    },
    error = function(e) {
      rlang::abort(
        glue::glue(
          "SQL script failed for '{params$complex_concept_name}':\n
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
