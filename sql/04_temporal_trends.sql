/*
============================================================
PROJETO  : DVD Rental Store — Análise de Desempenho Operacional
ARQUIVO  : 04_temporal_trends.sql
OBJETIVO : Análise da evolução temporal de receita e volume de aluguéis
PERGUNTA : Como a receita evoluiu ao longo do período?
           Há meses com queda ou pico relevante que exijam explicação?
AUTOR    : Anderson Sana
DATA     : 2025-04
BANCO    : MySQL 8.0+
============================================================
*/


-- ============================================================
-- SEÇÃO 1: RECEITA E VOLUME MENSAL
-- Objetivo: Construir a série temporal base de receita e aluguéis
-- Hipótese: Crescimento progressivo de mai a jul 2005;
--           ago pode mostrar queda (fim de temporada)
-- ============================================================

WITH receita_mensal AS (
    SELECT
        DATE_FORMAT(p.payment_date, '%Y-%m-01')  AS mes,
        COUNT(DISTINCT p.payment_id)             AS total_pagamentos,
        COUNT(DISTINCT p.rental_id)              AS total_alugueis_pagos,
        ROUND(SUM(p.amount), 2)                  AS receita_total,
        ROUND(AVG(p.amount), 2)                  AS ticket_medio,
        COUNT(DISTINCT p.customer_id)            AS clientes_ativos_no_mes
    FROM payment p
    WHERE p.rental_id IS NOT NULL
    GROUP BY DATE_FORMAT(p.payment_date, '%Y-%m-01')
)

SELECT
    mes,
    total_pagamentos,
    total_alugueis_pagos,
    receita_total,
    ticket_medio,
    clientes_ativos_no_mes,
    receita_total - LAG(receita_total) OVER (ORDER BY mes)       AS variacao_absoluta_mom,
    ROUND(
        (receita_total - LAG(receita_total) OVER (ORDER BY mes))
        * 100.0 / NULLIF(LAG(receita_total) OVER (ORDER BY mes), 0),
    2)                                                           AS crescimento_mom_pct,
    SUM(receita_total) OVER (
        ORDER BY mes
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                            AS receita_acumulada
FROM receita_mensal
ORDER BY mes;

/*
RESULTADO ESPERADO:
  - 5 linhas (mai, jun, jul, ago 2005 + fev 2006)
  - crescimento_mom_pct do primeiro mês será NULL
  - O salto ago/2005 → fev/2006 terá variação distorcida — documentar como limitação
*/


-- ============================================================
-- SEÇÃO 2: VOLUME DIÁRIO DE ALUGUÉIS — IDENTIFICAÇÃO DE PICOS
-- Objetivo: Detectar dias com volume anormalmente alto ou baixo
-- Hipótese: Fins de semana devem ter volume maior que dias úteis
-- ============================================================

WITH volume_diario AS (
    SELECT
        DATE(r.rental_date)              AS dia,
        DAYNAME(r.rental_date)           AS dia_semana,
        DAYOFWEEK(r.rental_date)         AS num_dia_semana, -- 1=Dom, 7=Sáb
        COUNT(r.rental_id)               AS total_alugueis
    FROM rental r
    GROUP BY DATE(r.rental_date), DAYNAME(r.rental_date), DAYOFWEEK(r.rental_date)
),
stats AS (
    SELECT
        AVG(total_alugueis)    AS media_diaria,
        STDDEV(total_alugueis) AS desvio_padrao
    FROM volume_diario
)

SELECT
    v.dia,
    v.dia_semana,
    v.total_alugueis,
    ROUND(s.media_diaria, 1)   AS media_geral_diaria,
    CASE
        WHEN v.total_alugueis > s.media_diaria + 2 * s.desvio_padrao THEN 'Pico'
        WHEN v.total_alugueis < s.media_diaria - 2 * s.desvio_padrao THEN 'Vale'
        ELSE 'Normal'
    END                        AS classificacao_volume,
    ROUND(
        (v.total_alugueis - s.media_diaria) / NULLIF(s.desvio_padrao, 0),
    2)                         AS desvios_da_media
FROM volume_diario v
CROSS JOIN stats s
ORDER BY v.dia;

/*
RESULTADO ESPERADO:
  - Uma linha por dia no período
  - 'Pico' deve ser raro (< 5% dos dias)
  - Fins de semana (num_dia_semana = 1 ou 7) devem ter maior total_alugueis
*/


-- ============================================================
-- SEÇÃO 3: DESEMPENHO POR DIA DA SEMANA
-- Objetivo: Identificar padrão semanal de demanda para orientar
--           decisões de estoque e escala de atendimento
-- NOTA MySQL: DAYOFWEEK() retorna 1=Domingo, 7=Sábado
-- ============================================================

SELECT
    CASE DAYOFWEEK(r.rental_date)
        WHEN 1 THEN '1 - Domingo'
        WHEN 2 THEN '2 - Segunda'
        WHEN 3 THEN '3 - Terça'
        WHEN 4 THEN '4 - Quarta'
        WHEN 5 THEN '5 - Quinta'
        WHEN 6 THEN '6 - Sexta'
        WHEN 7 THEN '7 - Sábado'
    END                                         AS dia_semana,
    COUNT(r.rental_id)                          AS total_alugueis,
    ROUND(AVG(p.amount), 2)                     AS ticket_medio,
    ROUND(COUNT(r.rental_id) * 100.0
          / NULLIF(SUM(COUNT(r.rental_id)) OVER (), 0), 2) AS pct_do_total
FROM rental r
JOIN payment p ON r.rental_id = p.rental_id
GROUP BY DAYOFWEEK(r.rental_date)
ORDER BY DAYOFWEEK(r.rental_date);

/*
RESULTADO ESPERADO:
  - 7 linhas, uma por dia da semana
  - Fins de semana devem ter pct_do_total acima de 14.3% (1/7)
*/


-- ============================================================
-- SEÇÃO 4: RECEITA POR CATEGORIA AO LONGO DO TEMPO
-- Objetivo: Verificar se a liderança de categorias é estável
--           ou se há alternância ao longo dos meses
-- ============================================================

SELECT
    DATE_FORMAT(p.payment_date, '%Y-%m-01')     AS mes,
    cat.name                                    AS categoria,
    COUNT(DISTINCT r.rental_id)                 AS total_alugueis,
    ROUND(SUM(p.amount), 2)                     AS receita_total,
    RANK() OVER (
        PARTITION BY DATE_FORMAT(p.payment_date, '%Y-%m-01')
        ORDER BY SUM(p.amount) DESC
    )                                           AS rank_no_mes
FROM payment p
JOIN rental r         ON p.rental_id    = r.rental_id
JOIN inventory i      ON r.inventory_id = i.inventory_id
JOIN film f           ON i.film_id      = f.film_id
JOIN film_category fc ON f.film_id      = fc.film_id
JOIN category cat     ON fc.category_id = cat.category_id
WHERE p.rental_id IS NOT NULL
GROUP BY DATE_FORMAT(p.payment_date, '%Y-%m-01'), cat.name
ORDER BY mes, rank_no_mes;

/*
RESULTADO ESPERADO:
  - Até 80 linhas (16 categorias × 5 meses)
  - rank_no_mes = 1 indica a categoria líder naquele mês
  - Mesmas categorias no topo todos os meses = liderança estável
*/


-- ============================================================
-- SEÇÃO 5: TICKET MÉDIO POR MÊS E TENDÊNCIA
-- ============================================================

WITH ticket_mensal AS (
    SELECT
        DATE_FORMAT(p.payment_date, '%Y-%m-01')  AS mes,
        ROUND(AVG(p.amount), 4)                  AS ticket_medio
    FROM payment p
    WHERE p.rental_id IS NOT NULL
    GROUP BY DATE_FORMAT(p.payment_date, '%Y-%m-01')
)

SELECT
    mes,
    ticket_medio,
    ticket_medio - LAG(ticket_medio) OVER (ORDER BY mes)        AS variacao_ticket_absoluta,
    ROUND(
        (ticket_medio - LAG(ticket_medio) OVER (ORDER BY mes))
        * 100.0 / NULLIF(LAG(ticket_medio) OVER (ORDER BY mes), 0),
    2)                                                          AS variacao_ticket_pct
FROM ticket_mensal
ORDER BY mes;

/*
RESULTADO ESPERADO:
  - 5 linhas (uma por mês)
  - ticket_medio deve variar pouco entre meses (~$3-5)
  - Variação > 10% entre meses indica mudança no mix de categorias alugadas
*/
