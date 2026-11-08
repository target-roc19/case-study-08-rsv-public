# The aim of the script is to:
# Load all the tables of interest from the CDM into a SQLite Database
# by:
# 1. Connecting to a new Database ori (origin)
# 2. Reading the cdm_metadata.fst files
# 3. Loading all CSV files form the D2 folder to the d2.db
# 4. Option: Exclude duplicate rows
# 5. Create unique id per row

log_starter()

logger::log_info("Loading the database and performing operations")

picard::load_config()

#################
# Loading files into the origin database
################

# load project settings
# set_db inputs
filepath_cdm_metadata <- config_project$set_db$cdm_metadata
database_loader_config <- config_project$set_db$database_loader_config

# deap configs
dir_d2 <- config_project$DEAP_configuration$data_instance
database_path <- config_project$DEAP_configuration$database_path

# output database
dir_d2_db <- config_project$set_db$output

if (is.null(database_path)) {
  if (exists("conn") && DBI::dbIsValid(conn)) {
    DBI::dbDisconnect(conn, shutdown = TRUE)
  }
  if (file.exists(dir_d2_db)) {
    file.remove(dir_d2_db)
  }
  if (file.exists(paste0(dir_d2_db, ".wal"))) {
    file.remove(paste0(dir_d2_db, ".wal"))
  }
}

loader <- T2.DMM::DatabaseLoader$new(
  db_path = dir_d2_db,
  data_instance = dir_d2,
  config_path = database_loader_config,
  cdm_metadata = filepath_cdm_metadata
)

loader$run_db_ops()

conn <- DBI::dbConnect(duckdb::duckdb(), dir_d2_db)
schema <- "cdm_synthea10"
tables_to_export <- list(
  "condition_occurrence" = list(order_by = "person_id"),
  "death" = list(order_by = "person_id"),
  "drug_exposure" = list(order_by = "person_id"),
  "measurement" = list(order_by = "person_id"),
  "observation_period" = list(order_by = "person_id"),
  "observation" = list(order_by = "person_id"),
  "person" = list(
    partition_on = "gender_concept_id",
    order_by = c("gender_concept_id", "person_id")
  ),
  "procedure_occurrence" = list(order_by = "person_id"),
  "vocabulary" = list(order_by = "vocabulary_id")
)

for (table in names(tables_to_export)) {
  print(table)
  name_view <- paste0(table, "_view_1")

  logger::log_info((paste0("Materializing: ", table)))
  query <- glue::glue("CREATE TABLE main.{table} AS
                   SELECT * FROM
                   {name_view}")
  DBI::dbExecute(
    conn,
    query
  )
}
DBI::dbDisconnect(conn)
rm(conn)
gc()
print(paste0("[Set Data Base]: IMPORT ACCOMPLISHED"))


log_ender()
