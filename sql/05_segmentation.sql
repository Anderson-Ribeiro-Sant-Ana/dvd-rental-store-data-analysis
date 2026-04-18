/*
============================================================
PROJETO  : DVD Rental Store — Análise de Desempenho Operacional
ARQUIVO  : 05_segmentation.sql
OBJETIVO : Comparação de desempenho entre lojas e análise de utilização do estoque
PERGUNTA : Quais lojas têm melhor desempenho em receita e volume?
           Qual a taxa de utilização do estoque por loja e categoria?
           Onde o estoque está imobilizado sem retorno?
AUTOR    : Anderson Sana
DATA     : 2025-04
============================================================

CONTEXTO:
  A rede opera duas lojas físicas com estoques independentes. A Diretora
  de Operações suspeita que as lojas têm perfis diferentes apesar de
  receita total semelhante. Esta análise separa desempenho por loja,
  calcula taxa de utilização do estoque por categoria e identifica
  onde o capital físico está imobilizado sem retorno financeiro.

NOTA TÉCNICA: A atribuição de aluguel à loja é feita via staff.store_id
(através de rental.staff_id), não via customer.store_id — um cliente
cadastrado em uma loja pode alugar na outra.
============================================================
*/


-- ============================================================
-- SEÇÃO 1: DESEMPENHO GERAL POR LOJA
-- Objetivo: Comparar receita total, volume e ticket médio entre
--           as duas lojas para identificar diferenças operacionais
-- Hipótese: Receita semelhante, mas perfis distintos de ticket
--           médio e volume de transações
-- ============================================================

SELECT
    st.store_id                                     AS loja,
    COUNT(DISTINCT r.rental_id)                     AS total_alugueis,
    COUNT(DISTINCT r.customer_id)                   AS clientes_unicos,
    ROUND(SUM(p.amount), 2)                         AS receita_total,
    ROUND(AVG(p.amount), 2)                         AS ticket_medio,
    -- Receita por cliente ativo na loja — mede eficiência de relacionamento
    ROUND(SUM(p.amount) / NULLIF(COUNT(DISTINCT r.customer_id), 0), 2) AS receita_por_cliente,
    -- Aluguéis por cliente — mede engajamento médio
    ROUND(COUNT(DISTINCT r.rental_id) * 1.0
          / NULLIF(COUNT(DISTINCT r.customer_id), 0), 2)               AS alugueis_por_cliente,
    -- Participação de cada loja na receita total da rede
    ROUND(SUM(p.amount) * 100.0
          / NULLIF(SUM(SUM(p.amount)) OVER (), 0), 2)                  AS participacao_receita_pct
FROM rental r
JOIN staff st   ON r.staff_id   = st.staff_id   -- Atribui aluguel à loja do atendente
JOIN payment p  ON r.rental_id  = p.rental_id
GROUP BY st.store_id
ORDER BY st.store_id;

/*
RESULTADO ESPERADO:
  - 2 linhas, uma por loja
  - participacao_receita_pct deve somar 100%
  - Diferença de receita total esperada: < 10%
  - Diferença de ticket_medio esperada: ~10-15%

INTERPRETAÇÃO:
  - Loja com maior ticket_medio + menor total_alugueis: perfil premium
  - Loja com menor ticket_medio + maior total_alugueis: perfil de volume
  - Ambas contribuem para o resultado total de formas diferentes
*/


-- ============================================================
-- SEÇÃO 2: DESEMPENHO POR LOJA E CATEGORIA
-- Objetivo: Identificar quais categorias são mais fortes em
--           cada loja — base para estratégia de estoque diferenciada
-- ============================================================

SELECT
    st.store_id                                     AS loja,
    cat.name                                        AS categoria,
    COUNT(DISTINCT r.rental_id)                     AS total_alugueis,
    ROUND(SUM(p.amount), 2)                         AS receita_total,
    -- Ranking da categoria dentro de cada loja
    RANK() OVER (
        PARTITION BY st.store_id
        ORDER BY SUM(p.amount) DESC
    )                                               AS rank_na_loja
FROM rental r
JOIN staff st        ON r.staff_id     = st.staff_id
JOIN payment p       ON r.rental_id    = p.rental_id
JOIN inventory i     ON r.inventory_id = i.inventory_id
JOIN film f          ON i.film_id      = f.film_id
JOIN film_category fc ON f.film_id     = fc.film_id
JOIN category cat    ON fc.category_id = cat.category_id
GROUP BY st.store_id, cat.name
ORDER BY st.store_id, rank_na_loja;

/*
RESULTADO ESPERADO:
  - 32 linhas (~16 categorias × 2 lojas)
  - rank_na_loja = 1 indica a categoria campeã de cada loja
  - Diferenças no top 3 entre lojas revelam perfis distintos de demanda

INTERPRETAÇÃO:
  - Categorias no top 3 de uma loja mas não da outra: candidatas a reequilíbrio de estoque
  - Categorias no top 3 de ambas: âncoras de demanda para toda a rede
*/


-- ============================================================
-- SEÇÃO 3: TAXA DE UTILIZAÇÃO DO ESTOQUE POR LOJA E CATEGORIA
-- Objetivo: Calcular que percentual do estoque físico de cada
--           categoria foi alugado ao menos uma vez no período
-- Hipótese: Categorias populares (Sports, Animation) devem ter
--           utilização > 90%; categorias de nicho < 60%
-- ============================================================

WITH estoque_total AS (
    -- Total de cópias físicas disponíveis por loja e categoria
    SELECT
        i.store_id,
        cat.name                        AS categoria,
        COUNT(DISTINCT i.inventory_id)  AS total_copias_estoque
    FROM inventory i
    JOIN film f          ON i.film_id      = f.film_id
    JOIN film_category fc ON f.film_id     = fc.film_id
    JOIN category cat    ON fc.category_id = cat.category_id
    GROUP BY i.store_id, cat.name
),

estoque_alugado AS (
    -- Cópias que foram alugadas ao menos 1 vez no período
    SELECT
        i.store_id,
        cat.name                              AS categoria,
        COUNT(DISTINCT i.inventory_id)        AS copias_com_movimento
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
    et.total_copias_estoque,
    COALESCE(ea.copias_com_movimento, 0)            AS copias_alugadas,
    et.total_copias_estoque
        - COALESCE(ea.copias_com_movimento, 0)      AS copias_paradas,
    ROUND(COALESCE(ea.copias_com_movimento, 0) * 100.0
          / NULLIF(et.total_copias_estoque, 0), 2)  AS taxa_utilizacao_pct,
    -- Classificação da eficiência do estoque
    CASE
        WHEN COALESCE(ea.copias_com_movimento, 0) * 100.0
             / NULLIF(et.total_copias_estoque, 0) >= 90 THEN 'Alta utilização'
        WHEN COALESCE(ea.copias_com_movimento, 0) * 100.0
             / NULLIF(et.total_copias_estoque, 0) >= 60 THEN 'Utilização moderada'
        ELSE 'Baixa utilização'
    END                                             AS classificacao_utilizacao
FROM estoque_total et
LEFT JOIN estoque_alugado ea
    ON et.store_id = ea.store_id
    AND et.categoria = ea.categoria
ORDER BY et.store_id, taxa_utilizacao_pct DESC;

/*
RESULTADO ESPERADO:
  - ~32 linhas (16 categorias × 2 lojas)
  - Categorias com Alta utilização: Sports, Animation, Sci-Fi (esperado)
  - Categorias com Baixa utilização: Travel, Music (esperado)
  - copias_paradas indica o estoque imobilizado sem retorno por segmento

INTERPRETAÇÃO:
  - Alta utilização + muitas cópias: demanda satisfeita, estoque adequado
  - Alta utilização + poucas cópias: demanda reprimida — prioridade de reposição
  - Baixa utilização + muitas cópias: estoque excessivo — candidato à realocação
*/


-- ============================================================
-- SEÇÃO 4: ESTOQUE PARADO — FILMES SEM ALUGUEL POR LOJA
-- Objetivo: Listar as cópias físicas específicas que nunca foram
--           alugadas — candidatas diretas à realocação ou descarte
-- ============================================================

SELECT
    i.store_id                          AS loja,
    f.title                             AS titulo,
    cat.name                            AS categoria,
    f.rental_rate                       AS preco_base,
    f.replacement_cost                  AS custo_reposicao,
    COUNT(DISTINCT i.inventory_id)      AS copias_paradas,
    -- Custo total imobilizado: cópias × custo de reposição
    ROUND(COUNT(DISTINCT i.inventory_id)
          * f.replacement_cost, 2)      AS custo_total_imobilizado
FROM inventory i
JOIN film f          ON i.film_id      = f.film_id
JOIN film_category fc ON f.film_id     = fc.film_id
JOIN category cat    ON fc.category_id = cat.category_id
LEFT JOIN rental r   ON i.inventory_id = r.inventory_id
WHERE r.rental_id IS NULL   -- Cópias sem nenhum aluguel registrado
GROUP BY i.store_id, f.title, cat.name, f.rental_rate, f.replacement_cost
ORDER BY i.store_id, custo_total_imobilizado DESC;

/*
RESULTADO ESPERADO:
  - Lista de títulos com cópias nunca alugadas por loja
  - custo_total_imobilizado indica o valor financeiro do estoque parado
  - Títulos com mais cópias paradas têm maior impacto operacional

INTERPRETAÇÃO:
  - Priorizar realocação de títulos com alto custo_total_imobilizado
  - Títulos com replacement_cost alto + 0 aluguéis = capital mal alocado
*/


-- ============================================================
-- SEÇÃO 5: RESUMO COMPARATIVO ENTRE LOJAS
-- Objetivo: Consolidar os principais KPIs das duas lojas em
--           uma visão única para apresentação executiva
-- ============================================================

WITH kpis_loja AS (
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

estoque_loja AS (
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
    e.total_copias,
    e.copias_alugadas,
    e.total_copias - e.copias_alugadas                          AS copias_paradas,
    ROUND(e.copias_alugadas * 100.0
          / NULLIF(e.total_copias, 0), 2)                       AS taxa_utilizacao_geral_pct
FROM kpis_loja k
JOIN estoque_loja e ON k.loja = e.store_id
ORDER BY k.loja;

/*
RESULTADO ESPERADO:
  - 2 linhas, uma por loja
  - Resumo executivo completo para a Diretora de Operações
  - taxa_utilizacao_geral_pct da rede deve ficar em ~82% (18% parado)

INTERPRETAÇÃO:
  - Esta visão alimenta diretamente o Insight 5 do insights.md
  - A loja com maior ticket_medio + menor total_alugueis confirma perfil premium
  - A loja com menor taxa_utilizacao_geral_pct tem o problema de estoque mais severo
*/
