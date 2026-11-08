## Metadata

| Table name                | D4_StudyCohortFup_<Main/Supplement>                                                                                                                                                                                                                                                                                                                 |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Data containing information on follow ups in the selected study cohort. Two parts:<br />first, dates of censoring events and any additional post-selection inclusion/exclusions. <br />Second: from this information, compute censoring date and reason, follow-up time.<br />Used to calculate censoring reason/ follow-up tables |
| Source                    | D4_StudyCohort_<mode>, D3_CONCEPTS_parquet, study_variables.csv, D3_SPELLS.parquet, config_values |
| Step                      | `transformations/T3_study_design/source_code/anchor_covariates.R` |
| Content                   | For each person_id/T0 record (row) in D4_StudyCohort, anchor outcomes from T0 + 1,<br />calculate censoring reason, followup time                                                                                                                                                                                                  |
| Population                | Selected study cohort                                                                                                                                                                                                                                                                                                              |
| Unit of Observation (UoO) | person(-spell) selected as exposed or control in the study cohort                                                                                                                                                                                                                                                                  |

## Codebook

| variable_in_output        | variable(s) needed | retrieved | computed | format    | rule_of_calculation                                                                                                                         | description                                                                                                                                                                                                | vocabulary |
| ------------------------- | ------------------ | --------- | -------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| person_id                 | D4_StudyCohort_<mode>/person_id | x | | character | Carried from the selected cohort | person_id | |
| T0                        | D4_StudyCohort_<mode>/T0 | x | | date | Carried from the selected cohort | Time zero | |
| group                     | D4_StudyCohort_<mode>/group | x | | character | Carried from the selected cohort | EXPOSED or CONTROL | |
| match_id                  | D4_StudyCohort_<mode>/match_id | x | | integer | Carried from the selected cohort | Matched pair or set identifier | |
| SV_HOSP_RSV_LRTI_d        | D3_CONCEPTS_parquet, study_variables.csv, D4_StudyCohort_<mode>/person_id,T0 | | x | date | Earliest anchored date of `SV_HOSP_RSV_LRTI` | RSV-associated hospitalization date; NA if none | |
| death_d                   | D3_SPELLS.parquet/person_id, death_date | x | | date | Carried from D3_SPELLS | Date of death; NA if none | |
| end_spell_d               | D3_SPELLS.parquet/person_id, end_spell | x | | date | Carried from D3_SPELLS as `end_spell_d` | End of observation spell | |
| general_fup_d             | D4_StudyCohort_<mode>/T0, config_values/general_fup_d | | x | date | `T0 + general_fup_d` | General follow-up limit | |
| end_study_d               | config_values/end_study_d | x | | date | Read from project configuration | End of study | |
| end_control_d             | D4_StudyCohort_<mode>/group, D3_CONCEPTS_parquet, study_variables.csv, D4_StudyCohort_<mode>/person_id,T0 | | x | date | For controls, date of anchored `SV_NIRSEVIMAB_IE` | Treatment initiation by control (Estimand 1 only) | |
| reason_censoring_est1     | SV_HOSP_RSV_LRTI_d, death_d, end_spell_d, general_fup_d, end_study_d, end_control_d | | x | integer | Index of the earliest Estimand 1 date; ties follow input order | Reason follow-up ended | |
| fup_d_est1                | SV_HOSP_RSV_LRTI_d, death_d, end_spell_d, general_fup_d, end_study_d, end_control_d | | x | date | Earliest Estimand 1 end date | Follow-up end date | |
| fup_length_days_est1      | fup_d_est1, T0 | | x | integer | `fup_d_est1 - T0 + 1` | Follow-up duration in days | |
| fup_length_pm_est1        | fup_length_days_est1, config_values/month_length | | x | numeric | `fup_length_days_est1 / month_length` | Follow-up duration in person-months for Estimand 1 | |
| event_est1                | SV_HOSP_RSV_LRTI_d, fup_d_est1 | | x | integer | 1 when the outcome date equals `fup_d_est1`, otherwise 0 | Outcome indicator for Estimand 1 | 0,1 |
| admin_censor_est1          | reason_censoring_est1 | | x | character | 1 -> uncensored; {6,3} -> non-admin; {2,4,5} -> admin | Censoring category for Estimand 1 | uncensored, non-admin, admin |
| reason_censoring_est2     | SV_HOSP_RSV_LRTI_d, death_d, end_spell_d, general_fup_d, end_study_d | | x | integer | Index of the earliest Estimand 2 date; ties follow input order | Reason follow-up ended | |
| fup_d_est2                | SV_HOSP_RSV_LRTI_d, death_d, end_spell_d, general_fup_d, end_study_d | | x | date | Earliest Estimand 2 end date | Follow-up end date | |
| fup_length_days_est2      | fup_d_est2, T0 | | x | integer | `fup_d_est2 - T0 + 1` | Follow-up duration in days | |
| fup_length_pm_est2        | fup_length_days_est2, config_values/month_length | | x | numeric | `fup_length_days_est2 / month_length` | Follow-up duration in person-months for Estimand 2 | |
| event_est2                | SV_HOSP_RSV_LRTI_d, fup_d_est2 | | x | integer | 1 when the outcome date equals `fup_d_est2`, otherwise 0 | Outcome indicator for Estimand 2 | 0,1 |

## Estimand-specific Rules

### Estimand 1

Follow-up ends at earliest of (tie-breaking priority follows the order below):

1. **Outcome event** (`SV_HOSP_RSV_LRTI_d`) → `reason_censoring_est1 = 1`
2. **Death** (`death_d`) → `reason_censoring_est1 = 2`
3. **End of observation** (`end_spell_d`) → `reason_censoring_est1 = 3`
4. **General follow-up limit** (`general_fup_d`, T0 + 180 days) → `reason_censoring_est1 = 4`
5. **End of study** (`end_study_d`) → `reason_censoring_est1 = 5`
6. **Treatment initiation by control** (`end_control_d`) → `reason_censoring_est1 = 6`

For IPCW weighting: use `admin_censor_est1` variable to identify non-administrative censoring events (value = "non-admin").

### Estimand 2

Intercurrent event strategy: **treatment policy** — treatment initiation by the control group does not censor follow-up; controls are followed regardless of whether they receive nirsevimab.

Follow-up ends at earliest of (tie-breaking priority follows the order below):

1. **Outcome event** (`SV_HOSP_RSV_LRTI_d`) → `reason_censoring_est2 = 1`
2. **Death** (`death_d`) → `reason_censoring_est2 = 2`
3. **End of observation** (`end_spell_d`) → `reason_censoring_est2 = 3`
4. **General follow-up limit** (`general_fup_d`, T0 + 180 days) → `reason_censoring_est2 = 4`
5. **End of study** (`end_study_d`) → `reason_censoring_est2 = 5`

`end_control_d` is **not** included as a censoring date for Estimand 2.

## Example

| person_id | T0         | group   | match_id | SV_HOSP_RSV_LRTI_d | death_d | end_spell_d | general_fup_d | end_study_d | end_control_d | reason_censoring_est1 | fup_d_est1 | fup_length_days_est1 | fup_length_pm_est1 | event_est1 | reason_censoring_est2 | fup_d_est2 | fup_length_days_est2 | fup_length_pm_est2 | event_est2 |
| --------- | ---------- | ------- | -------- | ------------------ | ------- | ------------ | ------------- | ----------- | ------------- | --------------------- | ---------- | -------------------- | ------------------ | ---------- | --------------------- | ---------- | -------------------- | ------------------ | ---------- |
| 1         | 2021-01-01 | EXPOSED | 1        | 2021-02-15         |         | 2021-12-31   | 2021-06-30    | 2022-12-31  |               | 1                     | 2021-02-15 | 45                   | 1.50               | TRUE       | 1                     | 2021-02-15 | 45                   | 1.50               | TRUE       |
| 3         | 2021-01-01 | CONTROL | 1        |                    |         | 2021-05-20   | 2021-06-30    | 2022-12-31  | 2021-03-10    | 6                     | 2021-03-10 | 68                   | 2.27               | FALSE      | 3                     | 2021-05-20 | 139                  | 4.63               | FALSE      |
