/*
============================================================
PROJETO  : DVD Rental Store — Análise de Desempenho Operacional
ARQUIVO  : 02_business_analysis.sql
OBJETIVO : Análise de receita por categoria e desempenho do catálogo de filmes
PERGUNTA : Quais categorias e títulos sustentam a receita da operação?
           Quais filmes têm maior e menor giro no catálogo?
AUTOR    : Anderson Sana
DATA     : 2025-04
============================================================

CONTEXTO:
  A Diretora de Operações precisa entender quais gêneros cinematográficos
  concentram a receita e quais títulos específicos têm melhor desempenho.
  A análise também identifica filmes que ocupam espaço no estoque sem
  gerar retorno — informação crítica para decisões de compra do próximo
  semestre.
============================================================
*/


-- ============================================================
-- SEÇÃO 1: RECEITA TOTAL POR CATEGORIA
-- Objetivo: Identificar quais gêneros sustentam a receita da operação
-- Hipótese: Sports e Sci-Fi devem liderar em volume;
--           categorias de nicho (Music, Travel) devem ter menor receita
-- ============================================================

WITH receita_por_categoria AS (
    -- Agrega receita de cada aluguel até a categoria do filme alugado
    SELECT
        cat.name                                AS categoria,
        COUNT(DISTINCT r.rental_id)             AS total_alugueis,
        COUNT(DISTINCT f.film_id)               AS total_filmes_no_catalogo,
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
    total_filmes_no_catalogo,
    receita_total,
    ticket_medio,
    -- Participação desta categoria na receita total da rede
    ROUND(receita_total * 100.0
          / NULLIF(SUM(receita_total) OVER (), 0), 2)          AS participacao_receita_pct,
    -- Ranking por receita total
    RANK() OVER (ORDER BY receita_total DESC)                   AS rank_receita,
    -- Receita média por filme no catálogo — mede eficiência do mix
    ROUND(receita_total / NULLIF(total_filmes_no_catalogo, 0), 2) AS receita_por_filme_catalogo
FROM receita_por_categoria
ORDER BY receita_total DESC;

/*
RESULTADO ESPERADO:
  - 16 linhas, uma por categoria
  - Sports, Sci-Fi e Animation devem liderar
  - participacao_receita_pct das top 3 deve somar ~40%
  - receita_por_filme_catalogo revela categorias com alto retorno por título

INTERPRETAÇÃO:
  - Alta participacao_receita_pct + baixo total_filmes_no_catalogo = categoria de alto retorno por título
  - Alta participacao_receita_pct + alto total_filmes_no_catalogo = categoria com receita diluída em muitos títulos
*/


-- ============================================================
-- SEÇÃO 2: TOP 10 FILMES POR RECEITA
-- Objetivo: Identificar os títulos campeões de receita na rede
-- Hipótese: Filmes de categorias líderes devem dominar o ranking,
--           mas pode haver surpresas de categorias menores
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
    JOIN rental r        ON p.rental_id    = r.rental_id
    JOIN inventory i     ON r.inventory_id = i.inventory_id
    JOIN film f          ON i.film_id      = f.film_id
    JOIN film_category fc ON f.film_id     = fc.film_id
    JOIN category cat    ON fc.category_id = cat.category_id
    GROUP BY f.film_id, f.title, cat.name, f.rental_rate, f.rating
)

SELECT
    titulo,
    categoria,
    preco_base,
    classificacao,
    total_alugueis,
    receita_total,
    -- Posição global por receita
    RANK() OVER (ORDER BY receita_total DESC)             AS rank_geral,
    -- Posição dentro da categoria — compara o filme com seus pares de gênero
    RANK() OVER (PARTITION BY categoria ORDER BY receita_total DESC) AS rank_na_categoria
FROM receita_por_filme
ORDER BY receita_total DESC
LIMIT 10;

/*
RESULTADO ESPERADO:
  - 10 filmes com maior receita no período
  - rank_na_categoria mostra se o filme é líder ou vice em seu gênero
  - Filmes com preco_base = 4.99 devem aparecer com menos aluguéis mas maior receita
*/


-- ============================================================
-- SEÇÃO 3: FILMES SEM NENHUM ALUGUEL NO PERÍODO
-- Objetivo: Identificar títulos que ocupam estoque sem gerar receita
-- Hipótese: Deve haver um grupo de filmes com 0 aluguéis —
--           candidatos à retirada ou reposicionamento no catálogo
-- ============================================================

SELECT
    f.film_id,
    f.title                     AS titulo,
    cat.name                    AS categoria,
    f.rental_rate               AS preco_base,
    f.rating                    AS classificacao,
    -- Quantas cópias físicas existem no estoque sem retorno
    COUNT(DISTINCT i.inventory_id) AS copias_no_estoque
FROM film f
JOIN film_category fc  ON f.film_id      = fc.film_id
JOIN category cat      ON fc.category_id = cat.category_id
JOIN inventory i       ON f.film_id      = i.film_id
-- LEFT JOIN traz filmes mesmo sem aluguéis
LEFT JOIN rental r     ON i.inventory_id = r.inventory_id
WHERE r.rental_id IS NULL   -- Apenas filmes sem nenhum aluguel registrado
GROUP BY f.film_id, f.title, cat.name, f.rental_rate, f.rating
ORDER BY copias_no_estoque DESC, categoria;

/*
RESULTADO ESPERADO:
  - Lista de filmes com zero aluguéis no período
  - copias_no_estoque indica o custo de oportunidade: espaço ocupado sem retorno
  - Concentração por categoria revela onde o mix está desalinhado com a demanda

INTERPRETAÇÃO:
  - Film com muitas copias e 0 aluguéis = candidato prioritário para realocação
  - Film com 1 cópia e 0 aluguéis = pode ser caso isolado ou recém-adicionado
*/


-- ============================================================
-- SEÇÃO 4: RANKING DE FILMES POR RECEITA DENTRO DE CADA CATEGORIA
-- Objetivo: Identificar o filme líder de receita em cada gênero
--           e o gap entre o 1º e o 2º colocado
-- Hipótese: Em categorias populares, a diferença entre 1º e 2º
--           deve ser pequena; em nichos, pode haver um título dominante
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
    JOIN rental r        ON p.rental_id    = r.rental_id
    JOIN inventory i     ON r.inventory_id = i.inventory_id
    JOIN film f          ON i.film_id      = f.film_id
    JOIN film_category fc ON f.film_id     = fc.film_id
    JOIN category cat    ON fc.category_id = cat.category_id
    GROUP BY cat.name, f.title
)

SELECT
    categoria,
    titulo,
    total_alugueis,
    receita_total,
    rank_na_categoria
FROM ranking_por_categoria
-- Traz apenas o top 3 por categoria para análise comparativa
WHERE rank_na_categoria <= 3
ORDER BY categoria, rank_na_categoria;

/*
RESULTADO ESPERADO:
  - 3 filmes por categoria (onde houver ao menos 3 com aluguéis)
  - Permite identificar quais títulos são âncoras de receita em cada gênero
  - Gestão de estoque deve garantir disponibilidade dos rank 1 de cada categoria
*/


-- ============================================================
-- SEÇÃO 5: ANÁLISE DE TICKET MÉDIO POR FAIXA DE PREÇO
-- Objetivo: Entender a distribuição de receita entre as três
--           faixas de preço base (0.99, 2.99, 4.99)
-- Hipótese: A faixa 4.99 deve ter menor volume mas maior receita total
--           quando o número de cópias é levado em conta
-- ============================================================

WITH faixas_de_preco AS (
    SELECT
        f.rental_rate                       AS preco_base,
        COUNT(DISTINCT f.film_id)           AS total_filmes,
        COUNT(DISTINCT r.rental_id)         AS total_alugueis,
        ROUND(SUM(p.amount), 2)             AS receita_total,
        ROUND(AVG(p.amount), 2)             AS ticket_medio_real
    FROM payment p
    JOIN rental r        ON p.rental_id    = r.rental_id
    JOIN inventory i     ON r.inventory_id = i.inventory_id
    JOIN film f          ON i.film_id      = f.film_id
    GROUP BY f.rental_rate
)

SELECT
    preco_base,
    total_filmes,
    total_alugueis,
    receita_total,
    ticket_medio_real,
    ROUND(receita_total * 100.0 / NULLIF(SUM(receita_total) OVER (), 0), 2) AS participacao_receita_pct,
    -- Aluguéis por filme — mede popularidade relativa dentro da faixa de preço
    ROUND(total_alugueis * 1.0 / NULLIF(total_filmes, 0), 1)                AS alugueis_por_filme
FROM faixas_de_preco
ORDER BY preco_base;

/*
RESULTADO ESPERADO:
  - 3 linhas (0.99, 2.99, 4.99)
  - ticket_medio_real pode ser maior que preco_base — indica multas embutidas
  - Faixa 4.99: menor alugueis_por_filme, maior receita_por_aluguel
  - Faixa 0.99: maior alugueis_por_filme, menor receita unitária

INTERPRETAÇÃO:
  - Se faixa 0.99 gera mais de 40% da receita, a estratégia de volume compensa a precificação baixa
  - Se faixa 4.99 gera menos de 20% da receita, há baixa penetração de títulos premium
*/
