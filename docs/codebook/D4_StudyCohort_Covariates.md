## Metadata

| Table name                | D4_StudyCohortCovariates_`<Main/Supplement>`                                                                                                                                     |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Table of covariate values evaluated at baseline (T0) for the study cohort. Used to create baseline descriptives tables; fit baseline weights models, etc. |
| Source                    | D4_StudyCohort_<mode>, D3_CONCEPTS_parquet, D3_SPELLS.parquet, study_variables.csv, config_values |
| Step                      | `transformations/T3_study_design/source_code/anchor_covariates.R` |
| Content                   | For each person_id/T0 record (row) in D4_Studycohort, calculate covariates anchored at T0                                                                 |
| Population                | Selected study cohort                                                                                                                                     |
| Unit of Observation (UoO) | person_id, T0. person(-spell) selected as exposed or control in the study cohort                                                                          |

## Codebook

| variable_in_output        | variable(s) needed | retrieved | computed | format    | rule_of_calculation             | description                                                                                                                                                                                                                              | vocabulary |
| ------------------------- | ------------------ | --------- | -------- | --------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| person_id                 | D4_StudyCohort_<mode>/person_id | x | | character | Carried from the selected cohort | person_id of exposed or control | |
| T0                        | D4_StudyCohort_<mode>/T0 | x | | date | Carried from the selected cohort | Time zero for exposed and matched control | |
| group                     | D4_StudyCohort_<mode>/group | x | | character | Carried from the selected cohort | EXPOSED or CONTROL | |
| match_id                  | D4_StudyCohort_<mode>/match_id | x | | integer | Carried from the selected cohort | Matched pair or set identifier | |
| SV_AGE_GROUP              | D4_StudyCohort_<mode>/SV_AGE_GROUP | x | | categorical | Carried from the selected cohort | 1: <=3 months, 2: >3 to <=6 months, 3: >6 months | 1-3 |
| SV_CALENDAR_WEEK          | D4_StudyCohort_<mode>/SV_CALENDAR_WEEK | x | | integer | Carried from the selected cohort | Calendar week matching variable | 1-53 |
| SV_PRIOR_LRTI              | D3_CONCEPTS_parquet, study_variables.csv, D4_StudyCohort_<mode>/person_id,T0 | | x | boolean | Anchored from configured study-variable metadata at T0 | Prior LRTI in the configured lookback window | |
| SV_HC_UTI                 | D3_CONCEPTS_parquet, study_variables.csv, D4_StudyCohort_<mode>/person_id,T0 | | x | integer | Anchored count in the configured lookback window | Number of healthcare visits prior to T0 | |
| SV_ANTIBIOTICS            | D3_CONCEPTS_parquet, study_variables.csv, D4_StudyCohort_<mode>/person_id,T0 | | x | integer | Anchored count in the configured lookback window | Number of antibiotic prescriptions prior to T0 | |
| SV_HC_UTI_CAT | SV_HC_UTI | | x | integer | `categorize_count(SV_HC_UTI)`: 0, 1, or 2+ visits | Categorised healthcare visits prior to T0 | 0, 1, 2 |
| SV_ANTIBIOTICS_CAT | SV_ANTIBIOTICS | | x | integer | `categorize_count(SV_ANTIBIOTICS)`: 0, 1, or 2+ prescriptions | Categorised antibiotic prescriptions prior to T0 | 0, 1, 2 |
| SV_SEX                    | D3_SPELLS.parquet/person_id, sex_at_instance_creation | x | | categorical | Joined from D3_SPELLS by person_id | Sex at instance creation | source vocabulary |
| SV_ADI             | D3_CONCEPTS_parquet, study_variables.csv, D4_StudyCohort_<mode>/person_id,T0 | | x | categorical | Anchored from configured study-variable metadata at T0 | Area deprivation index quintile; missing is coded as 0 in the baseline metadata | 0 missing, 1-5 |

## Example

| person_id | T0         | group   | match_id | SV_ADI | SV_AGE_GROUP | SV_HC_UTI | SV_ANTIBIOTICS | SV_HC_UTI_CAT | SV_ANTIBIOTICS_CAT | SV_SEX |
| --------- | ---------- | ------- | -------- | ------ | ------------ | --------- | -------------- | ------------- | ------------------ | ------ |
| 1         | 2021-01-01 | EXPOSED | 1        | 4      | 1            | 3         | 1              | 2             | 1                  | 1      |
| 3         | 2021-01-01 | CONTROL | 1        | 2      | 1            | 1         | 0              | 1             | 0                  | 1      |
