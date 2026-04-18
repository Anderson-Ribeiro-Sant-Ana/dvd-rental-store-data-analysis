/*
============================================================
PROJETO  : DVD Rental Store — Análise de Desempenho Operacional
ARQUIVO  : 01_data_quality_check.sql
OBJETIVO : Auditoria de integridade dos dados antes de qualquer análise
AUTOR    : Anderson Sana
DATA     : 2025-04
BANCO    : MySQL 8.0+
============================================================
*/


-- ============================================================
-- SEÇÃO 1: VOLUME GERAL POR TABELA
-- Objetivo: Confirmar que o banco foi restaurado corretamente
-- ============================================================

SELECT 'rental'      AS tabela, COUNT(*) AS total_registros FROM rental
UNION ALL
SELECT 'payment',                COUNT(*) FROM payment
UNION ALL
SELECT 'inventory',              COUNT(*) FROM inventory
UNION ALL
SELECT 'film',                   COUNT(*) FROM film
UNION ALL
SELECT 'film_category',          COUNT(*) FROM film_category
UNION ALL
SELECT 'category',               COUNT(*) FROM category
UNION ALL
SELECT 'customer',               COUNT(*) FROM customer
UNION ALL
SELECT 'store',                  COUNT(*) FROM store
UNION ALL
SELECT 'staff',                  COUNT(*) FROM staff
UNION ALL
SELECT 'actor',                  COUNT(*) FROM actor
UNION ALL
SELECT 'film_actor',             COUNT(*) FROM film_actor
UNION ALL
SELECT 'address',                COUNT(*) FROM address
UNION ALL
SELECT 'city',                   COUNT(*) FROM city
UNION ALL
SELECT 'country',                COUNT(*) FROM country
ORDER BY total_registros DESC;

/*
RESULTADO ESPERADO:
  - rental: ~16.044 | payment: ~14.596 | inventory: ~4.581
  - film_actor: ~5.462 | film: ~1.000 | customer: ~599
*/


-- ============================================================
-- SEÇÃO 2: NULOS EM CAMPOS CRÍTICOS
-- ============================================================

SELECT
    'rental.return_date'   AS campo,
    COUNT(*)               AS total_nulos,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM rental), 2) AS pct_nulos
FROM rental
WHERE return_date IS NULL

UNION ALL

SELECT
    'payment.rental_id',
    COUNT(*),
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM payment), 2)
FROM payment
WHERE rental_id IS NULL

UNION ALL

SELECT
    'customer.email',
    COUNT(*),
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer), 2)
FROM customer
WHERE email IS NULL

UNION ALL

SELECT
    'film.length',
    COUNT(*),
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM film), 2)
FROM film
WHERE length IS NULL

UNION ALL

SELECT
    'film.rating',
    COUNT(*),
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM film), 2)
FROM film
WHERE rating IS NULL;

/*
RESULTADO ESPERADO:
  - rental.return_date: ~6% de nulos
  - payment.rental_id: ~1-2% de nulos
  - customer.email: 0%
*/


-- ============================================================
-- SEÇÃO 3: REGISTROS ÓRFÃOS — CHAVES SEM CORRESPONDÊNCIA
-- ============================================================

-- 3a. Aluguéis sem pagamento correspondente
SELECT
    'rental sem payment' AS anomalia,
    COUNT(*)             AS total
FROM rental r
LEFT JOIN payment p ON r.rental_id = p.rental_id
WHERE p.rental_id IS NULL;

-- 3b. Pagamentos sem aluguel correspondente
SELECT
    'payment sem rental' AS anomalia,
    COUNT(*)             AS total
FROM payment p
LEFT JOIN rental r ON p.rental_id = r.rental_id
WHERE r.rental_id IS NULL
  AND p.rental_id IS NOT NULL;

-- 3c. Itens de estoque sem filme correspondente
SELECT
    'inventory sem film' AS anomalia,
    COUNT(*)             AS total
FROM inventory i
LEFT JOIN film f ON i.film_id = f.film_id
WHERE f.film_id IS NULL;

-- 3d. Filmes sem categoria cadastrada
SELECT
    'film sem category' AS anomalia,
    COUNT(*)            AS total
FROM film f
LEFT JOIN film_category fc ON f.film_id = fc.film_id
WHERE fc.film_id IS NULL;

-- 3e. Aluguéis de clientes inativos
SELECT
    'aluguel de cliente inativo' AS anomalia,
    COUNT(*)                     AS total
FROM rental r
JOIN customer c ON r.customer_id = c.customer_id
WHERE c.active = 0;

/*
RESULTADO ESPERADO:
  - inventory sem film: 0
  - film sem category: 0
  - aluguel de cliente inativo: 0 ou próximo de 0
*/


-- ============================================================
-- SEÇÃO 4: INCONSISTÊNCIAS TEMPORAIS
-- ============================================================

-- 4a. Distribuição de aluguéis por ano e mês
SELECT
    DATE_FORMAT(rental_date, '%Y-%m') AS mes,
    COUNT(*)                          AS total_alugueis
FROM rental
GROUP BY DATE_FORMAT(rental_date, '%Y-%m')
ORDER BY mes;

-- 4b. Distribuição de pagamentos por ano
SELECT
    YEAR(payment_date)      AS ano,
    COUNT(*)                AS total_pagamentos,
    ROUND(SUM(amount), 2)   AS receita_total
FROM payment
GROUP BY YEAR(payment_date)
ORDER BY ano;

-- 4c. Devoluções com data anterior ao aluguel
SELECT
    rental_id,
    rental_date,
    return_date,
    DATEDIFF(return_date, rental_date) AS diferenca_dias
FROM rental
WHERE return_date IS NOT NULL
  AND return_date < rental_date;

-- 4d. Aluguéis com prazo de devolução acima de 30 dias
SELECT
    COUNT(*) AS alugueis_prazo_acima_30_dias
FROM rental
WHERE return_date IS NOT NULL
  AND DATEDIFF(return_date, rental_date) > 30;

/*
RESULTADO ESPERADO:
  - Aluguéis concentrados em mai–ago 2005 e fev 2006
  - Devoluções anteriores ao aluguel: 0
*/


-- ============================================================
-- SEÇÃO 5: DUPLICATAS EM CHAVES PRIMÁRIAS
-- ============================================================

SELECT 'rental_id duplicado'    AS verificacao, COUNT(*) - COUNT(DISTINCT rental_id)    AS duplicatas FROM rental
UNION ALL
SELECT 'payment_id duplicado',                  COUNT(*) - COUNT(DISTINCT payment_id)   FROM payment
UNION ALL
SELECT 'inventory_id duplicado',                COUNT(*) - COUNT(DISTINCT inventory_id) FROM inventory
UNION ALL
SELECT 'film_id duplicado',                     COUNT(*) - COUNT(DISTINCT film_id)      FROM film
UNION ALL
SELECT 'customer_id duplicado',                 COUNT(*) - COUNT(DISTINCT customer_id)  FROM customer;

/*
RESULTADO ESPERADO: todos os campos com 0 duplicatas
*/


-- ============================================================
-- SEÇÃO 6: DISTRIBUIÇÃO DE CLIENTES ATIVOS E INATIVOS
-- ============================================================

SELECT
    active                                                   AS cliente_ativo,
    COUNT(*)                                                 AS total_clientes,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer), 2) AS pct_total
FROM customer
GROUP BY active
ORDER BY active DESC;

/*
RESULTADO ESPERADO:
  - ~584 clientes ativos (~97%)
  - ~15 clientes inativos (~3%)
*/


-- ============================================================
-- SEÇÃO 7: DISTRIBUIÇÃO DO ESTOQUE POR LOJA E CATEGORIA
-- ============================================================

SELECT
    s.store_id,
    cat.name                    AS categoria,
    COUNT(i.inventory_id)       AS total_copias
FROM inventory i
JOIN film f          ON i.film_id      = f.film_id
JOIN film_category fc ON f.film_id     = fc.film_id
JOIN category cat    ON fc.category_id = cat.category_id
JOIN store s         ON i.store_id     = s.store_id
GROUP BY s.store_id, cat.name
ORDER BY s.store_id, total_copias DESC;


-- ============================================================
-- SEÇÃO 8: RESUMO EXECUTIVO DA QUALIDADE DOS DADOS
-- ============================================================

SELECT
    (SELECT COUNT(*) FROM rental)                                          AS total_alugueis,
    (SELECT COUNT(*) FROM rental WHERE return_date IS NULL)                AS alugueis_sem_devolucao,
    ROUND(
        (SELECT COUNT(*) FROM rental WHERE return_date IS NULL) * 100.0
        / NULLIF((SELECT COUNT(*) FROM rental), 0), 2)                    AS pct_sem_devolucao,
    (SELECT COUNT(*) FROM payment)                                         AS total_pagamentos,
    (SELECT COUNT(*) FROM payment WHERE rental_id IS NULL)                 AS pagamentos_sem_aluguel,
    ROUND(
        (SELECT COUNT(*) FROM payment WHERE rental_id IS NULL) * 100.0
        / NULLIF((SELECT COUNT(*) FROM payment), 0), 2)                   AS pct_pagamentos_orfaos,
    (SELECT COUNT(*) FROM customer WHERE active = 1)                       AS clientes_ativos,
    (SELECT COUNT(DISTINCT inventory_id) FROM rental)                      AS copias_com_movimento,
    (SELECT COUNT(*) FROM inventory)                                       AS total_copias,
    (SELECT COUNT(*) FROM inventory)
        - (SELECT COUNT(DISTINCT inventory_id) FROM rental)                AS copias_sem_movimento,
    ROUND(
        ((SELECT COUNT(*) FROM inventory)
            - (SELECT COUNT(DISTINCT inventory_id) FROM rental)) * 100.0
        / NULLIF((SELECT COUNT(*) FROM inventory), 0), 2)                 AS pct_estoque_parado;

/*
RESULTADO ESPERADO:
  - pct_sem_devolucao ~6%
  - pct_pagamentos_orfaos ~1-2%
  - pct_estoque_parado ~18%
*/
