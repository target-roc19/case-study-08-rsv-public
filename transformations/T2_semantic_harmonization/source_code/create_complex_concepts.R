logger::log_info("[Complex Concepts] - STARTING")

### Initial setup
log_starter()
picard::load_config()

# Loads functions needed ------------------
files <- list.files(
  config_project$create_complex_concepts$functions,
  pattern = "\\.[Rr]$", full.names = TRUE
)
invisible(lapply(files, source))

# prepare directories ------------------
input_dir <- config_project$create_complex_concepts$input_dir
output_dir <- config_project$create_complex_concepts$output_dir

# prepare metadata ------------------
metadata <- picard::load(
  file_path = config_pipeline$common$dir_bridge,
  file_name = "concept_preprocessing.csv"
)

# creating a list of lists, grouped by concept_id and function
# where each inner list contains the
# necessary information to create a complex concept the reason for this is that
# we want to be able to easily iterate over this list
# and call the appropriate function for each complex concept
metadata_list <- metadata[,
  .(
    complex_concept_name = data.table::first(concept_id),
    sub_concept_ids = list(sub_concept_id),
    func_ = data.table::first(`function`),
    Comment = data.table::first(Comment)
  ),
  by = .(concept_id, `function`)
] |>
  base::split(by = c("concept_id", "function"))

# orchestrator for creating complex concepts
for (i in seq_along(metadata_list)) {
  concept_id <- metadata_list[[i]]$complex_concept_name
  func_ <- metadata_list[[i]]$func_
  if (exists(func_, mode = "function")) {
    logger::log_info(paste0(
      "Processing concept: ",
      concept_id,
      " with function: ",
      func_
    ))
    tryCatch(
      {
        do.call(
          what = get(func_, mode = "function"),
          args = list(
            input_dir = input_dir,
            output_dir = output_dir,
            complex_concept_name = metadata_list[[i]]$complex_concept_name,
            sub_concept_ids = unlist(metadata_list[[i]]$sub_concept_ids)
          )
        )
      },
      error = function(e) {
        stop(e)
      },
      warning = function(w) {
        logger::log_warn(paste0(
          "Warning while processing concept: ",
          concept_id,
          " with function: ",
          func_,
          " - ",
          w
        ))
      }
    )
  } else {
    logger::log_info(
      paste0("Function ", func_, " does not exist. Skipping.")
    )
  }
}

# tabulate all concepts
sql_path <- file.path(
  config_t2$T2$root,
  config_t2$T2$sql_queries,
  "tabulate_all_concepts.sql"
)
con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
res <- picard::execute_sql_file(
  sql = picard::load_sql_query(
    sql_path,
    params = list(input_dir = output_dir)
  ),
  conn = con
)
duckdb::dbDisconnect(con, shutdown = TRUE)
logger::log_info("Tabulate all concepts.")
logger::log_info(paste(capture.output(print(res)), collapse = "\n"))

# clean up memory
rm(metadata, metadata_list)
gc()
log_ender()
