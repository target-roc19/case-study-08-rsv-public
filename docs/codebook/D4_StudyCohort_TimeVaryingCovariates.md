## Metadata

| Table name                | D4_StudyCohort_TimeVaryingCovariates                                                                                                                            |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Time-varying covariates measured from T0 until end of follow-up for the study cohort. Includes the censoring indicator for the IPCW analysis (Estimand 1 only). |
| Source                    | D4_StudyCohort_FUP_<mode>, D4_StudyCohort_<mode>, D3_CONCEPTS_parquet, `study_variables.csv`, config_values |
| Step                      | `transformations/T3_study_design/source_code/timevarying_covariates.R` |
| Content                   | Longitudinal covariate states over follow-up (Estimand 1)                                                                                                       |
| Population                | Selected study cohort                                                                                                                                           |
| Unit of Observation (UoO) | person-time (interval-based representation)                                                                                                                     |

## Codebook

| variable_in_output    | variable(s) needed        | retrieved | computed | format                 | rule_of_calculation                                                                                                                                                                          | description                                                                                      | vocabulary       |
| --------------------- | ------------------------- | --------- | -------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ---------------- |
| person_id             | D4_StudyCohort_<mode>/person_id | x | | character | Carried from the selected cohort | person_id | |
| T0                    | D4_StudyCohort_<mode>/T0 | x | | date | Carried from the selected cohort | Time zero | |
| group                 | D4_StudyCohort_<mode>/group | x | | character | Carried from the selected cohort | EXPOSED or CONTROL | |
| match_id              | D4_StudyCohort_<mode>/match_id | x | | integer | Carried from the selected cohort | Matched pair or set identifier | |
| index_months          | D4_StudyCohort_FUP/fup_length_pm_est1 | | x | integer (time-varying) | Sequential month index from T0; `fup_months = pmin(6, pmax(0, ceiling(fup_length_pm_est1)))` | Follow-up month index used to encode person-time rows | 1, 2, 3, 4, 5, 6 |
| followup_day_interval | index_months              |           | x        | factor (time-varying)  | Map month index 1..6 to labels: 1 -> 0-29, 2 -> 30-59, 3 -> 60-89, 4 -> 90-119, 5 -> 120-149, 6 -> 150-180                                                                                | Follow-up day-interval label used in IPCW model                                                  | 0-29, 30-59, 60-89, 90-119, 120-149, 150-180 |
| T1                    | D4_StudyCohort_<mode>/T0, index_months, config_values/month_length | | x | date | `T0 + index_months * month_length` | Interval anchor date used to retrieve TV covariates | |
| admin_censor_est1      | D4_StudyCohort_FUP/admin_censor_est1 | x | | character | Carried from follow-up input | Censoring category for Estimand 1 | uncensored, non-admin, admin |
| fup_end_est1           | T1, D4_StudyCohort_FUP/fup_d_est1 | | x | binary (time-varying) | 1 in the interval containing `fup_d_est1`; otherwise 0 | Follow-up end marker for Estimand 1 interval rows | 0, 1 |
| fup_d_est1            | D4_StudyCohort_FUP/fup_d_est1 | x | | date | Carried from follow-up input | Follow-up end date for Estimand 1 | |
| reason_censoring_est1 | D4_StudyCohort_FUP/reason_censoring_est1 | x | | integer | Carried from follow-up input | Censoring reason code for Estimand 1 | |
| fup_length_days_est1  | T1, D4_StudyCohort_<mode>/T0 | | x | integer | `T1 - T0 + 1` for each interval row | Follow-up length in days through the interval | |
| fup_length_pm_est1    | fup_length_days_est1, config_values/month_length | | x | numeric | `fup_length_days_est1 / month_length` | Follow-up length in person-month units through the interval | |
| event_est1            | D4_StudyCohort_FUP/event_est1, fup_end_est1 | | x | binary | 1 only when the input event is 1 and this is the terminal interval | Outcome event indicator for Estimand 1 | 0, 1 |
| SV_HC_UTI_CAT_TV      | D3_CONCEPTS_parquet, study_variables.csv, D4_StudyCohort_<mode>/person_id,T0, index_months | | x | integer (time-varying) | Cumulative anchored visit count categorized as 0, 1, or 2+ | Time-varying categorised number of healthcare visits | 0, 1, 2+ |
| SV_ANTIBIOTICS_CAT_TV | D3_CONCEPTS_parquet, study_variables.csv, D4_StudyCohort_<mode>/person_id,T0, index_months | | x | integer (time-varying) | Cumulative anchored prescription count categorized as 0, 1, or 2+ | Time-varying categorised number of antibiotic prescriptions | 0, 1, 2+ |

## Steps

1. Load inputs:
	`D4_StudyCohortFup_Main`, `D4_StudyCohort_Main`, and TV metadata from `study_variables.csv` where `TV == TRUE`.
2. Build long person-time rows from follow-up length:
	compute `fup_months = pmin(6, pmax(0, ceiling(fup_length_pm_est1)))`, keep `fup_months > 0`, and replicate each person row `fup_months` times.
3. Create time fields:
	compute `index_months = 1..fup_months` by person, map `index_months` to `followup_day_interval`, and compute `T1 = as.Date(T0 + index_months * config_values$month_length)`.
4. Anchor and retrieve TV study variables at `T1`:
	run `anchoR::anchor_by_variable(...)`, retrieve wide results, and merge back to long person-time rows.
5. Compute cumulative TV counts by person from T0 to each T1:
	cumulative sum of anchored `SV_HC_UTI_TV` and `SV_ANTIBIOTICS_TV`, then categorize to `SV_HC_UTI_CAT_TV` and `SV_ANTIBIOTICS_CAT_TV`.
6. Merge `admin_censor_est1`, `fup_d_est1`, `reason_censoring_est1`, and `event_est1` from `D4_StudyCohort_FUP`; compute row-specific follow-up durations from `T0` and `T1`.
7. Compute IPCW dependent variable (implemented in step `weight_IPTW_IPCW`):
	first compute `fup_end_est1` as the follow-up-end interval marker; then define `y_ipcw_est1 = 1` when `fup_end_est1 == 1` and `admin_censor_est1 == "non-admin"`, else `0`.
8. Select and save final output columns as `D4_StudyCohort_TimeVaryingCovariates_Main`.

## Notes

### IPCW model role

- Pooled logistic IPCW uses `y_ipcw_est1` as outcome (non-administrative censoring event indicator).
- `y_ipcw_est1` is derived as `1` when `fup_end_est1 == 1` and `admin_censor_est1 == "non-admin"`, otherwise `0`.
- Model specification:
	`y_ipcw_est1 ~ as.factor(group) + as.factor(followup_day_interval) + baseline_matching_variables + SV_HC_UTI_CAT_TV + SV_ANTIBIOTICS_CAT_TV`
- `baseline_matching_variables` = `SV_AGE_GROUP` + `SV_CALENDAR_WEEK` + `SV_PRIOR_LRTI` + `SV_HC_UTI_CAT` + `SV_ANTIBIOTICS_CAT` + `SV_SEX` + `SV_ADI`.
- IPCW truncation is applied using empirical quantile bounds configured in `ipcw_trunc_bounds` (on interval-specific IPCW before accumulation).
- IPCW is accumulated over intervals within each person as cumulative product of interval-specific IPCW terms (after truncation).

### Time and row structure

- Rows are generated in month units (`index_months`), then labeled with `followup_day_interval` for readability and modeling.
- Time bins are fixed to six intervals: `0-29`, `30-59`, `60-89`, `90-119`, `120-149`, `150-180`.
- Row generation rule: one row per person-month from month 1 up to observed follow-up month (`ceiling(fup_length_pm_est1)`, capped at 6).
- Row counts are expected to differ across individuals.

### Censoring interpretation

- `fup_end_est1` marks the interval where follow-up ends.
- Exactly one row per censored person has `fup_end_est1 = 1` (the censoring month row); earlier rows are `0`.
- IPCW event for modeling is restricted to non-admin censoring through `y_ipcw_est1`.
- See `D4_StudyCohort_FUP` for the detailed coding of censoring reasons.

## Example

### Minimal Worked Example (One Person, Admin Censoring)

Input row in D4_StudyCohort_FUP (single person):

| person_id | T0         | group   | match_id | admin_censor_est1 | fup_d_est1  | reason_censoring_est1 | fup_length_days_est1 | fup_length_pm_est1 | event_est1 |
| --------- | ---------- | ------- | -------- | ----------------- | ----------- | --------------------- | -------------------- | ------------------ | ---------- |
| 101       | 2021-01-01 | EXPOSED | 10       | admin             | 2021-04-03  | 4                     | 93                   | 3.06               | 0          |

How this is transformed in D4_StudyCohort_TimeVaryingCovariates:

1. `fup_months = ceiling(3.06) = 4`, so 4 person-time rows are created.
2. `index_months` is generated as `1, 2, 3, 4`.
3. `followup_day_interval` is mapped from `index_months` as `0-29`, `30-59`, `60-89`, `90-119`.
4. `fup_end_est1 = 1` only in the row where `fup_d_est1` falls in `(lag(T1), T1]` (month 4 in this example); earlier rows are `0`.
5. Because `admin_censor_est1 = admin`, this person contributes `y_ipcw_est1 = 0` in all rows for the non-admin IPCW model outcome.
6. Time-varying covariates (`SV_HC_UTI_CAT_TV`, `SV_ANTIBIOTICS_CAT_TV`) are computed as cumulative counts between `T0` and each row-specific `T1`, then categorized, consistent with the codebook logic above.

Output rows (same person):

| person_id | T0         | group   | match_id | index_months | followup_day_interval | T1         | admin_censor_est1 | fup_end_est1 | fup_d_est1  | reason_censoring_est1 | fup_length_days_est1 | fup_length_pm_est1 | event_est1 | SV_HC_UTI_CAT_TV | SV_ANTIBIOTICS_CAT_TV |
| --------- | ---------- | ------- | -------- | ------------ | --------------------- | ---------- | ----------------- | ------------- | ----------- | --------------------- | -------------------- | ------------------ | ---------- | ---------------- | --------------------- |
| 101       | 2021-01-01 | EXPOSED | 10       | 1            | 0-29                  | 2021-01-31 | admin             | 0             | 2021-04-03  | 4                     | 93                   | 3.06               | 0          | 0                | 0                     |
| 101       | 2021-01-01 | EXPOSED | 10       | 2            | 30-59                 | 2021-03-02 | admin             | 0             | 2021-04-03  | 4                     | 93                   | 3.06               | 0          | 1                | 0                     |
| 101       | 2021-01-01 | EXPOSED | 10       | 3            | 60-89                 | 2021-04-02 | admin             | 0             | 2021-04-03  | 4                     | 93                   | 3.06               | 0          | 1                | 1                     |
| 101       | 2021-01-01 | EXPOSED | 10       | 4            | 90-119                | 2021-05-02 | admin             | 1             | 2021-04-03  | 4                     | 93                   | 3.06               | 0          | 2                | 1                     |
