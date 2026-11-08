-- Gestational age in range AND > 6 months old at RSV season start
--
-- Extends gest_age_condition.sql with a D3_SPELLS join to add the age-at-
-- season-start check. TRUE when GEST_AGE {gest_condition} AND the person is
-- older than {age_6m_days} days at the start of the RSV season, FALSE otherwise.
-- The date column is the GEST_AGE event date.
-- Reads from the DuckDB VIEW created in R (named after {complex_concept_name}).
--
-- Parameters (substituted via picard::load_sql_query in R):
--   {complex_concept_name} – name of the VIEW and output concept (partition value)
--   {d3_spells_path}       – path to D3_SPELLS.parquet
--   {gest_condition}       – SQL condition on TRY_CAST(value AS DOUBLE),
--                            e.g. "BETWEEN 29 * 7 AND 35 * 7"
--   {start_rsv_season}     – RSV season start date as YYYY-MM-DD string
--   {age_6m_days}          – integer: floor(6 * month_length)
--   {output_dir}           – path to output D3_CONCEPTS_parquet directory

COPY (
    WITH spells AS (
        SELECT DISTINCT
            person_id,
            birth_date
        FROM read_parquet('{d3_spells_path}')
        WHERE birth_date IS NOT NULL
    )
    SELECT *
    FROM (
        SELECT
            g.ori_table,
            g.unique_id,
            g.person_id,
            g.code,
            g.coding_system,
            (TRY_CAST(g.value AS DOUBLE) {gest_condition}
                AND s.birth_date + {age_6m_days} * INTERVAL '1 day' < DATE '{start_rsv_season}')
                                                            AS value,
            s.birth_date AS date,
            '{complex_concept_name}'                         AS concept_id
        FROM {complex_concept_name} AS g
    INNER JOIN spells AS s
        ON g.person_id = s.person_id
    ) q
    WHERE value IS TRUE
) TO '{output_dir}'
(FORMAT PARQUET, PARTITION_BY (concept_id), APPEND TRUE);
