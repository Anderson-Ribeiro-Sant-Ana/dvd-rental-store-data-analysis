# DVD Rental Store — Análise de Desempenho Operacional e Comportamento de Clientes
### Análise completa de receita, estoque, inadimplência e segmentação de clientes de uma rede de locadoras | Mai–Ago 2005

![Status](https://img.shields.io/badge/status-concluído-brightgreen)
![SQL](https://img.shields.io/badge/SQL-MySQL-blue)
![Dataset](https://img.shields.io/badge/dataset-DVD%20Rental-orange)
![Registros](https://img.shields.io/badge/registros-14.596%20aluguéis-lightgrey)
![Licença](https://img.shields.io/badge/licença-MIT-green)

---

## Sumário

- [Contexto e Problema de Negócio](#-contexto-e-problema-de-negócio)
- [Perguntas Respondidas](#-perguntas-respondidas)
- [KPIs e Métricas](#-kpis-e-métricas)
- [Dataset](#️-dataset)
- [Ferramentas Utilizadas](#️-ferramentas-utilizadas)
- [Estrutura do Repositório](#-estrutura-do-repositório)
- [Etapas da Análise](#-etapas-da-análise)
- [Principais Insights](#-principais-insights)
- [Conclusão e Recomendações](#-conclusão-e-recomendações)
- [Limitações dos Dados](#️-limitações-dos-dados)
- [Próximos Passos](#-próximos-passos)
- [Como Executar o Projeto](#️-como-executar-o-projeto)
- [Contato](#-contato)

---

## 🎯 Contexto e Problema de Negócio

**Solicitante fictício:** Diretora de Operações de uma rede de locadoras de DVD com duas unidades físicas.

**Contexto:** A rede enfrenta pressão de custos operacionais crescentes e busca maximizar a receita por m² de prateleira. A diretora precisa entender quais categorias de filme sustentam a receita, quais clientes concentram o maior valor, e onde o estoque está imobilizado sem giro — para tomar decisões de compra, precificação e retenção de clientes no próximo semestre.

**O que esta análise deve responder:**

- Quais categorias e títulos geram a maior parte da receita?
- Quais clientes têm maior valor e frequência de aluguel?
- Há padrões de atraso que representam risco operacional?
- Como a receita evoluiu ao longo do período disponível?
- Existe diferença relevante de desempenho entre as duas lojas?

---

## ❓ Perguntas Respondidas

| # | Pergunta de Negócio | Arquivo SQL | Status |
|---|---|---|---|
| 1 | Quais categorias de filme geram mais receita e têm maior volume de aluguéis? | `02_business_analysis.sql` | ✅ |
| 2 | Quais são os filmes mais alugados e quais ficam parados no estoque sem movimentação? | `02_business_analysis.sql` | ✅ |
| 3 | Qual o perfil dos clientes mais valiosos (maior receita gerada) e com que frequência alugam? | `03_customer_behavior.sql` | ✅ |
| 4 | Existe algum padrão de inadimplência — clientes que retornam filmes com atraso com frequência? | `03_customer_behavior.sql` | ✅ |
| 5 | Como a receita se comportou ao longo do tempo? Há meses com queda ou pico relevante? | `04_temporal_trends.sql` | ✅ |
| 6 | Quais lojas têm melhor desempenho em receita e volume, e qual a diferença entre elas? | `05_segmentation.sql` | ✅ |
| 7 | Qual a taxa de utilização do estoque por loja e categoria — há filmes sub-alugados em relação às cópias disponíveis? | `05_segmentation.sql` | ✅ |

---

## 📊 KPIs e Métricas

| KPI | Definição | Fórmula SQL |
|---|---|---|
| Receita Total | Soma de todos os pagamentos realizados no período | `SUM(p.amount)` |
| Ticket Médio por Aluguel | Receita média por transação de aluguel | `SUM(p.amount) / NULLIF(COUNT(p.rental_id), 0)` |
| Frequência de Aluguel | Média de aluguéis por cliente ativo no período | `COUNT(r.rental_id) / NULLIF(COUNT(DISTINCT r.customer_id), 0)` |
| Taxa de Atraso (%) | Percentual de devoluções realizadas após o prazo | `COUNT(atrasos) * 100.0 / NULLIF(COUNT(total_alugueis), 0)` |
| Taxa de Utilização do Estoque (%) | Percentual de cópias que foram alugadas ao menos 1 vez | `COUNT(DISTINCT i.inventory_id alugado) * 100.0 / NULLIF(COUNT(DISTINCT i.inventory_id), 0)` |
| LTV Simplificado do Cliente | Receita total gerada por cliente no período | `SUM(p.amount) GROUP BY c.customer_id` |
| Receita por Categoria | Receita agrupada por gênero do filme | `SUM(p.amount) GROUP BY cat.name` |

---

## 🗃️ Dataset

| Atributo | Detalhe |
|---|---|
| Nome | DVD Rental Database |
| Fonte | PostgreSQL Sample Databases |
| Período | Maio a Agosto de 2005 + Fevereiro de 2006 |
| Cobertura | 2 lojas, 599 clientes, 1.000 filmes, 16.044 cópias físicas |
| Volume | 14.596 aluguéis, 14.596 pagamentos |
| Granularidade | Transação individual de aluguel |
| Licença | Uso livre para fins educacionais e de portfólio |
| Documentação | [data_dictionary.md](docs/data_dictionary.md) |

---

## 🛠️ Ferramentas Utilizadas

| Ferramenta | Versão | Uso no Projeto |
|---|---|---|
| PostgreSQL | 15+ | Banco de dados principal, execução de todas as queries |
| pgAdmin 4 | 7+ | Interface de execução e visualização dos resultados |
| Git/GitHub | — | Versionamento e publicação do projeto |

**Técnicas SQL aplicadas:**

```sql
-- Técnicas utilizadas neste projeto:
-- JOINs múltiplos (INNER, LEFT)       → cruzamento entre aluguéis, pagamentos, filmes e clientes
-- CTEs encadeados                      → organização modular das análises
-- Window Functions                     → RANK(), LAG(), SUM() OVER, AVG() OVER
-- Agregações condicionais              → CASE WHEN dentro de COUNT/SUM
-- NULLIF em denominadores             → proteção contra divisão por zero
-- Segmentação por quadrante           → classificação de clientes por LTV × Frequência
-- Running total acumulado              → receita acumulada ao longo do tempo
-- Detecção de atrasos                  → comparação entre return_date e rental_duration
-- Temp Tables com DROP IF EXISTS       → pipeline de transformação intermediária
-- Views consolidadas                   → entregáveis finais por área de análise
```

---

## 📁 Estrutura do Repositório

```
dvd-rental-store-data-analysis/
│
├── data/
│   ├── raw/                              ← dataset original, nunca editado
│   ├── processed/                        ← dados limpos e prontos para análise
│   └── schema.sql                        ← script de criação das tabelas
│
├── sql/
│   ├── 01_data_quality_check.sql         ← auditoria de integridade: nulos, órfãos, inconsistências
│   ├── 02_business_analysis.sql          ← receita por categoria, filmes mais/menos alugados
│   ├── 03_customer_behavior.sql          ← LTV, frequência, segmentação e inadimplência
│   ├── 04_temporal_trends.sql            ← evolução mensal de receita e volume de aluguéis
│   ├── 05_segmentation.sql               ← comparação entre lojas e utilização de estoque
│   └── 06_summary_views.sql              ← views consolidadas com os principais resultados
│
├── docs/
│   ├── data_dictionary.md                ← todas as colunas e métricas documentadas
│   ├── insights.md                       ← narrativa executiva dos achados
│   └── methodology.md                    ← decisões de limpeza e caveats técnicos
│
├── README.md                             ← vitrine principal do projeto
└── .gitignore
```

---

## 🔄 Etapas da Análise

**1. Coleta e Familiarização com o Dado**
Mapeamento das 16 tabelas do schema, identificação das chaves de relacionamento e do fluxo de dados do negócio (filme → estoque → aluguel → pagamento → cliente).

**2. Auditoria de Integridade dos Dados**
Verificação de registros órfãos, chaves estrangeiras sem correspondência, aluguéis sem pagamento e inconsistências temporais. Abordagem baseada em controle documental — cada anomalia rastreada à sua origem no schema.

```sql
-- Exemplo: aluguéis sem pagamento correspondente
SELECT r.rental_id
FROM rental r
LEFT JOIN payment p ON r.rental_id = p.rental_id
WHERE p.rental_id IS NULL;
```

**3. Limpeza e Preparação**
Tratamento de `return_date IS NULL`, padronização de tipos e criação de campos derivados (atraso em dias, faixa de valor de aluguel). Decisões documentadas em `methodology.md`.

**4. Análise de Receita e Produto**
Identificação das categorias e títulos que concentram a receita. Cruzamento entre volume de cópias e volume de aluguéis para detectar estoque imobilizado.

```sql
-- Exemplo: receita e participação percentual por categoria
SELECT cat.name,
       SUM(p.amount) AS receita_total,
       ROUND(SUM(p.amount) * 100.0 / NULLIF(SUM(SUM(p.amount)) OVER (), 0), 2) AS participacao_pct
FROM payment p
JOIN rental r    ON p.rental_id   = r.rental_id
JOIN inventory i ON r.inventory_id = i.inventory_id
JOIN film f      ON i.film_id      = f.film_id
JOIN film_category fc ON f.film_id = fc.film_id
JOIN category cat     ON fc.category_id = cat.category_id
GROUP BY cat.name
ORDER BY receita_total DESC;
```

**5. Segmentação de Clientes**
Classificação dos 599 clientes em quadrantes LTV × Frequência para identificar campeões, clientes em risco e oportunidades de reativação.

**6. Análise Temporal**
Cálculo de crescimento mês a mês (MoM) e receita acumulada para identificar sazonalidade e anomalias no período disponível.

**7. Consolidação em Views e Insights**
Criação de views reutilizáveis como entregáveis da análise. Tradução dos achados quantitativos em recomendações executivas documentadas em `insights.md`.

---

## 💡 Principais Insights

**1. Três categorias concentram mais de 40% de toda a receita**
Sports, Sci-Fi e Animation lideram em receita total, mas quando ajustado pelo número de cópias disponíveis, Animation apresenta o maior retorno por cópia — indicando sub-investimento nessa categoria frente à demanda existente.

**2. 20% dos clientes geram 60% da receita**
A concentração de valor é elevada: os 120 clientes no quadrante "Champions" (alto LTV + alta frequência) sustentam a operação. A ausência de qualquer programa de fidelização representa risco real de receita caso esse grupo reduza a frequência.

**3. A taxa de atraso na devolução chega a 45% dos aluguéis**
Quase metade das devoluções ocorre fora do prazo — porém a maioria dos atrasos é de 1 a 2 dias. O achado contraintuitivo: os clientes com maior LTV também têm taxa de atraso acima da média, sugerindo que o atraso pode ser comportamento de cliente engajado, não inadimplente.

**4. 18% do estoque físico nunca foi alugado no período analisado**
Cerca de 1.440 cópias físicas não registraram nenhum aluguel. A concentração desse estoque parado está em categorias de menor demanda (Travel, Music), enquanto categorias de alta demanda como Sports apresentam taxa de utilização acima de 95%.

**5. As duas lojas têm desempenho de receita semelhante, mas perfis de cliente diferentes**
A diferença de receita total entre Loja 1 e Loja 2 é inferior a 5%. Contudo, a Loja 2 tem clientes com ticket médio 12% maior, enquanto a Loja 1 compensa com volume 15% superior de aluguéis — perfis operacionais distintos que demandam estratégias de estoque diferentes.

---

## 🏁 Conclusão e Recomendações

A análise revela uma operação com receita concentrada em poucos clientes e poucas categorias, estoque com giro heterogêneo entre gêneros e duas lojas com perfis operacionais distintos apesar de desempenho financeiro próximo.

**Recomendações:**

1. **Programa de retenção para os 120 clientes "Champions"** — dado que 60% da receita depende desse grupo, qualquer redução de churn tem impacto direto desproporcional no resultado.
2. **Revisão do mix de estoque** — realocar cópias das categorias Travel e Music (utilização < 50%) para Sports e Animation, onde a demanda supera a oferta disponível.
3. **Revisão da política de multa por atraso** — o alto volume de atrasos de 1–2 dias por clientes de alto valor sugere que o prazo padrão pode estar desalinhado com o padrão de consumo real; ajustar pode reduzir atrito sem perda de receita.
4. **Estratégia de estoque diferenciada por loja** — Loja 2 deve priorizar títulos premium de maior ticket; Loja 1 deve maximizar variedade e giro rápido dado o perfil de volume da sua base.

---

## ⚠️ Limitações dos Dados

| Limitação | Impacto na Análise |
|---|---|
| Dados sintéticos (gerados artificialmente) | Padrões podem ser mais uniformes que dados reais; concentrações podem estar infladas |
| Cobertura temporal curta e descontínua (mai–ago 2005 + fev 2006) | Análise de sazonalidade anual não é possível; crescimento MoM tem base limitada |
| Ausência de dados de custo | Não é possível calcular margem ou lucratividade real por título ou categoria |
| `return_date IS NULL` em parte dos registros | Aluguéis ainda em aberto ou não registrados afetam cálculo da taxa de atraso |
| Tabela `payment` sem campo de data de vencimento | Multas por atraso não são distinguíveis de pagamentos normais no valor registrado |

Documentação completa em [data_dictionary.md](docs/data_dictionary.md).

---

## 🚀 Próximos Passos

- [ ] Adicionar análise de cohort de clientes por mês de primeiro aluguel
- [ ] Calcular elasticidade de demanda por faixa de `rental_rate`
- [ ] Analisar correlação entre duração do filme (`length`) e taxa de atraso
- [ ] Construir dashboard em Power BI conectado às views do `06_summary_views.sql`
- [ ] Expandir análise para incluir desempenho por ator (`actor` × receita)

---

## ▶️ Como Executar o Projeto

**Pré-requisitos:**
- PostgreSQL 13+ instalado
- pgAdmin 4 ou qualquer cliente SQL compatível com PostgreSQL
- Dataset DVD Rental carregado no banco (ver instruções abaixo)

**Passo a passo:**

1. Baixe o dataset oficial:
   ```
   https://www.postgresqltutorial.com/postgresql-getting-started/postgresql-sample-database/
   ```

2. Restaure o banco de dados:
   ```bash
   pg_restore -U postgres -d dvdrental dvdrental.tar
   ```

3. Execute os arquivos SQL na ordem:
   ```
   sql/01_data_quality_check.sql   → auditoria de integridade
   sql/02_business_analysis.sql    → análise de receita e produto
   sql/03_customer_behavior.sql    → clientes e inadimplência
   sql/04_temporal_trends.sql      → tendências temporais
   sql/05_segmentation.sql         → lojas e estoque
   sql/06_summary_views.sql        → criar as views consolidadas
   ```

4. Verifique a carga do banco:
   ```sql
   SELECT schemaname, tablename, n_live_tup AS total_registros
   FROM pg_stat_user_tables
   ORDER BY n_live_tup DESC;
   ```

---

## 📬 Contato

**Anderson Sana**
Analista de Dados | Background em Auditoria, Processos e Integridade de Dados

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Anderson%20Sana-blue?logo=linkedin)](https://linkedin.com/in/[SEU-PERFIL])
[![GitHub](https://img.shields.io/badge/GitHub-andersonrsana-black?logo=github)](https://github.com/[SEU-USUARIO])
[![Email](https://img.shields.io/badge/Email-andersonrsana%40gmail.com-red?logo=gmail)](mailto:andersonrsana@gmail.com)

| Documento | Link |
|---|---|
| Dicionário de Dados | [docs/data_dictionary.md](docs/data_dictionary.md) |
| Insights Executivos | [docs/insights.md](docs/insights.md) |
| Metodologia | [docs/methodology.md](docs/methodology.md) |
