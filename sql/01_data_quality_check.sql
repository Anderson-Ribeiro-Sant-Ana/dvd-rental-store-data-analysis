/*
============================================================
PROJETO  : DVD Rental Store — Análise de Desempenho Operacional
ARQUIVO  : 01_data_quality_check.sql
OBJETIVO : Auditoria de integridade dos dados antes de qualquer análise
AUTOR    : Anderson Sana
DATA     : 2025-04
============================================================

CONTEXTO:
  Antes de qualquer análise de receita ou comportamento de clientes,
  é necessário garantir que o dado é confiável. Este arquivo audita
  as principais tabelas do schema buscando:
  - Registros órfãos (chaves sem correspondência)
  - Nulos em campos críticos para as análises
  - Inconsistências temporais (datas fora do período esperado)
  - Duplicatas em chaves primárias
  - Distribuição de completude por tabela

  Abordagem: cada seção rastreia um tipo específico de anomalia
  à sua origem no schema — princípio de rastreabilidade de dados.
============================================================
*/


-- ============================================================
-- SEÇÃO 1: VOLUME GERAL POR TABELA
-- Objetivo: Confirmar que o banco foi restaurado corretamente
--           e que os volumes estão dentro do esperado
-- Esperado: rental ~16k, payment ~14.5k, inventory ~4.5k,
--           film ~1k, customer ~600
-- ============================================================

SELECT 'rental'     AS tabela, COUNT(*) AS total_registros FROM rental
UNION ALL
SELECT 'payment',               COUNT(*) FROM payment
UNION ALL
SELECT 'inventory',             COUNT(*) FROM inventory
UNION ALL
SELECT 'film',                  COUNT(*) FROM film
UNION ALL
SELECT 'film_category',         COUNT(*) FROM film_category
UNION ALL
SELECT 'category',              COUNT(*) FROM category
UNION ALL
SELECT 'customer',              COUNT(*) FROM customer
UNION ALL
SELECT 'store',                 COUNT(*) FROM store
UNION ALL
SELECT 'staff',                 COUNT(*) FROM staff
UNION ALL
SELECT 'actor',                 COUNT(*) FROM actor
UNION ALL
SELECT 'film_actor',            COUNT(*) FROM film_actor
UNION ALL
SELECT 'address',               COUNT(*) FROM address
UNION ALL
SELECT 'city',                  COUNT(*) FROM city
UNION ALL
SELECT 'country',               COUNT(*) FROM country
ORDER BY total_registros DESC;

/*
RESULTADO ESPERADO:
  - rental: ~16.044 registros
  - payment: ~14.596 registros
  - inventory: ~4.581 registros
  - film_actor: ~5.462 registros
  - film: ~1.000 registros
  - customer: ~599 registros
  Qualquer volume muito abaixo do esperado indica restauração incompleta.
*/


-- ============================================================
-- SEÇÃO 2: NULOS EM CAMPOS CRÍTICOS
-- Objetivo: Identificar campos que terão impacto direto nas
--           análises e que possuem valores ausentes
-- Hipótese: return_date terá NULLs (aluguéis em aberto);
--           payment.rental_id pode ter NULLs esporádicos
-- ============================================================

SELECT
    'rental.return_date'       AS campo,
    COUNT(*)                   AS total_nulos,
    ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM rental), 0), 2) AS pct_nulos
FROM rental
WHERE return_date IS NULL

UNION ALL

SELECT
    'payment.rental_id',
    COUNT(*),
    ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM payment), 0), 2)
FROM payment
WHERE rental_id IS NULL

UNION ALL

SELECT
    'customer.email',
    COUNT(*),
    ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM customer), 0), 2)
FROM customer
WHERE email IS NULL

UNION ALL

SELECT
    'film.length',
    COUNT(*),
    ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM film), 0), 2)
FROM film
WHERE length IS NULL

UNION ALL

SELECT
    'film.rating',
    COUNT(*),
    ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM film), 0), 2)
FROM film
WHERE rating IS NULL;

/*
RESULTADO ESPERADO:
  - rental.return_date: ~6% de nulos — aluguéis sem devolução registrada
  - payment.rental_id: ~1-2% de nulos — pagamentos sem aluguel identificado
  - customer.email: 0% — todos os clientes ativos têm e-mail
  - film.length: < 1% de nulos
  Campos com nulos > 5% devem ser tratados explicitamente nas análises.
*/


-- ============================================================
-- SEÇÃO 3: REGISTROS ÓRFÃOS — CHAVES SEM CORRESPONDÊNCIA
-- Objetivo: Garantir integridade referencial entre as tabelas
--           principais do fluxo de negócio
-- Hipótese: Deveria haver 0 órfãos; qualquer resultado > 0
--           é uma anomalia que precisa ser documentada
-- ============================================================

-- 3a. Aluguéis sem pagamento correspondente
-- (filmes alugados mas sem registro financeiro — risco de receita perdida)
SELECT
    'rental sem payment' AS anomalia,
    COUNT(*)             AS total
FROM rental r
LEFT JOIN payment p ON r.rental_id = p.rental_id
WHERE p.rental_id IS NULL;

-- 3b. Pagamentos sem aluguel correspondente
-- (pagamentos sem transação de origem — risco de dado fantasma)
SELECT
    'payment sem rental' AS anomalia,
    COUNT(*)             AS total
FROM payment p
LEFT JOIN rental r ON p.rental_id = r.rental_id
WHERE r.rental_id IS NULL
  AND p.rental_id IS NOT NULL;  -- Exclui os que já têm rental_id nulo (tratados na Seção 2)

-- 3c. Itens de estoque sem filme correspondente
-- (cópias físicas sem cadastro de produto — inconsistência de inventário)
SELECT
    'inventory sem film' AS anomalia,
    COUNT(*)             AS total
FROM inventory i
LEFT JOIN film f ON i.film_id = f.film_id
WHERE f.film_id IS NULL;

-- 3d. Filmes sem categoria cadastrada
-- (filmes que não aparecerão nas análises por categoria)
SELECT
    'film sem category' AS anomalia,
    COUNT(*)            AS total
FROM film f
LEFT JOIN film_category fc ON f.film_id = fc.film_id
WHERE fc.film_id IS NULL;

-- 3e. Aluguéis de clientes inativos
-- (transações de clientes com active = false — dado suspeito)
SELECT
    'aluguel de cliente inativo' AS anomalia,
    COUNT(*)                     AS total
FROM rental r
JOIN customer c ON r.customer_id = c.customer_id
WHERE c.activebool = false;

/*
RESULTADO ESPERADO:
  - rental sem payment: pode haver alguns — representam risco de receita
  - payment sem rental: pode haver ~200 — documentados como limitação
  - inventory sem film: deve ser 0
  - film sem category: deve ser 0
  - aluguel de cliente inativo: deve ser 0 ou próximo de 0
*/


-- ============================================================
-- SEÇÃO 4: INCONSISTÊNCIAS TEMPORAIS
-- Objetivo: Identificar datas fora do período esperado (mai–ago 2005)
--           e devolucoes com data anterior ao aluguel
-- Hipótese: payment_date pode ter datas de 2007 (anomalia conhecida);
--           return_date anterior a rental_date indica erro de sistema
-- ============================================================

-- 4a. Distribuição de aluguéis por ano e mês
-- (confirma o período coberto e detecta outliers temporais)
SELECT
    DATE_TRUNC('month', rental_date) AS mes,
    COUNT(*)                         AS total_alugueis
FROM rental
GROUP BY mes
ORDER BY mes;

-- 4b. Distribuição de pagamentos por ano
-- (identifica pagamentos com datas fora do período de negócio)
SELECT
    EXTRACT(YEAR FROM payment_date) AS ano,
    COUNT(*)                        AS total_pagamentos,
    ROUND(SUM(amount), 2)           AS receita_total
FROM payment
GROUP BY ano
ORDER BY ano;

-- 4c. Devoluções com data anterior ao aluguel
-- (impossível no mundo real — indica erro de registro ou migração de dados)
SELECT
    rental_id,
    rental_date,
    return_date,
    return_date - rental_date AS diferenca
FROM rental
WHERE return_date IS NOT NULL
  AND return_date < rental_date;

-- 4d. Aluguéis com prazo de devolução excessivo (> 30 dias)
-- (pode indicar dado em aberto disfarçado de devolvido)
SELECT
    COUNT(*) AS alugueis_prazo_acima_30_dias
FROM rental
WHERE return_date IS NOT NULL
  AND EXTRACT(DAY FROM (return_date - rental_date)) > 30;

/*
RESULTADO ESPERADO:
  - Aluguéis concentrados em mai–ago 2005 e fev 2006
  - Pagamentos: maioria em 2005/2006, alguns em 2007 (anomalia a documentar)
  - Devoluções anteriores ao aluguel: deve ser 0
  - Aluguéis > 30 dias: deve ser muito baixo (< 1%)
*/


-- ============================================================
-- SEÇÃO 5: DUPLICATAS EM CHAVES PRIMÁRIAS
-- Objetivo: Confirmar unicidade nas PKs das tabelas principais
-- Hipótese: Deve ser 0 em todos os casos; qualquer resultado
--           indica problema na carga do banco
-- ============================================================

SELECT 'rental_id duplicado'   AS verificacao, COUNT(*) - COUNT(DISTINCT rental_id)   AS duplicatas FROM rental
UNION ALL
SELECT 'payment_id duplicado',                 COUNT(*) - COUNT(DISTINCT payment_id)  FROM payment
UNION ALL
SELECT 'inventory_id duplicado',               COUNT(*) - COUNT(DISTINCT inventory_id) FROM inventory
UNION ALL
SELECT 'film_id duplicado',                    COUNT(*) - COUNT(DISTINCT film_id)     FROM film
UNION ALL
SELECT 'customer_id duplicado',                COUNT(*) - COUNT(DISTINCT customer_id) FROM customer;

/*
RESULTADO ESPERADO:
  - Todos os campos: 0 duplicatas
  Qualquer valor > 0 deve ser investigado antes de prosseguir.
*/


-- ============================================================
-- SEÇÃO 6: DISTRIBUIÇÃO DE CLIENTES ATIVOS E INATIVOS
-- Objetivo: Entender a base de clientes disponível para análise
--           e identificar quantos estão fora do escopo
-- ============================================================

SELECT
    activebool                           AS cliente_ativo,
    COUNT(*)                             AS total_clientes,
    ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM customer), 0), 2) AS pct_total
FROM customer
GROUP BY activebool
ORDER BY activebool DESC;

/*
RESULTADO ESPERADO:
  - ~584 clientes ativos (~97%)
  - ~15 clientes inativos (~3%)
  As análises de comportamento de clientes devem focar nos ativos.
*/


-- ============================================================
-- SEÇÃO 7: DISTRIBUIÇÃO DO ESTOQUE POR LOJA E CATEGORIA
-- Objetivo: Verificar se o estoque está distribuído de forma
--           razoável entre as lojas antes das análises de segmentação
-- ============================================================

SELECT
    s.store_id,
    cat.name                           AS categoria,
    COUNT(i.inventory_id)              AS total_copias
FROM inventory i
JOIN film f          ON i.film_id      = f.film_id
JOIN film_category fc ON f.film_id     = fc.film_id
JOIN category cat    ON fc.category_id = cat.category_id
JOIN store s         ON i.store_id     = s.store_id
GROUP BY s.store_id, cat.name
ORDER BY s.store_id, total_copias DESC;

/*
RESULTADO ESPERADO:
  - Ambas as lojas devem ter cópias em todas ou quase todas as 16 categorias
  - Distribuição não precisa ser 50/50 mas não deve ter desvio extremo
  - Categorias ausentes em uma loja devem ser anotadas em methodology.md
*/


-- ============================================================
-- SEÇÃO 8: RESUMO EXECUTIVO DA QUALIDADE DOS DADOS
-- Objetivo: Consolidar os principais indicadores de qualidade
--           em uma visão única para documentação
-- ============================================================

WITH base AS (
    SELECT
        (SELECT COUNT(*) FROM rental)                                        AS total_alugueis,
        (SELECT COUNT(*) FROM rental WHERE return_date IS NULL)              AS alugueis_sem_devolucao,
        (SELECT COUNT(*) FROM payment)                                       AS total_pagamentos,
        (SELECT COUNT(*) FROM payment WHERE rental_id IS NULL)               AS pagamentos_sem_aluguel,
        (SELECT COUNT(*) FROM rental r
            LEFT JOIN payment p ON r.rental_id = p.rental_id
            WHERE p.rental_id IS NULL)                                       AS alugueis_sem_pagamento,
        (SELECT COUNT(*) FROM customer WHERE activebool = true)              AS clientes_ativos,
        (SELECT COUNT(DISTINCT inventory_id) FROM rental)                    AS copias_com_movimento,
        (SELECT COUNT(*) FROM inventory)                                     AS total_copias
)
SELECT
    total_alugueis,
    alugueis_sem_devolucao,
    ROUND(alugueis_sem_devolucao * 100.0 / NULLIF(total_alugueis, 0), 2)    AS pct_sem_devolucao,
    total_pagamentos,
    pagamentos_sem_aluguel,
    ROUND(pagamentos_sem_aluguel * 100.0 / NULLIF(total_pagamentos, 0), 2)  AS pct_pagamentos_orfaos,
    alugueis_sem_pagamento,
    clientes_ativos,
    copias_com_movimento,
    total_copias - copias_com_movimento                                      AS copias_sem_movimento,
    ROUND((total_copias - copias_com_movimento) * 100.0
          / NULLIF(total_copias, 0), 2)                                      AS pct_estoque_parado
FROM base;

/*
RESULTADO ESPERADO:
  Este resumo alimenta diretamente a seção "Limitações dos dados" do README
  e a seção "Notas sobre Qualidade dos Dados" do data_dictionary.md.

INTERPRETAÇÃO:
  - pct_sem_devolucao > 5%: risco de sub-contagem de atrasos nas análises
  - pct_pagamentos_orfaos > 2%: receita potencialmente sub-contada
  - pct_estoque_parado > 15%: ineficiência de estoque a investigar na Seção 5
*/
