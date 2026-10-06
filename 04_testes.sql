-- =====================================================================
-- Barbearia — testes de integridade
-- Executar depois de 02_seed.sql
--
-- Cada bloco tenta gravar algo INVÁLIDO e espera que o banco recuse.
-- A mensagem "PASSOU" significa que a restrição funcionou e o dado
-- ruim não entrou. "FALHOU" significa que o banco aceitou algo que
-- não deveria — aí há um defeito no modelo.
--
-- É aqui que se demonstra a tese do projeto: as regras de negócio
-- estão no SGBD, não na aplicação. Nenhum programa precisa lembrar
-- delas, e nenhum erro de digitação passa por cima.
-- =====================================================================

\set ON_ERROR_STOP off

CREATE OR REPLACE FUNCTION espera_erro(descricao text, comando text)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE comando;
    RETURN 'FALHOU   -> ' || descricao || ' (o banco ACEITOU, mas deveria recusar)';
EXCEPTION WHEN others THEN
    RETURN 'PASSOU   -> ' || descricao || ' | recusado: ' || SQLERRM;
END;
$$;

\echo '===================== TESTES DE INTEGRIDADE ====================='
\echo ''

-- 1. Agenda -----------------------------------------------------------
SELECT espera_erro(
  'Horario sobreposto no mesmo barbeiro (14:00-15:00 sobre 14:00-14:40)',
  $$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
    VALUES (1, 1, '2026-09-15 14:00', '2026-09-15 15:00')$$);

SELECT espera_erro(
  'Sobreposicao parcial (14:30-15:10 invade 14:00-14:40)',
  $$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
    VALUES (2, 1, '2026-09-15 14:30', '2026-09-15 15:10')$$);

SELECT espera_erro(
  'Agendamento terminando antes de comecar',
  $$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
    VALUES (1, 2, '2026-11-01 10:00', '2026-11-01 09:00')$$);

SELECT espera_erro(
  'Status fora da lista permitida',
  $$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim, status)
    VALUES (1, 2, '2026-11-02 10:00', '2026-11-02 10:40', 'remarcado')$$);

SELECT espera_erro(
  'Agendamento para cliente inexistente',
  $$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
    VALUES (999, 1, '2026-11-03 10:00', '2026-11-03 10:40')$$);

-- 2. Cadastros --------------------------------------------------------
SELECT espera_erro(
  'Telefone de cliente repetido',
  $$INSERT INTO cliente (nome, telefone)
    VALUES ('Clone do Carlos', '(62) 99811-2034')$$);

SELECT espera_erro(
  'Servico com duracao zero',
  $$INSERT INTO servico (nome, duracao_min, preco)
    VALUES ('Servico instantaneo', 0, 10.00)$$);

SELECT espera_erro(
  'Produto com preco negativo',
  $$INSERT INTO produto (nome, categoria, preco_venda, qtd_estoque)
    VALUES ('Produto de brinde', 'Cabelo', -5.00, 1)$$);

-- 3. Vendas -----------------------------------------------------------
SELECT espera_erro(
  'Duas vendas para o mesmo agendamento',
  $$INSERT INTO venda (id_cliente, id_barbeiro, id_agendamento, forma_pagamento, valor_total)
    VALUES (1, 1, 1, 'pix', 50.00)$$);

SELECT espera_erro(
  'Forma de pagamento inexistente',
  $$INSERT INTO venda (id_cliente, id_barbeiro, forma_pagamento, valor_total)
    VALUES (1, 1, 'boleto', 50.00)$$);

SELECT espera_erro(
  'Mesmo produto duas vezes na mesma venda',
  $$INSERT INTO item_venda (id_venda, id_produto, quantidade, preco_unitario)
    VALUES (1, 1, 1, 39.90)$$);

SELECT espera_erro(
  'Item de venda com quantidade zero',
  $$INSERT INTO item_venda (id_venda, id_produto, quantidade, preco_unitario)
    VALUES (2, 4, 0, 44.90)$$);

SELECT espera_erro(
  'Estoque ficando negativo',
  $$UPDATE produto SET qtd_estoque = qtd_estoque - 1000 WHERE id_produto = 1$$);

SELECT espera_erro(
  'Apagar um cliente que tem historico de atendimento',
  $$DELETE FROM cliente WHERE id_cliente = 1$$);

SELECT espera_erro(
  'Apagar um barbeiro que tem historico (deveria usar ativo = false)',
  $$DELETE FROM barbeiro WHERE id_barbeiro = 3$$);

\echo ''
\echo '=== O QUE DEVE SER ACEITO ==='

-- Venda de balcao: sem cliente, sem barbeiro, sem agendamento.
-- As tres FKs ficam nulas, e isso é permitido de propósito.
INSERT INTO venda (forma_pagamento, valor_total) VALUES ('dinheiro', 29.90);
\echo 'OK -> venda de balcao sem cliente e sem agendamento aceita'

-- Varias vendas de balcao convivem: no PostgreSQL, UNIQUE aceita
-- multiplos NULL em id_agendamento.
INSERT INTO venda (forma_pagamento, valor_total) VALUES ('pix', 44.90);
\echo 'OK -> segunda venda de balcao aceita (UNIQUE permite varios NULL)'

-- Horario encostado, sem sobreposicao: 14:40 comeca exatamente quando
-- o anterior termina. Deve ser aceito.
INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
VALUES (4, 1, '2026-09-15 14:40', '2026-09-15 15:20');
\echo 'OK -> agendamento encostado no anterior aceito (14:40 apos 14:40)'

-- O mesmo horario em barbeiro DIFERENTE é livre.
INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
VALUES (1, 2, '2026-09-15 14:00', '2026-09-15 14:40');
\echo 'OK -> mesmo horario em outro barbeiro aceito'

-- Horario cancelado libera a vaga para outro cliente.
INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim, status)
VALUES (2, 2, '2026-12-01 09:00', '2026-12-01 09:40', 'cancelado');
INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
VALUES (3, 2, '2026-12-01 09:00', '2026-12-01 09:40');
\echo 'OK -> horario de um agendamento cancelado volta a ficar livre'

\echo ''
\echo '================== FIM DOS TESTES =================='

DROP FUNCTION espera_erro(text, text);
