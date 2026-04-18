/*
============================================================
PROJETO  : DVD Rental Store — Análise de Desempenho Operacional
ARQUIVO  : 02_business_analysis.sql
OBJETIVO : Análise de receita por categoria e desempenho do catálogo de filmes
PERGUNTA : Quais categorias e títulos sustentam a receita da operação?
           Quais filmes têm maior e menor giro no catálogo?
AUTOR    : Anderson Sana
DATA     : 2025-04
BANCO    : MySQL 8.0+
============================================================
*/


-- ============================================================
-- SEÇÃO 1: RECEITA TOTAL POR CATEGORIA
-- Objetivo: Identificar quais gêneros sustentam a receita da operação
-- Hipótese: Sports e Sci-Fi devem liderar em volume;
--           categorias de nicho (Music, Travel) devem ter menor receita
-- ============================================================

WITH receita_por_categoria AS (
    SELECT
        cat.name                                AS categoria,
        COUNT(DISTINCT r.rental_id)             AS total_alugueis,
        COUNT(DISTINCT f.film_id)               AS total_filmes_no_catalogo,
        ROUND(SUM(p.amount), 2)                 AS receita_total,
        ROUND(AVG(p.amount), 2)                 AS ticket_medio
    FROM payment p
    JOIN rental r         ON p.rental_id    = r.rental_id
    JOIN inventory i      ON r.inventory_id = i.inventory_id
    JOIN film f           ON i.film_id      = f.film_id
    JOIN film_category fc ON f.film_id      = fc.film_id
    JOIN category cat     ON fc.category_id = cat.category_id
    GROUP BY cat.name
)

SELECT
    categoria,
    total_alugueis,
    total_filmes_no_catalogo,
    receita_total,
    ticket_medio,
    ROUND(receita_total * 100.0
          / NULLIF(SUM(receita_total) OVER (), 0), 2)             AS participacao_receita_pct,
    RANK() OVER (ORDER BY receita_total DESC)                     AS rank_receita,
    ROUND(receita_total / NULLIF(total_filmes_no_catalogo, 0), 2) AS receita_por_filme_catalogo
FROM receita_por_categoria
ORDER BY receita_total DESC;

/*
RESULTADO ESPERADO:
  - 16 linhas, uma por categoria
  - Sports, Sci-Fi e Animation devem liderar
  - participacao_receita_pct das top 3 deve somar ~40%
*/


-- ============================================================
-- SEÇÃO 2: TOP 10 FILMES POR RECEITA
-- Objetivo: Identificar os títulos campeões de receita na rede
-- ============================================================

WITH receita_por_filme AS (
    SELECT
        f.film_id,
        f.title                             AS titulo,
        cat.name                            AS categoria,
        f.rental_rate                       AS preco_base,
        f.rating                            AS classificacao,
        COUNT(DISTINCT r.rental_id)         AS total_alugueis,
        ROUND(SUM(p.amount), 2)             AS receita_total
    FROM payment p
    JOIN rental r         ON p.rental_id    = r.rental_id
    JOIN inventory i      ON r.inventory_id = i.inventory_id
    JOIN film f           ON i.film_id      = f.film_id
    JOIN film_category fc ON f.film_id      = fc.film_id
    JOIN category cat     ON fc.category_id = cat.category_id
    GROUP BY f.film_id, f.title, cat.name, f.rental_rate, f.rating
)

SELECT
    titulo,
    categoria,
    preco_base,
    classificacao,
    total_alugueis,
    receita_total,
    RANK() OVER (ORDER BY receita_total DESC)                             AS rank_geral,
    RANK() OVER (PARTITION BY categoria ORDER BY receita_total DESC)      AS rank_na_categoria
FROM receita_por_filme
ORDER BY receita_total DESC
LIMIT 10;

/*
RESULTADO ESPERADO:
  - 10 filmes com maior receita no período
  - rank_na_categoria mostra se o filme é líder em seu gênero
*/


-- ============================================================
-- SEÇÃO 3: FILMES SEM NENHUM ALUGUEL NO PERÍODO
-- Objetivo: Identificar títulos que ocupam estoque sem gerar receita
-- ============================================================

SELECT
    f.film_id,
    f.title                        AS titulo,
    cat.name                       AS categoria,
    f.rental_rate                  AS preco_base,
    f.rating                       AS classificacao,
    COUNT(DISTINCT i.inventory_id) AS copias_no_estoque
FROM film f
JOIN film_category fc  ON f.film_id      = fc.film_id
JOIN category cat      ON fc.category_id = cat.category_id
JOIN inventory i       ON f.film_id      = i.film_id
LEFT JOIN rental r     ON i.inventory_id = r.inventory_id
WHERE r.rental_id IS NULL
GROUP BY f.film_id, f.title, cat.name, f.rental_rate, f.rating
ORDER BY copias_no_estoque DESC, categoria;

/*
RESULTADO ESPERADO:
  - Lista de filmes com zero aluguéis no período
  - copias_no_estoque indica o custo de oportunidade por título
*/


-- ============================================================
-- SEÇÃO 4: RANKING DE FILMES POR RECEITA DENTRO DE CADA CATEGORIA
-- Objetivo: Identificar o filme líder de receita em cada gênero
-- ============================================================

WITH ranking_por_categoria AS (
    SELECT
        cat.name                            AS categoria,
        f.title                             AS titulo,
        COUNT(DISTINCT r.rental_id)         AS total_alugueis,
        ROUND(SUM(p.amount), 2)             AS receita_total,
        RANK() OVER (
            PARTITION BY cat.name
            ORDER BY SUM(p.amount) DESC
        )                                   AS rank_na_categoria
    FROM payment p
    JOIN rental r         ON p.rental_id    = r.rental_id
    JOIN inventory i      ON r.inventory_id = i.inventory_id
    JOIN film f           ON i.film_id      = f.film_id
    JOIN film_category fc ON f.film_id      = fc.film_id
    JOIN category cat     ON fc.category_id = cat.category_id
    GROUP BY cat.name, f.title
)

SELECT
    categoria,
    titulo,
    total_alugueis,
    receita_total,
    rank_na_categoria
FROM ranking_por_categoria
WHERE rank_na_categoria <= 3
ORDER BY categoria, rank_na_categoria;

/*
RESULTADO ESPERADO:
  - Top 3 filmes por receita em cada uma das 16 categorias
*/


-- ============================================================
-- SEÇÃO 5: ANÁLISE DE TICKET MÉDIO POR FAIXA DE PREÇO
-- Objetivo: Entender a distribuição de receita entre as três
--           faixas de preço base (0.99, 2.99, 4.99)
-- ============================================================

WITH faixas_de_preco AS (
    SELECT
        f.rental_rate                       AS preco_base,
        COUNT(DISTINCT f.film_id)           AS total_filmes,
        COUNT(DISTINCT r.rental_id)         AS total_alugueis,
        ROUND(SUM(p.amount), 2)             AS receita_total,
        ROUND(AVG(p.amount), 2)             AS ticket_medio_real
    FROM payment p
    JOIN rental r    ON p.rental_id    = r.rental_id
    JOIN inventory i ON r.inventory_id = i.inventory_id
    JOIN film f      ON i.film_id      = f.film_id
    GROUP BY f.rental_rate
)

SELECT
    preco_base,
    total_filmes,
    total_alugueis,
    receita_total,
    ticket_medio_real,
    ROUND(receita_total * 100.0 / NULLIF(SUM(receita_total) OVER (), 0), 2) AS participacao_receita_pct,
    ROUND(total_alugueis * 1.0 / NULLIF(total_filmes, 0), 1)                AS alugueis_por_filme
FROM faixas_de_preco
ORDER BY preco_base;

/*
RESULTADO ESPERADO:
  - 3 linhas (0.99, 2.99, 4.99)
  - Faixa 4.99: menor alugueis_por_filme, maior receita unitária
  - Faixa 0.99: maior alugueis_por_filme, menor receita unitária
*/
