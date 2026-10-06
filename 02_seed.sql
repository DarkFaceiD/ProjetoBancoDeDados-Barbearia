-- =====================================================================
-- Barbearia — carga de dados de teste
-- Executar depois de 01_schema.sql
--
-- Dados fictícios. Nomes, telefones e e-mails foram inventados para
-- demonstração; nenhum dado real de cliente é usado neste repositório.
--
-- A carga é coerente: o valor_total de cada venda é exatamente a soma
-- dos serviços do atendimento com os produtos levados, e o estoque
-- final bate com as saídas registradas.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Cadastros
-- ---------------------------------------------------------------------

INSERT INTO cliente (nome, telefone, email, data_cadastro) VALUES
  ('Carlos Mendes', '(62) 99811-2034', 'carlos.mendes@exemplo.com',  '2026-01-15'),
  ('Rafael Souza',  '(62) 99745-3310', 'rafael.souza@exemplo.com',   '2026-02-03'),
  ('Lucas Almeida', '(62) 98122-4587', 'lucas.almeida@exemplo.com',  '2026-03-21'),
  ('Pedro Costa',   '(62) 99230-7719', 'pedro.costa@exemplo.com',    '2026-05-08');

-- 3 barbeiros cadastrados, 2 atendendo hoje. Diego saiu da barbearia,
-- mas continua no banco: os atendimentos dele seguem no histórico.
INSERT INTO barbeiro (nome, telefone, ativo) VALUES
  ('João Batista',    '(62) 99101-1122', true),
  ('Marcos Vinícius', '(62) 99202-3344', true),
  ('Diego Ferreira',  '(62) 99303-5566', false);

INSERT INTO servico (nome, duracao_min, preco) VALUES
  ('Corte masculino', 40, 45.00),
  ('Barba',           30, 35.00),
  ('Corte + degradê', 50, 55.00),
  ('Sobrancelha',     15, 20.00);

-- Estoque inicial, antes das vendas abaixo.
INSERT INTO produto (nome, categoria, preco_venda, qtd_estoque) VALUES
  ('Pomada modeladora', 'Cabelo', 39.90, 28),
  ('Óleo para barba',   'Barba',  34.90, 20),
  ('Shampoo anticaspa', 'Cabelo', 29.90, 34),
  ('Balm pós-barba',    'Barba',  44.90, 14);

-- ---------------------------------------------------------------------
-- Agendamentos
-- ---------------------------------------------------------------------
-- data_hora_fim = início + duração do serviço contratado.
-- Nenhum barbeiro tem horários sobrepostos: se tivesse, a restrição
-- agendamento_sem_sobreposicao recusaria o INSERT.

INSERT INTO agendamento (id_cliente, id_barbeiro, data_hora_inicio, data_hora_fim, status) VALUES
  (1, 1, '2026-09-14 09:00', '2026-09-14 09:50', 'concluido'),
  (2, 2, '2026-09-14 10:00', '2026-09-14 10:30', 'concluido'),
  (3, 1, '2026-09-15 14:00', '2026-09-15 14:40', 'concluido'),
  (4, 3, '2026-09-16 16:30', '2026-09-16 17:20', 'concluido');

-- Serviços de cada atendimento.
-- Repare no agendamento 1: foi cobrado R$ 50,00 por um "Corte + degradê"
-- que hoje custa R$ 55,00. O preço subiu depois, e o histórico não muda.
INSERT INTO agendamento_servico (id_agendamento, id_servico, preco_cobrado) VALUES
  (1, 3, 50.00),
  (2, 2, 35.00),
  (3, 1, 45.00),
  (4, 3, 55.00);

-- ---------------------------------------------------------------------
-- Vendas (comandas) e seus produtos
-- ---------------------------------------------------------------------
-- valor_total = serviços do agendamento + produtos levados.

INSERT INTO venda (id_cliente, id_barbeiro, id_agendamento, data_hora, forma_pagamento, valor_total) VALUES
  (1, 1, 1, '2026-09-14 09:55', 'pix',            89.90),
  (2, 2, 2, '2026-09-14 10:35', 'cartao_credito', 99.80),
  (3, 1, 3, '2026-09-15 14:45', 'dinheiro',      189.60),
  (4, 3, 4, '2026-09-16 17:25', 'cartao_debito', 204.60);

INSERT INTO item_venda (id_venda, id_produto, quantidade, preco_unitario) VALUES
  (1, 1, 1, 39.90),
  (2, 2, 1, 34.90),
  (2, 3, 1, 29.90),
  (3, 1, 1, 39.90),
  (3, 3, 2, 29.90),   -- dois shampoos: quantidade 2, não duas linhas
  (3, 4, 1, 44.90),
  (4, 1, 1, 39.90),
  (4, 2, 1, 34.90),
  (4, 3, 1, 29.90),
  (4, 4, 1, 44.90);

-- Baixa de estoque correspondente às vendas acima.
-- Na operação real isso acontece na mesma transação da venda: se o
-- estoque ficasse negativo, o CHECK falharia e nada seria gravado.
UPDATE produto p
   SET qtd_estoque = p.qtd_estoque - v.vendido
  FROM (SELECT id_produto, SUM(quantidade) AS vendido
          FROM item_venda GROUP BY id_produto) v
 WHERE p.id_produto = v.id_produto;

COMMIT;

-- ---------------------------------------------------------------------
-- Conferência da carga
-- ---------------------------------------------------------------------

-- Cada venda deve bater: serviços + produtos = valor_total.
SELECT v.id_venda,
       v.valor_total                                   AS registrado,
       COALESCE(s.servicos, 0) + COALESCE(p.produtos, 0) AS calculado,
       CASE WHEN v.valor_total = COALESCE(s.servicos,0) + COALESCE(p.produtos,0)
            THEN 'OK' ELSE 'DIVERGENTE' END            AS conferencia
  FROM venda v
  LEFT JOIN (SELECT id_agendamento, SUM(preco_cobrado) AS servicos
               FROM agendamento_servico GROUP BY id_agendamento) s
         ON s.id_agendamento = v.id_agendamento
  LEFT JOIN (SELECT id_venda, SUM(quantidade * preco_unitario) AS produtos
               FROM item_venda GROUP BY id_venda) p
         ON p.id_venda = v.id_venda
 ORDER BY v.id_venda;
