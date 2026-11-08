## Metadata

| Table name                | D4_StudyCohortFup_<Main, Supplement>_MI                                                                                                                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Multiple-imputation follow-up dataset for Estimand 1. For rows with non-administrative censoring,`event_est1` is imputed using baseline covariates; follow-up is extended to `general_fup_d`. |
| Source                    | D4_StudyCohortFup_Main; D4_StudyCohortCovariates_Main; config_values                                                                                                                              |
| Step                      | `transformations/T3_study_design/source_code/impute_outcome_MI.R` |
| Content                   | Long-format output: each person_id/T0 row is repeated once per imputation (`imputation_id` from 1 to m).                                                                                        |
| Population                | Selected study cohort (Main mode)                                                                                                                                                                 |
| Unit of Observation (UoO) | person_id, T0, imputation_id                                                                                                                                                                      |

## Step Summary

1. Load D4 follow-up data and baseline covariates for Main mode.
2. Join tables by person_id, T0
3. For rows with `admin_censor_est1 == "non-admin"`, set `event_est1` to missing. `admin_censor_est1` was defined in D4_StudyCohort_FUP
   - `uncensored`: reason 1
   - `non-admin`: reasons 6 or 3
   - `admin`: reasons 2, 4, 5
4. Run `mice` multiple imputation (`method = "logreg"`) for `event_est1` using:
   - `group`
   - `SV_AGE_GROUP`
   - `SV_CALENDAR_WEEK`
   - `SV_SEX`
   - `SV_ADI`
   - `SV_PRIOR_LRTI`
   - `SV_HC_UTI_CAT`
   - `SV_ANTIBIOTICS_CAT`
5. Build long output with one copy per imputation (`imputation_id = 1..m`).
6. For imputed non-admin rows, set `fup_d_est1 = general_fup_d`, then recompute:
   - `fup_length_days_est1`
   - `fup_length_pm_est1`

## Codebook

| variable_in_output   | variable(s) needed                               | retrieved | computed | format    | rule_of_calculation                                                                          | description                                                | vocabulary                   |
| -------------------- | ------------------------------------------------ | --------- | -------- | --------- | -------------------------------------------------------------------------------------------- | ---------------------------------------------------------- | ---------------------------- |
| person_id            | D4_StudyCohort_FUP_<mode>/person_id | x | | character | Carried from follow-up input | Person identifier | |
| T0                   | D4_StudyCohort_FUP_<mode>/T0 | x | | date | Carried from follow-up input | Time-zero | |
| group                | D4_StudyCohort_FUP_<mode>/group | x | | character | Carried from follow-up input | EXPOSED or CONTROL | EXPOSED, CONTROL |
| match_id             | D4_StudyCohort_FUP_<mode>/match_id | x | | integer | Carried from follow-up input | Matched set identifier | |
| imputation_id        | impute_outcome configuration/model | | x | integer | 1..`n_imputations` | Imputation replicate index (long format) | 1..m |
| admin_censor_est1    | D4_StudyCohort_FUP_<mode>/admin_censor_est1 | x | | character | Carried from follow-up input | Censoring category used to define imputation target subset | uncensored, non-admin, admin |
| event_est1_observed  | D4_StudyCohort_FUP_<mode>/event_est1 | x | | integer | Carried from follow-up input before MI | Observed Estimand 1 event before MI | 0,1 |
| event_est1           | event_est1_observed, admin_censor_est1, D4_StudyCohortCovariates_<mode> model predictors | | x | integer | Keep observed values for admin/uncensored; impute for non-admin | Estimand 1 event indicator after MI | 0,1 |
| general_fup_d        | D4_StudyCohort_FUP_<mode>/general_fup_d | x | | date | Carried from follow-up input | General follow-up limit | |
| fup_d_est1           | D4_StudyCohort_FUP_<mode>/fup_d_est1, general_fup_d, admin_censor_est1 | | x | date | For non-admin rows, set to `general_fup_d`; otherwise retain input value | Follow-up end date after MI handling | |
| fup_length_days_est1 | fup_d_est1, T0 | | x | integer | `fup_d_est1 - T0 + 1` | Follow-up duration in days for Estimand 1 | |
| fup_length_pm_est1   | fup_length_days_est1, config_values/month_length | | x | numeric | `fup_length_days_est1 / month_length` | Follow-up duration in person-months for Estimand 1 | |

## Notes

1. This table is intended for Estimand 1 MI-based analyses.
2. Output is long format by design to preserve per-imputation records.
3. `event_est1_observed` is kept to enable diagnostics and sensitivity checks against imputed values.

## Example (Long Format)

| person_id | T0         | group   | match_id | imputation_id | admin_censor_est1 | event_est1_observed | event_est1 | fup_d_est1 | fup_length_days_est1 |
| --------- | ---------- | ------- | -------- | ------------- | ----------------- | ------------------- | ---------- | ---------- | -------------------- |
| 2         | 2021-01-01 | CONTROL | 1        | 1             | non-admin         | 0                   | 0          | 2021-06-29 | 180                  |
| 3         | 2021-01-01 | CONTROL | 1        | 1             | non-admin         | 0                   | 1          | 2021-06-29 | 180                  |
| 1         | 2021-01-01 | EXPOSED | 1        | 1             | non-admin         | 0                   | 1          | 2021-06-29 | 180                  |
| 2         | 2021-01-01 | CONTROL | 1        | 2             | non-admin         | 0                   | 1          | 2021-06-29 | 180                  |
| 3         | 2021-01-01 | CONTROL | 1        | 2             | non-admin         | 0                   | 1          | 2021-06-29 | 180                  |
| 1         | 2021-01-01 | EXPOSED | 1        | 2             | non-admin         | 0                   | 0          | 2021-06-29 | 180                  |
