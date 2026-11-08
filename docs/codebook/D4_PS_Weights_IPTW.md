## Metadata

| Table name                | D4_StudyCohort_IPTW_`<Main/Supplement>`  |
| ------------------------- | ---------------------------------------------------------------------- |
| Description               | Dataset consisting of propensity scores and IP weights for the study cohort  |
| Source                    | `D4_StudyCohortCovariates_<mode>.RDS`; PS model metadata |
| Step                      | `transformations/T3_study_design/source_code/weight_IPTW_IPCW.R` and `functions/fn_weight_IPTW.R` |
| Content                   | Propensity scores and IP weights                                       |
| Population                | Selected study cohort (exposed and control units)                      |
| Unit of Observation (UoO) | One row per person/T0 in the study cohort |

## Codebook

| variable name          | Description                                                                                                                       | variable(s) needed                   | retrieved | computed | format    | rule_of_calculation                                                                                                                | vocabulary       |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | --------- | -------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| person_id              | | D4_StudyCohort_Covariates_<mode>/person_id | x | | character | Carried from covariates input | | |
| match_id               | Matching pair or set identifier | D4_StudyCohort_Covariates_<mode>/match_id | x | | integer | Carried from covariates input | |
| T0                     | | D4_StudyCohort_Covariates_<mode>/T0 | x | | date | Carried from covariates input | | |
| group                  | Group identifier: EXPOSED and CONTROL | D4_StudyCohort_Covariates_<mode>/group | x | | character | Carried from covariates input | EXPOSED, CONTROL |
| group_binary           | Binary version of group (exposed = 1, control = 0) | D4_StudyCohort_Covariates_<mode>/group | | x | integer | 1 when group is EXPOSED, otherwise 0 | 0, 1 |
| p_score                | Predicted probability of exposure from the final PS model | D4_StudyCohort_Covariates_<mode> baseline variables, configured PS-model metadata | | x | numeric | Predicted probability from the final model | [0, 1] |
| include_after_trimming | Indicator whether included in the weighted analysis | p_score, configured `iptw_trunc_bounds` | | x | logical | TRUE when score is non-missing and within configured bounds; without bounds, TRUE when non-missing | TRUE, FALSE |
| raw_iptw               | Inverse probability of treatment weight | p_score, group_binary | | x | numeric | `1 / p_score` for exposed; `1 / (1 - p_score)` for control | > 0 |
| stabilized_iptw        | Stabilized inverse probability weight | raw_iptw, group_binary, include_after_trimming | | x | numeric | Multiply raw weight by marginal probability of the received group among retained rows | > 0 |
| stabilized_trunc_iptw  | Truncated stabilized IPTW | stabilized_iptw, configured IPTW truncation bounds | | x | numeric | Truncate within group at configured quantile bounds | > 0 |

## Processing Steps

IPTW estimation:

1. Extract predicted probabilities of exposed group membership from the model
2. If trimming of propensity score required, input lower and upper bound of propensity score values (provided by metadata/global parameter). If supplied, select only units who have `p_score` within the trimming bounds, record in `include_after_trimming` who meets these criteria
3. Compute raw IPT weights from `p_score` for individuals with `include_after_trimming == TRUE`. IPTW-ATE weights given by `A*(1/p_score) + (1-A)*(1/1-p_score)`.
4. Compute stabilized IPT weights using the marginal probability of the treatment actually received, by `A*(sum(A == 1)/N) * iptw_raw + (1-A)*(sum(A == 0)/N)*iptw_raw`, where `N` is the number of individuals with `include_after_trimming == TRUE`
5. Calculate truncated stabilized IPT weights; compute 1st and 99th percentile; all values lower than 1st percentile get set to 1st percentile, all values higher than 99th percentile get set to 99th percentile.

## Example

| person_id | match_id | T0         | group   | group_binary | p_score | include_after_trimming | raw_iptw | stabilized_iptw | stabilized_trunc_iptw |
| --------- | -------- | ---------- | ------- | ------------ | ------- | ---------------------- | -------- | --------------- | --------------------- |
| 1         | NA       | 2024-10-20 | CONTROL | 0            | 0.42    | TRUE                   | 1.72     | 1.03            | 1.03                  |
| 2         | NA       | 2024-10-20 | EXPOSED | 1            | 0.78    | TRUE                   | 1.28     | 0.51            | 0.51                  |
| 5         | NA       | 2024-10-20 | CONTROL | 0            | 0.31    | TRUE                   | 1.45     | 0.87            | 0.87                  |
