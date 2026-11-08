## Metadata

| Table name | D5_CohortAnalyticLookup |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description | Incidence and risk-ratio estimates from CohortAnalytics across five predefined analyses |
| Primary step | transformations/T4_statistical_analysis/source_code/outcome_analysis_lookup.R |
| Core functions | transformations/T4_statistical_analysis/source_code/functions/cohort_analytic_lookup_functions.R |
| Analysis metadata | transformations/T4_statistical_analysis/table_metadata/outcome_analysis_types.csv |
| Output folder | data/D5_results |
| Output file pattern | <DEAP>_D5_CohortAnalyticLookup.csv |
| Unit of observation | One AESI estimate row for one analysis after pooling/subsetting rules |

## Analysis Definition (Current Metadata)

The script executes one list element per row in outcome_analysis_types.csv (analysis_index 1..5). Splitting and pooling are metadata-driven.

| analysis_index | analysis_type | estimand | source_fup | source_weight | listed_by | pooling_method | pooling_condition | runtime behavior |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | main | 1 | D4_StudyCohortFup_MI_Main | D4_PS_Weights_IPTW_Main | imputation_id | rubin | (empty) | Split by imputation_id, run CohortAnalytics per split, then Rubin pool |
| 2 | main | 2 | D4_StudyCohortFup_Main | D4_PS_Weights_IPTW_Main | (empty) | NA | (empty) | Single run, no split/pooling |
| 3 | sensitivity | 1 | D4_StudyCohortFup_Main | D4_PS_Weights_IPCW_Main | (empty) | NA | (empty) | Single run, no split/pooling |
| 4 | sensitivity | 1 | D4_StudyCohortFup_BW_Main | (empty) | bw_id | subset | bw_id %in% 1:4 | Split by bw_id, run per split, keep rows matching pooling_condition |
| 5 | supplement | 1 | D4_StudyCohortFup_MI_Supplement | D4_PS_Weights_IPTW_Supplement | imputation_id | rubin | (empty) | Split by imputation_id, run CohortAnalytics per split, then Rubin pool |

## Processing Logic

1. Load enabled analysis rows from outcome_analysis_types.csv.
2. Load all required follow-up and weight datasets referenced by metadata.
3. For each analysis row:
	- reshape follow-up columns to fup, pm, eventCount for the selected estimand,
	- merge weights when source_weight/weight_col are provided,
	- split by listed_by when listed_by is non-empty,
	- run CohortAnalytics::compute_rates_cohort per split.
4. Apply pooling_method per analysis row:
	- rubin: pool estimate/CI triplets with mice::pool.scalar,
	- subset: filter rows using pooling_condition expression,
	- NA/empty: keep rows as produced.
5. Concatenate pooled list elements to D5_CohortAnalyticLookup.
6. Keep split-tracking columns imputation_id and bw_id in the saved D5 output for traceability.

## Codebook

Analysis-specific follow-up files resolve from `outcome_analysis_types.csv` (`source_fup`) and are loaded from the configured D4 directory. When `source_weight` is set, the corresponding D4 weight file and `weight_col` are also used.

| variable_in_output | variable(s) needed | retrieved | computed | format | rule_of_calculation | description | vocabulary |
| --- | --- | --- | --- | --- | --- | --- | --- |
| aesi | configured `aesi_name` | x | | character | Passed to CohortAnalytics as `target_aesi` | AESI name used in the model | SV_HOSP_RSV_LRTI |
| n_pat_exp | `D4_analytic_datasets/<source_fup>.<ext>`/person_id,group; `outcome_analysis_types.csv` | | x | numeric | CohortAnalytics incidence output | Number of exposed individuals | |
| n_out_exp | `D4_analytic_datasets/<source_fup>.<ext>`/event_est<estimand>,group; `outcome_analysis_types.csv` | | x | numeric | CohortAnalytics incidence output | Number of exposed events | |
| py_exp | `D4_analytic_datasets/<source_fup>.<ext>`/fup_length_pm_est<estimand>,group; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics incidence output | Exposed person-time (pm scale in this study) | |
| ir_est_exp | `D4_analytic_datasets/<source_fup>.<ext>`; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics incidence output | Exposed incidence estimate | |
| ir_lb_exp | `D4_analytic_datasets/<source_fup>.<ext>`; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics incidence output | Exposed incidence lower CI | |
| ir_ub_exp | `D4_analytic_datasets/<source_fup>.<ext>`; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics incidence output | Exposed incidence upper CI | |
| n_pat_con | `D4_analytic_datasets/<source_fup>.<ext>`/person_id,group; `outcome_analysis_types.csv` | | x | numeric | CohortAnalytics incidence output | Number of control individuals | |
| n_out_con | `D4_analytic_datasets/<source_fup>.<ext>`/event_est<estimand>,group; `outcome_analysis_types.csv` | | x | numeric | CohortAnalytics incidence output | Number of control events | |
| py_con | `D4_analytic_datasets/<source_fup>.<ext>`/fup_length_pm_est<estimand>,group; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics incidence output | Control person-time (pm scale in this study) | |
| ir_est_con | `D4_analytic_datasets/<source_fup>.<ext>`; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics incidence output | Control incidence estimate | |
| ir_lb_con | `D4_analytic_datasets/<source_fup>.<ext>`; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics incidence output | Control incidence lower CI | |
| ir_ub_con | `D4_analytic_datasets/<source_fup>.<ext>`; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics incidence output | Control incidence upper CI | |
| rr_est_crude | `D4_analytic_datasets/<source_fup>.<ext>`; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics log-binomial output | Crude risk ratio estimate | |
| rr_lb_crude | `D4_analytic_datasets/<source_fup>.<ext>`; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics log-binomial output | Crude risk ratio lower CI | |
| rr_ub_crude | `D4_analytic_datasets/<source_fup>.<ext>`; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics log-binomial output | Crude risk ratio upper CI | |
| rr_est_adj | `D4_analytic_datasets/<source_fup>.<ext>`; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics log-binomial output | Adjusted risk ratio estimate | |
| rr_lb_adj | `D4_analytic_datasets/<source_fup>.<ext>`; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics log-binomial output | Adjusted risk ratio lower CI | |
| rr_ub_adj | `D4_analytic_datasets/<source_fup>.<ext>`; optional `<source_weight>.<ext>`/weight_col | | x | numeric | CohortAnalytics log-binomial output | Adjusted risk ratio upper CI | |
| rr_type | `CohortAnalytics::compute_rates_cohort` output | x | | character | CohortAnalytics output field | RR model type | logbinomial |
| imputation_id | `D4_analytic_datasets/<source_fup>.<ext>`/imputation_id, `outcome_analysis_types.csv`/listed_by | x | | integer | Carried through split; cleared after Rubin pooling | Imputation identifier; NA after pooling or for non-MI analyses | 1..m or NA |
| bw_id | `D4_analytic_datasets/<source_fup>.<ext>`/bw_id, `outcome_analysis_types.csv`/listed_by | x | | integer | Carried through split and subset pooling | Best/worst scenario identifier | 1..4 |
| bw_scenario | `D4_analytic_datasets/<source_fup>.<ext>`/bw_scenario | x | | character | Carried through the BW analysis | Best/worst scenario code; NA for non-BW rows | bb, bw, wb, ww |

## Weighting Rules

- Analyses 1, 2, 5: IPTW from D4_PS_Weights_IPTW_<mode> via weight_col in metadata.
- Analysis 3: IPCW-combined weight from D4_PS_Weights_IPCW_Main using iptw_ipcw.
- Analysis 4: no external weight file; ip_weight defaults to 1.0.

## NA Codes

| Code | Meaning |
| --- | --- |
| -99 | Missing variables or no eligible cases |
| -88 | Model non-convergence |
| -77 | Non-reportable (for example insufficient events) |
| -66 | Masked value |

## Notes

- Splitting and pooling behavior is fully controlled by outcome_analysis_types.csv.
- Changing pooling_condition for subset analyses changes which scenario rows are retained in final D5 output.
- Table outputs (Table12/Table13/Table15) are derived downstream from this D5 workflow.

## Minimal Example

| aesi | n_pat_exp | n_out_exp | py_exp | ir_est_exp | ir_lb_exp | ir_ub_exp | n_pat_con | n_out_con | py_con | ir_est_con | ir_lb_con | ir_ub_con | end_risk | time | cuminc_est_exp_crude | cuminc_lb_exp_crude | cuminc_ub_exp_crude | cuminc_est_con_crude | cuminc_lb_con_crude | cuminc_ub_con_crude | cuminc_est_exp_adj | cuminc_lb_exp_adj | cuminc_ub_exp_adj | cuminc_est_con_adj | cuminc_lb_con_adj | cuminc_ub_con_adj | rr_est_crude | rr_lb_crude | rr_ub_crude | rr_est_adj | rr_lb_adj | rr_ub_adj | rd_est_crude | rd_lb_crude | rd_ub_crude | rd_est_adj | rd_lb_adj | rd_ub_adj | rr_type | rd_type | imputation_id | bw_id |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| "SV_HOSP_RSV_LRTI" | 335 | 47 | 1991.95137976347 | 2359.49534097468 | 1753.88605961116 | 3174.21889157126 | 335 | 86.08 | 1991.95137976347 | 4306.15746119852 | 3359.0337503084 | 5520.33514963438 | "NULL" | -99 | -99 | -99 | -99 | -99 | -99 | -99 | -99 | -99 | -99 | -99 | -99 | -99 | 0.547935221189825 | 0.381120979938247 | 0.78776300026566 | 0.605290429630798 | 0.419990036930397 | 0.872345703437137 | -88 | -88 | -88 | -88 | -88 | -88 | "logbinomial" | "logbinomial" | NA | NA |
| "SV_HOSP_RSV_LRTI" | 335 | 47 | 1098.22601839685 | 4279.62907568053 | 3144.51047312438 | 5690.99942030899 | 335 | 54 | 1076.97109067017 | 5014.06216636672 | 3848.33753088263 | 6532.90393746308 | "NULL" | -99 | -99 | -99 | -99 | -99 | -99 | -99 | -99 | -99 | -99 | -99 | -99 | -99 | 0.870370370371719 | 0.606952874546707 | 1.24811103693473 | 0.943656205647655 | 0.658456964339561 | 1.35238456373606 | -88 | -88 | -88 | -88 | -88 | -88 | "logbinomial" | "logbinomial" | NA | NA |
