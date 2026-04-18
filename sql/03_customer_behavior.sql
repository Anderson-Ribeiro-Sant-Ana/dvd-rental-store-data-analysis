/*
============================================================
PROJETO  : DVD Rental Store — Análise de Desempenho Operacional
ARQUIVO  : 03_customer_behavior.sql
OBJETIVO : Análise de comportamento, valor e inadimplência de clientes
PERGUNTA : Quem são os clientes mais valiosos? Com que frequência alugam?
           Há padrão de atraso na devolução que representa risco operacional?
AUTOR    : Anderson Sana
DATA     : 2025-04
============================================================

CONTEXTO:
  A Diretora de Operações suspeita que uma parcela pequena de clientes
  é responsável pela maior parte da receita, mas não tem visibilidade
  sobre quem são, nem sobre o comportamento de devolução. Esta análise
  segmenta a base de 599 clientes por valor e frequência, identifica
  padrões de atraso e entrega uma classificação acionável para decisões
  de retenção e política de multas.
============================================================
*/


-- ============================================================
-- SEÇÃO 1: LTV E FREQUÊNCIA POR CLIENTE
-- Objetivo: Calcular o valor total gerado e o volume de aluguéis
--           por cliente no período — base para a segmentação
-- Hipótese: Distribuição 80/20 esperada — 20% dos clientes devem
--           gerar ~60-80% da receita
-- ============================================================

DROP TABLE IF EXISTS temp_metricas_cliente;

CREATE TEMP TABLE temp_metricas_cliente AS
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name          AS nome_cliente,
    c.store_id                                   AS loja_cadastro,
    -- LTV simplificado: receita total gerada pelo cliente no período
    ROUND(SUM(p.amount), 2)                      AS ltv_total,
    -- Frequência: número total de aluguéis realizados
    COUNT(DISTINCT r.rental_id)                  AS total_alugueis,
    -- Ticket médio por aluguel deste cliente
    ROUND(SUM(p.amount) / NULLIF(COUNT(DISTINCT r.rental_id), 0), 2) AS ticket_medio,
    -- Data do primeiro e último aluguel — janela de relacionamento
    MIN(r.rental_date)                           AS primeiro_aluguel,
    MAX(r.rental_date)                           AS ultimo_aluguel,
    -- Dias entre primeiro e último aluguel — mede longevidade do cliente
    EXTRACT(DAY FROM MAX(r.rental_date) - MIN(r.rental_date)) AS dias_como_cliente
FROM customer c
JOIN rental r  ON c.customer_id = r.customer_id
JOIN payment p ON r.rental_id   = p.rental_id
WHERE c.activebool = true   -- Foco nos clientes ativos
GROUP BY c.customer_id, c.first_name, c.last_name, c.store_id;

-- Visualização do resultado base
SELECT * FROM temp_metricas_cliente
ORDER BY ltv_total DESC;

/*
RESULTADO ESPERADO:
  - ~584 linhas (clientes ativos com ao menos 1 aluguel e 1 pagamento)
  - ltv_total deve variar de ~$20 a ~$200
  - total_alugueis deve variar de 1 a ~45
*/


-- ============================================================
-- SEÇÃO 2: TOP 20 CLIENTES POR LTV
-- Objetivo: Identificar os clientes campeões de receita com
--           perfil completo para ações de retenção
-- ============================================================

SELECT
    nome_cliente,
    loja_cadastro,
    ltv_total,
    total_alugueis,
    ticket_medio,
    dias_como_cliente,
    -- Ranking global por LTV
    RANK() OVER (ORDER BY ltv_total DESC)             AS rank_ltv,
    -- Participação deste cliente na receita total
    ROUND(ltv_total * 100.0
          / NULLIF(SUM(ltv_total) OVER (), 0), 2)     AS participacao_receita_pct
FROM temp_metricas_cliente
ORDER BY ltv_total DESC
LIMIT 20;

/*
RESULTADO ESPERADO:
  - 20 clientes com maior LTV no período
  - participacao_receita_pct mostra o peso individual de cada um
  - Clientes com alto ltv + baixo total_alugueis = alto ticket médio (clientes premium)
  - Clientes com alto ltv + alto total_alugueis = alta frequência (clientes regulares)
*/


-- ============================================================
-- SEÇÃO 3: SEGMENTAÇÃO DE CLIENTES POR QUADRANTE LTV × FREQUÊNCIA
-- Objetivo: Classificar todos os clientes em 4 perfis estratégicos
--           com base em LTV e frequência de aluguel
-- Hipótese: "Champions" devem representar ~20% dos clientes mas
--           concentrar ~60% da receita
-- ============================================================

WITH medianas AS (
    -- Mediana de LTV e frequência como fronteira de segmentação
    SELECT
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ltv_total)     AS mediana_ltv,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_alugueis) AS mediana_frequencia
    FROM temp_metricas_cliente
),

clientes_segmentados AS (
    SELECT
        m.*,
        med.mediana_ltv,
        med.mediana_frequencia,
        CASE
            WHEN m.ltv_total >= med.mediana_ltv
             AND m.total_alugueis >= med.mediana_frequencia
            THEN 'Champions'          -- Alto valor + alta frequência: base de retenção prioritária
            WHEN m.ltv_total >= med.mediana_ltv
             AND m.total_alugueis < med.mediana_frequencia
            THEN 'High Value'         -- Alto valor + baixa frequência: potencial de ativação
            WHEN m.ltv_total < med.mediana_ltv
             AND m.total_alugueis >= med.mediana_frequencia
            THEN 'Frequent Low Value' -- Baixo valor + alta frequência: oportunidade de upsell
            ELSE 'At Risk'            -- Baixo valor + baixa frequência: risco de churn
        END                          AS segmento
    FROM temp_metricas_cliente m
    CROSS JOIN medianas med
)

SELECT
    segmento,
    COUNT(*)                                            AS total_clientes,
    ROUND(COUNT(*) * 100.0 / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS pct_clientes,
    ROUND(SUM(ltv_total), 2)                            AS receita_total_segmento,
    ROUND(SUM(ltv_total) * 100.0
          / NULLIF(SUM(SUM(ltv_total)) OVER (), 0), 2)  AS pct_receita,
    ROUND(AVG(ltv_total), 2)                            AS ltv_medio,
    ROUND(AVG(total_alugueis), 1)                       AS frequencia_media,
    ROUND(AVG(ticket_medio), 2)                         AS ticket_medio_segmento
FROM clientes_segmentados
GROUP BY segmento
ORDER BY receita_total_segmento DESC;

/*
RESULTADO ESPERADO:
  - 4 linhas, uma por segmento
  - Champions: ~25% dos clientes, ~60% da receita
  - At Risk: ~25% dos clientes, ~5-10% da receita
  - pct_receita confirma ou refuta a hipótese 80/20

INTERPRETAÇÃO:
  - Champions: ação imediata de retenção (programa de fidelidade)
  - High Value: campanha de reativação de frequência
  - Frequent Low Value: campanha de upsell para títulos de maior valor
  - At Risk: segmento a monitorar — custo de reativação pode não compensar
*/


-- ============================================================
-- SEÇÃO 4: ANÁLISE DE ATRASOS NA DEVOLUÇÃO
-- Objetivo: Calcular a taxa de inadimplência por cliente e
--           identificar se os clientes de maior valor são também
--           os que mais atrasam
-- Hipótese: Taxa geral de atraso ~40-50%; clientes Champions
--           podem ter taxa acima da média por alta frequência
-- ============================================================

DROP TABLE IF EXISTS temp_atrasos_cliente;

CREATE TEMP TABLE temp_atrasos_cliente AS
SELECT
    r.customer_id,
    COUNT(r.rental_id)                                  AS total_alugueis_com_devolucao,
    -- Aluguéis devolvidos após o prazo contratado
    SUM(CASE
            WHEN EXTRACT(DAY FROM (r.return_date - r.rental_date)) > f.rental_duration
            THEN 1 ELSE 0
        END)                                            AS total_atrasos,
    -- Média de dias de atraso nos aluguéis que atrasaram
    ROUND(AVG(CASE
                  WHEN EXTRACT(DAY FROM (r.return_date - r.rental_date)) > f.rental_duration
                  THEN EXTRACT(DAY FROM (r.return_date - r.rental_date)) - f.rental_duration
                  ELSE NULL
              END), 1)                                  AS media_dias_atraso,
    -- Dias máximos de atraso em um único aluguel
    MAX(GREATEST(0,
        EXTRACT(DAY FROM (r.return_date - r.rental_date)) - f.rental_duration
    ))                                                  AS max_dias_atraso
FROM rental r
JOIN film f ON (
    SELECT i.film_id FROM inventory i WHERE i.inventory_id = r.inventory_id LIMIT 1
) = f.film_id
WHERE r.return_date IS NOT NULL  -- Exclui aluguéis sem devolução registrada
GROUP BY r.customer_id;

-- Visão consolidada: perfil de atrasos por cliente com seu segmento
WITH medianas AS (
    SELECT
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ltv_total)      AS mediana_ltv,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_alugueis)  AS mediana_frequencia
    FROM temp_metricas_cliente
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
  - 4 linhas, uma por segmento
  - taxa_atraso_pct dos Champions deve estar acima ou igual à média geral
  - media_dias_atraso deve ser baixa (1-3 dias) em todos os segmentos
  - Segmento At Risk pode ter taxa menor simplesmente por fazer menos aluguéis

INTERPRETAÇÃO:
  - Champions com alta taxa + baixa media_dias_atraso = comportamento de consumo, não inadimplência
  - At Risk com alta media_dias_atraso = inadimplência real que justifica tratamento diferenciado
*/


-- ============================================================
-- SEÇÃO 5: DISTRIBUIÇÃO DE ATRASOS EM FAIXAS
-- Objetivo: Entender se os atrasos são principalmente de 1-2 dias
--           (comportamentais) ou de muitos dias (inadimplência real)
-- ============================================================

SELECT
    CASE
        WHEN EXTRACT(DAY FROM (r.return_date - r.rental_date)) <= f.rental_duration
        THEN '00 — No prazo'
        WHEN EXTRACT(DAY FROM (r.return_date - r.rental_date)) - f.rental_duration BETWEEN 1 AND 2
        THEN '01-02 dias de atraso'
        WHEN EXTRACT(DAY FROM (r.return_date - r.rental_date)) - f.rental_duration BETWEEN 3 AND 7
        THEN '03-07 dias de atraso'
        WHEN EXTRACT(DAY FROM (r.return_date - r.rental_date)) - f.rental_duration BETWEEN 8 AND 14
        THEN '08-14 dias de atraso'
        ELSE '15+ dias de atraso'
    END                                AS faixa_atraso,
    COUNT(*)                           AS total_alugueis,
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
  - 5 linhas de faixas de atraso
  - "No prazo" deve representar ~55% dos aluguéis
  - "01-02 dias" deve ser a maior faixa de atraso (~25-30%)
  - "15+ dias" deve ser < 5% do total

INTERPRETAÇÃO:
  - Se "01-02 dias" domina os atrasos, a política de prazo pode estar 1-2 dias abaixo do ideal
  - Alta concentração em "15+ dias" indicaria inadimplência crônica — não esperado neste dataset
*/
