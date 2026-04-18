/*
============================================================
PROJETO  : DVD Rental Store — Análise de Desempenho Operacional
ARQUIVO  : 03_customer_behavior.sql
OBJETIVO : Análise de comportamento, valor e inadimplência de clientes
PERGUNTA : Quem são os clientes mais valiosos? Com que frequência alugam?
           Há padrão de atraso na devolução que representa risco operacional?
AUTOR    : Anderson Sana
DATA     : 2025-04
BANCO    : MySQL 8.0+
============================================================
*/


-- ============================================================
-- SEÇÃO 1: LTV E FREQUÊNCIA POR CLIENTE
-- Objetivo: Calcular o valor total gerado e o volume de aluguéis
--           por cliente no período — base para a segmentação
-- ============================================================

DROP TEMPORARY TABLE IF EXISTS temp_metricas_cliente;

CREATE TEMPORARY TABLE temp_metricas_cliente AS
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name)              AS nome_cliente,
    c.store_id                                           AS loja_cadastro,
    ROUND(SUM(p.amount), 2)                              AS ltv_total,
    COUNT(DISTINCT r.rental_id)                          AS total_alugueis,
    ROUND(SUM(p.amount) / NULLIF(COUNT(DISTINCT r.rental_id), 0), 2) AS ticket_medio,
    MIN(r.rental_date)                                   AS primeiro_aluguel,
    MAX(r.rental_date)                                   AS ultimo_aluguel,
    DATEDIFF(MAX(r.rental_date), MIN(r.rental_date))     AS dias_como_cliente
FROM customer c
JOIN rental r  ON c.customer_id = r.customer_id
JOIN payment p ON r.rental_id   = p.rental_id
WHERE c.active = 1
GROUP BY c.customer_id, c.first_name, c.last_name, c.store_id;

SELECT * FROM temp_metricas_cliente
ORDER BY ltv_total DESC;

/*
RESULTADO ESPERADO:
  - ~584 linhas (clientes ativos)
  - ltv_total entre ~$20 e ~$200
  - total_alugueis entre 1 e ~45
*/


-- ============================================================
-- SEÇÃO 2: TOP 20 CLIENTES POR LTV
-- ============================================================

SELECT
    nome_cliente,
    loja_cadastro,
    ltv_total,
    total_alugueis,
    ticket_medio,
    dias_como_cliente,
    RANK() OVER (ORDER BY ltv_total DESC)                         AS rank_ltv,
    ROUND(ltv_total * 100.0 / NULLIF(SUM(ltv_total) OVER (), 0), 2) AS participacao_receita_pct
FROM temp_metricas_cliente
ORDER BY ltv_total DESC
LIMIT 20;

/*
RESULTADO ESPERADO:
  - 20 clientes com maior LTV no período
  - Alto ltv + baixo total_alugueis = perfil premium
  - Alto ltv + alto total_alugueis = perfil frequente
*/


-- ============================================================
-- SEÇÃO 3: SEGMENTAÇÃO DE CLIENTES POR QUADRANTE LTV × FREQUÊNCIA
-- Objetivo: Classificar todos os clientes em 4 perfis estratégicos
-- Hipótese: Champions devem representar ~20% dos clientes mas
--           concentrar ~60% da receita
--
-- NOTA MySQL: PERCENTILE_CONT não existe no MySQL.
-- Workaround com ROW_NUMBER() para calcular a mediana.
-- ============================================================

WITH ordered_ltv AS (
    SELECT ltv_total,
           ROW_NUMBER() OVER (ORDER BY ltv_total) AS rn,
           COUNT(*) OVER ()                        AS total_rows
    FROM temp_metricas_cliente
),
ordered_freq AS (
    SELECT total_alugueis,
           ROW_NUMBER() OVER (ORDER BY total_alugueis) AS rn,
           COUNT(*) OVER ()                             AS total_rows
    FROM temp_metricas_cliente
),
medianas AS (
    SELECT
        (SELECT AVG(ltv_total)
         FROM ordered_ltv
         WHERE rn IN (
             FLOOR((total_rows + 1) / 2.0),
             CEIL((total_rows + 1) / 2.0)
         ))                      AS mediana_ltv,
        (SELECT AVG(total_alugueis)
         FROM ordered_freq
         WHERE rn IN (
             FLOOR((total_rows + 1) / 2.0),
             CEIL((total_rows + 1) / 2.0)
         ))                      AS mediana_frequencia
),
clientes_segmentados AS (
    SELECT
        m.*,
        CASE
            WHEN m.ltv_total >= med.mediana_ltv
             AND m.total_alugueis >= med.mediana_frequencia
            THEN 'Champions'
            WHEN m.ltv_total >= med.mediana_ltv
             AND m.total_alugueis < med.mediana_frequencia
            THEN 'High Value'
            WHEN m.ltv_total < med.mediana_ltv
             AND m.total_alugueis >= med.mediana_frequencia
            THEN 'Frequent Low Value'
            ELSE 'At Risk'
        END AS segmento
    FROM temp_metricas_cliente m
    CROSS JOIN medianas med
)

SELECT
    segmento,
    COUNT(*)                                                           AS total_clientes,
    ROUND(COUNT(*) * 100.0 / NULLIF(SUM(COUNT(*)) OVER (), 0), 2)    AS pct_clientes,
    ROUND(SUM(ltv_total), 2)                                          AS receita_total_segmento,
    ROUND(SUM(ltv_total) * 100.0
          / NULLIF(SUM(SUM(ltv_total)) OVER (), 0), 2)                AS pct_receita,
    ROUND(AVG(ltv_total), 2)                                          AS ltv_medio,
    ROUND(AVG(total_alugueis), 1)                                     AS frequencia_media,
    ROUND(AVG(ticket_medio), 2)                                       AS ticket_medio_segmento
FROM clientes_segmentados
GROUP BY segmento
ORDER BY receita_total_segmento DESC;

/*
RESULTADO ESPERADO:
  - 4 linhas, uma por segmento
  - Champions: ~25% dos clientes, ~60% da receita
  - At Risk: ~25% dos clientes, ~5-10% da receita
*/


-- ============================================================
-- SEÇÃO 4: ANÁLISE DE ATRASOS NA DEVOLUÇÃO
-- Objetivo: Calcular a taxa de inadimplência por segmento
-- Hipótese: Taxa geral ~40-50%; Champions podem ter taxa
--           acima da média por alta frequência
-- ============================================================

DROP TEMPORARY TABLE IF EXISTS temp_atrasos_cliente;

CREATE TEMPORARY TABLE temp_atrasos_cliente AS
SELECT
    r.customer_id,
    COUNT(r.rental_id)                                       AS total_alugueis_com_devolucao,
    SUM(CASE
            WHEN DATEDIFF(r.return_date, r.rental_date) > f.rental_duration
            THEN 1 ELSE 0
        END)                                                 AS total_atrasos,
    ROUND(AVG(CASE
                  WHEN DATEDIFF(r.return_date, r.rental_date) > f.rental_duration
                  THEN DATEDIFF(r.return_date, r.rental_date) - f.rental_duration
                  ELSE NULL
              END), 1)                                       AS media_dias_atraso,
    MAX(GREATEST(0,
        DATEDIFF(r.return_date, r.rental_date) - f.rental_duration
    ))                                                       AS max_dias_atraso
FROM rental r
JOIN inventory i ON r.inventory_id = i.inventory_id
JOIN film f      ON i.film_id      = f.film_id
WHERE r.return_date IS NOT NULL
GROUP BY r.customer_id;

-- Taxa de atraso por segmento
WITH ordered_ltv AS (
    SELECT ltv_total,
           ROW_NUMBER() OVER (ORDER BY ltv_total) AS rn,
           COUNT(*) OVER ()                        AS total_rows
    FROM temp_metricas_cliente
),
ordered_freq AS (
    SELECT total_alugueis,
           ROW_NUMBER() OVER (ORDER BY total_alugueis) AS rn,
           COUNT(*) OVER ()                             AS total_rows
    FROM temp_metricas_cliente
),
medianas AS (
    SELECT
        (SELECT AVG(ltv_total)
         FROM ordered_ltv
         WHERE rn IN (FLOOR((total_rows + 1) / 2.0), CEIL((total_rows + 1) / 2.0))) AS mediana_ltv,
        (SELECT AVG(total_alugueis)
         FROM ordered_freq
         WHERE rn IN (FLOOR((total_rows + 1) / 2.0), CEIL((total_rows + 1) / 2.0))) AS mediana_frequencia
),
segmentos AS (
    SELECT
        m.customer_id,
        CASE
            WHEN m.ltv_total >= med.mediana_ltv AND m.total_alugueis >= med.mediana_frequencia THEN 'Champions'
            WHEN m.ltv_total >= med.mediana_ltv AND m.total_alugueis < med.mediana_frequencia  THEN 'High Value'
            WHEN m.ltv_total < med.mediana_ltv  AND m.total_alugueis >= med.mediana_frequencia THEN 'Frequent Low Value'
            ELSE 'At Risk'
        END AS segmento
    FROM temp_metricas_cliente m
    CROSS JOIN medianas med
)

SELECT
    s.segmento,
    COUNT(a.customer_id)                                             AS total_clientes,
    SUM(a.total_atrasos)                                             AS total_atrasos,
    SUM(a.total_alugueis_com_devolucao)                              AS total_alugueis,
    ROUND(SUM(a.total_atrasos) * 100.0
          / NULLIF(SUM(a.total_alugueis_com_devolucao), 0), 2)      AS taxa_atraso_pct,
    ROUND(AVG(a.media_dias_atraso), 1)                               AS media_dias_atraso,
    ROUND(AVG(a.max_dias_atraso), 1)                                 AS media_max_dias_atraso
FROM temp_atrasos_cliente a
JOIN segmentos s ON a.customer_id = s.customer_id
GROUP BY s.segmento
ORDER BY taxa_atraso_pct DESC;

/*
RESULTADO ESPERADO:
  - Champions com taxa acima ou igual à média geral
  - media_dias_atraso baixa (1-3 dias) em todos os segmentos
*/


-- ============================================================
-- SEÇÃO 5: DISTRIBUIÇÃO DE ATRASOS EM FAIXAS
-- ============================================================

SELECT
    CASE
        WHEN DATEDIFF(r.return_date, r.rental_date) <= f.rental_duration
        THEN '00 — No prazo'
        WHEN DATEDIFF(r.return_date, r.rental_date) - f.rental_duration BETWEEN 1 AND 2
        THEN '01-02 dias de atraso'
        WHEN DATEDIFF(r.return_date, r.rental_date) - f.rental_duration BETWEEN 3 AND 7
        THEN '03-07 dias de atraso'
        WHEN DATEDIFF(r.return_date, r.rental_date) - f.rental_duration BETWEEN 8 AND 14
        THEN '08-14 dias de atraso'
        ELSE '15+ dias de atraso'
    END                                         AS faixa_atraso,
    COUNT(*)                                    AS total_alugueis,
    ROUND(COUNT(*) * 100.0
          / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS pct_total
FROM rental r
JOIN inventory i ON r.inventory_id = i.inventory_id
JOIN film f      ON i.film_id      = f.film_id
WHERE r.return_date IS NOT NULL
GROUP BY faixa_atraso
ORDER BY faixa_atraso;

/*
RESULTADO ESPERADO:
  - "No prazo": ~55% dos aluguéis
  - "01-02 dias": maior faixa de atraso (~25-30%)
  - "15+ dias": < 5% do total
*/
