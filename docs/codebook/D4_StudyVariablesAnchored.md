# METADATA

| Table name | D4 StudyVariablesAnchored_`<Main/Supplement>`|
| --- | --- |
| Description | Long-format study-variable values anchored to each selected cohort person and T0. |
| Source | D4_StudyCohort_<mode>, D3_CONCEPTS_parquet, D3_SPELLS.parquet, and `study_variables.csv` |
| Step | `transformations/T3_study_design/source_code/anchor_covariates.R` |
| Content | Anchored study-variable records written as hive-partitioned parquet |
| Population | Main and supplementary D4 study cohorts |
| Unit of Observation (UoO) | Person, T0, lookback window, and `variable_id` |

# CODEBOOK

| variable_in_output | variable(s) needed | retrieved | computed | format | rule_of_calculation | description | vocabulary |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `anchor_row_id` | D4_StudyCohort_<mode>/person_id,T0 | | x | character/integer | Identifier assigned to each anchored cohort row | Anchor-row identifier | Unique |
| `person_id` | D4_StudyCohort_<mode>/person_id | x | | character/integer | Carried from cohort | Person identifier | Source |
| `T0` | D4_StudyCohort_<mode>/T0 | x | | date | Carried from cohort | Time zero | YYYY-MM-DD |
| `window_name` | `study_variables.csv`/window metadata | x | | character | Lookback window selected by the anchoring configuration | Anchoring window | Metadata-defined |
| `value` | D3_CONCEPTS_parquet/value, `study_variables.csv`/concept and window metadata | x | x | character/logical/numeric | Anchored concept value at T0 and within the configured window | Study-variable value | Variable-specific |
| `date` | D3_CONCEPTS_parquet/date | x | | date | Date of the anchored source record, when applicable | Source event date | YYYY-MM-DD |
| `n` | D3_CONCEPTS_parquet/person_id, date, value | x | x | integer | Count of source records in the anchored window, when applicable | Count value | Non-negative integer |
| `variable_id` | `study_variables.csv`/variable_id | x | x | character | Study-variable identifier; also the parquet partition key | Anchored study variable | `SV_*` |

# PROCESSING STEPS

| Step | Description |
| --- | --- |
| Step 1 | Load project configuration, study-variable metadata, D3 concepts, D3 spells, and the selected Main or Supplement cohort. |
| Step 2 | Construct one anchor row per cohort `person_id`/`T0` record. |
| Step 3 | Anchor each configured study variable using its lookback window and constructor. |
| Step 4 | Keep the long-format fields `value`, `date`, and `n` with the variable and anchor identifiers. |
| Step 5 | Write `D4_StudyVariablesAnchored_<mode>_parquet/`, partitioned by `variable_id`. |

## Anchoring functions - indicated in study_variables.csv

| Function | Description |
| --- | --- |
| `LATEST` | Select the latest source record in the configured lookback window. |
| `GENERIC` | Apply the generic anchoR constructor using variable metadata. |
| `LOOKBACK` | Restrict source records to configured offsets relative to T0. |

# EXAMPLE

| anchor_row_id | person_id | T0 | window_name | variable_id | value | date | n |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 2024-10-20 | lookback | SV_HC_UTI | 3 | 2024-10-18 | 3 |
| 1 | 1 | 2024-10-20 | lookback | SV_ADI | 4 |  |  |
| 1 | 1 | 2024-10-20 | lookback | SV_PRIOR_LRTI | FALSE |  |  |