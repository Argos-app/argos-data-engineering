--create database dbArgos;

create EXTENSION if not exists pgcrypto;
-- gerar o uuid aleatório


-- tabelas de identidade e acesso


create table permission
(
    id          UUID primary key     default gen_random_uuid(),
    code        VARCHAR(30) not null unique,
    name        VARCHAR(40) not null,
    description TEXT,
    active      BOOLEAN     not null default true,
    constraint ck_permission_code check (code = UPPER(code))
);

create table app_user
(
    id            UUID primary key      default gen_random_uuid(),
    permission_id UUID         not null references permission (id) on delete restrict,
    name          VARCHAR(120) not null,
    cpf           CHAR(11)     not null unique,
    email         VARCHAR(120) not null unique,
    active        BOOLEAN      not null default true,
    first_login   BOOLEAN               default true,
    created_at    TIMESTAMP    not null default current_timestamp,
    updated_at    TIMESTAMP    not null default current_timestamp,
    constraint ck_app_user_cpf check (cpf ~ '^[0-9]{11}$'),
    constraint ck_app_user_email check (email like '%_@_%._%')
);

create table property
(
    id            UUID primary key      default gen_random_uuid(),
    user_id       UUID         not null references app_user (id) on delete restrict,
    name          VARCHAR(120) not null,
    cnpj          CHAR(14),
    address       VARCHAR(255) not null,
    city          VARCHAR(100) not null,
    state         CHAR(2)      not null,
    area_hectares NUMERIC(10, 2),
    phone         VARCHAR(20),
    source_id     INTEGER,
    active        BOOLEAN      not null default true,
    created_at    TIMESTAMP    not null default current_timestamp,
    constraint ck_property_cnpj check (cnpj is null or cnpj ~ '^[0-9]{14}$'),
    constraint ck_property_area check (area_hectares is null or area_hectares > 0)
);


create table user_property
(
    user_id     UUID    not null references app_user (id) on delete cascade,
    property_id UUID    not null references property (id) on delete cascade,
    link_date   DATE    not null default current_date,
    unlink_date DATE,
    active      BOOLEAN not null default true,
    primary key (user_id, property_id),
    constraint ck_user_property_datas check (unlink_date is null or unlink_date >= link_date)
);

create table device
(
    id         UUID primary key      default gen_random_uuid(),
    user_id    UUID         not null references app_user (id) on delete cascade,
    push_token VARCHAR(255) not null unique,
    platform   VARCHAR(10)  not null,
    model      VARCHAR(60),
    last_sync  TIMESTAMP,
    active     BOOLEAN      not null default true,
    created_at TIMESTAMP    not null default current_timestamp,
    constraint ck_device_platform check (platform in ('ANDROID', 'IOS'))
);


-- tabelas legadas do 1o ano (rpa)


create table herd
(
    id          UUID primary key     default gen_random_uuid(),
    property_id UUID        not null references property (id) on delete restrict,
    herd_name   VARCHAR(60) not null,
    breed       VARCHAR(40) not null,
    head_count  INTEGER     not null default 0,
    source_id   INTEGER,
    active      BOOLEAN     not null default true,
    created_at  TIMESTAMP   not null default current_timestamp,
    updated_at  TIMESTAMP   not null default current_timestamp,
    constraint uq_herd_nome unique (property_id, herd_name),
    constraint ck_herd_count check (head_count >= 0)
);



create table lot
(
    id                     UUID primary key     default gen_random_uuid(),
    herd_id                UUID        not null references herd (id) on delete restrict,
    parent_lot_id          UUID        references lot (id) on delete set null,
    lot_code               VARCHAR(20) not null,
    category               VARCHAR(30) not null,
    is_exception_lot       BOOLEAN     not null default false,
    head_count             INTEGER     not null default 0,
    slaughter_release_date DATE,
    fit_for_slaughter      BOOLEAN     not null default true,
    open_date              DATE        not null default current_date,
    close_date             DATE,
    active                 BOOLEAN     not null default true,
    created_at             TIMESTAMP   not null default current_timestamp,
    updated_at             TIMESTAMP   not null default current_timestamp,
    constraint uq_lot_code unique (herd_id, lot_code),
    constraint ck_lot_datas check (close_date is null or close_date >= open_date),
    constraint ck_lot_count check (head_count >= 0),
    constraint ck_lot_nao_ciclo check (parent_lot_id is null or parent_lot_id <> id),
    constraint ck_lot_excecao check (is_exception_lot = false or parent_lot_id is not null)
);



create table animal_exception
(
    id                     UUID primary key      default gen_random_uuid(),
    lot_id                 UUID         not null references lot (id) on delete restrict,
    origin_lot_id          UUID         not null references lot (id) on delete restrict,
    ear_tag                VARCHAR(20)  not null,
    category               VARCHAR(20)  not null,
    birth_date             DATE,
    current_weight         NUMERIC(7, 2),
    exception_date         DATE         not null default current_date,
    exception_reason       VARCHAR(255) not null,
    slaughter_release_date DATE,
    fit_for_slaughter      BOOLEAN      not null default true,
    status                 VARCHAR(15)  not null default 'ATIVO',
    source_id              INTEGER,
    created_at             TIMESTAMP    not null default current_timestamp,
    updated_at             TIMESTAMP    not null default current_timestamp,
    constraint ck_animal_exception_status check (status in ('ATIVO', 'VENDIDO', 'ABATIDO', 'MORTO', 'RECUPERADO')),
    constraint ck_animal_exception_peso check (current_weight is null or current_weight > 0),
    constraint ck_animal_exception_nascto check (birth_date is null or birth_date <= current_date)
);

create table supplier
(
    id           UUID primary key      default gen_random_uuid(),
    company_name VARCHAR(120) not null,
    cnpj         CHAR(14)     not null unique,
    email        VARCHAR(120),
    phone        VARCHAR(20),
    address      VARCHAR(255),
    source_id    INTEGER,
    active       BOOLEAN      not null default true,
    created_at   TIMESTAMP    not null default current_timestamp,
    updated_at   TIMESTAMP    not null default current_timestamp,
    constraint ck_supplier_cnpj check (cnpj ~ '^[0-9]{14}$')
);

create table therapeutic_category
(
    id          UUID primary key default gen_random_uuid(),
    name        VARCHAR(40) not null unique,
    description TEXT
);

create table medicine
(
    id                      UUID primary key        default gen_random_uuid(),
    supplier_id             UUID           not null references supplier (id) on delete restrict,
    therapeutic_category_id UUID           not null references therapeutic_category (id) on delete restrict,
    brand_name              VARCHAR(80)    not null,
    active_ingredient       VARCHAR(80)    not null,
    mapa_registration       VARCHAR(20),
    indication              TEXT           not null,
    description             TEXT,
    needs_prescription      BOOLEAN        not null default false,
    meat_withdrawal_days    INTEGER        not null default 0,
    dose                    NUMERIC(10, 3) not null,
    unit                    VARCHAR(10)    not null,
    route                   VARCHAR(20)    not null,
    source_id               INTEGER,
    active                  BOOLEAN        not null default true,
    created_at              TIMESTAMP      not null default current_timestamp,
    updated_at              TIMESTAMP      not null default current_timestamp,
    constraint ck_medicine_carencia check (meat_withdrawal_days >= 0),
    constraint ck_medicine_dose check (dose > 0),
    constraint ck_medicine_unit check (unit in ('ml', 'mg', 'g', 'UI', 'dose')),
    constraint ck_medicine_route check (route in ('INTRAMUSCULAR', 'SUBCUTANEA', 'ORAL', 'TOPICA', 'INTRAVENOSA'))
);

create table medicine_batch
(
    id               UUID primary key        default gen_random_uuid(),
    medicine_id      UUID           not null references medicine (id) on delete restrict,
    batch_number     VARCHAR(30)    not null,
    manufacture_date DATE           not null,
    expiry_date      DATE           not null,
    delivery_date    DATE           not null,
    initial_quantity NUMERIC(10, 3) not null,
    storage_place    VARCHAR(60),
    status           VARCHAR(15)    not null default 'DISPONIVEL',
    source_id        INTEGER,
    created_at       TIMESTAMP      not null default current_timestamp,
    updated_at       TIMESTAMP      not null default current_timestamp,
    constraint uq_medicine_batch unique (medicine_id, batch_number),
    constraint ck_medicine_batch_qt check (initial_quantity > 0),
    constraint ck_medicine_batch_dt check (expiry_date > manufacture_date),
    constraint ck_medicine_batch_st check (status in ('DISPONIVEL', 'VENCIDO', 'ESGOTADO', 'RECOLHIDO'))
);

-- tabels operacionais
create table application
(
    id                  UUID primary key        default gen_random_uuid(),
    lot_id              UUID           not null references lot (id) on delete restrict,
    medicine_batch_id   UUID           not null references medicine_batch (id) on delete restrict,
    user_id             UUID           not null references app_user (id) on delete restrict,
    application_date    DATE           not null default current_date,
    application_time    TIME,
    dose                NUMERIC(10, 3) not null,
    unit                VARCHAR(10)    not null,
    route               VARCHAR(20)    not null,
    head_count_applied  INTEGER        not null,
    meat_withdrawal_end DATE,
    goal                VARCHAR(120),
    notes               TEXT,
    synced_at           TIMESTAMP,
    created_at          TIMESTAMP      not null default current_timestamp,
    constraint ck_application_dose check (dose > 0),
    constraint ck_application_count check (head_count_applied > 0),
    constraint ck_application_data check (application_date <= current_date)
);


create table application_animal
(
    id                     UUID primary key        default gen_random_uuid(),
    application_id         UUID           not null references application (id) on delete cascade,
    animal_exception_id    UUID           not null references animal_exception (id) on delete restrict,
    dose_given             NUMERIC(10, 3) not null,
    weight_at_time         NUMERIC(7, 2),
    meat_withdrawal_end    DATE,
    released_for_slaughter BOOLEAN        not null default false,
    created_at             TIMESTAMP      not null default current_timestamp,
    constraint uq_application_animal unique (application_id, animal_exception_id),
    constraint ck_application_animal_dose check (dose_given > 0)
);

create table stock_movement
(
    id                UUID primary key        default gen_random_uuid(),
    medicine_batch_id UUID           not null references medicine_batch (id) on delete restrict,
    application_id    UUID           references application (id) on delete set null,
    user_id           UUID           not null references app_user (id) on delete restrict,
    type              CHAR(1)        not null,
    quantity          NUMERIC(10, 3) not null,
    movement_date     TIMESTAMP      not null default current_timestamp,
    reason            VARCHAR(60)    not null,
    created_at        TIMESTAMP      not null default current_timestamp,
    constraint ck_stock_movement_type check (type in ('E', 'S')),
    constraint ck_stock_movement_qt check (quantity > 0)
);

create table occurrence
(
    id                  UUID primary key     default gen_random_uuid(),
    animal_exception_id UUID        not null references animal_exception (id) on delete restrict,
    user_id             UUID        not null references app_user (id) on delete restrict,
    type                VARCHAR(20) not null,
    occurrence_date     DATE        not null default current_date,
    description         TEXT        not null,
    diagnosis           TEXT,
    resolved            BOOLEAN     not null default false,
    resolved_at         DATE,
    created_at          TIMESTAMP   not null default current_timestamp,
    constraint ck_occurrence_type check (type in ('DOENCA', 'MORTE', 'REACAO_ADVERSA', 'FERIMENTO')),
    constraint ck_occurrence_resolved check (resolved = false or resolved_at is not null)
);


create table animal_lot_history
(
    id                  UUID primary key     default gen_random_uuid(),
    animal_exception_id UUID        not null references animal_exception (id) on delete cascade,
    lot_id              UUID        not null references lot (id) on delete restrict,
    entry_date          DATE        not null default current_date,
    exit_date           DATE,
    reason              VARCHAR(60) not null,
    created_at          TIMESTAMP   not null default current_timestamp,
    constraint ck_animal_lot_history_datas check (exit_date is null or exit_date >= entry_date)
);

create table alert
(
    id                  UUID primary key      default gen_random_uuid(),
    user_id             UUID         not null references app_user (id) on delete cascade,
    lot_id              UUID references lot (id) on delete cascade,
    animal_exception_id UUID references animal_exception (id) on delete cascade,
    type                VARCHAR(30)  not null,
    severity            VARCHAR(10)  not null default 'MEDIA',
    title               VARCHAR(120) not null,
    message             TEXT         not null,
    created_at          TIMESTAMP    not null default current_timestamp,
    read_at             TIMESTAMP,
    status              VARCHAR(15)  not null default 'NOVO',
    constraint ck_alert_type check (type in ('CARENCIA', 'VALIDADE', 'ESTOQUE_BAIXO', 'OCORRENCIA')),
    constraint ck_alert_severity check (severity in ('BAIXA', 'MEDIA', 'ALTA')),
    constraint ck_alert_status check (status in ('NOVO', 'LIDO', 'RESOLVIDO'))
);

create table notification_delivery
(
    id        UUID primary key     default gen_random_uuid(),
    alert_id  UUID        not null references alert (id) on delete cascade,
    device_id UUID        not null references device (id) on delete cascade,
    channel   VARCHAR(15) not null,
    status    VARCHAR(15) not null default 'PENDENTE',
    attempts  INTEGER     not null default 0,
    sent_at   TIMESTAMP,
    error     TEXT,
    constraint ck_notification_channel check (channel in ('PUSH', 'SMS', 'EMAIL')),
    constraint ck_notification_status check (status in ('PENDENTE', 'ENVIADO', 'FALHOU'))
);


create table attachment
(
    id         UUID primary key      default gen_random_uuid(),
    user_id    UUID         not null references app_user (id) on delete restrict,
    entity     VARCHAR(30)  not null,
    entity_id  UUID         not null,
    type       VARCHAR(20)  not null,
    file_path  VARCHAR(255) not null,
    file_hash  CHAR(64)     not null,
    size_bytes INTEGER      not null,
    created_at TIMESTAMP    not null default current_timestamp,
    constraint ck_attachment_type check (type in ('FOTO_BRINCO', 'BULA', 'NOTA_FISCAL', 'LAUDO', 'RECEITA')),
    constraint ck_attachment_size check (size_bytes > 0)
);

-- auditoria e monitoramento de carga

create table change_audit
(
    id          UUID primary key     default gen_random_uuid(),
    table_name  VARCHAR(60) not null,
    operation   CHAR(6)     not null,
    record_id   VARCHAR(40) not null,
    old_data    JSONB,
    new_data    JSONB,
    db_user     VARCHAR(60) not null,
    app_user_id UUID,
    ip_address  INET,
    happened_at TIMESTAMP   not null default current_timestamp,
    constraint ck_change_audit_op check (operation in ('INSERT', 'UPDATE', 'DELETE'))
);

create table access_audit
(
    id             UUID primary key      default gen_random_uuid(),
    user_id        UUID         references app_user (id) on delete set null,
    login_tried    VARCHAR(120) not null,
    success        BOOLEAN      not null,
    failure_reason VARCHAR(60),
    ip_address     INET,
    user_agent     VARCHAR(255),
    happened_at    TIMESTAMP    not null default current_timestamp,
    constraint ck_access_audit_motivo check (
        failure_reason is null or failure_reason in
                                  ('SENHA_ERRADA', 'CONTA_BLOQUEADA', 'USUARIO_INEXISTENTE', 'TOKEN_INVALIDO')
        )
);


create table interaction_audit
(
    id                  UUID primary key     default gen_random_uuid(),
    user_id             UUID        not null references app_user (id) on delete cascade,
    device_id           UUID        references device (id) on delete set null,
    action_type         VARCHAR(20) not null,
    element_type        VARCHAR(20) not null,
    element_id          VARCHAR(60) not null,
    element_name        VARCHAR(60) not null,
    element_description VARCHAR(120),
    created_at          TIMESTAMP   not null default current_timestamp,
    constraint ck_interaction_action check (action_type in ('CLIQUE', 'ENTRAR_TELA', 'SAIR_TELA', 'OCULTAR', 'SCROLL')),
    constraint ck_interaction_element check (element_type in ('BOTAO', 'ACTIVITY', 'FRAGMENT', 'CAMPO', 'LISTA'))
);

create table daily_access
(
    id               UUID primary key     default gen_random_uuid(),
    user_id          UUID        not null references app_user (id) on delete cascade,
    date             DATE        not null default current_date,
    source           VARCHAR(10) not null,
    session_count    INTEGER     not null default 1,
    first_login_time TIMESTAMP   not null default current_timestamp,
    constraint uq_daily_access unique (user_id, date, source),
    constraint ck_daily_access_src check (source in ('WEB', 'MOBILE', 'API'))
);

create table data_catalog
(
    id               UUID primary key     default gen_random_uuid(),
    table_name       VARCHAR(60) not null,
    column_name      VARCHAR(60) not null,
    data_type        VARCHAR(30) not null,
    description      TEXT        not null,
    business_rule    TEXT,
    access_level     VARCHAR(15) not null default 'INTERNO',
    personal_data    BOOLEAN     not null default false,
    lgpd_legal_basis VARCHAR(60),
    updated_at       TIMESTAMP   not null default current_timestamp,
    constraint uq_data_catalog unique (table_name, column_name),
    constraint ck_data_catalog_nivel check (access_level in ('PUBLICO', 'INTERNO', 'RESTRITO', 'SENSIVEL')),
    constraint ck_data_catalog_lgpd check (personal_data = false or lgpd_legal_basis is not null)
);


create table load_run
(
    id            UUID primary key     default gen_random_uuid(),
    routine_name  VARCHAR(60) not null,
    source        VARCHAR(40) not null,
    start_time    TIMESTAMP   not null default current_timestamp,
    end_time      TIMESTAMP,
    rows_read     INTEGER     not null default 0,
    rows_inserted INTEGER     not null default 0,
    rows_updated  INTEGER     not null default 0,
    rows_rejected INTEGER     not null default 0,
    status        VARCHAR(15) not null default 'EXECUTANDO',
    loaded_until  TIMESTAMP,
    message       TEXT,
    constraint ck_load_run_status check (status in ('EXECUTANDO', 'SUCESSO', 'ERRO', 'PARCIAL'))
);


create table load_error
(
    id               UUID primary key      default gen_random_uuid(),
    load_run_id      UUID         not null references load_run (id) on delete cascade,
    source_table     VARCHAR(60)  not null,
    natural_key      VARCHAR(120) not null,
    original_content JSONB        not null,
    error_message    TEXT         not null,
    attempts         INTEGER      not null default 1,
    reprocessed      BOOLEAN      not null default false
);


create table load_mapping
(
    id          UUID primary key      default gen_random_uuid(),
    table_name  VARCHAR(60)  not null,
    source_id   VARCHAR(40)  not null,
    target_id   UUID         not null,
    natural_key VARCHAR(120) not null,
    load_date   TIMESTAMP    not null default current_timestamp,
    constraint uq_load_mapping unique (table_name, source_id)
);


create table load_staging
(
    id             UUID primary key   default gen_random_uuid(),
    load_run_id    UUID      not null references load_run (id) on delete cascade,
    source_columns TEXT      not null,
    row_hash       CHAR(64)  not null,
    processed      BOOLEAN   not null default false,
    extract_date   TIMESTAMP not null default current_timestamp
);

-- indices


create index idx_application_carencia
    on application (meat_withdrawal_end)
    where meat_withdrawal_end is not null;


create unique index idx_animal_exception_lot_ear_tag
    on animal_exception (lot_id, ear_tag);


create index idx_change_audit_tabela_data
    on change_audit (table_name, happened_at);


create index idx_stock_movement_lote_data
    on stock_movement (medicine_batch_id, movement_date);

create index idx_application_lot_data on application (lot_id, application_date);
create index idx_lot_parent on lot (parent_lot_id);
create index idx_interaction_user_data on interaction_audit (user_id, created_at);
create index idx_access_audit_user_data on access_audit (user_id, happened_at);

-- functions


create or replace FUNCTION fn_data_fim_carencia(p_medicine_id UUID, p_data DATE)
    returns DATE as
$$
DECLARE
    v_dias INTEGER;
begin
    select meat_withdrawal_days into v_dias from medicine where id = p_medicine_id;

    if v_dias is null then
        raise EXCEPTION 'Medicamento % nao encontrado', p_medicine_id;
    end if;

    return p_data + v_dias;
end;
$$ language plpgsql;


create or replace FUNCTION fn_lote_apto_abate(p_lot_id UUID, p_data DATE default current_date)
    returns BOOLEAN as
$$
begin
    return not exists (select 1
                       from application
                       where lot_id = p_lot_id
                         and meat_withdrawal_end > p_data);
end;
$$ language plpgsql;


create or replace FUNCTION fn_saldo_medicine_batch(p_batch_id UUID)
    returns NUMERIC as
$$
DECLARE
    v_saldo NUMERIC(10, 3);
begin
    select COALESCE(SUM(case when type = 'E' then quantity else -quantity end), 0)
    into v_saldo
    from stock_movement
    where medicine_batch_id = p_batch_id;

    return v_saldo;
end;
$$ language plpgsql;


create or replace FUNCTION fn_tentativas_falhas(p_user_id UUID)
    returns INTEGER as
$$
DECLARE
    v_ultimo_sucesso TIMESTAMP;
    v_tentativas     INTEGER;
begin
    select MAX(happened_at)
    into v_ultimo_sucesso
    from access_audit
    where user_id = p_user_id
      and success;

    select COUNT(*)
    into v_tentativas
    from access_audit
    where user_id = p_user_id
      and not success
      and (v_ultimo_sucesso is null or happened_at > v_ultimo_sucesso);

    return v_tentativas;
end;
$$ language plpgsql;

-- triggers
create or replace FUNCTION fn_atualiza_data()
    returns trigger as
$$
begin
    NEW.updated_at := current_timestamp;
    return NEW;
end;
$$ language plpgsql;

create trigger trg_atualiza_data_app_user
    BEFORE update
    on app_user
    for each row
execute FUNCTION fn_atualiza_data();
create trigger trg_atualiza_data_herd
    BEFORE update
    on herd
    for each row
execute FUNCTION fn_atualiza_data();
create trigger trg_atualiza_data_lot
    BEFORE update
    on lot
    for each row
execute FUNCTION fn_atualiza_data();
create trigger trg_atualiza_data_animal_exception
    BEFORE update
    on animal_exception
    for each row
execute FUNCTION fn_atualiza_data();
create trigger trg_atualiza_data_supplier
    BEFORE update
    on supplier
    for each row
execute FUNCTION fn_atualiza_data();
create trigger trg_atualiza_data_medicine
    BEFORE update
    on medicine
    for each row
execute FUNCTION fn_atualiza_data();
create trigger trg_atualiza_data_medicine_batch
    BEFORE update
    on medicine_batch
    for each row
execute FUNCTION fn_atualiza_data();
create trigger trg_atualiza_data_data_catalog
    BEFORE update
    on data_catalog
    for each row
execute FUNCTION fn_atualiza_data();

create or replace FUNCTION fn_auditoria()
    returns trigger as
$$
DECLARE
    v_app_user UUID;
    v_ip       INET;
begin
    begin
        v_app_user := NULLIF(current_setting('app.usuario', true), '')::UUID;
        v_ip := NULLIF(current_setting('app.ip', true), '')::INET;
    EXCEPTION
        when OTHERS then
            v_app_user := null;
            v_ip := null;
    end;

    insert into change_audit (table_name, operation, record_id, old_data, new_data,
                              db_user, app_user_id, ip_address)
    values (TG_TABLE_NAME,
            TG_OP,
            COALESCE(NEW.id, OLD.id)::VARCHAR,
            case when TG_OP in ('UPDATE', 'DELETE') then row_to_json(OLD)::JSONB end,
            case when TG_OP in ('INSERT', 'UPDATE') then row_to_json(NEW)::JSONB end,
            CURRENT_USER,
            v_app_user,
            v_ip);

    return COALESCE(NEW, OLD);
end;
$$ language plpgsql;

create trigger trg_auditoria_application
    AFTER insert or update or delete
    on application
    for each row
execute FUNCTION fn_auditoria();

create trigger trg_auditoria_stock_movement
    AFTER insert or update or delete
    on stock_movement
    for each row
execute FUNCTION fn_auditoria();


create or replace FUNCTION fn_calcula_carencia_lote()
    returns trigger as
$$
DECLARE
    v_medicine_id UUID;
begin
    select medicine_id
    into v_medicine_id
    from medicine_batch
    where id = NEW.medicine_batch_id;

    NEW.meat_withdrawal_end := fn_data_fim_carencia(v_medicine_id, NEW.application_date);

    if NEW.head_count_applied is null then
        select head_count into NEW.head_count_applied from lot where id = NEW.lot_id;
    end if;

    return NEW;
end;
$$ language plpgsql;

create trigger trg_calcula_carencia_lote
    BEFORE insert
    on application
    for each row
execute FUNCTION fn_calcula_carencia_lote();


create or replace FUNCTION fn_atualiza_apto_abate_lote()
    returns trigger as
$$
DECLARE
    v_maior DATE;
begin
    select MAX(meat_withdrawal_end)
    into v_maior
    from application
    where lot_id = NEW.lot_id;

    update lot
    set slaughter_release_date = v_maior,
        fit_for_slaughter      = (v_maior is null or v_maior <= current_date)
    where id = NEW.lot_id;

    return NEW;
end;
$$ language plpgsql;

create trigger trg_atualiza_apto_abate_lote
    AFTER insert or update
    on application
    for each row
execute FUNCTION fn_atualiza_apto_abate_lote();


create or replace FUNCTION fn_calcula_carencia_excecao()
    returns trigger as
$$
DECLARE
    v_medicine_id UUID;
    v_data        DATE;
begin
    select mb.medicine_id, ap.application_date
    into v_medicine_id, v_data
    from application ap
             join medicine_batch mb on mb.id = ap.medicine_batch_id
    where ap.id = NEW.application_id;

    NEW.meat_withdrawal_end := fn_data_fim_carencia(v_medicine_id, v_data);
    NEW.released_for_slaughter := (NEW.meat_withdrawal_end <= current_date);

    update animal_exception
    set slaughter_release_date = GREATEST(COALESCE(slaughter_release_date, NEW.meat_withdrawal_end),
                                          NEW.meat_withdrawal_end),
        fit_for_slaughter      = false
    where id = NEW.animal_exception_id;

    return NEW;
end;
$$ language plpgsql;

create trigger trg_calcula_carencia_excecao
    BEFORE insert
    on application_animal
    for each row
execute FUNCTION fn_calcula_carencia_excecao();


create or replace FUNCTION fn_baixa_estoque()
    returns trigger as
$$
begin
    insert into stock_movement (medicine_batch_id, application_id, user_id,
                                type, quantity, reason)
    values (NEW.medicine_batch_id, NEW.id, NEW.user_id,
            'S', NEW.dose * NEW.head_count_applied, 'APLICACAO');

    return NEW;
end;
$$ language plpgsql;

create trigger trg_baixa_estoque
    AFTER insert
    on application
    for each row
execute FUNCTION fn_baixa_estoque();


create or replace FUNCTION fn_gera_alerta()
    returns trigger as
$$
DECLARE
    v_codigo VARCHAR(20);
begin
    select lot_code into v_codigo from lot where id = NEW.lot_id;

    insert into alert (user_id, lot_id, type, severity, title, message)
    values (NEW.user_id,
            NEW.lot_id,
            'CARENCIA',
            'MEDIA',
            'Lote em carencia: ' || v_codigo,
            'O lote ' || v_codigo || ' fica em carencia ate ' ||
            TO_CHAR(NEW.meat_withdrawal_end, 'DD/MM/YYYY') || '.');

    return NEW;
end;
$$ language plpgsql;

create trigger trg_gera_alerta
    AFTER insert
    on application
    for each row
execute FUNCTION fn_gera_alerta();


create or replace FUNCTION fn_atualiza_contagem()
    returns trigger as
$$
begin
    if TG_OP = 'INSERT' then
        update lot set head_count = head_count - 1 where id = NEW.origin_lot_id;
        update lot set head_count = head_count + 1 where id = NEW.lot_id;
    ELSIF TG_OP = 'UPDATE' and NEW.lot_id <> OLD.lot_id then
        update lot set head_count = head_count - 1 where id = OLD.lot_id;
        update lot set head_count = head_count + 1 where id = NEW.lot_id;
    end if;

    return NEW;
end;
$$ language plpgsql;

create trigger trg_atualiza_contagem
    AFTER insert or update
    on animal_exception
    for each row
execute FUNCTION fn_atualiza_contagem();


create or replace FUNCTION fn_registra_acesso_diario()
    returns trigger as
$$
begin
    if NEW.success and NEW.user_id is not null then
        insert into daily_access (user_id, date, source, session_count, first_login_time)
        values (NEW.user_id, NEW.happened_at::DATE, 'MOBILE', 1, NEW.happened_at)
        on CONFLICT (user_id, date, source)
            do update set session_count = daily_access.session_count + 1;
    end if;

    return NEW;
end;
$$ language plpgsql;

create trigger trg_registra_acesso_diario
    AFTER insert
    on access_audit
    for each row
execute FUNCTION fn_registra_acesso_diario();

-- procedures
create or replace procedure sp_registrar_aplicacao(
    p_lot_id UUID,
    p_medicine_batch_id UUID,
    p_user_id UUID,
    p_dose NUMERIC,
    p_unit VARCHAR,
    p_route VARCHAR,
    p_goal VARCHAR default null
) as
$$
DECLARE
    v_cabecas INTEGER;
    v_saldo   NUMERIC(10, 3);
begin
    select head_count into v_cabecas from lot where id = p_lot_id;

    if v_cabecas is null or v_cabecas = 0 then
        raise EXCEPTION 'Lote % nao tem animal', p_lot_id;
    end if;

    v_saldo := fn_saldo_medicine_batch(p_medicine_batch_id);

    if v_saldo < p_dose * v_cabecas then
        raise EXCEPTION 'Saldo insuficiente no frasco %: tem %, precisa de %',
            p_medicine_batch_id, v_saldo, p_dose * v_cabecas;
    end if;

    insert into application (lot_id, medicine_batch_id, user_id, application_date,
                             application_time, dose, unit, route, head_count_applied, goal)
    values (p_lot_id, p_medicine_batch_id, p_user_id, current_date,
            current_time, p_dose, p_unit, p_route, v_cabecas, p_goal);

    commit;
EXCEPTION
    when OTHERS then
        rollback;
        raise;
end;
$$ language plpgsql;

create or replace procedure sp_marcar_excecao(
    p_lot_id UUID,
    p_ear_tag VARCHAR,
    p_motivo VARCHAR,
    p_peso NUMERIC default null
) as
$$
DECLARE
    v_sublote UUID;
    v_herd    UUID;
    v_codigo  VARCHAR(20);
    v_animal  UUID;
begin
    select herd_id, lot_code into v_herd, v_codigo from lot where id = p_lot_id;

    if v_herd is null then
        raise EXCEPTION 'Lote % nao encontrado', p_lot_id;
    end if;

    select id
    into v_sublote
    from lot
    where parent_lot_id = p_lot_id
      and is_exception_lot = true
      and active = true;

    if v_sublote is null then
        insert into lot (herd_id, parent_lot_id, lot_code, category, is_exception_lot)
        values (v_herd, p_lot_id, left(v_codigo, 14) || '-EXC', 'EXCECAO', true)
        returning id into v_sublote;
    end if;

    insert into animal_exception (lot_id, origin_lot_id, ear_tag, category,
                                  current_weight, exception_reason)
    values (v_sublote, p_lot_id, p_ear_tag, 'BOI', p_peso, p_motivo)
    returning id into v_animal;

    insert into animal_lot_history (animal_exception_id, lot_id, reason)
    values (v_animal, v_sublote, 'EXCECAO');

    commit;
EXCEPTION
    when OTHERS then
        rollback;
        raise;
end;
$$ language plpgsql;


create or replace procedure sp_carga_rpa(p_load_run_id UUID)
as
$$
DECLARE
    r            RECORD;
    v_json       JSONB;
    v_tabela     VARCHAR(60);
    v_target     UUID;
    v_lidos      INTEGER := 0;
    v_inseridos  INTEGER := 0;
    v_atualizado INTEGER := 0;
    v_rejeitados INTEGER := 0;
begin
    for r in select *
             from load_staging
             where load_run_id = p_load_run_id
               and processed = false
        loop
            v_lidos := v_lidos + 1;

            begin
                v_json := r.source_columns::JSONB;
                v_tabela := v_json ->> 'tabela';

                if v_tabela = 'supplier' then
                    select id into v_target from supplier where cnpj = v_json ->> 'cnpj';

                    if v_target is null then
                        insert into supplier (company_name, cnpj, email, phone, address, source_id)
                        values (v_json ->> 'company_name', v_json ->> 'cnpj', v_json ->> 'email',
                                v_json ->> 'phone', v_json ->> 'address',
                                (v_json ->> 'source_id')::INTEGER)
                        returning id into v_target;
                        v_inseridos := v_inseridos + 1;
                    else
                        update supplier
                        set company_name = v_json ->> 'company_name',
                            email        = v_json ->> 'email',
                            phone        = v_json ->> 'phone',
                            address      = v_json ->> 'address'
                        where id = v_target;
                        v_atualizado := v_atualizado + 1;
                    end if;

                    insert into load_mapping (table_name, source_id, target_id, natural_key)
                    values ('supplier', v_json ->> 'source_id', v_target, v_json ->> 'cnpj')
                    on CONFLICT (table_name, source_id) do NOTHING;
                else
                    raise EXCEPTION 'Tabela de origem nao mapeada: %', v_tabela;
                end if;

                update load_staging set processed = true where id = r.id;

            EXCEPTION
                when OTHERS then
                    v_rejeitados := v_rejeitados + 1;
                    insert into load_error (load_run_id, source_table, natural_key,
                                            original_content, error_message)
                    values (p_load_run_id,
                            COALESCE(v_tabela, 'DESCONHECIDA'),
                            COALESCE(v_json ->> 'cnpj', r.row_hash),
                            COALESCE(v_json, jsonb_build_object('raw', r.source_columns)),
                            SQLERRM);
            end;
        end loop;

    update load_run
    set end_time      = current_timestamp,
        rows_read     = v_lidos,
        rows_inserted = v_inseridos,
        rows_updated  = v_atualizado,
        rows_rejected = v_rejeitados,
        loaded_until  = current_timestamp,
        status        = case
                            when v_rejeitados = 0 then 'SUCESSO'
                            when v_rejeitados = v_lidos then 'ERRO'
                            else 'PARCIAL' end
    where id = p_load_run_id;

    commit;
end;
$$ language plpgsql;

-- views analitcas


create or replace view vw_saldo_estoque as
select mb.id                                                      as medicine_batch_id,
       m.brand_name,
       mb.batch_number,
       sm.movement_date,
       sm.type,
       sm.quantity,
       SUM(case when sm.type = 'E' then sm.quantity else -sm.quantity end)
       over (partition by mb.id order by sm.movement_date, sm.id) as saldo_acumulado
from stock_movement sm
         join medicine_batch mb on mb.id = sm.medicine_batch_id
         join medicine m on m.id = mb.medicine_id;


create or replace view vw_evolucao_peso as
select ae.id                           as animal_exception_id,
       ae.ear_tag,
       ap.application_date,
       aa.weight_at_time,
       LAG(aa.weight_at_time) over w   as peso_anterior,
       LAG(ap.application_date) over w as data_anterior,
       ROUND(
               (aa.weight_at_time - LAG(aa.weight_at_time) over w)
                   / NULLIF(ap.application_date - LAG(ap.application_date) over w, 0)::NUMERIC
           , 3)                        as ganho_medio_diario
from application_animal aa
         join application ap on ap.id = aa.application_id
         join animal_exception ae on ae.id = aa.animal_exception_id
where aa.weight_at_time is not null
WINDOW w as (partition by ae.id order by ap.application_date);


create or replace view vw_ranking_conformidade as
select l.id                                                        as lot_id,
       l.lot_code,
       p.name                                                      as property_name,
       l.head_count,
       l.fit_for_slaughter,
       l.slaughter_release_date,
       RANK() over (order by l.slaughter_release_date nulls FIRST) as posicao
from lot l
         join herd h on h.id = l.herd_id
         join property p on p.id = h.property_id
where l.active = true;


create or replace view vw_linhagem_lote as
with recursive linhagem as (select l.id,
                                   l.lot_code,
                                   l.parent_lot_id,
                                   1                as nivel,
                                   l.lot_code::TEXT as caminho,
                                   l.id             as lote_consultado
                            from lot l
                            union all
                            select pai.id,
                                   pai.lot_code,
                                   pai.parent_lot_id,
                                   f.nivel + 1,
                                   pai.lot_code || ' > ' || f.caminho,
                                   f.lote_consultado
                            from lot pai
                                     join linhagem f on f.parent_lot_id = pai.id)
select lote_consultado, id as lote_ancestral, lot_code, nivel, caminho
from linhagem;

-- tabelas de fato e dimensao star schema

create table dim_date
(
    date_key   INTEGER primary key,
    date       DATE        not null unique,
    day        INTEGER     not null,
    month      INTEGER     not null,
    month_name VARCHAR(12) not null,
    quarter    INTEGER     not null,
    year       INTEGER     not null,
    week       INTEGER     not null,
    is_weekend BOOLEAN     not null
);

insert into dim_date (date_key, date, day, month, month_name, quarter, year, week, is_weekend)
select TO_CHAR(d, 'YYYYMMDD')::INTEGER,
       d::DATE,
       EXTRACT(DAY from d)::INTEGER,
       EXTRACT(MONTH from d)::INTEGER,
       TRIM(TO_CHAR(d, 'Month')),
       EXTRACT(QUARTER from d)::INTEGER,
       EXTRACT(YEAR from d)::INTEGER,
       EXTRACT(WEEK from d)::INTEGER,
       EXTRACT(ISODOW from d) in (6, 7)
from generate_series('2024-01-01'::DATE, '2030-12-31'::DATE, '1 day') as d;

create or replace view dim_property as
select id as property_key, name, city, state, area_hectares
from property;

create or replace view dim_lot as
select l.id as lot_key,
       l.lot_code,
       l.category,
       h.herd_name,
       h.breed,
       l.is_exception_lot,
       l.head_count,
       l.open_date,
       l.close_date,
       l.active
from lot l
         join herd h on h.id = l.herd_id;

create or replace view dim_animal_exception as
select id      as animal_exception_key,
       ear_tag,
       category,
       case
           when birth_date is null then null
           else (EXTRACT(YEAR from AGE(current_date, birth_date)) * 12
               + EXTRACT(MONTH from AGE(current_date, birth_date)))::INTEGER
           end as age_months,
       exception_reason,
       status,
       fit_for_slaughter
from animal_exception;


create or replace view dim_medicine as
select m.id           as medicine_key,
       m.brand_name,
       m.active_ingredient,
       tc.name        as therapeutic_category,
       m.needs_prescription,
       m.meat_withdrawal_days,
       m.route,
       s.company_name as supplier_name
from medicine m
         join therapeutic_category tc on tc.id = m.therapeutic_category_id
         join supplier s on s.id = m.supplier_id;

create or replace view dim_user as
select u.id as user_key, u.name, p.code as permission_code, u.active
from app_user u
         join permission p on p.id = u.permission_id;


create or replace view fact_application as
select ap.id                                             as application_id,
       TO_CHAR(ap.application_date, 'YYYYMMDD')::INTEGER as date_key,
       ap.lot_id                                         as lot_key,
       mb.medicine_id                                    as medicine_key,
       pr.id                                             as property_key,
       ap.user_id                                        as user_key,
       ap.dose,
       ap.head_count_applied,
       m.meat_withdrawal_days                            as withdrawal_days,
       (ap.meat_withdrawal_end - current_date)           as days_to_release,
       (ap.meat_withdrawal_end <= current_date)          as released_for_slaughter,
       1                                                 as application_count
from application ap
         join medicine_batch mb on mb.id = ap.medicine_batch_id
         join medicine m on m.id = mb.medicine_id
         join lot l on l.id = ap.lot_id
         join herd h on h.id = l.herd_id
         join property pr on pr.id = h.property_id;


create or replace view fact_stock_movement as
select sm.id                                                                     as stock_movement_id,
       TO_CHAR(sm.movement_date, 'YYYYMMDD')::INTEGER                            as date_key,
       mb.medicine_id                                                            as medicine_key,
       pr.id                                                                     as property_key,
       sm.user_id                                                                as user_key,
       case when sm.type = 'E' then sm.quantity else 0 end                       as quantity_in,
       case when sm.type = 'S' then sm.quantity else 0 end                       as quantity_out,
       SUM(case when sm.type = 'E' then sm.quantity else -sm.quantity end)
       over (partition by sm.medicine_batch_id order by sm.movement_date, sm.id) as running_balance
from stock_movement sm
         join medicine_batch mb on mb.id = sm.medicine_batch_id
         left join application ap on ap.id = sm.application_id
         left join lot l on l.id = ap.lot_id
         left join herd h on h.id = l.herd_id
         left join property pr on pr.id = h.property_id;


create or replace view fact_occurrence as
select oc.id                                            as occurrence_id,
       TO_CHAR(oc.occurrence_date, 'YYYYMMDD')::INTEGER as date_key,
       oc.animal_exception_id                           as animal_exception_key,
       ae.lot_id                                        as lot_key,
       pr.id                                            as property_key,
       oc.type,
       oc.resolved,
       (oc.resolved_at - oc.occurrence_date)            as days_to_resolve,
       1                                                as occurrence_count
from occurrence oc
         join animal_exception ae on ae.id = oc.animal_exception_id
         join lot l on l.id = ae.lot_id
         join herd h on h.id = l.herd_id
         join property pr on pr.id = h.property_id;
