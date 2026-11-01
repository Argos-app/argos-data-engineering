CREATE VIEW vw_bi_aplicacoes_propriedade AS
WITH aplicacoes_base AS (
    SELECT property_key, date_key, head_count_applied
    FROM fact_application
)
SELECT property_key,
       date_key,
       COUNT(*) AS total_aplicacoes,
       SUM(head_count_applied) AS total_cabecas_aplicadas
FROM aplicacoes_base
GROUP BY property_key, date_key;
