## Metadata

| Table name                | D4_UNIVARIATE_EPISODES                                                                                                                                                                                                                                                                                                           |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Time-varying univariate dataset. This dataset is generated for time-varying eligibility, and it is the input dataset of a multivariate dataset. The rows of this dataset are episodes of study variables, generated using the concepts datasets (found in D3_CONCEPTS) and the lookback period of the respective study variable. |
| Source                    | `study_variables.csv`, `D3_CONCEPTS_parquet/`, and `D3_SPELLS.parquet` |
| Step                      | create_univariate_episodes.R                                                                                                                                                                                                                                                                                                     |
| Content                   | This dataset contains the start and end episodes, along with their respective values for each selected study variable. For each study variable, each person must have a complete history of episodes during the eligibility period. Thus, empty periods of time must be filled with new episodes.                                |
| Population                | Persons represented in `D3_SPELLS` |
| Unit of Observation (UoO) | One or more rows per person and `variable_id` |

## Codebook

| variable_in_output | variable(s) needed | retrieved | computed | format | rule_of_calculation                                                                                                                                                       | description                                                                                                                       | vocabulary                                                                               |
| ------------------ | ------------------ | --------- | -------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| person_id          | `D3_SPELLS/person_id` | x | | string | Person IDs loaded from D3_SPELLS | Unique identifier | |
| variable_id        | `study_variables/variable_id` | x | | string | Study-variable metadata used to select concepts | Study-variable identifier | `INCL_*`, `EXCL_*`, `SV_*` |
| start_episode      | `D3_CONCEPTS/date` |           | x        | Date   | Concept date or configured eligibility start | Start of the episode | YYYY-MM-DD |
| end_episode        | `start_episode`, `BRIDGE/study_variables`  |           | x        | Date   | Derived from episode interval and configured lookback | End of the episode | YYYY-MM-DD |
| value              | `D3_CONCEPTS/value` |           | x | string/logical/numeric | Carried from the selected concept and gap-fill rule | Value during the episode | Concept-specific |

## Processing Steps

| Step number                                                    |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Step 1: Generate spells for each record related to the concept | Load the eligible study-variable metadata, read matching concept partitions, and create intervals from concept dates and lookback settings. |
| Step 2: Merging overlapping episodes                           | Merge overlapping intervals with the same value; crop the preceding interval when values change. |
| Step 3: Filling gaps                                           | Fill gaps across the eligibility period with the configured default value, such as `FALSE` for boolean variables or `NA` for categorical variables. |
| Step 4: Generating univariate episodes for missing population  | Create default intervals for persons without a matching concept record. |
| Step 5: Reducing number of univariate episodes                 | Remove intervals outside the configured eligibility period. |
| Step 6: Trimming univariate episodes                         | Trim interval boundaries to the study eligibility period. |

## Example

| person_id | variable_id | start_episode | end_episode | value |
| --------- | --- | --- | --- | --- |
| 1 | INCL_UNDER12M | 2024-10-01 | 2025-01-01 | TRUE |
