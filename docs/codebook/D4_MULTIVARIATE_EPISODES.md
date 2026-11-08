## Metadata

| Table name                | D3_MULTIVARIATE_EPISODES |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Multivariate episode table combining the selected univariate study-variable intervals. |
| Source                    | `D3_UNIVARIATE_EPISODES_parquet/` and `D3_SPELLS.parquet` |
| Step                      | create_multivariate_episodes.R                                                                                                                                                                                                                                                                            |
| Content                   | One row per person and combined interval with inclusion, exclusion, and study-variable values. |
| Population                | Persons represented in `D3_SPELLS` |
| Unit of Observation (UoO) | Person and multivariate episode interval |

## Codebook

| variable_in_output | variable(s) needed | retrieved | computed | format | rule_of_calculation | description | vocabulary |
|---------------|----------------|---------|---------|-------|---------------|-----------|-----|
| person_id | D3_SPELLS/person_id, D3_UNIVARIATE_EPISODES/person_id | x | | character | Carried from the multivariate-episodes input | Person identifier | |
| start_episode | D3_UNIVARIATE_EPISODES/start_episode | | x | date | Combined interval start | Episode start | |
| end_episode | D3_UNIVARIATE_EPISODES/end_episode | | x | date | Combined interval end | Episode end | |
| `INCL_*`, `EXCL_*`, `SV_*` | D3_UNIVARIATE_EPISODES/variable_id, study_variables.csv | | x | logical/integer | Combined status at the interval for metadata-selected variables | Study-variable status | Metadata-defined |

## Processing Steps

| Step number |     |
|-------------|-----|
| Step 1      | Load eligibility-flagged study variables and the univariate episode dataset. |
| Step 2      | Run `episodeR::multivariate_episodes_pipeline` to combine intervals and values. |
| Step 3      | Write `D3_MULTIVARIATE_EPISODES.parquet` for use by `create_eligibility.R`. |

## Example

| person_id | start_episode | end_episode | INCL_UNDER12M | SV_AGE_GROUP | SV_NIRSEVIMAB |
|-----------|---------------|-------------|---------------|--------------|---------------|
| 1 | 2024-10-01 | 2025-01-01 | TRUE | 2 | TRUE |
