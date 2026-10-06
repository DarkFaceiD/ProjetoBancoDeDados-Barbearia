-- =====================================================================
-- Barbearia — consultas gerenciais e operações CRUD
-- Executar depois de 02_seed.sql
--
-- São as perguntas que o dono hoje não consegue responder com o
-- caderno. Cada uma vira uma consulta.
--
-- COMO RODAR
--   psql:     psql -d barbearia -f 03_consultas.sql   (mostra tudo)
--   Supabase: o SQL Editor exibe apenas o resultado do ÚLTIMO comando.
--             Selecione UMA consulta com o mouse e clique em Run —
--             ele executa só o trecho selecionado.
-- =====================================================================


-- =====================================================================
-- 1. Agenda do dia (substitui a folha do caderno)
-- =====================================================================
SELECT a.data_hora_inicio::time AS hora,
       b.nome                   AS barbeiro,
       c.nome                   AS cliente,
       string_agg(s.nome, ' + ' ORDER BY s.nome) AS servicos,
       a.status
  FROM agendamento a
  JOIN cliente  c ON c.id_cliente  = a.id_cliente
  JOIN barbeiro b ON b.id_barbeiro = a.id_barbeiro
  LEFT JOIN agendamento_servico asv ON asv.id_agendamento = a.id_agendamento
  LEFT JOIN servico s ON s.id_servico = asv.id_servico
 WHERE a.data_hora_inicio::date = DATE '2026-09-14'
 GROUP BY a.id_agendamento, a.data_hora_inicio, b.nome, c.nome, a.status
 ORDER BY a.data_hora_inicio;


-- =====================================================================
-- 2. Faturamento por barbeiro
-- =====================================================================
SELECT b.nome                        AS barbeiro,
       COUNT(v.id_venda)             AS vendas,
       SUM(v.valor_total)            AS faturamento,
       ROUND(AVG(v.valor_total), 2)  AS ticket_medio
  FROM venda v
  JOIN barbeiro b ON b.id_barbeiro = v.id_barbeiro
 GROUP BY b.nome
 ORDER BY faturamento DESC;


-- =====================================================================
-- 3. Serviços mais vendidos
-- =====================================================================
SELECT s.nome                 AS servico,
       COUNT(*)               AS vezes,
       SUM(asv.preco_cobrado) AS receita
  FROM agendamento_servico asv
  JOIN servico s ON s.id_servico = asv.id_servico
 GROUP BY s.nome
 ORDER BY vezes DESC, receita DESC;


-- =====================================================================
-- 4. Produtos mais vendidos
-- =====================================================================
SELECT p.nome                                 AS produto,
       SUM(iv.quantidade)                     AS unidades,
       SUM(iv.quantidade * iv.preco_unitario) AS receita
  FROM item_venda iv
  JOIN produto p ON p.id_produto = iv.id_produto
 GROUP BY p.nome
 ORDER BY unidades DESC;


-- =====================================================================
-- 5. Clientes que mais faltam
-- =====================================================================
SELECT c.nome,
       COUNT(*) FILTER (WHERE a.status = 'faltou')    AS faltas,
       COUNT(*)                                       AS agendamentos,
       ROUND(100.0 * COUNT(*) FILTER (WHERE a.status = 'faltou')
                   / NULLIF(COUNT(*), 0), 1)          AS pct_falta
  FROM agendamento a
  JOIN cliente c ON c.id_cliente = a.id_cliente
 GROUP BY c.nome
HAVING COUNT(*) FILTER (WHERE a.status = 'faltou') > 0
 ORDER BY faltas DESC;


-- =====================================================================
-- 6. Produtos com estoque baixo (menos de 20 unidades)
-- =====================================================================
SELECT nome, categoria, qtd_estoque
  FROM produto
 WHERE qtd_estoque < 20
 ORDER BY qtd_estoque;


-- =====================================================================
-- 7. Conferência de caixa: vendas cujo total não bate
-- =====================================================================
-- Enquanto o valor_total for digitado por quem fecha a conta, esta
-- consulta é a rede de segurança. Em produção, viraria uma trigger.
-- Resultado vazio = todas as vendas conferem.
SELECT v.id_venda, v.valor_total AS registrado,
       COALESCE(s.servicos,0) + COALESCE(p.produtos,0) AS calculado
  FROM venda v
  LEFT JOIN (SELECT id_agendamento, SUM(preco_cobrado) AS servicos
               FROM agendamento_servico GROUP BY id_agendamento) s
         ON s.id_agendamento = v.id_agendamento
  LEFT JOIN (SELECT id_venda, SUM(quantidade * preco_unitario) AS produtos
               FROM item_venda GROUP BY id_venda) p
         ON p.id_venda = v.id_venda
 WHERE v.valor_total <> COALESCE(s.servicos,0) + COALESCE(p.produtos,0);


-- =====================================================================
-- 8. Horários ocupados de um barbeiro num dia
-- =====================================================================
-- O que sobra entre as janelas está livre para encaixe.
SELECT b.nome                    AS barbeiro,
       a.data_hora_inicio::time  AS ocupado_de,
       a.data_hora_fim::time     AS ate
  FROM agendamento a
  JOIN barbeiro b ON b.id_barbeiro = a.id_barbeiro
 WHERE b.id_barbeiro = 1
   AND a.data_hora_inicio::date = DATE '2026-09-14'
   AND a.status <> 'cancelado'
 ORDER BY a.data_hora_inicio;


-- =====================================================================
-- CRUD — as quatro operações básicas
-- =====================================================================
-- ATENÇÃO: os comandos abaixo ALTERAM os dados. Rode depois das
-- consultas acima, ou recarregue o 02_seed.sql para voltar ao início.

-- INSERT: novo agendamento.
-- O banco recusa se o barbeiro já estiver ocupado nesse intervalo.
INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim)
VALUES (2, 1, '2026-10-20 09:00', '2026-10-20 09:40');

-- UPDATE: o cliente não compareceu.
UPDATE agendamento
   SET status = 'faltou'
 WHERE id_agendamento = 5;

-- DELETE: item lançado por engano na comanda, devolvendo ao estoque.
BEGIN;
  INSERT INTO item_venda (id_venda, id_produto, quantidade, preco_unitario)
  VALUES (1, 4, 1, 44.90);
  UPDATE produto SET qtd_estoque = qtd_estoque - 1 WHERE id_produto = 4;

  DELETE FROM item_venda WHERE id_venda = 1 AND id_produto = 4;
  UPDATE produto SET qtd_estoque = qtd_estoque + 1 WHERE id_produto = 4;
COMMIT;

-- Confere o efeito do UPDATE acima: agora há uma falta registrada.
SELECT c.nome, COUNT(*) FILTER (WHERE a.status = 'faltou') AS faltas
  FROM agendamento a
  JOIN cliente c ON c.id_cliente = a.id_cliente
 GROUP BY c.nome
HAVING COUNT(*) FILTER (WHERE a.status = 'faltou') > 0;
