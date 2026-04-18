# Metodologia — DVD Rental Store

> **Projeto:** DVD Rental Store — Análise de Desempenho Operacional  
> **Elaborado por:** Anderson Sana  
> **Última atualização:** Abril de 2025  

Este documento registra as decisões técnicas e analíticas tomadas ao longo do projeto — o que foi feito, por que foi feito assim e quais alternativas foram descartadas. Serve como rastreabilidade das escolhas metodológicas para qualquer pessoa que precise reproduzir, auditar ou expandir a análise.

---

## Sumário

- [Fonte e Restauração dos Dados](#1-fonte-e-restauração-dos-dados)
- [Atribuição de Aluguéis por Loja](#2-atribuição-de-aluguéis-por-loja)
- [Tratamento de return_date IS NULL](#3-tratamento-de-return_date-is-null)
- [Tratamento de payment_date em 2007](#4-tratamento-de-payment_date-em-2007)
- [Cálculo de Atraso na Devolução](#5-cálculo-de-atraso-na-devolução)
- [Critério de Segmentação de Clientes](#6-critério-de-segmentação-de-clientes)
- [Definição de LTV Simplificado](#7-definição-de-ltv-simplificado)
- [Critério de Utilização do Estoque](#8-critério-de-utilização-do-estoque)
- [Exclusão de Clientes Inativos](#9-exclusão-de-clientes-inativos)
- [Proteção contra Divisão por Zero](#10-proteção-contra-divisão-por-zero)

---

## 1. Fonte e Restauração dos Dados

**Decisão:** Usar o dataset oficial DVD Rental do PostgreSQL Tutorial sem nenhuma alteração nos dados originais.

**Por quê:** Dados originais nunca devem ser editados — princípio fundamental de rastreabilidade. Todas as transformações ocorrem nas queries SQL, não na fonte. A pasta `data/raw/` contém o arquivo `.tar` original; `data/processed/` ficaria reservada para eventuais exportações tratadas.

**Como restaurar:**
```bash
pg_restore -U postgres -d dvdrental dvdrental.tar
```

---

## 2. Atribuição de Aluguéis por Loja

**Decisão:** Atribuir cada aluguel à loja do atendente que registrou a transação (`rental.staff_id → staff.store_id`), não à loja de cadastro do cliente (`customer.store_id`).

**Por quê:** `customer.store_id` representa onde o cliente foi cadastrado, não onde ele alugou. Um cliente pode se cadastrar na Loja 1 e realizar todos os aluguéis na Loja 2. A atribuição correta para análise de receita por loja é sempre pela loja que processou a transação.

**Alternativa descartada:** Usar `customer.store_id` — introduziria distorção na segmentação de receita por loja.

**Query de referência:** `05_segmentation.sql` — todas as seções com JOIN em `staff`.

---

## 3. Tratamento de return_date IS NULL

**Decisão:** Excluir registros com `return_date IS NULL` dos cálculos de atraso e prazo de devolução. Incluí-los na contagem geral de aluguéis como volume total, mas não nos cálculos de taxa de inadimplência.

**Por quê:** Não é possível determinar se `return_date IS NULL` representa:
- Aluguel ainda em aberto na data de extração dos dados
- Filme não devolvido (perda)
- Falha no registro do sistema

Tratar como "atrasado" inflaria artificialmente a taxa de inadimplência. Tratar como "no prazo" a ignoraria completamente. A decisão mais honesta é segregar e reportar como limitação.

**Impacto quantificado:** ~6% dos aluguéis afetados. Taxa de atraso calculada apenas sobre os ~94% com devolução registrada.

**Cláusula usada:** `WHERE r.return_date IS NOT NULL`

---

## 4. Tratamento de payment_date em 2007

**Decisão:** Incluir os pagamentos com `payment_date` em 2007 no cálculo de receita total, mas sinalizá-los como anomalia na documentação.

**Por quê:** Excluí-los reduziria a receita total reportada sem justificativa de negócio clara — a transação ocorreu e o dinheiro foi recebido. A origem da inconsistência (erro de sistema, migração de dados) é desconhecida e não há evidência de que o valor seja inválido.

**Alternativa avaliada:** Filtrar apenas `payment_date` entre mai/2005 e dez/2006. Descartada por introduzir um corte arbitrário sem respaldo no negócio.

**Registro:** Documentado como limitação no `data_dictionary.md` e `README.md`.

---

## 5. Cálculo de Atraso na Devolução

**Decisão:** Calcular atraso como `EXTRACT(DAY FROM (return_date - rental_date)) - rental_duration`, onde `rental_duration` vem da tabela `film` (prazo contratado em dias para aquele título específico).

**Por quê:** O prazo varia por filme (valores: 3, 5, 6 ou 7 dias conforme `film.rental_duration`). Usar um prazo fixo único seria incorreto — um filme com prazo de 3 dias devolvido em 4 dias está atrasado, mas o mesmo intervalo para um filme de prazo 7 dias estaria no prazo.

**Limitação conhecida:** A subtração `return_date - rental_date` em PostgreSQL retorna um `INTERVAL`. O `EXTRACT(DAY FROM ...)` captura apenas a parte inteira dos dias, ignorando horas. Um aluguel de 6 dias e 23 horas seria contado como 6 dias — potencialmente favorecendo o cliente em poucos minutos de atraso. Aceito como trade-off de simplicidade.

**Query de referência:** `03_customer_behavior.sql` — Seções 4 e 5.

---

## 6. Critério de Segmentação de Clientes

**Decisão:** Segmentar clientes em 4 quadrantes usando a **mediana** de LTV e frequência como fronteira, não a média.

**Por quê:** A média é sensível a outliers — clientes com LTV muito alto ou muito baixo distorcem o ponto de corte. A mediana divide a base exatamente ao meio independentemente da distribuição, produzindo segmentos mais equilibrados e estáveis. Em análises de segmentação de clientes, a mediana é a prática padrão de mercado.

**Nomes dos segmentos e lógica:**
| Segmento | LTV | Frequência | Ação estratégica |
|---|---|---|---|
| Champions | ≥ mediana | ≥ mediana | Retenção prioritária |
| High Value | ≥ mediana | < mediana | Ativação de frequência |
| Frequent Low Value | < mediana | ≥ mediana | Upsell de ticket |
| At Risk | < mediana | < mediana | Monitoramento |

**Query de referência:** `03_customer_behavior.sql` — Seção 3; `06_summary_views.sql` — `vw_segmentacao_clientes`.

---

## 7. Definição de LTV Simplificado

**Decisão:** LTV calculado como `SUM(payment.amount)` por cliente no período disponível — sem projeção futura, sem desconto a valor presente, sem dedução de custos.

**Por quê:** O dataset não contém dados de custo operacional, custo de estoque por título ou margem. Qualquer cálculo de LTV "real" exigiria premissas não verificáveis. O LTV simplificado (receita bruta gerada) é honesto dentro das limitações dos dados e suficiente para ranqueamento e segmentação relativa entre clientes.

**Nomenclatura usada:** `ltv_total` em todas as queries para deixar claro que é o total do período, não uma projeção.

---

## 8. Critério de Utilização do Estoque

**Decisão:** Definir "cópia utilizada" como qualquer `inventory_id` que apareça em ao menos **um** registro na tabela `rental` dentro do período analisado.

**Por quê:** O objetivo é identificar estoque completamente parado — cópias que nunca saíram da prateleira. Uma cópia alugada uma única vez já prova sua relevância para a base de clientes; o foco da análise é o estoque com utilização zero, não o de baixa utilização.

**Limitação:** Uma cópia alugada 1 vez em 4 meses tem taxa de utilização idêntica a uma alugada 30 vezes na métrica binária. Para análise de intensidade de uso, seria necessário calcular frequência média de aluguel por cópia — não incluído neste escopo.

**Query de referência:** `05_segmentation.sql` — Seção 3; `06_summary_views.sql` — `vw_utilizacao_estoque_categoria`.

---

## 9. Exclusão de Clientes Inativos

**Decisão:** Filtrar `WHERE c.activebool = true` em todas as análises de comportamento de clientes.

**Por quê:** Clientes inativos (~15 registros, ~3% da base) têm histórico de transações que pode distorcer métricas de frequência e LTV se incluídos sem distinção. A análise de comportamento é relevante para decisões sobre a base atual — clientes inativos seriam objeto de uma análise de churn separada, fora do escopo deste projeto.

**Nota:** `activebool` (BOOLEAN) foi preferido sobre `active` (INT) por ser o campo mais confiável conforme documentado no `data_dictionary.md`.

---

## 10. Proteção contra Divisão por Zero

**Decisão:** Usar `NULLIF(denominador, 0)` em **todos** os cálculos percentuais e de médias derivadas, sem exceção.

**Por quê:** Em análises com filtros e segmentações, é possível que um denominador resulte em zero para subgrupos específicos (ex: categoria sem aluguéis em uma loja, mês sem pagamentos). Uma divisão por zero interrompe a query ou retorna resultado incorreto. `NULLIF` retorna `NULL` ao invés de erro, permitindo que a query complete e o analista identifique os casos problemáticos nos resultados.

**Padrão aplicado:**
```sql
ROUND(valor * 100.0 / NULLIF(total, 0), 2)
```

Aplicado consistentemente em todas as queries de todos os 6 arquivos SQL do projeto.
