## Metadata

| Table name                | D4_StudyCohort_`<Main/Supplementary>`                                                                                                                                                                                                                                                                             |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Selected study cohort, obtained via matching (outputted by CohortCreator).                                                                                                                                                                                                                                          |
| Source                    | D3_ELIGIBILITY                                                                                                                                                                                                                                                                                                      |
| Step                      | create_cohort.R                                                                                                                                                                                                                                                                                                     |
| Content                   | Main analysis (matching without replacement): eligible exposed can enter the study only once, at their first eligible index date granted that they have not been previously matched as controls; controls are matched by matching variables without replacement. Supplementary analysis: matching with replacement. |
| Population                | Eligible person(-spells)                                                                                                                                                                                                                                                                                            |
| Unit of Observation (UoO) | person(-spell) selected as exposed or control in the study cohort                                                                                                                                                                                                                                                   |

## Codebook

| variable_in_output | variable(s) needed | retrieved | computed | format    | rule_of_calculation | description                                                                                                                                                                                                                           | vocabulary                  |
| ------------------ | ------------------ | --------- | -------- | --------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| person_id          | D3_ELIGIBILITY/person_id | x | | character | Carried from eligible population | person_id of exposed or control following the processing steps | |
| T0                 | D3_ELIGIBILITY/start_episode, end_episode, eligible_exposed, eligible_control | | x | date | Assigned by the matching process; control T0 is capped at end_episode | Time-zero for exposed and matched control | |
| group              | D3_ELIGIBILITY/eligible_exposed, eligible_control | | x | character | Assigned by the matching process | EXPOSED, CONTROL, or UNMATCHED exposed | EXPOSED, CONTROL, UNMATCHED |
| match_id           | D3_ELIGIBILITY/person_id, matching variables | | x | integer | Assigned to the matched pair/set | Matched pair or set identifier | |
| start              | D3_ELIGIBILITY/start_episode | x | | Date | Carried from eligible episode | Start date of the eligible episode | |
| end                | D3_ELIGIBILITY/end_episode | x | | Date | Carried from eligible episode | End date of the eligible episode | |
| SV_AGE_GROUP       | D3_ELIGIBILITY/SV_AGE_GROUP | x | | integer | Matching variable passed to the matching process | Matching variable age group | |
| SV_CALENDAR_WEEK   | D3_ELIGIBILITY/SV_CALENDAR_WEEK | x | | integer | Matching variable passed to the matching process | Matching variable calendar week | 1-53 |

## Processing steps

The script loads `D3_ELIGIBILITY`, adds the alternating `year_birth` field required by CohortBuilder, sets the matching seed, and runs `CohortBuilder::build_study_cohort` for each configured mode. Before saving, control `T0` is capped at `end_episode`.

### Main analysis: `D4_StudyCohort_Main` matching without replacement

Matching without replacement will be implemented using a greedy matching approach (i.e., individuals should only be enrolled once). We will use essentially a matching without replacement algorithm sequentially, whereby first matched pairs are found, then duplicates are removed (keeping units enrolled at earlier T0's) from both the matched pairs. The available pool is then updated, removing the spells from a person that has already been matched. The process of updating the available pools of spells, matching, and pair checking is repeated until no eligible exposed or control remain unmatched in the pool, or not further matches can be found (whatever occurs first).

First, initialize pool of available spells (all eligible exposed and control spells). While exposed spells remain on the available pool, repeat the following steps:

1. Loop over exposed spells ordered by index date T0.
   1.1. From D3_ELIGIBILITY, keep all rows eligible_exposed = TRUE or eligible_control = TRUE.
   1.2. Build exact matching profiles from the matching variables, encoded as groupkey.
   1.3. Define T0 for exposed candidates as their exposed start date.
   1.4. Order exposed candidates by ascending T0, then apply deterministic seeded tie-breaking for reproducibility.
   1.5. For each exposed candidate, find currently available controls with same groupkey, exposed T0 within control eligibility interval (`start` and `end` defined in D3_ELIGIBILITY), different person_id (no self-match).
   1.6 Select one control per exposed candidate using deterministic seeded ranking (reproducible random choice).
   1.7 If a control is found, create one matched set (EXPOSED + CONTROL), assign a unique match_id, and assign exposed T0 to both rows.
   1.8 If no control is found, continue; this exposed spell may become UNMATCHED in final output unless matched in a later round.
2. Resolve within-round conflicts.
   2.1. If multiple exposed candidates select the same control, keep the highest-priority proposal (earliest exposed order). If the exposed order is equal, pick one at random.
   2.2. If a person appears in accepted proposals in both roles (as EXPOSED and CONTROL), keep the earliest-priority proposal and dissolve the others.
   2.3. This guarantees person-level no replacement within the round.
3. Update pools and iterate.
   3.1. Remove all persons accepted in this round from both exposed and control pools.

Build final output labels.

- EXPOSED: exposed spells accepted in matched sets.
- CONTROL: selected controls from matched sets.
- UNMATCHED: exposed spells never accepted as EXPOSED by the end of all rounds.

Tie-breaking rules for repeated selection of the same control unit:

1. Primary priority: earliest exposed T0.
2. Secondary priority: deterministic seeded ordering for ties.

### Supplementary analysis: `D4_StudyCohort_Supplementary` matching with replacement

Controls (unexposed) will be allowed to be matched multiple times (i.e., matching with replacement). While exposed spells can only be matched once, a person may serve as control before being exposed.

Computationally, the following steps are performed:

1. From D3_ELIGIBILITY, select all rows with eligible_exposed == TRUE and all rows with eligible_control == TRUE. Define the exact matching profile as the combination of the matching variables (use a group-key profile factor encoding the specific combination of matching variables). Define group EXPOSED and CONTROL.
2. Among rows with eligible_exposed == TRUE, define T0 as this start date.
3. Order the exposed candidates by ascending T0. When multiple exposed candidates share the same T0 and matching profile, break ties using a fixed random seed so that the matching procedure is reproducible.
4. For each exposed candidate in this order, identify the set of available control rows with eligible_control == TRUE and the same matching profile. From this set, sample one control (with replacement).
5. If a control is found, create one matched set consisting of the exposed person and the sampled control, assign a unique match_id, and assign the exposed person's T0 to both members of the matched set.
6. If no eligible control is available for an exposed candidate, label that exposed candidate as UNMATCHED.
7. Continue to the next exposed candidate.

## Example

Below a matched pair selected from D3_ELIGIBILITY, by matching based on T0 and the covariate SV_AGE_GROUP and SV_CALENDAR_WEEK

| person_id | T0         | group   | match_id | start      | end        | SV_AGE_GROUP | SV_CALENDAR_WEEK |
| --------- | ---------- | ------- | -------- | ---------- | ---------- | ------------ | ---------------- |
| 4         | 2021-01-01 | EXPOSED | 1        | 2021-01-01 | 2021-01-01 | 1            | 2                |
| 3         | 2021-01-01 | CONTROL | 1        | 2020-11-05 | 2021-04-06 | 1            | 2                |
