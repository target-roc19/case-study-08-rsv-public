## DMetadata

| Table name                | D3_PERSONS                                                                                                                                                                                            |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Processing the persons information. Imputation of dates and exclusion of cases with missing information (death date or birth date)                                                                    |
| Source                    | D2_CDM.PERSONS                                                                                                                                                                                        |
| Step                      | transformations/T2_semantic_harmonization/source_code/process_persons.R                                                                                                                               |
| Content                   | processed records from the D2_CDM.PERSONS table                                                                                                                                                       |
| Population                | Persons that comply with the quality inclusion criteria and are no more than `year_length` days old at `start_rsv_season` (365.25 days for this project) |
| Unit of Observation (UoO) | One row per individual                                                                                                                                                                                |

## Codebook

| variable_in_output       | variable(s) needed                      | retrieved | computed | format                       | rule_of_calculation                                                             | description                                                                                               | vocabulary |
| ------------------------ | --------------------------------------- | --------- | -------- | ---------------------------- | ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ---------- |
| person_id                | D2_CDM/PERSONS/person_id                | X         |          | chr                          |                                                                                 | Key identifier                                                                                            |            |
| sex_at_instance_creation | D2_CDM/PERSONS/sex_at_instance_creation | X         |          | character                    | Set to NA when the source value is not `F` or `M`                               | Sex at instance creation                                                                                  | F,M        |
| imputed_birth_day        | D2_CDM/PERSONS/day_of_birth, year_of_birth |           | X        | Boolean (TRUE/FALSE)         | TRUE when `year_of_birth` is present and `day_of_birth` is missing; the day is set to 16 | Whether the birth day was imputed                                                                |            |
| imputed_birth_month      | D2_CDM/PERSONS/month_of_birth, year_of_birth |         | X        | Boolean (TRUE/FALSE)         | TRUE when `year_of_birth` is present and `month_of_birth` is missing; the month is set to 6 (or 5 when the imputed day is 31) | Whether the birth month was imputed                                                   |            |
| imputed_death_day        | D2_CDM/PERSONS/day_of_death, year_of_death |           | X        | Boolean (TRUE/FALSE)         | TRUE when `year_of_death` is present and `day_of_death` is missing; the day is set to 16 | Whether the death day was imputed                                                               |            |
| imputed_death_month      | D2_CDM/PERSONS/month_of_death, year_of_death |         | X        | Boolean (TRUE/FALSE)         | TRUE when `year_of_death` is present and `month_of_death` is missing; the month is set to 6 (or 5 when the imputed day is 31) | Whether the death month was imputed                                                   |            |
| birth_date               | D2_CDM/PERSONS/day_of_birth, month_of_birth, year_of_birth |           | X        | Date YYYY-MM-DD              | Combine day, month, and year when all are present after imputation               | Date of birth                                                                                             |            |
| death_date               | D2_CDM/PERSONS/day_of_death, month_of_death, year_of_death |           | X        | Date YYYY-MM-DD              | Combine day, month, and year when all are present after imputation               | Date of death (if available; otherwise NA)                                                                |            |
| missing_year_of_birth    | D2_CDM/PERSONS/year_of_birth            |           | X        | Boolean (TRUE/FALSE)         | if year_of_birth missing or na, missing_year_of_birth equal to TRUE             | Boolean checking whether the year_of_birth is empty or not. Due to data missingness we need to check this |            |
| not_missing_year_death   | D2_CDM/PERSONS/year_of_death, day_of_death, month_of_death |           | X        | Boolean (TRUE/FALSE)         | `!(is.na(year_of_death) & (!is.na(day_of_death) | !is.na(month_of_death)))`     | Flag used by the script's death-date quality filter                                                      |            |
| death_before_birth       | death_date, birth_date                  |           | X        | Boolean (TRUE/FALSE)         | TRUE when `death_date < birth_date`; missing comparisons are set to FALSE       | Death date precedes birth date                                                                            |            |
| missing_sex              | D2_CDM/PERSONS/sex_at_instance_creation |           | X        | Boolean (TRUE/FALSE)         | TRUE when sex is missing or is not `F` or `M`                                   | Missing or invalid sex flag                                                                                |            |
| year_of_birth            | D2_CDM/PERSONS/year_of_birth            | x         |          | integer                      |                                                                                 |                                                                                                           |            |
| infant_pop               | birth_date, config_values/start_rsv_season, config_values/year_length |           | X        | Boolean (TRUE/FALSE)         | TRUE when `start_rsv_season - birth_date <= year_length`; rows with FALSE are removed | Whether the person is within the configured infant-age limit at RSV-season start | TRUE, FALSE |

## Processing Steps

Apply record imputation: day/month of birth, day/month of death. Missing days are set to 16 and missing months to 6 when the corresponding year is present; an imputed month is set to 5 when the day is 31.

| Step number                                                   |        |               |                       |
| ------------------------------------------------------------- | ------ | ------------- | --------------------- |
| Stepwise record removal                                       | Remove | Left          | N-original no of rows |
| 1 missing year of birth                                       | n1     | N1:= N-n1     |                       |
| 2 missing year of death when day/month of death are available | n2     | N2:= N1-n2    |                       |
| 3 death date before birth date                                | n3     | N3:= N2-n3    |                       |
| 4 duplicated person_id                                        | n4     | N4:= N3-n4    |                       |
| 5 missing sex                                                 | n5     | N5:= N4-n5    |                       |
| 6 not in infant population at start of RSV season             | n6     | N6 := N5 - n6 |                       |

## Example

| person_id | sex_at_instance_creation | imputed_birth_day | imputed_birth_month | imputed_death_day | imputed_death_month | birth_date | death_date | missing_year_of_birth | not_missing_year_death | death_before_birth | missing_sex | year_of_birth | infant_pop |
| --------- | ------------------------ | ----------------- | ------------------- | ----------------- | ------------------- | ---------- | ---------- | --------------------- | ---------------------- | ------------------ | ----------- | ------------- | ---------- |
| 1001      | F                        | FALSE             | FALSE               | FALSE             | FALSE               | 2023-12-12 |            | FALSE                 | FALSE                  | FALSE              | FALSE       | 2023          | TRUE       |
| 1002      | M                        | TRUE              | FALSE               | TRUE              | TRUE                | 2023-11-15 |            | FALSE                 | FALSE                  | FALSE              | FALSE       | 2023          | TRUE       |
