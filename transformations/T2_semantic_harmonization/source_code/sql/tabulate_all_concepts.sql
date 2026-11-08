SELECT
    concept_id,
    COUNT(DISTINCT person_id) AS n_unique_person_id
FROM read_parquet(
    '{input_dir}/**/*.parquet',
    hive_partitioning = true
)
GROUP BY concept_id
