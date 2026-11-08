get_script_name <- function() {
  # Case 1: script was sourced
  for (i in sys.nframe():1) {
    ofile <- sys.frame(i)$ofile
    if (!is.null(ofile)) {
      return(basename(normalizePath(ofile)))
    }
  }

  # Case 2: running interactively via Positron/VS Code/R RStudio
  if (
    requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable()
  ) {
    ctx <- rstudioapi::getSourceEditorContext()
    if (!is.null(ctx) && nzchar(ctx$path)) {
      return(basename(normalizePath(ctx$path)))
    }
  }

  stop("Could not determine script path — file may be unsaved.")
}

log_starter <- function(
  capture_prints = getOption(
    "picard.capture_prints",
    default = !interactive()
  )
) {
  if (
    !base::exists("logr", inherits = TRUE) ||
      !base::inherits(logr, "LoggerManager")
  ) {
    logr <- NULL
  }
  if (!base::is.null(logr)) {
    script_name <- tryCatch(get_script_name(), error = function(e) print(e))
    if (is.null(script_name) || !nzchar(script_name)) {
      script_name <- "<interactive>"
    }

    logr$start_script(script_name)

    has_step_log <- (!is.null(logr$step_log_file) &&
      length(logr$step_log_file) == 1L &&
      nzchar(logr$step_log_file))

    if (isTRUE(capture_prints) && has_step_log) {
      logr$start_capturing_prints()
    }
  }
  logr
}

log_ender <- function(logr = NULL) {
  if (!base::is.null(logr)) {
    logr$stop_capturing_prints()
    logr$end_script()
  }
}

render_config <- function(
  path = NULL,
  out_path = NULL,
  overwrite = FALSE,
  output_directory = NULL,
  database_instance = NULL,
  ...
) {
  # Fall back to values already in out_path only if not explicitly supplied
  if (
    (is.null(output_directory) || is.null(database_instance)) &&
      file.exists(out_path)
  ) {
    existing_config <- yaml::read_yaml(out_path)
    if (is.null(output_directory)) {
      output_directory <- existing_config$DEAP_configuration$output_data_directory
    }
    if (is.null(database_instance)) {
      database_instance <- existing_config$DEAP_configuration$data_instance
    }
  }

  if (is.null(output_directory)) {
    stop(
      "render_config(): 'output_directory' must be supplied (no existing config to fall back on)."
    )
  }
  if (is.null(database_instance)) {
    stop(
      "render_config(): 'database_instance' must be supplied (no existing config to fall back on)."
    )
  }

  data_dir <- sub("[/\\\\]+$", "", output_directory)

  raw_yaml <- readr::read_file(path)
  params <- list(...)

  # Fingerprint of everything that determines the rendered output
  content_hash <- digest::digest(list(
    template = raw_yaml,
    data_dir = data_dir,
    database_instance = database_instance,
    params = params
  ))

  # Guard against clobbering an already-current or hand-edited file
  if (file.exists(out_path) && !overwrite) {
    existing <- readr::read_file(out_path)
    marker <- regmatches(
      existing,
      regexpr("(?<=# render_hash: )[a-f0-9]+", existing, perl = TRUE)
    )

    if (length(marker) == 0) {
      stop(
        "'",
        out_path,
        "' exists with no render marker (looks hand-edited). ",
        "Pass overwrite = TRUE to replace it."
      )
    }
    if (identical(marker, content_hash)) {
      message("'", out_path, "' is already up to date — skipping.")
      return(invisible(data_dir))
    }
  }

  logger::log_info(glue::glue("Rendering output directory to: '{data_dir}'"))

  rendered_yaml <- glue::glue(
    raw_yaml,
    data_dir_placeholder = data_dir,
    database_instance_placeholder = database_instance,
    .open = "<<",
    .close = ">>",
    .envir = list2env(params)
  )

  # Stamp a hash marker so future calls can detect "nothing changed"
  rendered_yaml <- paste0(
    "# render_hash: ",
    content_hash,
    "\n",
    as.character(rendered_yaml),
    "\n"
  )

  readr::write_file(rendered_yaml, out_path)

  invisible(data_dir)
}

initialise_configs <- function(
  output_directory = NULL,
  database_instance = NULL,
  overwrite = FALSE,
  ...
) {
  if (is.null(output_directory) || !nzchar(output_directory)) {
    output_directory <- yaml::read_yaml(
      "configuration/config_project.yaml"
    )$DEAP_configuration$output_data_directory |>
      sub("[/\\\\]+$", "", x = _)
  }

  if (is.null(database_instance) || !nzchar(database_instance)) {
    database_instance <- yaml::read_yaml(
      "configuration/config_project.yaml"
    )$DEAP_configuration$data_instance
  }

  # Render project config first — this is the source of truth for data_dir
  data_dir <- render_config(
    path = "configuration/config_project_template.yaml",
    out_path = "configuration/config_project.yaml",
    overwrite = overwrite,
    output_directory = output_directory,
    database_instance = database_instance,
    ...
  )

  render_config(
    path = "configuration/config_pipeline_template.yaml",
    out_path = "configuration/config_pipeline.yaml",
    overwrite = overwrite,
    output_directory = output_directory,
    database_instance = database_instance,
    ...
  )

  # Only now create directories, using the value just rendered — not a re-read
  create_data_directory(data_dir)

  logger::log_info("Configuration files initialised successfully.")
  logger::log_info(glue::glue("Data directory set at ('{data_dir}')"))
}

create_data_directory <- function(data_directory) {
  if (is.null(data_directory)) {
    stop("create_data_directory(): 'data_directory' must be supplied.")
  }

  data_dir_folders <- c(
    "D2_CDM",
    "D3_study_variables",
    "D4_analytic_datasets",
    "D5_results",
    "D6_report"
  )

  if (!dir.exists(data_directory)) {
    dir.create(data_directory, recursive = TRUE)
    logger::log_info(glue::glue(
      "Data directory created at ('{data_directory}')"
    ))
  } else {
    logger::log_info(glue::glue(
      "Data directory already exists at ('{data_directory}')"
    ))
  }

  for (folder in data_dir_folders) {
    folder_path <- file.path(data_directory, folder)
    if (!dir.exists(folder_path)) {
      dir.create(folder_path, recursive = TRUE)
      logger::log_info(glue::glue(
        "{folder} directory created at ('{folder_path}')"
      ))
    } else {
      logger::log_info(glue::glue(
        "{folder} directory already exists at ('{folder_path}')"
      ))
    }
  }
}
