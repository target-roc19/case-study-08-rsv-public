-- Create the view in connection 'con'
CREATE OR REPLACE VIEW {complex_concept_name} AS
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
        value,
        s.birth_date AS date,
        '{complex_concept_name}' AS concept_id
    FROM (
        SELECT *
        FROM read_parquet(
            ['{input_dir}/**/*.parquet'],
            hive_partitioning = true,
            union_by_name     = true
        )
        WHERE concept_id IN ('{sub_concept_ids}')
    ) AS g
    INNER JOIN spells AS s
        ON g.person_id = s.person_id
) q;

-- Write to output directory
COPY (
    SELECT * FROM {complex_concept_name}
) TO '{output_dir}'
(FORMAT PARQUET, PARTITION_BY (concept_id), APPEND TRUE);
