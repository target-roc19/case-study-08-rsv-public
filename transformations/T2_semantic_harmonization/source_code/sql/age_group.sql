-- Age group concept
--
-- Generates three boundary rows per person from D3_SPELLS using birth_date:
--   value = 1 dated at birth_date (≤ 3.0 months)
--   value = 2 dated at birth_date + {age_3m_days} + 1 days (>3.0–≤6.0 months)
--   value = 3 dated at birth_date + {age_6m_days} + 1 days (>6.0 months)
-- A LATEST extraction at t0 returns the integer category (1,2,3).
--
-- Parameters (substituted via picard::load_sql_query in R):
--   {d3_spells_path}       – path to D3_SPELLS.parquet
--   {age_3m_days}          – integer: floor(3 * month_length)
--   {age_6m_days}          – integer: floor(6 * month_length)
--   {output_dir}           – path to output D3_CONCEPTS_parquet directory
--   {complex_concept_name} – name of the output concept (partition value)

CREATE OR REPLACE VIEW {complex_concept_name} AS
    SELECT
        'D3_SPELLS'                                              AS ori_table,
        NULL                                                     AS unique_id,
        person_id,
        NULL                                                     AS code,
        NULL                                                     AS coding_system,
        1                                                        AS value,
        birth_date                                               AS date,
        '{complex_concept_name}'                                 AS concept_id
    FROM read_parquet('{d3_spells_path}')
    WHERE birth_date IS NOT NULL

    UNION ALL

    SELECT
        'D3_SPELLS'                                              AS ori_table,
        NULL                                                     AS unique_id,
        person_id,
        NULL                                                     AS code,
        NULL                                                     AS coding_system,
        2                                                        AS value,
        birth_date + ({age_3m_days} + 1) * INTERVAL '1 day'      AS date,
        '{complex_concept_name}'                                 AS concept_id
    FROM read_parquet('{d3_spells_path}')
    WHERE birth_date IS NOT NULL

    UNION ALL

    SELECT
        'D3_SPELLS'                                              AS ori_table,
        NULL                                                     AS unique_id,
        person_id,
        NULL                                                     AS code,
        NULL                                                     AS coding_system,
        3                                                        AS value,
        birth_date + ({age_6m_days} + 1) * INTERVAL '1 day'      AS date,
        '{complex_concept_name}'                                 AS concept_id
    FROM read_parquet('{d3_spells_path}')
    WHERE birth_date IS NOT NULL;

COPY (
    SELECT * FROM {complex_concept_name}
) TO '{output_dir}'
(FORMAT PARQUET, PARTITION_BY (concept_id), APPEND TRUE);
