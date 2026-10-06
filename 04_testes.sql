-- =====================================================================
-- Barbearia — testes de integridade
-- Executar depois de 02_seed.sql
--
-- Cada teste tenta uma operação e verifica se o banco reage como
-- deveria. Os de violação tentam gravar algo INVÁLIDO e esperam ser
-- recusados; os de permissão tentam algo VÁLIDO e esperam ser aceitos.
--
-- "PASSOU" = o banco se comportou como o modelo promete.
-- "FALHOU" = há um defeito no modelo.
--
-- É aqui que se demonstra a tese do projeto: as regras de negócio
-- estão no SGBD, não na aplicação. Nenhum programa precisa lembrar
-- delas, e nenhum erro de digitação passa por cima.
--
-- Roda tanto no psql quanto no SQL Editor do Supabase: selecione tudo
-- e execute. O resultado é uma única tabela com todos os testes.
-- =====================================================================

-- Espera que o comando seja RECUSADO pelo banco.
CREATE OR REPLACE FUNCTION espera_erro(descricao text, comando text)
RETURNS TABLE (resultado text, teste text, detalhe text)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE comando;
    RETURN QUERY SELECT 'FALHOU'::text, descricao,
                        'o banco ACEITOU, mas deveria recusar'::text;
EXCEPTION WHEN others THEN
    RETURN QUERY SELECT 'PASSOU'::text, descricao, SQLERRM::text;
END;
$$;

-- Espera que o comando seja ACEITO pelo banco.
CREATE OR REPLACE FUNCTION espera_sucesso(descricao text, comando text)
RETURNS TABLE (resultado text, teste text, detalhe text)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE comando;
    RETURN QUERY SELECT 'PASSOU'::text, descricao, 'aceito, como esperado'::text;
EXCEPTION WHEN others THEN
    RETURN QUERY SELECT 'FALHOU'::text, descricao,
                        ('o banco RECUSOU algo valido: ' || SQLERRM)::text;
END;
$$;

-- ---------------------------------------------------------------------
-- O relatório: uma linha por teste
-- ---------------------------------------------------------------------

WITH t AS (

  -- 1 a 5: regras da agenda ------------------------------------------
  SELECT 1 AS n, 'Agenda' AS grupo, * FROM espera_erro(
    'Horario sobreposto no mesmo barbeiro (14:00-15:00 sobre 14:00-14:40)',
    $q$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
       VALUES (1, 1, '2026-09-15 14:00', '2026-09-15 15:00')$q$)
  UNION ALL
  SELECT 2, 'Agenda', * FROM espera_erro(
    'Sobreposicao parcial (14:30-15:10 invade 14:00-14:40)',
    $q$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
       VALUES (2, 1, '2026-09-15 14:30', '2026-09-15 15:10')$q$)
  UNION ALL
  SELECT 3, 'Agenda', * FROM espera_erro(
    'Agendamento terminando antes de comecar',
    $q$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
       VALUES (1, 2, '2026-11-01 10:00', '2026-11-01 09:00')$q$)
  UNION ALL
  SELECT 4, 'Agenda', * FROM espera_erro(
    'Status fora da lista permitida',
    $q$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim, status)
       VALUES (1, 2, '2026-11-02 10:00', '2026-11-02 10:40', 'remarcado')$q$)
  UNION ALL
  SELECT 5, 'Agenda', * FROM espera_erro(
    'Agendamento para cliente inexistente',
    $q$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
       VALUES (999, 1, '2026-11-03 10:00', '2026-11-03 10:40')$q$)

  -- 6 a 8: regras dos cadastros --------------------------------------
  UNION ALL
  SELECT 6, 'Cadastros', * FROM espera_erro(
    'Telefone de cliente repetido',
    $q$INSERT INTO cliente (nome, telefone) VALUES ('Clone do Carlos', '(62) 99811-2034')$q$)
  UNION ALL
  SELECT 7, 'Cadastros', * FROM espera_erro(
    'Servico com duracao zero',
    $q$INSERT INTO servico (nome, duracao_min, preco) VALUES ('Servico instantaneo', 0, 10.00)$q$)
  UNION ALL
  SELECT 8, 'Cadastros', * FROM espera_erro(
    'Produto com preco negativo',
    $q$INSERT INTO produto (nome, categoria, preco_venda, qtd_estoque)
       VALUES ('Produto de brinde', 'Cabelo', -5.00, 1)$q$)

  -- 9 a 13: regras das vendas ----------------------------------------
  UNION ALL
  SELECT 9, 'Vendas', * FROM espera_erro(
    'Duas vendas para o mesmo agendamento',
    $q$INSERT INTO venda (id_cliente, id_barbeiro, id_agendamento, forma_pagamento, valor_total)
       VALUES (1, 1, 1, 'pix', 50.00)$q$)
  UNION ALL
  SELECT 10, 'Vendas', * FROM espera_erro(
    'Forma de pagamento inexistente',
    $q$INSERT INTO venda (id_cliente, id_barbeiro, forma_pagamento, valor_total)
       VALUES (1, 1, 'boleto', 50.00)$q$)
  UNION ALL
  SELECT 11, 'Vendas', * FROM espera_erro(
    'Mesmo produto duas vezes na mesma venda',
    $q$INSERT INTO item_venda (id_venda, id_produto, quantidade, preco_unitario)
       VALUES (1, 1, 1, 39.90)$q$)
  UNION ALL
  SELECT 12, 'Vendas', * FROM espera_erro(
    'Item de venda com quantidade zero',
    $q$INSERT INTO item_venda (id_venda, id_produto, quantidade, preco_unitario)
       VALUES (2, 4, 0, 44.90)$q$)
  UNION ALL
  SELECT 13, 'Vendas', * FROM espera_erro(
    'Estoque ficando negativo',
    $q$UPDATE produto SET qtd_estoque = qtd_estoque - 1000 WHERE id_produto = 1$q$)

  -- 14 e 15: preservacao do historico --------------------------------
  UNION ALL
  SELECT 14, 'Historico', * FROM espera_erro(
    'Apagar um cliente que tem historico de atendimento',
    $q$DELETE FROM cliente WHERE id_cliente = 1$q$)
  UNION ALL
  SELECT 15, 'Historico', * FROM espera_erro(
    'Apagar um barbeiro que tem historico (deveria usar ativo = false)',
    $q$DELETE FROM barbeiro WHERE id_barbeiro = 3$q$)

  -- 16 a 20: o que o banco DEVE aceitar ------------------------------
  UNION ALL
  SELECT 16, 'Deve aceitar', * FROM espera_sucesso(
    'Venda de balcao, sem cliente e sem agendamento',
    $q$INSERT INTO venda (forma_pagamento, valor_total) VALUES ('dinheiro', 29.90)$q$)
  UNION ALL
  SELECT 17, 'Deve aceitar', * FROM espera_sucesso(
    'Segunda venda de balcao (UNIQUE permite varios NULL)',
    $q$INSERT INTO venda (forma_pagamento, valor_total) VALUES ('pix', 44.90)$q$)
  UNION ALL
  SELECT 18, 'Deve aceitar', * FROM espera_sucesso(
    'Agendamento encostado no anterior, sem sobrepor (comeca as 14:40)',
    $q$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
       VALUES (4, 1, '2026-09-15 14:40', '2026-09-15 15:20')$q$)
  UNION ALL
  SELECT 19, 'Deve aceitar', * FROM espera_sucesso(
    'Mesmo horario em outro barbeiro',
    $q$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
       VALUES (1, 2, '2026-09-15 14:00', '2026-09-15 14:40')$q$)
  UNION ALL
  SELECT 20, 'Deve aceitar', * FROM espera_sucesso(
    'Horario de um agendamento cancelado volta a ficar livre',
    $q$INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim, status)
       VALUES (2, 2, '2026-12-01 09:00', '2026-12-01 09:40', 'cancelado');
       INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
       VALUES (3, 2, '2026-12-01 09:00', '2026-12-01 09:40')$q$)
)
SELECT n AS "#", resultado AS "Resultado", grupo AS "Grupo",
       teste AS "O que foi testado", detalhe AS "Resposta do banco"
  FROM t
 ORDER BY n;

-- ---------------------------------------------------------------------
-- Limpeza
-- ---------------------------------------------------------------------
-- Os testes 16 a 20 gravam de verdade, porque precisam provar que o
-- banco aceita. Sem desfazer isso, uma segunda execução acusaria falha
-- nos horários que a primeira já ocupou. Com a limpeza abaixo, o script
-- pode ser rodado quantas vezes quiser, sempre com o mesmo resultado —
-- o que importa numa demonstração ao vivo.

DELETE FROM venda
 WHERE id_cliente IS NULL
   AND id_barbeiro IS NULL
   AND id_agendamento IS NULL;

DELETE FROM agendamento
 WHERE (id_cliente, id_barbeiro, data_hora_inicio) IN (
         (4, 1, TIMESTAMP '2026-09-15 14:40'),
         (1, 2, TIMESTAMP '2026-09-15 14:00'),
         (2, 2, TIMESTAMP '2026-12-01 09:00'),
         (3, 2, TIMESTAMP '2026-12-01 09:00')
       );
