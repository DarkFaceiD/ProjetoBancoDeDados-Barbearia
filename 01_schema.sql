-- =====================================================================
-- Barbearia — esquema do banco de dados
-- PostgreSQL 16
--
-- Projeto de extensão universitária.
-- Cria as 8 tabelas do modelo, com todas as regras de negócio
-- declaradas como restrições do próprio SGBD.
--
-- Ordem de execução: 01_schema -> 02_seed -> 03_consultas / 04_testes
-- =====================================================================

-- Necessária para a restrição EXCLUDE combinar igualdade (=) em
-- id_barbeiro com sobreposição (&&) de um intervalo de tempo.
-- Sem ela, o CREATE TABLE de AGENDAMENTO falha.
CREATE EXTENSION IF NOT EXISTS btree_gist;

DROP TABLE IF EXISTS item_venda, venda, agendamento_servico, agendamento,
                     produto, servico, barbeiro, cliente CASCADE;

-- ---------------------------------------------------------------------
-- CADASTROS
-- ---------------------------------------------------------------------

CREATE TABLE cliente (
    id_cliente    int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome          varchar(100) NOT NULL,
    -- Telefone é único porque é por ele que a barbearia localiza o
    -- cliente no balcão. Guardado como texto: tem parênteses e hífen,
    -- e um número apagaria zeros à esquerda.
    telefone      varchar(15)  NOT NULL UNIQUE,
    email         varchar(100),
    data_cadastro date         NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE barbeiro (
    id_barbeiro int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome        varchar(100) NOT NULL,
    telefone    varchar(15)  NOT NULL,
    -- Barbeiro que sai é desativado, nunca apagado: o histórico de
    -- atendimentos e vendas precisa continuar apontando para ele.
    ativo       boolean      NOT NULL DEFAULT true
);

CREATE TABLE servico (
    id_servico  int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome        varchar(60)   NOT NULL,
    duracao_min int           NOT NULL CHECK (duracao_min > 0),
    -- Preço ATUAL do serviço. O valor cobrado em cada atendimento fica
    -- em agendamento_servico.preco_cobrado.
    preco       numeric(10,2) NOT NULL CHECK (preco >= 0)
);

CREATE TABLE produto (
    id_produto  int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome        varchar(100)  NOT NULL,
    categoria   varchar(30)   NOT NULL,
    preco_venda numeric(10,2) NOT NULL CHECK (preco_venda >= 0),
    qtd_estoque int           NOT NULL DEFAULT 0 CHECK (qtd_estoque >= 0)
);

-- ---------------------------------------------------------------------
-- AGENDAMENTO
-- ---------------------------------------------------------------------

CREATE TABLE agendamento (
    id_agendamento   int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_cliente       int       NOT NULL REFERENCES cliente  (id_cliente),
    id_barbeiro      int       NOT NULL REFERENCES barbeiro (id_barbeiro),
    data_hora_inicio timestamp NOT NULL,
    -- Redundante em relação à soma das durações dos serviços, e isso é
    -- intencional: é a coluna que permite a restrição EXCLUDE abaixo.
    data_hora_fim    timestamp NOT NULL,
    status           varchar(10) NOT NULL DEFAULT 'agendado',

    CONSTRAINT agendamento_fim_depois_inicio
        CHECK (data_hora_fim > data_hora_inicio),
    CONSTRAINT agendamento_status_valido
        CHECK (status IN ('agendado','confirmado','concluido','cancelado','faltou'))
);

-- O coração do modelo: o banco recusa dois atendimentos do MESMO
-- barbeiro cujos intervalos se cruzem. Não é só horário de início
-- igual — 14:00-15:00 e 14:30-15:00 também é recusado.
-- Agendamentos cancelados ficam de fora: o horário volta a ficar livre.
ALTER TABLE agendamento
    ADD CONSTRAINT agendamento_sem_sobreposicao
    EXCLUDE USING gist (
        id_barbeiro WITH =,
        tsrange(data_hora_inicio, data_hora_fim) WITH &&
    ) WHERE (status <> 'cancelado');

CREATE TABLE agendamento_servico (
    id_agend_servico int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_agendamento   int NOT NULL REFERENCES agendamento (id_agendamento),
    id_servico       int NOT NULL REFERENCES servico     (id_servico),
    -- Preço HISTÓRICO: o valor cobrado naquele atendimento. Sem esta
    -- coluna, um reajuste no catálogo mudaria o valor de atendimentos
    -- já realizados.
    preco_cobrado    numeric(10,2) NOT NULL CHECK (preco_cobrado >= 0),

    -- O mesmo serviço não se repete no mesmo agendamento.
    CONSTRAINT agendamento_servico_unico UNIQUE (id_agendamento, id_servico)
);

-- ---------------------------------------------------------------------
-- VENDAS
-- ---------------------------------------------------------------------

CREATE TABLE venda (
    id_venda        int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Cliente e barbeiro são opcionais: cobrem a venda de balcão, em
    -- que alguém entra, compra uma pomada e vai embora.
    id_cliente      int REFERENCES cliente     (id_cliente),
    id_barbeiro     int REFERENCES barbeiro    (id_barbeiro),
    -- Opcional e único: um atendimento gera no máximo uma venda.
    -- No PostgreSQL, UNIQUE aceita vários NULL, então continuam
    -- cabendo quantas vendas de balcão forem necessárias.
    id_agendamento  int UNIQUE REFERENCES agendamento (id_agendamento),
    data_hora       timestamp     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    forma_pagamento varchar(20)   NOT NULL,
    valor_total     numeric(10,2) NOT NULL CHECK (valor_total >= 0),

    CONSTRAINT venda_forma_pagamento_valida
        CHECK (forma_pagamento IN ('dinheiro','pix','cartao_debito','cartao_credito'))
);

CREATE TABLE item_venda (
    id_item_venda  int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_venda       int NOT NULL REFERENCES venda   (id_venda),
    id_produto     int NOT NULL REFERENCES produto (id_produto),
    quantidade     int NOT NULL CHECK (quantidade > 0),
    -- Preço histórico, mesma lógica de agendamento_servico.
    preco_unitario numeric(10,2) NOT NULL CHECK (preco_unitario >= 0),

    -- Dois shampoos iguais viram quantidade = 2, não duas linhas.
    CONSTRAINT item_venda_produto_unico UNIQUE (id_venda, id_produto)
);

-- ---------------------------------------------------------------------
-- ÍNDICES DE APOIO ÀS CONSULTAS DO DIA A DIA
-- ---------------------------------------------------------------------

CREATE INDEX idx_agendamento_inicio  ON agendamento (data_hora_inicio);
CREATE INDEX idx_agendamento_cliente ON agendamento (id_cliente);
CREATE INDEX idx_venda_data          ON venda       (data_hora);
CREATE INDEX idx_venda_barbeiro      ON venda       (id_barbeiro);
CREATE INDEX idx_item_venda_produto  ON item_venda  (id_produto);
