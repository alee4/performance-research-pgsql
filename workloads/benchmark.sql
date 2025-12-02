DROP TABLE IF EXISTS test_table;
CREATE TABLE test_table AS 
    SELECT 
        generate_series(1, 1000000) AS id,
        md5(random()::text) AS data,
        random() * 1000 AS value;

CREATE INDEX idx_test_value ON test_table(value);

SELECT COUNT(*) FROM test_table WHERE value < 500;
SELECT AVG(value) FROM test_table;
SELECT id, data FROM test_table WHERE value BETWEEN 100 AND 200 ORDER BY value LIMIT 100;
