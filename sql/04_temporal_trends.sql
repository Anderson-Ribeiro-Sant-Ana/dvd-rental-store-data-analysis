/*
============================================================
PROJETO  : DVD Rental Store — Análise de Desempenho Operacional
ARQUIVO  : 04_temporal_trends.sql
OBJETIVO : Análise da evolução temporal de receita e volume de aluguéis
PERGUNTA : Como a receita evoluiu ao longo do período?
           Há meses com queda ou pico relevante que exijam explicação?
AUTOR    : Anderson Sana
DATA     : 2025-04
============================================================

CONTEXTO:
  A Diretora de Operações quer entender se a receita da rede está em
  crescimento, estabilidade ou declínio. O dataset cobre mai–ago 2005
  com um ponto isolado em fev 2006 — a análise precisa tratar essa
  descontinuidade e comunicar com clareza as limitações da série temporal.

NOTA: payment_date é usado como base da análise temporal, pois representa
      o momento de realização da receita. rental_date é usada para
      análise de volume de aluguéis.
============================================================
*/


-- ============================================================
-- SEÇÃO 1: RECEITA E VOLUME MENSAL
-- Objetivo: Construir a série temporal base de receita e aluguéis
-- Hipótese: Crescimento progressivo de mai a jul 2005;
--           ago pode mostrar queda (fim de temporada de verão nos EUA)
-- ============================================================

WITH receita_mensal AS (
    SELECT
        DATE_TRUNC('month', p.payment_date)     AS mes,
        COUNT(DISTINCT p.payment_id)            AS total_pagamentos,
        COUNT(DISTINCT p.rental_id)             AS total_alugueis_pagos,
        ROUND(SUM(p.amount), 2)                 AS receita_total,
        ROUND(AVG(p.amount), 2)                 AS ticket_medio,
        COUNT(DISTINCT p.customer_id)           AS clientes_ativos_no_mes
    FROM payment p
    WHERE p.rental_id IS NOT NULL   -- Exclui pagamentos órfãos sem aluguel
    GROUP BY DATE_TRUNC('month', p.payment_date)
)

SELECT
    mes,
    total_pagamentos,
    total_alugueis_pagos,
    receita_total,
    ticket_medio,
    clientes_ativos_no_mes,
    -- Crescimento mês a mês em valor absoluto
    receita_total - LAG(receita_total) OVER (ORDER BY mes)          AS variacao_absoluta_mom,
    -- Crescimento mês a mês em percentual
    ROUND(
        (receita_total - LAG(receita_total) OVER (ORDER BY mes))
        * 100.0 / NULLIF(LAG(receita_total) OVER (ORDER BY mes), 0),
    2)                                                              AS crescimento_mom_pct,
    -- Receita acumulada desde o início da série
    SUM(receita_total) OVER (ORDER BY mes
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)          AS receita_acumulada
FROM receita_mensal
ORDER BY mes;

/*
RESULTADO ESPERADO:
  - 5 linhas (mai, jun, jul, ago 2005 + fev 2006)
  - crescimento_mom_pct do primeiro mês será NULL (sem mês anterior)
  - O pulo de ago/2005 para fev/2006 terá crescimento_mom_pct distorcido
    — documentar como limitação temporal na análise

INTERPRETAÇÃO:
  - crescimento_mom_pct positivo: expansão de receita
  - crescimento_mom_pct negativo: contração — investigar causas (sazonalidade? estoque?)
  - receita_acumulada mostra o total gerado até cada ponto da série
*/


-- ============================================================
-- SEÇÃO 2: VOLUME DIÁRIO DE ALUGUÉIS — IDENTIFICAÇÃO DE PICOS
-- Objetivo: Detectar dias com volume anormalmente alto ou baixo
--           que possam indicar eventos operacionais relevantes
-- Hipótese: Fins de semana devem ter volume maior que dias úteis
-- ============================================================

WITH volume_diario AS (
    SELECT
        r.rental_date::DATE                         AS dia,
        TO_CHAR(r.rental_date, 'Day')               AS dia_semana,
        EXTRACT(DOW FROM r.rental_date)             AS num_dia_semana, -- 0=Dom, 6=Sáb
        COUNT(r.rental_id)                          AS total_alugueis
    FROM rental r
    GROUP BY r.rental_date::DATE, TO_CHAR(r.rental_date, 'Day'), EXTRACT(DOW FROM r.rental_date)
),

stats AS (
    -- Média e desvio padrão para detectar dias anômalos
    SELECT
        AVG(total_alugueis)    AS media_diaria,
        STDDEV(total_alugueis) AS desvio_padrao
    FROM volume_diario
)

SELECT
    v.dia,
    v.dia_semana,
    v.total_alugueis,
    ROUND(s.media_diaria, 1)    AS media_geral_diaria,
    -- Flag de anomalia: dias com volume > média + 2 desvios
    CASE
        WHEN v.total_alugueis > s.media_diaria + 2 * s.desvio_padrao
        THEN 'Pico'
        WHEN v.total_alugueis < s.media_diaria - 2 * s.desvio_padrao
        THEN 'Vale'
        ELSE 'Normal'
    END                         AS classificacao_volume,
    -- Distância da média em número de desvios padrão
    ROUND(
        (v.total_alugueis - s.media_diaria) / NULLIF(s.desvio_padrao, 0),
    2)                          AS desvios_da_media
FROM volume_diario v
CROSS JOIN stats s
ORDER BY v.dia;

/*
RESULTADO ESPERADO:
  - Uma linha por dia no período
  - classificacao_volume = 'Pico' deve ser raro (< 5% dos dias)
  - Fins de semana (num_dia_semana = 0 ou 6) devem ter maior total_alugueis

INTERPRETAÇÃO:
  - Dias classificados como 'Pico' merecem investigação: podem indicar promoção,
    evento especial ou simplesmente padrão de consumo não documentado
  - 'Vale' em dia útil pode indicar problema operacional (sistema fora, loja fechada)
*/


-- ============================================================
-- SEÇÃO 3: DESEMPENHO POR DIA DA SEMANA
-- Objetivo: Identificar se há padrão semanal de demanda que
--           possa orientar decisões de estoque e escala de atendimento
-- ============================================================

SELECT
    CASE EXTRACT(DOW FROM r.rental_date)
        WHEN 0 THEN '0 - Domingo'
        WHEN 1 THEN '1 - Segunda'
        WHEN 2 THEN '2 - Terça'
        WHEN 3 THEN '3 - Quarta'
        WHEN 4 THEN '4 - Quinta'
        WHEN 5 THEN '5 - Sexta'
        WHEN 6 THEN '6 - Sábado'
    END                                         AS dia_semana,
    COUNT(r.rental_id)                          AS total_alugueis,
    ROUND(AVG(p.amount), 2)                     AS ticket_medio,
    ROUND(COUNT(r.rental_id) * 100.0
          / NULLIF(SUM(COUNT(r.rental_id)) OVER (), 0), 2) AS pct_do_total
FROM rental r
JOIN payment p ON r.rental_id = p.rental_id
GROUP BY EXTRACT(DOW FROM r.rental_date)
ORDER BY EXTRACT(DOW FROM r.rental_date);

/*
RESULTADO ESPERADO:
  - 7 linhas, uma por dia da semana
  - Fins de semana devem ter pct_do_total acima de 1/7 (~14.3%)
  - Padrão claro de concentração nos fins de semana seria relevante para
    decisões de escala de atendimento e reposição de estoque

INTERPRETAÇÃO:
  - Se fins de semana concentram > 35% dos aluguéis: operação típica de lazer
  - Distribuição uniforme: base de clientes com comportamento mais diverso
*/


-- ============================================================
-- SEÇÃO 4: RECEITA POR CATEGORIA AO LONGO DO TEMPO
-- Objetivo: Verificar se a liderança de categorias é estável
--           ou se há alternância ao longo dos meses
-- Hipótese: As categorias líderes devem manter posição consistente;
--           variações podem indicar campanhas ou sazonalidade
-- ============================================================

SELECT
    DATE_TRUNC('month', p.payment_date)         AS mes,
    cat.name                                    AS categoria,
    COUNT(DISTINCT r.rental_id)                 AS total_alugueis,
    ROUND(SUM(p.amount), 2)                     AS receita_total,
    -- Ranking da categoria dentro de cada mês
    RANK() OVER (
        PARTITION BY DATE_TRUNC('month', p.payment_date)
        ORDER BY SUM(p.amount) DESC
    )                                           AS rank_no_mes
FROM payment p
JOIN rental r        ON p.rental_id    = r.rental_id
JOIN inventory i     ON r.inventory_id = i.inventory_id
JOIN film f          ON i.film_id      = f.film_id
JOIN film_category fc ON f.film_id     = fc.film_id
JOIN category cat    ON fc.category_id = cat.category_id
WHERE p.rental_id IS NOT NULL
GROUP BY DATE_TRUNC('month', p.payment_date), cat.name
ORDER BY mes, rank_no_mes;

/*
RESULTADO ESPERADO:
  - Múltiplas linhas por mês (16 categorias × 5 meses = até 80 linhas)
  - rank_no_mes = 1 indica a categoria líder naquele mês
  - Mesmas categorias no topo em todos os meses = liderança estável
  - Alternância de categorias = possível influência de estoque ou sazonalidade

INTERPRETAÇÃO:
  - Categorias que sobem de rank no verão (jun-ago) podem ter perfil sazonal
  - Categorias que caem consistentemente podem estar perdendo participação por falta de títulos novos
*/


-- ============================================================
-- SEÇÃO 5: TICKET MÉDIO POR MÊS E TENDÊNCIA
-- Objetivo: Verificar se o valor médio por aluguel está crescendo,
--           estável ou caindo — indicador de precificação e mix de produto
-- ============================================================

WITH ticket_mensal AS (
    SELECT
        DATE_TRUNC('month', p.payment_date)     AS mes,
        ROUND(AVG(p.amount), 4)                 AS ticket_medio
    FROM payment p
    WHERE p.rental_id IS NOT NULL
    GROUP BY DATE_TRUNC('month', p.payment_date)
)

SELECT
    mes,
    ticket_medio,
    -- Variação do ticket médio em relação ao mês anterior
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
  - ticket_medio deve variar pouco entre meses (~$3-5 na maioria)
  - Variação > 10% entre meses indica mudança no mix de categorias alugadas

INTERPRETAÇÃO:
  - Ticket crescente: clientes migrando para títulos de maior valor (4.99)
  - Ticket decrescente: maior volume de aluguéis de títulos baratos (0.99)
  - Ticket estável: mix de produto consistente ao longo do período
*/
