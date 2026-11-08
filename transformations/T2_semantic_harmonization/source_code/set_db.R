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

# function to move a table
move_table_schema <- function(con, table_name, new_schema) {
  # create schema if not exists
  DBI::dbExecute(con, sprintf("CREATE SCHEMA IF NOT EXISTS %s", new_schema))

  # copy table into new schema
  DBI::dbExecute(con, sprintf(
    "CREATE TABLE %s.%s AS SELECT * FROM main.%s",
    new_schema, table_name, table_name
  ))

  # drop the old table
  DBI::dbExecute(con, sprintf("DROP TABLE main.%s", table_name))
}

count_table <- function(conn, schema, table) {
  fq_table <- paste0(
    as.character(DBI::dbQuoteIdentifier(conn, schema)),
    ".",
    as.character(DBI::dbQuoteIdentifier(conn, table))
  )

  sql <- picard::load_sql_query(
    file_path = paste0(
      "transformations/T2_semantic_harmonization/",
      "source_code/sql/set_db_count.sql"
    ),
    params = list(fq_table = fq_table)
  )

  count <- picard::execute_sql_file(conn = conn, sql = sql)$count
  base::format(count, scientific = FALSE, trim = TRUE)
}

if (is.null(database_path)) {
  loader$set_database()
  conn <- duckdb::dbConnect(duckdb::duckdb(), dir_d2_db)
  tables_loaded <- unique(DBI::dbListTables(conn))

  lapply(
    tables_loaded,
    function(table) {
      move_table_schema(conn, table, "ConcePTION")
    }
  )

  logger::log_info("rows for each table loaded start:")
  # Create empty data.table to store the counts
  dt <- data.table::data.table(table = character(), count = integer())
  for (table in tables_loaded) {
    count <- count_table(conn = conn, schema = "ConcePTION", table = table)
    dt <- rbind(dt, data.table::data.table(table = table, count = count))
    logger::log_info(paste0(table, ": ", count))
  }

  DBI::dbDisconnect(conn)
}

loader$run_db_ops()

conn <- duckdb::dbConnect(duckdb::duckdb(), dir_d2_db)

# data.table with the count after cleanup to the same row as the table name
dt_ac <- data.table::data.table(table = character(), count = integer())
for (table in tables_loaded) {
  logger::log_info(paste0("Creating view for: ", table))
  if (table == "PERSONS") {
    name_view <- paste0(table, "_view_3")
  } else {
    name_view <- paste0(table, "_view_2")
  }
  logger::log_info(paste0("Materializing: ", table))
  create_table <- picard::load_sql_query(
    file_path =
      paste0(
        "transformations/T2_semantic_harmonization/",
        "source_code/sql/set_db_create_table.sql"
      ),
    params = list(table = table, name_view = name_view)
  )
  picard::execute_sql_file(
    conn = conn,
    sql = create_table
  )
  logger::log_info("DONE")

  logger::log_info("rows for each table after clean up:")
  count <- count_table(conn = conn, schema = "main", table = table)
  dt_ac <- rbind(dt_ac, data.table::data.table(table = table, count = count))
  logger::log_info(paste0("after clean up of ", table, ": ", count))
}

# compute the difference in counts before and after cleanup
dt_final <- data.table::merge.data.table(
  dt, dt_ac,
  by = "table", suffixes = c("_before", "_after")
)
# convert count columns to numeric
dt_final[, count_before := as.numeric(count_before)]
dt_final[, count_after := as.numeric(count_after)]
dt_final[, difference := count_after - count_before]
logger::log_info("Difference in counts before and after cleanup:")

picard::audit_start(file_name = "set_db_counts")
picard::audit_add(dt_final)
picard::audit_end()
DBI::dbDisconnect(conn)
rm(conn)
gc()
print(paste0("[Set Data Base]: IMPORT ACCOMPLISHED"))

log_ender()
