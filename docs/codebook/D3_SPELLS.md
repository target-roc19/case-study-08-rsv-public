## Metadata

| Table name                | D3_SPELLS                                                                                                                                           |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Merging observation periods that overlap or are separated by no more than 180 days into spells, then correcting spell boundaries using person dates. |
| Source                    | D2_CDM/OBSERVATION_PERIODS, D3_PERSONS.parquet, and config_values/start_study_d, end_study_d, recommended_end_date, date_creation |
| Step                      | `transformations/T2_semantic_harmonization/source_code/process_observation_periods.R` |
| Content                   |                                                                                                                                                     |
| Population                | Observation periods for people present in D3_PERSONS, retaining spells with both boundaries and start before end |
| Unit of Observation (UoO) | One row per valid distinct spell; a person may have multiple rows |

## Codebook

| variable_in_output       | variable(s) needed                                                                    | retrieved | computed | format               | rule_of_calculation                                                                                                                                                                                                                                                                                                                                                                                       | description                                                                                                                                                              | vocabulary |
| ------------------------ | ------------------------------------------------------------------------------------- | --------- | -------- | -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| person_id                | D2_CDM/OBSERVATION_PERIODS/person_id, D3_PERSONS/person_id | X | | character/integer | Join observation periods to D3_PERSONS by `person_id` | Person identifier | |
| start_spell              | D2_CDM/OBSERVATION_PERIODS/op_start_date, D3_PERSONS/birth_date | | X | date | Create merged spell start; replace with `birth_date` when earlier | Start date of the spell | YYYY-MM-DD |
| end_spell                | D2_CDM/OBSERVATION_PERIODS/op_end_date, config_values/end_study_d, D3_PERSONS/death_date | | X | date | Merge periods; fill missing end with `end_study_d` when start is earlier; cap at `death_date` when later | End date of the spell | YYYY-MM-DD |
| year_of_birth            | D3_PERSONS/year_of_birth | X | | integer | Carried from D3_PERSONS | Year of birth | |
| sex_at_instance_creation | D3_PERSONS/sex_at_instance_creation | X | | character | Carried from D3_PERSONS | Sex at instance creation | F,M |
| birth_date               | D3_PERSONS/birth_date | X | | date | Carried from D3_PERSONS | Date of birth | YYYY-MM-DD |
| death_date               | D3_PERSONS/death_date | X | | date | Carried from D3_PERSONS | Date of death, if available | YYYY-MM-DD |
| with_start_and_end       | start_spell, end_spell | | X | Boolean (TRUE/FALSE) | TRUE when both spell boundaries are present | Spell has both start and end dates | TRUE, FALSE |
| start_before_end         | start_spell, end_spell | | X | Boolean (TRUE/FALSE) | TRUE when `start_spell < end_spell` | Spell starts before it ends | TRUE, FALSE |

## Processing Steps

| Step number | Actions |
| ----------- | ------- |
| Step 1 | If `op_end_date` is missing and `op_start_date` is before `end_study_d`, impute `op_end_date` with `end_study_d`; exclude periods where both dates are missing. |
| Step 2 | Create spells by merging overlapping observation periods or periods separated by no more than 180 days. Replace remaining missing end dates with `end_study_d` before merging. |
| Step 3 | Join spells to observation periods, then inner join to D3_PERSONS by `person_id`. |
| Step 4 | If `start_spell` is before `birth_date`, set it to `birth_date`; if `end_spell` is after `death_date`, set it to `death_date`; fill a missing `end_spell` with `end_study_d` when `start_spell` is earlier. |
| Step 5 | Derive `with_start_and_end` and `start_before_end`; retain spells where both are TRUE and remove duplicate rows. |
| Step 6 | Save all retained spells to `D3_SPELLS.parquet`; multiple spells per person may remain. |

## Example

| person_id | start_spell | end_spell  | year_of_birth | sex_at_instance_creation | birth_date | death_date | with_start_and_end | start_before_end |
| --------- | ----------- | ---------- | ------------- | ------------------------ | ---------- | ---------- | ------------------ | ---------------- |
| 1001      | 2020-01-15  | 2023-06-30 | 2019          | F                        | 2019-04-03 |            | TRUE               | TRUE             |
| 1002      | 2018-09-01  | 2029-03-31 | 2018          | M                        | 2018-07-20 | 2029-03-31 | TRUE               | TRUE             |
