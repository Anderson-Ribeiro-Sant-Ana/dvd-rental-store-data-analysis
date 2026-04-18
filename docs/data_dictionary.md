# Dicionário de Dados — DVD Rental Store

> **Fonte:** PostgreSQL Sample Database — DVD Rental  
> **Período:** Maio a Agosto de 2005 + Fevereiro de 2006  
> **Granularidade:** Transação individual de aluguel  
> **Total de tabelas:** 15 tabelas de dados + 1 view  
> **Total de colunas documentadas:** 67  
> **Responsável:** Anderson Sana  

---

## Sumário

- [Tabelas do Projeto](#tabelas-do-projeto)
- [Grupo 1 — Transações (rental, payment)](#grupo-1--transações)
- [Grupo 2 — Produto (film, film_category, category, language)](#grupo-2--produto)
- [Grupo 3 — Estoque (inventory)](#grupo-3--estoque)
- [Grupo 4 — Cliente (customer, address, city, country)](#grupo-4--cliente)
- [Grupo 5 — Operação (store, staff)](#grupo-5--operação)
- [Grupo 6 — Elenco (actor, film_actor)](#grupo-6--elenco)
- [Métricas Derivadas Criadas no Projeto](#métricas-derivadas-criadas-no-projeto)
- [Notas sobre Qualidade dos Dados](#notas-sobre-qualidade-dos-dados)
- [Limitações e Caveats](#limitações-e-caveats)
- [Referências e Fontes](#referências-e-fontes)

---

## Tabelas do Projeto

| Tabela | Arquivo SQL Principal | Colunas-chave | Volume Aproximado |
|---|---|---|---|
| `rental` | `02_business_analysis.sql` | `rental_id`, `customer_id`, `inventory_id`, `rental_date`, `return_date` | 16.044 registros |
| `payment` | `02_business_analysis.sql` | `payment_id`, `customer_id`, `rental_id`, `amount`, `payment_date` | 14.596 registros |
| `inventory` | `05_segmentation.sql` | `inventory_id`, `film_id`, `store_id` | 4.581 registros |
| `film` | `02_business_analysis.sql` | `film_id`, `title`, `rental_rate`, `rental_duration`, `length` | 1.000 registros |
| `film_category` | `02_business_analysis.sql` | `film_id`, `category_id` | 1.000 registros |
| `category` | `02_business_analysis.sql` | `category_id`, `name` | 16 registros |
| `customer` | `03_customer_behavior.sql` | `customer_id`, `store_id`, `email`, `active` | 599 registros |
| `store` | `05_segmentation.sql` | `store_id`, `address_id`, `manager_staff_id` | 2 registros |
| `staff` | `05_segmentation.sql` | `staff_id`, `store_id` | 2 registros |
| `address` | — (referência geográfica) | `address_id`, `city_id`, `postal_code` | 603 registros |
| `city` | — (referência geográfica) | `city_id`, `country_id`, `city` | 600 registros |
| `country` | — (referência geográfica) | `country_id`, `country` | 109 registros |
| `actor` | `02_business_analysis.sql` | `actor_id`, `first_name`, `last_name` | 200 registros |
| `film_actor` | `02_business_analysis.sql` | `film_id`, `actor_id` | 5.462 registros |
| `language` | — (referência de produto) | `language_id`, `name` | 6 registros |

**Fluxo principal de JOIN:**
```
customer → rental → inventory → film → film_category → category
                ↓
            payment
```

---

## Grupo 1 — Transações

### Tabela: `rental`

| Coluna | Tipo SQL | Nulo? | Exemplo | Descrição | Observação |
|---|---|---|---|---|---|
| `rental_id` | INT (PK) | Não | 1 | Identificador único do aluguel | Chave primária; referenciada em `payment` |
| `rental_date` | TIMESTAMP | Não | 2005-05-24 22:54:33 | Data e hora em que o aluguel foi realizado | Base para análise temporal |
| `inventory_id` | INT (FK) | Não | 367 | Cópia física alugada | Referencia `inventory.inventory_id` |
| `customer_id` | INT (FK) | Não | 130 | Cliente que realizou o aluguel | Referencia `customer.customer_id` |
| `return_date` | TIMESTAMP | Sim | 2005-05-26 22:04:30 | Data e hora da devolução | **NULL indica aluguel ainda aberto ou não registrado** |
| `staff_id` | INT (FK) | Não | 1 | Atendente responsável pelo registro | Referencia `staff.staff_id` |
| `last_update` | TIMESTAMP | Não | 2006-02-15 21:30:53 | Data de última atualização do registro | Campo de controle interno; não usar em análise temporal |

### Tabela: `payment`

| Coluna | Tipo SQL | Nulo? | Exemplo | Descrição | Observação |
|---|---|---|---|---|---|
| `payment_id` | INT (PK) | Não | 17503 | Identificador único do pagamento | Chave primária |
| `customer_id` | INT (FK) | Não | 341 | Cliente que realizou o pagamento | Referencia `customer.customer_id` |
| `staff_id` | INT (FK) | Não | 2 | Atendente que registrou o pagamento | Referencia `staff.staff_id` |
| `rental_id` | INT (FK) | Sim | 1520 | Aluguel correspondente ao pagamento | **NULL em ~1.5% dos registros** — pagamentos sem aluguel identificado |
| `amount` | NUMERIC(5,2) | Não | 7.99 | Valor pago em dólares | Inclui possíveis multas por atraso (indistinguíveis do valor base) |
| `payment_date` | TIMESTAMP | Não | 2007-01-24 21:40:19 | Data e hora do pagamento | Datas de 2007 presentes — inconsistência com período de 2005/2006 |

---

## Grupo 2 — Produto

### Tabela: `film`

| Coluna | Tipo SQL | Nulo? | Exemplo | Descrição | Observação |
|---|---|---|---|---|---|
| `film_id` | INT (PK) | Não | 1 | Identificador único do filme | Chave primária |
| `title` | VARCHAR(255) | Não | ACADEMY DINOSAUR | Título do filme | Armazenado em maiúsculas |
| `description` | TEXT | Sim | A Epic Drama... | Sinopse do filme | Não utilizado nas análises |
| `release_year` | YEAR | Sim | 2006 | Ano de lançamento | Todos os filmes têm 2006; campo sem variação útil |
| `language_id` | INT (FK) | Não | 1 | Idioma do filme | Todos os filmes são idioma 1 (English); sem variação útil |
| `rental_duration` | SMALLINT | Não | 6 | Prazo de devolução em dias | Base para cálculo de atraso: `return_date - rental_date > rental_duration` |
| `rental_rate` | NUMERIC(4,2) | Não | 0.99 | Valor base do aluguel por período | Valores: 0.99, 2.99 ou 4.99 |
| `length` | SMALLINT | Sim | 86 | Duração do filme em minutos | Potencial variável para análise de correlação com atraso |
| `replacement_cost` | NUMERIC(5,2) | Não | 20.99 | Custo de reposição em caso de perda | Não presente em `payment`; não utilizado diretamente |
| `rating` | MPAA_RATING | Sim | PG | Classificação indicativa (G, PG, PG-13, R, NC-17) | Útil para segmentação de público-alvo |
| `special_features` | TEXT[] | Sim | {Trailers,Deleted Scenes} | Recursos especiais incluídos | Array PostgreSQL; não utilizado nas análises |
| `fulltext` | TSVECTOR | Não | — | Campo de busca textual gerado automaticamente | Campo técnico; não utilizado nas análises |
| `last_update` | TIMESTAMP | Não | 2006-02-15 | Campo de controle interno | Não usar em análise temporal |

### Tabela: `category`

| Coluna | Tipo SQL | Nulo? | Exemplo | Descrição |
|---|---|---|---|---|
| `category_id` | INT (PK) | Não | 1 | Identificador único da categoria |
| `name` | VARCHAR(25) | Não | Action | Nome da categoria/gênero do filme |
| `last_update` | TIMESTAMP | Não | — | Campo de controle interno |

**Categorias disponíveis (16):** Action, Animation, Children, Classics, Comedy, Documentary, Drama, Family, Foreign, Games, Horror, Music, New, Sci-Fi, Sports, Travel

### Tabela: `film_category`

| Coluna | Tipo SQL | Nulo? | Descrição |
|---|---|---|---|
| `film_id` | INT (FK, PK) | Não | Referencia `film.film_id` |
| `category_id` | INT (FK, PK) | Não | Referencia `category.category_id` |
| `last_update` | TIMESTAMP | Não | Campo de controle interno |

> Cada filme pertence a exatamente **uma** categoria. Cardinalidade: 1:1 entre `film` e `category` via esta tabela.

### Tabela: `language`

| Coluna | Tipo SQL | Nulo? | Descrição | Observação |
|---|---|---|---|---|
| `language_id` | INT (PK) | Não | Identificador do idioma | |
| `name` | CHAR(20) | Não | Nome do idioma | Todos os filmes registrados usam `language_id = 1` (English) |

---

## Grupo 3 — Estoque

### Tabela: `inventory`

| Coluna | Tipo SQL | Nulo? | Exemplo | Descrição | Observação |
|---|---|---|---|---|---|
| `inventory_id` | INT (PK) | Não | 1 | Identificador único da cópia física | Cada linha representa **uma cópia física** de um filme |
| `film_id` | INT (FK) | Não | 1 | Filme ao qual esta cópia pertence | Referencia `film.film_id` |
| `store_id` | INT (FK) | Não | 1 | Loja onde esta cópia está alocada | Valores: 1 ou 2 |
| `last_update` | TIMESTAMP | Não | — | Campo de controle interno | |

> **Nota de utilização:** A taxa de utilização do estoque é calculada como a proporção de `inventory_id` distintos que aparecem em pelo menos um registro de `rental` no período analisado.

---

## Grupo 4 — Cliente

### Tabela: `customer`

| Coluna | Tipo SQL | Nulo? | Exemplo | Descrição | Observação |
|---|---|---|---|---|---|
| `customer_id` | INT (PK) | Não | 1 | Identificador único do cliente | Chave primária |
| `store_id` | INT (FK) | Não | 1 | Loja de cadastro do cliente | Não necessariamente a loja onde aluga |
| `first_name` | VARCHAR(45) | Não | MARY | Primeiro nome | Armazenado em maiúsculas |
| `last_name` | VARCHAR(45) | Não | SMITH | Sobrenome | Armazenado em maiúsculas |
| `email` | VARCHAR(50) | Sim | mary.smith@sakilacustomer.org | E-mail do cliente | Domínio fictício; não deve ser usado para contato |
| `address_id` | INT (FK) | Não | 5 | Endereço do cliente | Referencia `address.address_id` |
| `activebool` | BOOLEAN | Não | true | Status ativo/inativo como booleano | Campo mais confiável que `active` |
| `create_date` | DATE | Não | 2006-02-14 | Data de cadastro do cliente | |
| `last_update` | TIMESTAMP | Sim | — | Campo de controle interno | |
| `active` | INT | Sim | 1 | Status ativo/inativo como inteiro (1=ativo, 0=inativo) | Usar `activebool` como referência primária |

### Tabelas de Endereço (`address`, `city`, `country`)

Utilizadas apenas para contextualização geográfica. Não fazem parte das análises principais.

| Tabela | Colunas Relevantes | Uso |
|---|---|---|
| `address` | `address_id`, `address`, `district`, `city_id`, `postal_code`, `phone` | Localização do cliente |
| `city` | `city_id`, `city`, `country_id` | Nome da cidade |
| `country` | `country_id`, `country` | Nome do país |

---

## Grupo 5 — Operação

### Tabela: `store`

| Coluna | Tipo SQL | Nulo? | Descrição |
|---|---|---|---|
| `store_id` | INT (PK) | Não | Identificador único da loja (valores: 1, 2) |
| `manager_staff_id` | INT (FK) | Não | Gerente responsável pela loja |
| `address_id` | INT (FK) | Não | Endereço físico da loja |
| `last_update` | TIMESTAMP | Não | Campo de controle interno |

### Tabela: `staff`

| Coluna | Tipo SQL | Nulo? | Descrição | Observação |
|---|---|---|---|---|
| `staff_id` | INT (PK) | Não | Identificador único do atendente | |
| `store_id` | INT (FK) | Não | Loja onde o atendente trabalha | |
| `first_name` | VARCHAR(45) | Não | Primeiro nome | |
| `last_name` | VARCHAR(45) | Não | Sobrenome | |
| `email` | VARCHAR(50) | Sim | E-mail do atendente | Fictício |
| `username` | VARCHAR(16) | Não | Login do sistema | |
| `active` | BOOLEAN | Não | Status ativo/inativo | |
| `password` | VARCHAR(40) | Sim | Hash da senha | **Não utilizar em análises** |
| `picture` | BYTEA | Sim | Foto do atendente | **Não utilizar em análises** |

---

## Grupo 6 — Elenco

### Tabela: `actor`

| Coluna | Tipo SQL | Nulo? | Descrição |
|---|---|---|---|
| `actor_id` | INT (PK) | Não | Identificador único do ator |
| `first_name` | VARCHAR(45) | Não | Primeiro nome |
| `last_name` | VARCHAR(45) | Não | Sobrenome |
| `last_update` | TIMESTAMP | Não | Campo de controle interno |

### Tabela: `film_actor`

| Coluna | Tipo SQL | Nulo? | Descrição |
|---|---|---|---|
| `actor_id` | INT (FK, PK) | Não | Referencia `actor.actor_id` |
| `film_id` | INT (FK, PK) | Não | Referencia `film.film_id` |
| `last_update` | TIMESTAMP | Não | Campo de controle interno |

> Cardinalidade: muitos-para-muitos. Um filme pode ter múltiplos atores e um ator pode estar em múltiplos filmes.

---

## Métricas Derivadas Criadas no Projeto

| Métrica | Fórmula SQL | Descrição | Arquivo de Origem |
|---|---|---|---|
| `dias_de_atraso` | `GREATEST(0, EXTRACT(DAY FROM (r.return_date - r.rental_date)) - f.rental_duration)` | Dias além do prazo contratado na devolução | `03_customer_behavior.sql` |
| `flag_atraso` | `CASE WHEN return_date IS NULL THEN NULL WHEN EXTRACT(DAY FROM (return_date - rental_date)) > rental_duration THEN 1 ELSE 0 END` | Flag binária: 1 = atrasado, 0 = no prazo, NULL = não devolvido | `03_customer_behavior.sql` |
| `ltv_cliente` | `SUM(p.amount) OVER (PARTITION BY p.customer_id)` | Receita total acumulada por cliente no período | `03_customer_behavior.sql` |
| `frequencia_cliente` | `COUNT(r.rental_id) OVER (PARTITION BY r.customer_id)` | Número total de aluguéis por cliente | `03_customer_behavior.sql` |
| `quadrante_cliente` | `CASE WHEN ltv >= mediana_ltv AND freq >= mediana_freq THEN 'Champions' ...` | Segmentação 2×2: LTV × Frequência | `03_customer_behavior.sql` |
| `participacao_receita_pct` | `SUM(amount) * 100.0 / NULLIF(SUM(SUM(amount)) OVER (), 0)` | Participação percentual de cada categoria na receita total | `02_business_analysis.sql` |
| `taxa_utilizacao_estoque_pct` | `COUNT(DISTINCT r.inventory_id) * 100.0 / NULLIF(COUNT(DISTINCT i.inventory_id), 0)` | % de cópias físicas com ao menos 1 aluguel no período | `05_segmentation.sql` |
| `crescimento_mom_pct` | `(receita_mes - LAG(receita_mes) OVER (ORDER BY mes)) * 100.0 / NULLIF(LAG(receita_mes) OVER (ORDER BY mes), 0)` | Variação percentual da receita mês a mês | `04_temporal_trends.sql` |
| `receita_acumulada` | `SUM(receita_mes) OVER (ORDER BY mes ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)` | Receita total acumulada ao longo do tempo | `04_temporal_trends.sql` |

---

## Notas sobre Qualidade dos Dados

### Completude

| Campo | Completude | Observação |
|---|---|---|
| `rental.return_date` | ~94% | ~6% dos registros com `return_date IS NULL` — tratados como abertos |
| `payment.rental_id` | ~98.5% | ~1.5% dos pagamentos sem `rental_id` correspondente |
| `film.length` | ~99% | Poucos registros com `length IS NULL` |
| `customer.email` | ~100% | Todos os clientes ativos têm e-mail registrado |

### Tratamento de Nulos

```sql
-- Aluguéis sem devolução registrada — excluídos do cálculo de atraso
WHERE r.return_date IS NOT NULL

-- Pagamentos sem aluguel correspondente — excluídos da análise de receita por aluguel
WHERE p.rental_id IS NOT NULL

-- Proteção contra divisão por zero em todas as métricas percentuais
ROUND(valor * 100.0 / NULLIF(total, 0), 2)
```

### Inconsistências Identificadas

- `payment.payment_date` contém datas de 2007 (ex: `2007-01-24`), fora do período principal de 2005/2006. Esses registros são incluídos na receita total mas sinalizam possível erro de sistema.
- `film.release_year` é 2006 para todos os 1.000 filmes — campo sem variação analítica útil.
- `film.language_id` é 1 (English) para todos os filmes — campo sem variação analítica útil.

---

## Limitações e Caveats

| # | Limitação | Impacto na Análise | Como Mitigar |
|---|---|---|---|
| 1 | Dados sintéticos gerados artificialmente | Padrões estatísticos podem ser mais uniformes que dados reais; conclusões não extrapoláveis para negócios reais | Tratar como exercício analítico; não extrapolar tendências |
| 2 | Cobertura temporal descontínua (mai–ago 2005 + fev 2006) | Impossível calcular sazonalidade anual ou tendência de longo prazo | Limitar análise temporal ao período disponível com aviso explícito |
| 3 | Multas por atraso indistinguíveis no campo `amount` | O valor de `payment.amount` pode incluir multa por atraso embutida, inflando o ticket médio de clientes inadimplentes | Não comparar ticket médio entre clientes com e sem histórico de atraso sem ressalva |
| 4 | Ausência de dados de custo e margem | Não é possível determinar lucratividade real por título, categoria ou loja | Análises de receita não implicam análises de lucro |
| 5 | Clientes cadastrados em uma loja podem alugar na outra | `customer.store_id` não representa onde o aluguel ocorreu; `rental.staff_id` é o correto para atribuição por loja | Usar `staff.store_id` via `rental.staff_id` para segmentação por loja, não `customer.store_id` |
| 6 | `return_date IS NULL` — causa desconhecida | Pode representar aluguel não devolvido, erro de sistema ou dado em aberto; afeta taxa de atraso | Tratar separadamente na análise de inadimplência; reportar como limitação |

---

## Referências e Fontes

| Fonte | URL | Tipo |
|---|---|---|
| PostgreSQL Sample Databases | https://www.postgresqltutorial.com/postgresql-getting-started/postgresql-sample-database/ | Dataset original |
| PostgreSQL 15 Documentation | https://www.postgresql.org/docs/15/ | Referência técnica SQL |
| Schema ERD | Disponível na documentação oficial do PostgreSQL Tutorial | Diagrama de entidade-relacionamento |
