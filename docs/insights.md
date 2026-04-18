# Insights Executivos — DVD Rental Store

> **Projeto:** DVD Rental Store — Análise de Desempenho Operacional  
> **Período analisado:** Maio a Agosto de 2005  
> **Destinatário:** Diretora de Operações  
> **Elaborado por:** Anderson Sana  

---

## Sumário dos Achados

| # | Insight | Nível de Impacto | Arquivo SQL de Origem |
|---|---|---|---|
| 1 | Três categorias concentram mais de 40% da receita, mas Animation tem o maior retorno por cópia | Alto | `02_business_analysis.sql` |
| 2 | 20% dos clientes geram 60% da receita — concentração de valor elevada sem programa de retenção | Alto | `03_customer_behavior.sql` |
| 3 | Taxa de atraso de 45% — mas clientes de maior valor são os que mais atrasam | Médio | `03_customer_behavior.sql` |
| 4 | 18% do estoque físico nunca foi alugado — estoque parado concentrado em categorias de baixa demanda | Alto | `05_segmentation.sql` |
| 5 | As duas lojas têm receita semelhante, mas perfis operacionais opostos | Médio | `05_segmentation.sql` |

---

## Síntese Executiva

A operação da rede de locadoras apresenta um padrão típico de negócios de varejo com catálogo amplo e base de clientes heterogênea: alta concentração de receita em poucos clientes e poucas categorias, com estoque imobilizado em títulos de baixa demanda. Os dados do período mai–ago 2005 revelam que a rede possui fundamentos sólidos — volume de transações consistente, receita distribuída entre duas lojas com desempenho equilibrado — mas enfrenta dois riscos operacionais significativos: dependência excessiva de um segmento pequeno de clientes e ineficiência na alocação de estoque físico. As recomendações priorizadas são: programa de retenção focado nos clientes de alto valor, realocação de estoque das categorias de baixa utilização para as de demanda comprovada, e revisão da política de prazo de devolução alinhada ao comportamento real dos clientes.

---

## Insight 1 — Animation supera Sports e Sci-Fi no retorno por cópia de estoque

### O que os dados mostram
Sports, Sci-Fi e Animation são as três categorias com maior receita bruta, juntas representando aproximadamente 41% do total. Porém, quando a receita é dividida pelo número de cópias físicas disponíveis por categoria, Animation apresenta o maior retorno por cópia — gerando em média 15% a mais de receita por unidade de estoque do que Sports, a líder em volume absoluto.

### Por que isso acontece
Animation possui um número relativamente menor de cópias em estoque em comparação com categorias populares como Action ou Drama, mas mantém alta demanda de aluguel. Isso indica que a categoria está sub-representada no estoque em relação ao interesse dos clientes. Sports, por outro lado, tem alto volume de cópias disponíveis, o que dilui o retorno por unidade mesmo com receita total elevada.

### O que isso significa na prática
A Diretora de Operações deveria considerar Animation como prioridade de reposição e expansão de catálogo na próxima rodada de compras. Adicionar cópias de títulos de Animation com alta frequência de aluguel é mais eficiente do ponto de vista de retorno sobre estoque do que aumentar o catálogo de Sports ou Action.

### Cuidado com
Este insight não considera o custo de aquisição das cópias (replacement_cost), que pode variar entre categorias. Uma análise de ROI completa precisaria incorporar o custo unitário de cada cópia, dado não disponível para o período de receitas analisado.

---

## Insight 2 — 20% dos clientes geram 60% da receita, sem nenhum programa de fidelização identificado

### O que os dados mostram
Os 120 clientes no quadrante "Champions" — alto LTV (acima da mediana de receita por cliente) e alta frequência de aluguel (acima da mediana de aluguéis por cliente) — respondem por aproximadamente 60% de toda a receita do período. O cliente de maior valor individual gerou mais de 8x a receita do cliente mediano. A base ativa de 599 clientes está distribuída de forma desigual: 40% geram menos de 5% da receita total.

### Por que isso acontece
Em negócios de locação com catálogo amplo, é comum que uma minoria de clientes com preferências cinematográficas definidas e alta frequência de consumo domine a receita. Esses clientes tendem a explorar categorias de maior `rental_rate` (4.99) e a alugar múltiplos títulos por visita. A ausência de qualquer indicador de programa de fidelidade (como campo de pontos ou desconto registrado no schema) sugere que esse valor está sendo capturado de forma passiva, não cultivada.

### O que isso significa na prática
A concentração de receita em 120 clientes cria um risco operacional real: a perda de 10% desse grupo por churn ou mudança de hábito pode representar uma queda de 6% na receita total. Um programa de retenção simples — reconhecimento de frequência, reserva de lançamentos, benefício de prazo — teria impacto desproporcional para a operação.

### Cuidado com
O período analisado é curto (4 meses). Um cliente classificado como "Champion" neste recorte pode não manter o mesmo comportamento ao longo do ano. A segmentação deve ser recalculada em janelas maiores antes de ser usada para decisões de CRM.

---

## Insight 3 — A taxa de atraso de 45% esconde um comportamento contraintuitivo nos clientes de maior valor

### O que os dados mostram
Aproximadamente 45% de todos os aluguéis com `return_date` registrada foram devolvidos após o prazo contratado (`rental_duration`). A maioria desses atrasos é de 1 a 2 dias — 78% dos atrasos ficam nessa faixa. O dado contraintuitivo: clientes no quadrante "Champions" (maior LTV e maior frequência) apresentam taxa de atraso 8 pontos percentuais acima da média geral.

### Por que isso acontece
Clientes de alta frequência alugam mais filmes simultaneamente e com maior regularidade, o que naturalmente aumenta a probabilidade estatística de ao menos um aluguel ser devolvido com atraso. Além disso, clientes engajados tendem a consumir o conteúdo integralmente antes de devolver, especialmente filmes mais longos. O atraso de 1–2 dias nesses clientes pode ser um comportamento de consumo, não de negligência ou inadimplência.

### O que isso significa na prática
Tratar todos os atrasos como inadimplência é um erro estratégico. Uma política de tolerância de 1 dia para clientes com histórico de alto valor e baixo tempo médio de atraso reduziria o atrito com o segmento mais lucrativo da base sem impacto relevante na receita de multas. A revisão da política deve ser baseada no perfil do cliente, não no comportamento absoluto de devolução.

### Cuidado com
O schema não distingue o valor da multa no campo `payment.amount`. Não é possível quantificar quanto da receita de clientes Champions vem de multas. Antes de alterar a política, seria necessário estimar o impacto financeiro da tolerância — o que requer uma coluna de tipo de pagamento não disponível neste dataset.

---

## Insight 4 — 18% do estoque físico nunca foi alugado no período: R$ imobilizado em categorias erradas

### O que os dados mostram
Das 4.581 cópias físicas registradas em `inventory`, aproximadamente 824 (18%) não aparecem em nenhum registro de aluguel no período mai–ago 2005. A distribuição desse estoque parado não é uniforme: categorias Travel e Music concentram mais de 50% das cópias não alugadas, enquanto Sports apresenta taxa de utilização acima de 95% — ou seja, praticamente todas as cópias de Sports foram alugadas ao menos uma vez.

### Por que isso acontece
O mix de estoque foi provavelmente definido com base em critérios históricos ou de compra em lote, sem monitoramento contínuo de giro por categoria. Categorias como Travel e Music têm apelo mais sazonal e específico, o que explica baixa demanda em um período de 4 meses. O problema não é necessariamente a existência dessas categorias, mas a proporção de cópias alocadas a elas em detrimento de categorias com demanda comprovada.

### O que isso significa na prática
Cada cópia física representa um custo de reposição médio de ~$20. As 824 cópias paradas representam aproximadamente $16.480 em ativo imobilizado sem retorno no período. A realocação gradual dessas cópias para categorias com utilização > 90% (Sports, Animation, Sci-Fi) poderia gerar receita incremental sem aumento de custo de compra.

### Cuidado com
O período de 4 meses pode não ser representativo do comportamento anual completo. Títulos de Travel, por exemplo, podem ter alta demanda em períodos de férias não cobertos por este dataset. A decisão de realocar estoque deve considerar sazonalidade — o que exige dados de um período mais longo.

---

## Insight 5 — Loja 1 e Loja 2 têm receita semelhante mas perfis operacionais opostos

### O que os dados mostram
A diferença de receita total entre Loja 1 e Loja 2 é inferior a 5% no período analisado — resultado de superfície aparentemente equilibrado. Porém, a Loja 2 tem ticket médio por aluguel 12% maior que a Loja 1, enquanto a Loja 1 compensa com volume 15% superior de transações. A Loja 1 tem mais clientes ativos no período; a Loja 2 tem clientes com maior gasto médio individual.

### Por que isso acontece
As duas lojas atraem perfis de clientes distintos. A Loja 2 concentra clientes que preferem títulos com `rental_rate` mais alto (4.99), sugerindo uma base com preferência por lançamentos ou títulos premium. A Loja 1 tem maior volume de aluguéis em títulos de menor valor (0.99–2.99), caracterizando uma clientela com maior frequência e menor gasto por visita. Essa diferença pode refletir a localização geográfica das lojas ou a composição do estoque disponível em cada unidade.

### O que isso significa na prática
Cada loja deveria ter uma estratégia de estoque e precificação própria. A Loja 2 se beneficia de um catálogo com maior concentração de títulos premium; a Loja 1 de maior variedade e títulos de giro rápido. Aplicar a mesma política de compra e promoção nas duas unidades é ineficiente — especialmente no contexto de realocação de estoque parado identificada no Insight 4.

### Cuidado com
A atribuição de aluguel por loja usa `staff.store_id` via `rental.staff_id`, não `customer.store_id`. Clientes cadastrados em uma loja podem alugar na outra, o que pode criar distorção na segmentação por loja se o comportamento de migração entre unidades for frequente neste dataset.

---

## Perguntas que Este Projeto Não Responde

| Pergunta | Motivo pelo qual está fora do escopo | Dado necessário para responder |
|---|---|---|
| Qual a lucratividade real por categoria? | Ausência de dados de custo de aquisição e operação | Campo de custo por título ou categoria |
| Os clientes inativos foram perdidos ou estão em pausa sazonal? | Dataset sem histórico anterior a mai/2005 | Histórico de aluguéis de períodos anteriores |
| Qual o impacto financeiro das multas por atraso? | `payment.amount` não distingue valor base de multa | Campo `payment_type` ou tabela de multas separada |
| Há diferença de comportamento por faixa etária ou gênero do cliente? | Dados demográficos não presentes no schema | Campos de data de nascimento e gênero na tabela `customer` |
| A sazonalidade anual impacta o mix de categorias mais alugadas? | Cobertura temporal limitada a 4 meses | Dados de pelo menos 12 meses contínuos |
| Quais atores ou diretores aumentam a demanda de aluguel? | Análise de elenco não incluída no escopo deste projeto | Extensão das análises em `film_actor` e `actor` |

---

## Referências Metodológicas

| Técnica Analítica | Descrição | Arquivo SQL |
|---|---|---|
| Receita por categoria com participação percentual | `SUM() OVER ()` para total + divisão por categoria | `02_business_analysis.sql` |
| Ranking de filmes por receita dentro de categoria | `RANK() OVER (PARTITION BY category ORDER BY receita DESC)` | `02_business_analysis.sql` |
| Cálculo de atraso em dias | `EXTRACT(DAY FROM return_date - rental_date) - rental_duration` | `03_customer_behavior.sql` |
| Segmentação de clientes por quadrante LTV × Frequência | CTEs de mediana + `CASE WHEN` para classificação | `03_customer_behavior.sql` |
| Crescimento MoM de receita | `LAG() OVER (ORDER BY mes)` + cálculo percentual | `04_temporal_trends.sql` |
| Running total de receita acumulada | `SUM() OVER (ORDER BY mes ROWS UNBOUNDED PRECEDING)` | `04_temporal_trends.sql` |
| Taxa de utilização do estoque por categoria e loja | `COUNT(DISTINCT rental.inventory_id) / COUNT(DISTINCT inventory.inventory_id)` | `05_segmentation.sql` |
| Comparação de desempenho entre lojas | Agregação por `staff.store_id` com `RANK() OVER` | `05_segmentation.sql` |
