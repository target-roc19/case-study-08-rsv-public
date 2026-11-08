-- Direct translation of dates present in sub-concepts to calendar-week values
SELECT
    person_id,
    ori_table,
    unique_id,
    '{complex_concept_name}' AS concept_id,
    coding_system,
    code,
    date,
    'W' || week(date) || '_' || year(date) AS value
FROM
    "{complex_concept_name}"

UNION ALL

-- Weekly series starting at birth_date and repeating every 7 days until end_study_date
-- Uses a small bounded series (0..500 weeks) and filters by end date to avoid infinite expansion
SELECT
    s.person_id,
    'D3_SPELLS' AS ori_table,
    NULL AS unique_id,
    '{complex_concept_name}' AS concept_id,
    NULL AS coding_system,
    NULL AS code,
    s.birth_date + (g.value * INTERVAL '7 day') AS date,
    'W' || week(s.birth_date + (g.value * INTERVAL '7 day')) || '_' || year(s.birth_date + (g.value * INTERVAL '7 day')) AS value
FROM
    read_parquet('{d3_spells_path}') AS s,
    generate_series(0, 500) AS g(value)
WHERE
    s.birth_date IS NOT NULL
    AND s.birth_date + (g.value * INTERVAL '7 day') <= DATE '{end_study_date}'
