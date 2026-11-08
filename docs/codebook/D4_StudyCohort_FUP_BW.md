## Metadata

| Table name                | D4_StudyCohortFup_<Main, Supplement>_BW                                                                                                                                                                                            |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Best/worst case-imputation follow-up dataset for Estimand 1. For rows with non-administrative censoring,`event_est1` is imputed with best (all FALSE) or worst (all TRUE) senario; follow-up is extended to `general_fup_d`. |
| Source                    | D4_StudyCohortFup_Main; config_values                                                                                                                                                                                            |
| Step                      | `transformations/T3_study_design/source_code/impute_outcome_BW.R` |
| Content                   | Long-format output: each person_id/T0 row is repeated twice - one scenario each.                                                                                                                                                 |
| Population                | Selected study cohort (Main mode)                                                                                                                                                                                                |
| Unit of Observation (UoO) | person_id, T0, bw_id                                                                                                                                                                                                             |

## Step Summary

1. Load the configured D4 follow-up dataset for each mode.
2. Select the follow-up fields used to create the scenarios; baseline covariates are not joined by this script.
3. For rows with `admin_censor_est1 == "non-admin"`, assign event and follow-up dates according to each scenario. `admin_censor_est1` was defined in D4_StudyCohort_FUP.
   - `uncensored`: reason 1
   - `non-admin`: reasons 6 or 3
   - `admin`: reasons 2, 4, 5
4. Create four best/worst scenarios, assigning `event_est1` for the non-admin-censored subset:
   - best: assign `event_est1` as `0`
   - worst: assign `event_est1` as `1`
5. Extend `fup_d_est1` to `general_fup_d` for scenario records assigned no event; otherwise retain the observed follow-up end date.
6. Recalculate follow-up lengths and save the four scenarios in long format.

## Codebook

| variable_in_output   | variable(s) needed                               | retrieved | computed | format    | rule_of_calculation                                                                                                                                                                                                                                                                                                      | description                                                     | vocabulary                   |
| -------------------- | ------------------------------------------------ | --------- | -------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------- | ---------------------------- |
| person_id            | D4_StudyCohort_FUP_<mode>/person_id | x | | character | Carried from follow-up input | Person identifier | |
| T0                   | D4_StudyCohort_FUP_<mode>/T0 | x | | date | Carried from follow-up input | Time-zero | |
| group                | D4_StudyCohort_FUP_<mode>/group | x | | character | Carried from follow-up input | EXPOSED or CONTROL | EXPOSED, CONTROL |
| match_id             | D4_StudyCohort_FUP_<mode>/match_id | x | | integer | Carried from follow-up input | Matched set identifier | |
| bw_scenario          | D4_StudyCohort_FUP_<mode>/admin_censor_est1, group | | x | character | Scenario assigned to each copy of the input follow-up data | Scenario categories (long format) | 'bb', 'bw', 'wb', 'ww' |
| bw_id                | bw_scenario | | x | integer | 'bw' -> 1, 'wb' -> 2, 'bb' -> 3, 'ww' -> 4 | Scenario identifier | 1,2,3,4 |
| admin_censor_est1    | D4_StudyCohort_FUP_<mode>/admin_censor_est1 | x | | character | Carried from follow-up input | Censoring category used to define scenario subset | uncensored, non-admin, admin |
| event_est1_observed  | D4_StudyCohort_FUP_<mode>/event_est1 | x | | integer | Carried from follow-up input | Observed Estimand 1 event before scenario assignment | 0,1 |
| event_est1           | event_est1_observed, admin_censor_est1, group, bw_scenario | | x | integer | Assign scenario-specific event values to the non-admin-censored subset | Estimand 1 event indicator after best/worst scenario assumption | 0,1 |
| general_fup_d        | D4_StudyCohort_FUP_<mode>/general_fup_d | x | | date | Carried from follow-up input | General follow-up limit | |
| fup_d_est1           | D4_StudyCohort_FUP_<mode>/fup_d_est1, general_fup_d, admin_censor_est1, group, bw_scenario | | x | date | Set to `general_fup_d` for scenario records assigned no event; otherwise retain input value | Follow-up end date after scenario handling | |
| fup_length_days_est1 | fup_d_est1, T0 | | x | integer | `fup_d_est1 - T0 + 1` | Follow-up duration in days for Estimand 1 | |
| fup_length_pm_est1   | fup_length_days_est1, config_values/month_length | | x | numeric | `fup_length_days_est1 / month_length` | Follow-up duration in person-months for Estimand 1 | |

## Example (Long Format)

| person_id | T0         | group   | match_id | bw_scenario | bw_id | admin_censor_est1 | event_est1_observed | event_est1 | fup_d_est1 | fup_length_days_est1 |
| --------- | ---------- | ------- | -------- | ----------- | ----- | ----------------- | ------------------- | ---------- | ---------- | -------------------- |
| 3         | 2021-01-01 | CONTROL | 1        | bb          | 1     | non-admin         | 0                   | 0          | 2021-06-29 | 180                  |
| 1         | 2021-01-01 | EXPOSED | 1        | bb          | 1     | non-admin         | 0                   | 0          | 2021-06-29 | 180                  |
| 3         | 2021-01-01 | CONTROL | 1        | bw          | 2     | non-admin         | 0                   | 1          | 2021-03-29 | 88                  |
| 1         | 2021-01-01 | EXPOSED | 1        | bw          | 2     | non-admin         | 0                   | 0          | 2021-06-29 | 180                  |
