## Metadata

| Table name                | concept_table (in D3_concepts.db)                                                                                                                                                                                                                                                   |
| ------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Concept table specific for the study. This database has the records related to each concept used in the study.                                                                                                                                                                      |
| Source                    | D2_CDM tables, D3_SPELLS.parquet, configured DAP-specific codelists, `dap_specific_concept_map.rds`, and `concept_preprocessing.csv` |
| Step                      | `transformations/T2_semantic_harmonization/source_code/create_simple_concepts.R`, `transformations/T2_semantic_harmonization/source_code/create_complex_concepts.R` |
| Content                   | Records from D2_CDM categorized in `concept_id`.                                                                                                                                                                                                                                    |
| Population                | Persons represented in `D3_SPELLS`                                                                                                                                                                                                                                                   |
| Unit of Observation (UoO) | One row per source record and concept. Source records are restricted to people in `D3_SPELLS`; date-completeness filtering is applied to vaccine codelist records. |
| File format               | Parquet file organised in a Parquet Hive with '`concept_id`' as the partition variable.                                                                                                                                                                                             |

## Codebook
| variable_in_output | variable(s) needed                                                                                                       | retrieved | computed | format | rule_of_calculation  | description                                                                                                | vocabulary                                 |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------ | --------- | -------- | ------ | -------------------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| person_id          | D2_CDM/<cdm_table>/person_id, D3_SPELLS/person_id                                                                        | x         |          | string |                      | Unique person identifier                                                                                   |                                            |
| ori_table          | D2_CDM/<cdm_table>/ori_table, concept constructor | x | | string | Carried from source or set to constructor source | Origin table name | EVENTS, VACCINES, MEDICAL_OBSERVATIONS, D3_SPELLS |
| unique_id          | D2_CDM/<cdm_table>/unique_id                                                                                             | x         |          | string |                      | A Universally Unique Identifier (UUID) is a 128-bit number, displayed as a 36-character hexadecimal string |                                            |
| concept_id         | configured DAP-specific codelist/concept_id, `dap_specific_concept_map.rds`/concept_id, `concept_preprocessing.csv`/concept_id | x | | string | Assigned by codelist, concept map, or complex-concept constructor | Concept identifier | |
| coding_system      | codelist_<cdm_table>/coding_system                                                                                       | x         |          | string |                      | Coding system used for identifying the code                                                                |                                            |
| code               | codelist_<cdm_table>/code                                                                                                | x         |          | string |                      | Code matched to the study codelist                                                                         |                                            |
| date               | D2_CDM/<cdm_table>/<date column>, `dap_specific_concept_map.rds`/keep_date_column_name | x | | date | Selected source or mapped date | Date of the concept record | |
| value              | D2_CDM/<cdm_table>/<value column>, `dap_specific_concept_map.rds`/keep_value_column_name | | x | string/numeric/logical | Source value or constructor rule | Value retained for the concept | INT,TRUE/FALSE,CAT |
## Creation of simple concepts

| Step number                       | Actions                                                                                                                                                                                                                                                                                                                                                                                                                              |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Step 1                            | Read `since_when_data_complete` from D2_CDM/INSTANCE (or use 1900-01-01 if INSTANCE is unavailable); this cutoff is applied to vaccine codelist records. |
| Use of dap_specific_codelists     |                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Step 2                            | Load each configured DAP-specific codelist, retain rows with `match_status = 'MATCHED'`, and uppercase its `code`, `coding_system`, and `concept_id` values. |
| Step 3                            | Build source views for available CDM tables by joining their records to `D3_SPELLS`, normalizing the source code/date fields as described below, and excluding rows without a usable date. |
|                                   | **EVENTS:** Use `event_free_text` when `event_record_vocabulary` is `FREE_TEXT`; otherwise use `event_code`. Uppercase the selected code. Use `start_date_record` as the date. |
|                                   | **MEDICINES:** Use `medicinal_product_id` and `PRODCODEID` for CPRD; otherwise use `medicinal_product_atc_code` and `ATC`. Uppercase the code. Use `date_prescription` when `date_dispensing` is missing; otherwise use `date_dispensing`. |
|                                   | **VACCINES:** Use `vx_type` and `VX_TYPE` when `vx_atc` is missing, blank, or `NA`; otherwise use `vx_atc` and `VX_ATC`. Use `vx_record_date` when `vx_admin_date` is missing; otherwise use `vx_admin_date`. |
|                                   | **PROCEDURES:** Use `procedure_code` as stored, uppercase `procedure_code_vocabulary`, and use `procedure_date`. |
| Step 4                            | Delete records from the temporal table that date is empty                                                                                                                                                                                                                                                                                                                                                                            |
| Step 5                            | Join each edited source view to its DAP-specific codelist on the normalized `code` and `coding_system` fields. |
|                                   | - EVENTS: `event_code` = codelist `code`; `event_record_vocabulary` = codelist `coding_system`. |
|                                   | - MEDICINES and VACCINES: `code` and `coding_system` match the corresponding codelist fields. |
|                                   | - PROCEDURES: `procedure_code` = codelist `code`; `procedure_code_vocabulary` = codelist `coding_system`. |
| Step 6                            | Add results in concept_table with the column names as described above                                                                                                                                                                                                                                                                                                                                                                |
| Use of `dap_specific_concept_map` |                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Step 7                            | Using the RWEBRIDGE::`dap_specific_concept_map` table, records that follow the combination of values in the `expected_value_X` column within the cdm column names defined in the `column_name_X`. <br /><br />Select the **date** of the concept as: CDM column defined in the `keep_date_column_name`, date >= `start_look_back`. <br />Select the **value** of the concept as: CDM column defined in the `keep_value_column_name`. |
| Step 8                            | Add results in concept_table with the column names as described above |
## Example

| ori_table | unique_id | person_id | code | coding_system | value | date | concept_id |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EVENTS | source-001 | 1 | RSV-LRTI | ICD10 | TRUE | 2024-10-12 | LRTI_RSV_INFECTION |
| MEDICINES | source-002 | 1 | NIRSEVIMAB | ATC | TRUE | 2024-10-20 | VP_NIRSEVIMAB |

## Creation of complex concepts

Complex concepts are created by the functions under
`transformations/T2_semantic_harmonization/source_code/functions/` and SQL
queries under `source_code/sql/`. The orchestrator reads
`concept_preprocessing.csv`, selects the configured constructor, and passes the
input parquet directory, output directory, output concept name, and source
concept IDs to that constructor.

### `create_under12m.R`

| Step number | Actions |
| --- | --- |
| Step 1 | Read `D3_SPELLS` to obtain each person’s `birth_date`; no source concept partition is required. |
| Step 2 | Calculate the 12-month boundary as `floor(12 * config_values$month_length)` days after birth. |
| Step 3 | Write a `TRUE` boundary at birth plus 12 months and a `FALSE` boundary one day later. |
| Step 4 | Store the output as `CC_12M_ONEXPOSURE`; `study_variables.csv` maps this intermediate concept to `INCL_UNDER12M`. A LATEST anchor returns TRUE through 12 months and FALSE afterward. |

### `create_29w_gestage.R`

| Step number | Actions |
| --- | --- |
| Step 1 | Read the configured gestational-age simple concept partition, normally `GEST_AGE`. |
| Step 2 | Parse gestational age as weeks and compare it with the threshold `>= 29`. |
| Step 3 | Join to `D3_SPELLS` where required and retain the gestational-age event date. |
| Step 4 | Store TRUE/FALSE output in `CC_29W_GESTAGE`; `study_variables.csv` maps it to `INCL_29W_GESTAGE`. |

### `create_age_group.R`

| Step number | Actions |
| --- | --- |
| Step 1 | Read each person’s `birth_date` from `D3_SPELLS`; no source concept partition is required. |
| Step 2 | Calculate boundaries at 3 and 6 months using `floor(months * config_values$month_length)`. |
| Step 3 | Write boundary values for age groups 1 (<=3 months), 2 (>3 to <=6 months), and 3 (>6 months). |
| Step 4 | Store the output as `PP_AGE_GROUP`; `study_variables.csv` maps it to `SV_AGE_GROUP`. A LATEST anchor returns the category at T0. |

### `calculate_calendar_week.R`

| Step number | Actions |
| --- | --- |
| Step 1 | Read the configured source concept partitions and `D3_SPELLS`. |
| Step 2 | Run `calendar_week_time.sql` to derive calendar-week values from the exposure/treatment date. |
| Step 3 | Use the configured study end date to close the generated time intervals. |
| Step 4 | Store the output as `PP_CALENDAR_WEEK`; `study_variables.csv` maps it to `SV_CALENDAR_WEEK`. |

### `create_enrolled.R`

| Step number | Actions |
| --- | --- |
| Step 1 | Read `D3_SPELLS`, which represents observation/enrollment spells. |
| Step 2 | For each spell, set `start_spell` to TRUE and `end_spell + 1` to FALSE. |
| Step 3 | Melt the start and end boundaries into one dated `value` column. |
| Step 4 | Add the configured concept ID `PP_ENROLLED` and required concept columns; `study_variables.csv` maps it to `INCL_ENROLLED`. |

### `create_gestage_ageseas.R`

| Step number | Actions |
| --- | --- |
| Step 1 | Read the configured gestational-age concept partition and join it to `D3_SPELLS` for `birth_date`. |
| Step 2 | Select gestational ages between 29 and 35 weeks. |
| Step 3 | Evaluate whether the person is older than 6 months at `config_values$start_rsv_season`. |
| Step 4 | Store TRUE/FALSE values dated at the gestational-age record date in `CC_GESTAGE_AGESEAS`; `study_variables.csv` maps it to `EXCL_GESTAGE_AGESEAS`. |

### `create_adi.R`

| Step number | Actions |
| --- | --- |
| Step 1 | Read the configured area-deprivation concept partitions from `D3_CONCEPTS_parquet`. |
| Step 2 | Join the source records to `D3_SPELLS` to obtain each person’s `birth_date`. |
| Step 3 | Replace the source concept date with `birth_date`, preserving the area-deprivation value. |
| Step 4 | Store the result as `PP_ADI`, which `study_variables.csv` maps and anchors later as `SV_ADI`. |

### `create_or.R`

| Step number | Actions |
| --- | --- |
| Step 1 | Discover the configured source concept partitions and retain only partitions that exist and contain data. |
| Step 2 | Read all selected source partitions with DuckDB and union their records. |
| Step 3 | Exclude the source `concept_id` and replace it with the requested output concept name. |
| Step 4 | Write the union to the output parquet directory, partitioned by the new `concept_id`. This implements OR logic across source concepts. |

### Shared preprocessing helpers

| Function | Documentation |
| --- | --- |
| `normalise_inputs()` | Converts constructor arguments to the common input/output/concept/subconcept interface. |
| `validate_inputs()` | Checks the input directory, output concept name, and required source-concept arguments before processing. |
| `ensure_clean_output_directory()` | Removes or recreates the target concept partition so reruns do not append stale rows. |
| `prepare_sub_concept_ids()` | Normalizes configured source concept IDs, retains existing parquet partitions, and excludes unavailable or empty partitions. |
| `get_counts()` | Reads the generated partition and reports row counts for audit logging. |

### SQL procedures

| SQL file | Function |
| --- | --- |
| `under12m.sql` | Creates the 12-month age boundary records. |
| `gest_age_condition.sql` | Applies the gestational-age threshold and joins D3 spells. |
| `age_group.sql` | Creates 3- and 6-month age-group boundaries. |
| `calendar_week_time.sql` | Creates calendar-week time intervals. |
| `gest_age_ageseas.sql` | Applies the 29-35 week and RSV-season age conditions. |
| `adi_date.sql` | Replaces area-deprivation concept dates with birth dates. |

## Composite concepts

| Step number | Actions |
| --- | --- |
| Step 1 | Load source partitions listed in `concept_preprocessing.csv`. |
| Step 2 | Apply the constructor-specific date, interval, threshold, or OR rule above. |
| Step 3 | Add the requested output `concept_id` and required standard columns. |
| Step 4 | Write the result to `D3_CONCEPTS_parquet/` partitioned by `concept_id`. |

### Study-variable metadata

The complete project concept list, variable type, eligibility flag, lookback,
constructor, and source definition are maintained in
`transformations/common_configuration/RWE-BRIDGE/study_variables.csv` and
`concept_preprocessing.csv`.

## Example

| person_id | date | concept_id | value |
| --- | --- | --- | --- |
| 1 | 2024-10-20 | SV_NIRSEVIMAB | TRUE |
| 1 | 2024-10-20 | SV_CALENDAR_WEEK | 43 |
| 1 | 2024-10-20 | SV_AGE_GROUP | 2 |
| 1 | 2024-10-20 | INCL_UNDER12M | TRUE |
