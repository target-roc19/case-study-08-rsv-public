## Metadata

| Table name | D4_StudyCohort_IPCW_Main |
| --- | --- |
| Description | Time-varying inverse-probability censoring weights combined with IPTW for the IPCW sensitivity analysis. |
| Source | `D4_StudyCohort_TimeVaryingCovariates_Main.RDS`, `D4_PS_Weights_IPTW_Main.RDS`, and PS/IPCW configuration |
| Step | `transformations/T3_study_design/source_code/weight_IPTW_IPCW.R` |
| Content | Person/follow-up interval covariates, censoring probabilities, IPCW, and combined IPTW x IPCW weights |
| Population | Main study cohort with time-varying follow-up records |
| Unit of Observation (UoO) | One person/T0/follow-up interval record |

## Codebook

| variable name | Description | variable(s) needed | retrieved | computed | format | rule_of_calculation | vocabulary |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `person_id` | Person identifier | D4_StudyCohort_TimeVaryingCovariates_Main/person_id | x | | character/integer | Carried from input | |
| `T0` | Time zero | D4_StudyCohort_TimeVaryingCovariates_Main/T0 | x | | Date | Carried from input | YYYY-MM-DD |
| `group` | Exposure group | D4_StudyCohort_TimeVaryingCovariates_Main/group | x | | character | Carried from input | `EXPOSED`, `CONTROL` |
| `match_id` | Matching pair/set identifier | D4_StudyCohort_TimeVaryingCovariates_Main/match_id | x | | integer | Carried from input | |
| `T1` | End of the current follow-up interval | D4_StudyCohort_TimeVaryingCovariates_Main/T1 | x | | Date | Carried from input | YYYY-MM-DD |
| `index_months` | Follow-up month index | D4_StudyCohort_TimeVaryingCovariates_Main/index_months | x | | integer | Carried from time-varying covariates input | 1..6 |
| `followup_day_interval` | Follow-up interval label | D4_StudyCohort_TimeVaryingCovariates_Main/followup_day_interval | x | | character | Carried from time-varying covariates input | Six configured intervals |
| `SV_HC_UTI_CAT_TV` | Categorized time-varying healthcare visits | D4_StudyCohort_TimeVaryingCovariates_Main/SV_HC_UTI_CAT_TV | x | | integer | Carried from time-varying covariates input | 0, 1, 2+ |
| `SV_ANTIBIOTICS_CAT_TV` | Categorized time-varying antibiotic prescriptions | D4_StudyCohort_TimeVaryingCovariates_Main/SV_ANTIBIOTICS_CAT_TV | x | | integer | Carried from time-varying covariates input | 0, 1, 2+ |
| `admin_censor_est1` | Censoring category | D4_StudyCohort_TimeVaryingCovariates_Main/admin_censor_est1 | x | | character | Carried from time-varying covariates input | `uncensored`, `non-admin`, `admin` |
| `fup_end_est1` | Terminal follow-up indicator | D4_StudyCohort_TimeVaryingCovariates_Main/fup_end_est1 | x | | integer | Carried from time-varying covariates input | 0, 1 |
| `y_ipcw_est1` | IPCW censoring outcome | D4_StudyCohort_TimeVaryingCovariates_Main/y_ipcw_est1 | x | | integer | Carried from time-varying covariates input | 0, 1 |
| `prob_censoring` | Estimated probability of censoring | pooled logistic model covariates |  | x | numeric | Predicted censoring probability for the interval | [0, 1] |
| `prob_uncensored` | Estimated probability of remaining uncensored | `prob_censoring` |  | x | numeric | `1 - prob_censoring` | [0, 1] |
| `ipcw_raw` | Raw interval IPCW | `prob_uncensored`, censoring history |  | x | numeric | Inverse probability contribution for the interval | > 0 |
| `ipcw_stabilized` | Stabilized interval IPCW | numerator model, `ipcw_raw` |  | x | numeric | Stabilized IPCW contribution | > 0 |
| `ipcw_trunc` | Truncated interval IPCW | `ipcw_stabilized` and configured bounds |  | x | numeric | Apply configured empirical truncation bounds | > 0 |
| `ipcw_stabilized_cum` | Cumulative stabilized IPCW | `ipcw_stabilized` |  | x | numeric | Cumulative product within person/T0 | > 0 |
| `ipcw_trunc_cum` | Cumulative truncated IPCW | `ipcw_trunc` |  | x | numeric | Cumulative product within person/T0 | > 0 |
| `iptw_ipcw` | Combined weight | D4_PS_Weights_IPTW_Main/stabilized_iptw, ipcw_stabilized_cum | | x | numeric | Stabilized IPTW multiplied by cumulative stabilized IPCW | > 0 |
| `trunc_iptw_ipcw` | Combined truncated weight | D4_PS_Weights_IPTW_Main/stabilized_trunc_iptw, ipcw_trunc_cum | | x | numeric | Truncated stabilized IPTW multiplied by cumulative truncated IPCW | > 0 |

## Processing Steps

IPCW estimation:

1. Load the main time-varying covariates and main IPTW output.
2. Use follow-up intervals, baseline matching variables, and time-varying categorized covariates to fit the pooled logistic censoring model.
3. Estimate the interval probability of censoring and the probability of remaining uncensored.
4. Calculate raw, stabilized, and truncated interval IPCW values using the configured truncation bounds.
5. Accumulate IPCW values within each person/T0 trajectory.
6. Merge the accumulated IPCW with IPTW and write `iptw_ipcw` and `trunc_iptw_ipcw`.
7. Save `D4_PS_Weights_IPCW_Main.RDS` for the sensitivity outcome analysis.

## Example

| person_id | T0 | T1 | followup_day_interval | admin_censor_est1 | y_ipcw_est1 | prob_uncensored | ipcw_trunc_cum | iptw_ipcw | trunc_iptw_ipcw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 2024-10-20 | 2024-11-18 | 0-29 | uncensored | 0 | 0.98 | 1.02 | 1.15 | 1.17 |
| 1 | 2024-10-20 | 2024-12-18 | 30-59 | non-admin | 1 | 0.95 | 1.07 | 1.21 | 1.23 |
