/*
============================================================
PROJETO  : DVD Rental Store — Análise de Desempenho Operacional
ARQUIVO  : 06_summary_views.sql
OBJETIVO : Criar views consolidadas com os principais resultados
           de cada área de análise do projeto
PERGUNTA : Como entregar os resultados analíticos de forma reutilizável
           e consultável sem reexecutar as queries completas?
AUTOR    : Anderson Sana
DATA     : 2025-04
============================================================

CONTEXTO:
  Este arquivo cria views permanentes que consolidam os principais
  resultados do projeto. As views servem como entregáveis finais —
  qualquer stakeholder pode consultá-las diretamente sem conhecer
  a estrutura das queries originais.

  Cada view é precedida de DROP VIEW IF EXISTS para garantir
  que o arquivo possa ser reexecutado sem erros.

  ORDEM DE EXECUÇÃO OBRIGATÓRIA:
  Execute este arquivo APÓS os arquivos 01 a 05.
============================================================
*/


-- ============================================================
-- VIEW 1: vw_receita_por_categoria
-- Fonte: 02_business_analysis.sql — Seção 1
-- Uso: Visão executiva de desempenho por gênero cinematográfico
-- ============================================================

DROP VIEW IF EXISTS vw_receita_por_categoria;

CREATE VIEW vw_receita_por_categoria AS
WITH receita_base AS (
    SELECT
        cat.name                                AS categoria,
        COUNT(DISTINCT r.rental_id)             AS total_alugueis,
        COUNT(DISTINCT f.film_id)               AS total_filmes_catalogo,
        ROUND(SUM(p.amount), 2)                 AS receita_total,
        ROUND(AVG(p.amount), 2)                 AS ticket_medio
    FROM payment p
    JOIN rental r        ON p.rental_id    = r.rental_id
    JOIN inventory i     ON r.inventory_id = i.inventory_id
    JOIN film f          ON i.film_id      = f.film_id
    JOIN film_category fc ON f.film_id     = fc.film_id
    JOIN category cat    ON fc.category_id = cat.category_id
    GROUP BY cat.name
)
SELECT
    categoria,
    total_alugueis,
    total_filmes_catalogo,
    receita_total,
    ticket_medio,
    ROUND(receita_total * 100.0 / NULLIF(SUM(receita_total) OVER (), 0), 2) AS participacao_pct,
    RANK() OVER (ORDER BY receita_total DESC)                               AS rank_receita,
    ROUND(receita_total / NULLIF(total_filmes_catalogo, 0), 2)              AS receita_por_filme
FROM receita_base;

-- Verificação: SELECT * FROM vw_receita_por_categoria ORDER BY rank_receita;


-- ============================================================
-- VIEW 2: vw_top_filmes
-- Fonte: 02_business_analysis.sql — Seções 2 e 4
-- Uso: Ranking completo de filmes por receita com posição na categoria
-- ============================================================

DROP VIEW IF EXISTS vw_top_filmes;

CREATE VIEW vw_top_filmes AS
SELECT
    f.film_id,
    f.title                                     AS titulo,
    cat.name                                    AS categoria,
    f.rental_rate                               AS preco_base,
    f.rating                                    AS classificacao,
    COUNT(DISTINCT r.rental_id)                 AS total_alugueis,
    ROUND(SUM(p.amount), 2)                     AS receita_total,
    RANK() OVER (ORDER BY SUM(p.amount) DESC)   AS rank_geral,
    RANK() OVER (
        PARTITION BY cat.name
        ORDER BY SUM(p.amount) DESC
    )                                           AS rank_na_categoria
FROM payment p
JOIN rental r        ON p.rental_id    = r.rental_id
JOIN inventory i     ON r.inventory_id = i.inventory_id
JOIN film f          ON i.film_id      = f.film_id
JOIN film_category fc ON f.film_id     = fc.film_id
JOIN category cat    ON fc.category_id = cat.category_id
GROUP BY f.film_id, f.title, cat.name, f.rental_rate, f.rating;

-- Verificação: SELECT * FROM vw_top_filmes ORDER BY rank_geral LIMIT 20;


-- ============================================================
-- VIEW 3: vw_segmentacao_clientes
-- Fonte: 03_customer_behavior.sql — Seções 1, 2 e 3
-- Uso: Classificação completa de clientes por quadrante LTV × Frequência
-- ============================================================

DROP VIEW IF EXISTS vw_segmentacao_clientes;

CREATE VIEW vw_segmentacao_clientes AS
WITH metricas AS (
    SELECT
        c.customer_id,
        c.first_name || ' ' || c.last_name              AS nome_cliente,
        c.store_id                                       AS loja_cadastro,
        ROUND(SUM(p.amount), 2)                          AS ltv_total,
        COUNT(DISTINCT r.rental_id)                      AS total_alugueis,
        ROUND(SUM(p.amount) / NULLIF(COUNT(DISTINCT r.rental_id), 0), 2) AS ticket_medio
    FROM customer c
    JOIN rental r  ON c.customer_id = r.customer_id
    JOIN payment p ON r.rental_id   = p.rental_id
    WHERE c.activebool = true
    GROUP BY c.customer_id, c.first_name, c.last_name, c.store_id
),
medianas AS (
    SELECT
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ltv_total)      AS mediana_ltv,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_alugueis)  AS mediana_frequencia
    FROM metricas
)
SELECT
    m.customer_id,
    m.nome_cliente,
    m.loja_cadastro,
    m.ltv_total,
    m.total_alugueis,
    m.ticket_medio,
    RANK() OVER (ORDER BY m.ltv_total DESC)             AS rank_ltv,
    ROUND(m.ltv_total * 100.0
          / NULLIF(SUM(m.ltv_total) OVER (), 0), 2)     AS participacao_receita_pct,
    CASE
        WHEN m.ltv_total >= med.mediana_ltv AND m.total_alugueis >= med.mediana_frequencia
        THEN 'Champions'
        WHEN m.ltv_total >= med.mediana_ltv AND m.total_alugueis < med.mediana_frequencia
        THEN 'High Value'
        WHEN m.ltv_total < med.mediana_ltv  AND m.total_alugueis >= med.mediana_frequencia
        THEN 'Frequent Low Value'
        ELSE 'At Risk'
    END                                                 AS segmento
FROM metricas m
CROSS JOIN medianas med;

-- Verificação: SELECT segmento, COUNT(*), ROUND(SUM(ltv_total),2) FROM vw_segmentacao_clientes GROUP BY segmento;


-- ============================================================
-- VIEW 4: vw_tendencia_mensal
-- Fonte: 04_temporal_trends.sql — Seção 1
-- Uso: Série temporal de receita com crescimento MoM e acumulado
-- ============================================================

DROP VIEW IF EXISTS vw_tendencia_mensal;

CREATE VIEW vw_tendencia_mensal AS
WITH receita_mes AS (
    SELECT
        DATE_TRUNC('month', p.payment_date)     AS mes,
        COUNT(DISTINCT p.payment_id)            AS total_pagamentos,
        COUNT(DISTINCT p.rental_id)             AS total_alugueis,
        ROUND(SUM(p.amount), 2)                 AS receita_total,
        ROUND(AVG(p.amount), 2)                 AS ticket_medio,
        COUNT(DISTINCT p.customer_id)           AS clientes_ativos
    FROM payment p
    WHERE p.rental_id IS NOT NULL
    GROUP BY DATE_TRUNC('month', p.payment_date)
)
SELECT
    mes,
    total_pagamentos,
    total_alugueis,
    receita_total,
    ticket_medio,
    clientes_ativos,
    receita_total - LAG(receita_total) OVER (ORDER BY mes)          AS variacao_absoluta_mom,
    ROUND(
        (receita_total - LAG(receita_total) OVER (ORDER BY mes))
        * 100.0 / NULLIF(LAG(receita_total) OVER (ORDER BY mes), 0),
    2)                                                              AS crescimento_mom_pct,
    SUM(receita_total) OVER (ORDER BY mes
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)          AS receita_acumulada
FROM receita_mes
ORDER BY mes;

-- Verificação: SELECT * FROM vw_tendencia_mensal;


-- ============================================================
-- VIEW 5: vw_desempenho_lojas
-- Fonte: 05_segmentation.sql — Seções 1 e 5
-- Uso: Comparativo executivo entre as duas lojas da rede
-- ============================================================

DROP VIEW IF EXISTS vw_desempenho_lojas;

CREATE VIEW vw_desempenho_lojas AS
WITH kpis AS (
    SELECT
        st.store_id                                             AS loja,
        COUNT(DISTINCT r.rental_id)                             AS total_alugueis,
        COUNT(DISTINCT r.customer_id)                           AS clientes_unicos,
        ROUND(SUM(p.amount), 2)                                 AS receita_total,
        ROUND(AVG(p.amount), 2)                                 AS ticket_medio
    FROM rental r
    JOIN staff st  ON r.staff_id  = st.staff_id
    JOIN payment p ON r.rental_id = p.rental_id
    GROUP BY st.store_id
),
estoque AS (
    SELECT
        i.store_id,
        COUNT(DISTINCT i.inventory_id)                          AS total_copias,
        COUNT(DISTINCT r.inventory_id)                          AS copias_alugadas
    FROM inventory i
    LEFT JOIN rental r ON i.inventory_id = r.inventory_id
    GROUP BY i.store_id
)
SELECT
    k.loja,
    k.total_alugueis,
    k.clientes_unicos,
    k.receita_total,
    k.ticket_medio,
    ROUND(k.receita_total / NULLIF(k.clientes_unicos, 0), 2)    AS receita_por_cliente,
    ROUND(k.total_alugueis * 1.0
          / NULLIF(k.clientes_unicos, 0), 2)                    AS alugueis_por_cliente,
    ROUND(k.receita_total * 100.0
          / NULLIF(SUM(k.receita_total) OVER (), 0), 2)         AS participacao_receita_pct,
    e.total_copias,
    e.copias_alugadas,
    e.total_copias - e.copias_alugadas                          AS copias_paradas,
    ROUND(e.copias_alugadas * 100.0
          / NULLIF(e.total_copias, 0), 2)                       AS taxa_utilizacao_estoque_pct
FROM kpis k
JOIN estoque e ON k.loja = e.store_id
ORDER BY k.loja;

-- Verificação: SELECT * FROM vw_desempenho_lojas;


-- ============================================================
-- VIEW 6: vw_utilizacao_estoque_categoria
-- Fonte: 05_segmentation.sql — Seção 3
-- Uso: Taxa de utilização do estoque por loja e categoria
--      para orientar decisões de realocação de cópias
-- ============================================================

DROP VIEW IF EXISTS vw_utilizacao_estoque_categoria;

CREATE VIEW vw_utilizacao_estoque_categoria AS
WITH estoque_total AS (
    SELECT
        i.store_id,
        cat.name                        AS categoria,
        COUNT(DISTINCT i.inventory_id)  AS total_copias
    FROM inventory i
    JOIN film f          ON i.film_id      = f.film_id
    JOIN film_category fc ON f.film_id     = fc.film_id
    JOIN category cat    ON fc.category_id = cat.category_id
    GROUP BY i.store_id, cat.name
),
estoque_com_movimento AS (
    SELECT
        i.store_id,
        cat.name                              AS categoria,
        COUNT(DISTINCT i.inventory_id)        AS copias_alugadas
    FROM rental r
    JOIN inventory i     ON r.inventory_id = i.inventory_id
    JOIN film f          ON i.film_id      = f.film_id
    JOIN film_category fc ON f.film_id     = fc.film_id
    JOIN category cat    ON fc.category_id = cat.category_id
    GROUP BY i.store_id, cat.name
)
SELECT
    et.store_id                                     AS loja,
    et.categoria,
    et.total_copias,
    COALESCE(em.copias_alugadas, 0)                 AS copias_com_movimento,
    et.total_copias - COALESCE(em.copias_alugadas, 0) AS copias_paradas,
    ROUND(COALESCE(em.copias_alugadas, 0) * 100.0
          / NULLIF(et.total_copias, 0), 2)          AS taxa_utilizacao_pct,
    CASE
        WHEN COALESCE(em.copias_alugadas, 0) * 100.0
             / NULLIF(et.total_copias, 0) >= 90 THEN 'Alta'
        WHEN COALESCE(em.copias_alugadas, 0) * 100.0
             / NULLIF(et.total_copias, 0) >= 60 THEN 'Moderada'
        ELSE 'Baixa'
    END                                             AS classificacao
FROM estoque_total et
LEFT JOIN estoque_com_movimento em
    ON et.store_id = em.store_id AND et.categoria = em.categoria
ORDER BY et.store_id, taxa_utilizacao_pct DESC;

-- Verificação: SELECT * FROM vw_utilizacao_estoque_categoria WHERE classificacao = 'Baixa';


-- ============================================================
-- VIEW 7: vw_desempenho_equipe
-- Fonte: 05_segmentation.sql — Seção 6
-- Uso: Comparativo de desempenho entre os colaboradores da rede
-- ============================================================

DROP VIEW IF EXISTS vw_desempenho_equipe;

CREATE VIEW vw_desempenho_equipe AS
SELECT
    s.staff_id,
    CONCAT(s.first_name, ' ', s.last_name)              AS colaborador,
    s.store_id                                           AS loja,
    COUNT(DISTINCT r.rental_id)                          AS total_alugueis_processados,
    COUNT(DISTINCT r.customer_id)                        AS clientes_atendidos,
    ROUND(SUM(p.amount), 2)                              AS receita_gerada,
    ROUND(AVG(p.amount), 2)                              AS ticket_medio,
    ROUND(SUM(p.amount) * 100.0
          / NULLIF(SUM(SUM(p.amount)) OVER (), 0), 2)    AS participacao_receita_pct,
    RANK() OVER (ORDER BY SUM(p.amount) DESC)            AS rank_receita,
    ROUND(SUM(p.amount)
          / NULLIF(COUNT(DISTINCT r.customer_id), 0), 2) AS receita_por_cliente
FROM staff s
JOIN rental r  ON s.staff_id  = r.staff_id
JOIN payment p ON r.rental_id = p.rental_id
GROUP BY s.staff_id, s.first_name, s.last_name, s.store_id;

-- Verificação: SELECT * FROM vw_desempenho_equipe;


-- ============================================================
-- VIEW 8: vw_perda_estimada_multas
-- Fonte: 03_customer_behavior.sql — Seções 6 e 7
-- Uso: Estimativa de receita não capturada por atrasos na devolução
-- ============================================================

DROP VIEW IF EXISTS vw_perda_estimada_multas;

CREATE VIEW vw_perda_estimada_multas AS
SELECT
    cat.name                                                         AS categoria,
    COUNT(r.rental_id)                                               AS total_alugueis_atrasados,
    SUM(GREATEST(0, DATEDIFF(r.return_date, r.rental_date)
        - f.rental_duration))                                        AS total_dias_atraso,
    ROUND(SUM(
        GREATEST(0, DATEDIFF(r.return_date, r.rental_date) - f.rental_duration)
        * (f.rental_rate / NULLIF(f.rental_duration, 0))
    ), 2)                                                            AS perda_estimada,
    ROUND(SUM(
        GREATEST(0, DATEDIFF(r.return_date, r.rental_date) - f.rental_duration)
        * (f.rental_rate / NULLIF(f.rental_duration, 0))
    ) * 100.0 / NULLIF(SUM(SUM(
        GREATEST(0, DATEDIFF(r.return_date, r.rental_date) - f.rental_duration)
        * (f.rental_rate / NULLIF(f.rental_duration, 0))
    )) OVER (), 0), 2)                                               AS participacao_perda_pct,
    RANK() OVER (
        ORDER BY SUM(
            GREATEST(0, DATEDIFF(r.return_date, r.rental_date) - f.rental_duration)
            * (f.rental_rate / NULLIF(f.rental_duration, 0))
        ) DESC
    )                                                                AS rank_perda
FROM rental r
JOIN inventory i      ON r.inventory_id = i.inventory_id
JOIN film f           ON i.film_id      = f.film_id
JOIN film_category fc ON f.film_id      = fc.film_id
JOIN category cat     ON fc.category_id = cat.category_id
WHERE r.return_date IS NOT NULL
  AND DATEDIFF(r.return_date, r.rental_date) > f.rental_duration
GROUP BY cat.name;

-- Verificação: SELECT * FROM vw_perda_estimada_multas ORDER BY rank_perda;


-- ============================================================
-- CONSULTA FINAL: CONFIRMAR TODAS AS VIEWS CRIADAS
-- MySQL usa information_schema.views no lugar de pg_views
-- ============================================================

SELECT
    table_name              AS view_name,
    'Criada com sucesso'    AS status
FROM information_schema.views
WHERE table_schema = DATABASE()
  AND table_name LIKE 'vw_%'
ORDER BY table_name;

/*
RESULTADO ESPERADO:
  8 linhas com as views:
  - vw_desempenho_equipe
  - vw_desempenho_lojas
  - vw_perda_estimada_multas
  - vw_receita_por_categoria
  - vw_segmentacao_clientes
  - vw_tendencia_mensal
  - vw_top_filmes
  - vw_utilizacao_estoque_categoria
*/
