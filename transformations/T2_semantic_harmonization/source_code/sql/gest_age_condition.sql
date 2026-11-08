-- Gestational age condition
--
-- Reads from the DuckDB VIEW created in R (named after {complex_concept_name}).
-- The resulting 'value' column is a BOOLEAN evaluated via {condition}.
-- 'date' is taken from D3_SPELLS/birth_date
--
-- Parameters (substituted via picard::load_sql_query in R):
--   {complex_concept_name} – name of the VIEW and output concept (partition value)
--   {output_dir}           – path to output D3_CONCEPTS_parquet directory
--   {condition}            – SQL condition on TRY_CAST(value AS DOUBLE),
--                            e.g. ">= 29" or "BETWEEN 29 AND 35"

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
            ori_table,
            unique_id,
            g.person_id,
            code,
            coding_system,
            TRY_CAST(value AS DOUBLE) {condition} AS value,
            s.birth_date AS date,
            '{complex_concept_name}'                 AS concept_id
        FROM {complex_concept_name} AS g
        INNER JOIN spells AS s
            ON g.person_id = s.person_id
    ) q
    WHERE value IS TRUE
) TO '{output_dir}'
(FORMAT PARQUET, PARTITION_BY (concept_id), APPEND TRUE);
