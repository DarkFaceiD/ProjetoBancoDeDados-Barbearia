# Banco de dados de uma barbearia — PostgreSQL

Projeto de extensão universitária: modelagem e implementação de um banco relacional que substitui o controle em caderno e WhatsApp de uma barbearia de bairro por uma base única, com agendamento, vendas e estoque.

A ideia central é simples: **as regras de negócio ficam no banco, não na aplicação.** Nenhum programa precisa lembrar que dois clientes não podem marcar o mesmo horário com o mesmo barbeiro — o PostgreSQL recusa a gravação.

## O problema

A barbearia controlava tudo no papel, e daí vinham cinco falhas:

- dois clientes marcados no mesmo horário, descobertos só na hora do atendimento;
- faltas sem registro, sem saber quem falta nem quanto custa;
- venda de produto desconectada do atendimento, sem saber o que cada barbeiro faturou;
- estoque no olho, com produto acabando sem aviso;
- reajuste de preço apagando o valor realmente cobrado nos atendimentos antigos.

## O modelo

Oito tabelas em três blocos:

| Bloco | Tabelas |
|---|---|
| Cadastros | `cliente`, `barbeiro`, `servico`, `produto` |
| Agendamento | `agendamento`, `agendamento_servico` |
| Vendas | `venda`, `item_venda` |

Três decisões que valem explicação:

**Preço histórico.** `agendamento_servico.preco_cobrado` e `item_venda.preco_unitario` guardam o valor cobrado na hora, separado do preço atual do catálogo. Sem isso, um reajuste mudaria retroativamente o valor de vendas já fechadas.

**A venda é a comanda.** Uma venda pode cobrir um atendimento (`id_agendamento`) e também produtos levados no balcão. Como `id_agendamento` é `UNIQUE` e aceita nulo, cada atendimento gera no máximo uma conta, e vendas de balcão sem agendamento continuam cabendo — no PostgreSQL, `UNIQUE` permite vários nulos.

**Barbeiro não se apaga.** Quem sai vira `ativo = false`. As chaves estrangeiras não têm `CASCADE`, então o banco recusa apagar cliente, barbeiro ou serviço que tenha histórico.

## A trava de horário

É o diferencial técnico do projeto, e o motivo da escolha do PostgreSQL:

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE agendamento
    ADD CONSTRAINT agendamento_sem_sobreposicao
    EXCLUDE USING gist (
        id_barbeiro WITH =,
        tsrange(data_hora_inicio, data_hora_fim) WITH &&
    ) WHERE (status <> 'cancelado');
```

Um `UNIQUE (id_barbeiro, data_hora_inicio)` só impediria horários de início idênticos. A restrição `EXCLUDE` compara **intervalos**: 14h–15h e 14h30–15h também colidem, e o banco recusa. MySQL, SQL Server e SQLite exigiriam uma trigger escrita à mão para a mesma garantia.

Agendamentos cancelados ficam de fora da regra, então o horário volta a ficar livre.

## Como rodar

**Pré-requisito:** PostgreSQL 16 com a extensão `btree_gist` disponível (vem no pacote padrão e no Supabase).

### Local, com Docker

```bash
docker run --name barbearia -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16

psql -h localhost -U postgres -c "CREATE DATABASE barbearia;"
psql -h localhost -U postgres -d barbearia -f 01_schema.sql
psql -h localhost -U postgres -d barbearia -f 02_seed.sql
psql -h localhost -U postgres -d barbearia -f 03_consultas.sql
psql -h localhost -U postgres -d barbearia -f 04_testes.sql
```

### Em nuvem, no Supabase

Abra o **SQL Editor** do projeto e cole o conteúdo dos arquivos, na ordem numerada. O `CREATE EXTENSION btree_gist` já está no começo do `01_schema.sql` e funciona no plano gratuito.

Dois detalhes do SQL Editor: ele mostra apenas o resultado do **último** comando, então no `03_consultas.sql` convém selecionar uma consulta de cada vez com o mouse e clicar em Run — ele executa só o trecho selecionado. O `04_testes.sql` já devolve tudo numa tabela só, então basta colar e rodar inteiro.

## Os arquivos

| Arquivo | O que faz |
|---|---|
| `01_schema.sql` | Cria as 8 tabelas, as chaves, os `CHECK`, os `UNIQUE`, a restrição `EXCLUDE` e os índices |
| `02_seed.sql` | Carga de teste e uma consulta que confere se cada venda fecha |
| `03_consultas.sql` | Consultas gerenciais e exemplos de `INSERT`, `UPDATE` e `DELETE` |
| `04_testes.sql` | Tenta gravar dados inválidos e verifica que o banco recusa |

## Os testes

`04_testes.sql` é a prova de que o modelo se sustenta. Ele roda 20 verificações e devolve **uma única tabela** com o resultado de cada uma:

| # | Resultado | Grupo | O que foi testado | Resposta do banco |
|---|---|---|---|---|
| 1 | PASSOU | Agenda | Horario sobreposto no mesmo barbeiro | conflicting key value violates exclusion constraint "agendamento_sem_sobreposicao" |
| 6 | PASSOU | Cadastros | Telefone de cliente repetido | duplicate key value violates unique constraint "cliente_telefone_key" |
| 13 | PASSOU | Vendas | Estoque ficando negativo | new row for relation "produto" violates check constraint "produto_qtd_estoque_check" |
| 16 | PASSOU | Deve aceitar | Venda de balcao, sem cliente e sem agendamento | aceito, como esperado |

São **15 tentativas de gravar dados inválidos**, que o banco precisa recusar — horário sobreposto, preço negativo, telefone repetido, estoque negativo, apagar cliente com histórico — e **5 operações válidas**, que ele precisa aceitar: venda de balcão sem cliente, duas vendas de balcão ao mesmo tempo, agendamento encostado no anterior sem sobrepor, mesmo horário em outro barbeiro, e horário liberado depois de um cancelamento.

O script se limpa no fim, então pode ser executado várias vezes seguidas sempre com o mesmo resultado — o que importa numa demonstração ao vivo.

Testado no PostgreSQL 16.15: 20 de 20 passam.

## Consultas que o banco responde

Faturamento e ticket médio por barbeiro, serviços e produtos mais vendidos, clientes que mais faltam, produtos com estoque baixo, agenda do dia, horários ocupados de um barbeiro e uma conferência de caixa que aponta vendas cujo total não bate com a soma dos itens.

## Dados

Os dados de `02_seed.sql` são fictícios. Nomes, telefones e e-mails foram inventados para demonstração: nenhum dado real de cliente da barbearia está neste repositório, em linha com a LGPD (Lei nº 13.709/2018).

## Documentação completa

A documentação do projeto — introdução, objetivos, justificativa, metodologia, análise do local, cronograma e referências — está publicada no Medium:

**[Banco de dados em PostgreSQL para uma barbearia: agenda sem conflito e vendas integradas](https://medium.com/@edu2015pitaluga2011/banco-de-dados-em-postgresql-para-uma-barbearia-agenda-sem-conflito-e-vendas-integradas-37f59e4d7ccd)**

## Equipe

Eduardo · Danilo · Wandrey · Jeffry
Projeto de Extensão em Banco de Dados — Prof. Wanderson P. Medeiros
Outubro de 2026
