library(testthat)
library(data.table)
library(yaml)

config_test_path <- "configuration/config_test.yaml"
config_project_path <- "configuration/config_project.yaml"

config_test <- yaml::read_yaml(config_test_path)
old_project_config <- if (file.exists(config_project_path)) yaml::read_yaml(config_project_path) else NULL

yaml::write_yaml(config_test, config_project_path)

integration_steps <- config_test$integration_tests

if (is.null(integration_steps) || length(integration_steps) == 0L) {
  testthat::skip("No integration tests configured in configuration/config_test.yaml")
}

for (step in integration_steps) {
  testthat::test_that(paste0("integration step: ", step$name), {
    config_key <- step$config_key
    step_cfg <- config_test[[config_key]]

    testthat::expect_false(is.null(step_cfg), info = paste("Missing config block for:", config_key))

    script_path <- step_cfg$script_path
    output_path <- step_cfg$output_path
    expected_path <- step_cfg$expected_output_path

    testthat::expect_true(file.exists(script_path), info = paste("Missing step script:", script_path))

    # check config output files = = expected output files
    if (!is.null(output_path)) {
      testthat::expect_equal(length(output_path), length(expected_path))
      for (i in seq_along(output_path)) {
        testthat::expect_true(
          file.exists(expected_path[[i]]),
          info = paste("Missing expected output:", expected_path[[i]])
        )
      }
    }

    # clean up existing output files before running the step
    if (!is.null(output_path)) {
      for (p in output_path) {
        if (file.exists(p)) {
          unlink(p)
        }
      }
    }

    # create output
    source("run/run_logger.R")
    suppressWarnings(source(script_path))

    if (!is.null(output_path)) {
      for (i in seq_along(output_path)) {
        actual_i <- data.table::fread(output_path[[i]])
        expected_i <- data.table::fread(expected_path[[i]])

        data.table::setindex(actual_i, NULL)
        data.table::setindex(expected_i, NULL)

        testthat::expect_equal(actual_i, expected_i)
      }
    }
  })
}
