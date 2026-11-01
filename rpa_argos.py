import hashlib
import json
import os

import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import RealDictCursor


CATEGORIAS_LOTE = {
    "FATTENING": "ENGORDA",
    "BREEDING": "CRIA",
    "REARING": "RECRIA",
    "ENGORDA": "ENGORDA",
    "CRIA": "CRIA",
    "RECRIA": "RECRIA",
}

VIAS_APLICACAO = {
    "INTRAMUSCULAR": "INTRAMUSCULAR",
    "SUBCUTANEOUS": "SUBCUTANEA",
    "ORAL": "ORAL",
    "TOPICAL": "TOPICA",
    "INTRAVENOUS": "INTRAVENOSA",
    "SUBCUTANEA": "SUBCUTANEA",
    "TOPICA": "TOPICA",
    "INTRAVENOSA": "INTRAVENOSA",
}

STATUS_ENCERRADOS = {"RECUPERADO", "VENDIDO", "ABATIDO", "MORTO"}

def conectar_banco(prefixo):
    """Abre uma conexão usando LEGACY_DB_* ou DB_*."""
    return psycopg2.connect(
        host=os.environ[f"{prefixo}DB_HOST"],
        port=os.environ[f"{prefixo}DB_PORT"],
        dbname=os.environ[f"{prefixo}DB_NAME"],
        user=os.environ[f"{prefixo}DB_USER"],
        password=os.environ[f"{prefixo}DB_PASSWORD"],
    )


def consultar_dados(cursor, sql):
    cursor.execute(sql)
    return [dict(linha) for linha in cursor.fetchall()]


def extrair_dados(cursor):
    """Lê somente as tabelas legadas e prepara as colunas da procedure."""
    registros = []
    pendencias = []

    propriedades = consultar_dados(
        cursor,
        """
        SELECT p.id_property AS source_id,
               'RPA_TECNICO' AS source_user_id,
               p.name, p.cnpj, p.phone, p.active,
               a.street, a.number::text AS number, a.complement,
               a.zip_code, a.city, a.state
        FROM property p
        JOIN address a ON a.id_address = p.id_address
        """,
    )
    for linha in propriedades:
        registros.append({"tabela": "property", **linha})

    rebanhos = consultar_dados(
        cursor,
        """
        SELECT id_herd AS source_id, id_property AS source_property_id,
               herd_name, breed, head_count, active
        FROM herd
        """,
    )
    for linha in rebanhos:
        registros.append({"tabela": "herd", **linha})

    lotes = consultar_dados(
        cursor,
        """
        SELECT id_lot AS source_id, id_herd AS source_herd_id,
               lot_code, category, head_count, open_date, active
        FROM lot
        """,
    )
    for linha in lotes:
        categoria_original = linha["category"].strip().upper()
        if categoria_original not in CATEGORIAS_LOTE:
            raise ValueError(f"Categoria de lote desconhecida: {categoria_original}")
        linha["category"] = CATEGORIAS_LOTE[categoria_original]
        registros.append({"tabela": "lot", **linha})

    animais = consultar_dados(
        cursor,
        """
        SELECT a.id_animal AS source_id, a.id_lot AS source_lot_id,
               a.id_origin_lot AS source_origin_lot_id,
               a.ear_tag, a.current_weight, a.birth_date,
               a.exception_reason, a.exception_start_date AS exception_date,
               a.exception_end_date, a.notes, a.active,
               h_atual.id_property AS current_property_id,
               h_origem.id_property AS origin_property_id
        FROM animal a
        LEFT JOIN lot l_atual ON l_atual.id_lot = a.id_lot
        LEFT JOIN herd h_atual ON h_atual.id_herd = l_atual.id_herd
        LEFT JOIN lot l_origem ON l_origem.id_lot = a.id_origin_lot
        LEFT JOIN herd h_origem ON h_origem.id_herd = l_origem.id_herd
        """,
    )
    for linha in animais:
        desfecho = (linha["notes"] or "").strip().upper()
        if not linha["source_origin_lot_id"]:
            pendencias.append(
                ("animal", linha, "Lote de origem não informado. Animal não importado.")
            )
        elif not linha["current_property_id"] or not linha["origin_property_id"]:
            pendencias.append(
                ("animal", linha, "Propriedade dos lotes não identificada. Animal não importado.")
            )
        elif linha["current_property_id"] != linha["origin_property_id"]:
            pendencias.append(
                ("animal", linha, "Lotes em propriedades diferentes; verificar histórico. Animal não importado.")
            )
        elif desfecho == "RECUPERADO" and linha["source_lot_id"] != linha["source_origin_lot_id"]:
            pendencias.append(
                ("animal", linha, "Animal recuperado fora do lote de origem. Animal não importado.")
            )
        elif linha["active"] is True and linha["exception_end_date"] is None:
            if desfecho in STATUS_ENCERRADOS:
                pendencias.append(
                    ("animal", linha, "Desfecho encerrado sem data de fim. Animal não importado.")
                )
                continue
            linha["status"] = "ATIVO"
            registros.append({"tabela": "animal_exception", **linha})
        elif linha["exception_end_date"] is not None and desfecho in STATUS_ENCERRADOS:
            linha["status"] = desfecho
            registros.append({"tabela": "animal_exception", **linha})
        else:
            pendencias.append(
                (
                    "animal",
                    linha,
                    "Data de fim ou desfecho não informado ou inválido. Animal não importado.",
                )
            )

    fornecedores = consultar_dados(
        cursor,
        """
        SELECT s.id_supplier AS source_id, s.full_name AS company_name,
               s.cnpj, s.email, s.phone, s.active,
               CONCAT_WS(', ', a.street, a.number::text, a.city, a.state)
                   AS address
        FROM supplier s
        LEFT JOIN address a ON a.id_address = s.id_address
        """,
    )
    for linha in fornecedores:
        registros.append({"tabela": "supplier", **linha})

    medicamentos = consultar_dados(
        cursor,
        """
        SELECT id_medicine AS source_id,
               id_supplier AS source_supplier_id,
               brand_name, active_ingredient, indication,
               indicated_withdrawal_days AS meat_withdrawal_days,
               therapeutic_category, dose, unit, active
        FROM medicine
        """,
    )
    for linha in medicamentos:
        registros.append({"tabela": "medicine", **linha})

    lotes_medicamento = consultar_dados(
        cursor,
        """
        SELECT b.id_medication_batch AS source_id,
               b.id_medicine AS source_medicine_id,
               b.batch_number, b.manufacture_date, b.expiry_date,
               b.delivery_date, b.initial_quantity,
               COALESCE(SUM(i.available_quantity), 0) AS available_quantity,
               SUM(i.minimum_stock) AS min_stock,
               SUM(i.maximum_stock) AS max_stock,
               STRING_AGG(i.storage_location, '; ') AS storage_place
        FROM medication_batch b
        LEFT JOIN medication_inventory i
               ON i.id_medication_batch = b.id_medication_batch
        GROUP BY b.id_medication_batch
        """,
    )
    for linha in lotes_medicamento:
        registros.append({"tabela": "medicine_batch", **linha})

    aplicacoes = consultar_dados(
        cursor,
        """
        SELECT id_application AS source_id,
               id_lot AS source_lot_id,
               id_medication_batch AS source_batch_id,
               date_time, dose, unit, route,
               treated_head_count AS head_count_applied,
               application_limb AS applied_limb,
               application_site AS applied_site,
               goal, notes, active
        FROM application
        """,
    )
    for linha in aplicacoes:
        rota_original = (linha["route"] or "").strip().upper()
        if rota_original not in VIAS_APLICACAO:
            raise ValueError(f"Via de aplicação desconhecida: {rota_original!r}")
        linha["route"] = VIAS_APLICACAO[rota_original]
        data_hora = linha.pop("date_time")
        if data_hora is None:
            raise ValueError(f"Aplicação sem data: {linha['source_id']}")
        linha["application_date"] = data_hora.date()
        linha["application_time"] = data_hora.time()
        # Não enviamos source_user_id: a procedure atribui o usuário técnico.
        registros.append({"tabela": "application", **linha})

    return registros, pendencias


def preparar_json(registro):
    # default=str converte UUID, data e Decimal para texto aceito pelo JSON.
    return json.dumps(registro, ensure_ascii=False, sort_keys=True, default=str)


def conferir_usuario_tecnico(cursor):
    cursor.execute(
        "SELECT id FROM app_user WHERE cpf = '00000000000'"
    )
    resultado = cursor.fetchone()
    if resultado is None:
        raise RuntimeError("O usuário técnico da RPA não existe no Argos.")
    return resultado[0]


def registrar_execucao(cursor):
    cursor.execute(
        """
        INSERT INTO load_run (routine_name, source)
        VALUES ('rpa_argos_iniciante', 'BANCO_LEGADO')
        RETURNING id
        """
    )
    return cursor.fetchone()[0]


def carregar_staging(cursor, id_execucao, registros):
    for registro in registros:
        conteudo = preparar_json(registro)
        resumo = hashlib.sha256(conteudo.encode("utf-8")).hexdigest()
        cursor.execute(
            """
            INSERT INTO load_staging (load_run_id, source_columns, row_hash)
            VALUES (%s::uuid, %s, %s)
            ON CONFLICT (load_run_id, row_hash) DO NOTHING
            """,
            (str(id_execucao), conteudo, resumo),
        )


def registrar_pendencias(cursor, id_execucao, pendencias):
    """Guarda no próprio Argos as linhas que não podem ser convertidas."""
    for tabela, linha, motivo in pendencias:
        cursor.execute(
            """
            INSERT INTO load_error (
                load_run_id, source_table, natural_key,
                original_content, error_message
            )
            VALUES (%s::uuid, %s, %s, %s::jsonb, %s)
            """,
            (
                str(id_execucao),
                tabela,
                str(linha["source_id"]),
                preparar_json(linha),
                motivo,
            ),
        )

    if pendencias:
        cursor.execute(
            """
            UPDATE load_run
            SET rows_read = rows_read + %s,
                rows_rejected = rows_rejected + %s,
                status = CASE
                    WHEN rows_inserted + rows_updated = 0 THEN 'ERRO'
                    ELSE 'PARCIAL'
                END,
                message = 'Registros sem correspondência segura em load_error'
            WHERE id = %s::uuid
            """,
            (len(pendencias), len(pendencias), str(id_execucao)),
        )


def mostrar_resultado(cursor, id_execucao):
    cursor.execute(
        """
        SELECT status, rows_read, rows_inserted, rows_updated, rows_rejected
        FROM load_run WHERE id = %s::uuid
        """,
        (str(id_execucao),),
    )
    print("Resultado da carga:", cursor.fetchone())
    cursor.execute(
        """
        SELECT source_table, natural_key, error_message
        FROM load_error WHERE load_run_id = %s::uuid
        ORDER BY source_table, natural_key
        """,
        (str(id_execucao),),
    )
    for erro in cursor.fetchall():
        print("Linha rejeitada:", erro)


if __name__ == "__main__":
    load_dotenv()
    origem = conectar_banco("LEGACY_")
    destino = conectar_banco("")
    id_execucao = None

    try:
        # O banco legado fica protegido contra INSERT, UPDATE e DELETE.
        origem.set_session(readonly=True)
        with origem.cursor(cursor_factory=RealDictCursor) as cursor_origem:
            registros, pendencias = extrair_dados(cursor_origem)

        print(f"Registros preparados: {len(registros)}")
        print(f"Registros sem conversão segura: {len(pendencias)}")
        print("Histórico de carência individual fora do escopo da migração.")
        print("Animais ativos sem categoria no legado recebem BOI pelo padrão da procedure.")

        with destino.cursor() as cursor_destino:
            usuario_tecnico = conferir_usuario_tecnico(cursor_destino)

            if os.getenv("CONFIRMAR_CARGA") != "SIM":
                print("Modo de conferência: nenhuma linha foi gravada no Argos.")
                print("Defina CONFIRMAR_CARGA=SIM para executar a migração.")
            else:

                # A procedure exige esta associação, mas não migra usuários antigos.
                cursor_destino.execute(
                    """
                    INSERT INTO load_mapping (table_name, source_id, target_id, natural_key)
                    VALUES ('app_user', 'RPA_TECNICO', %s::uuid, 'RPA_TECNICO')
                    ON CONFLICT (table_name, source_id) DO NOTHING
                    """,
                    (str(usuario_tecnico),),
                )
                id_execucao = registrar_execucao(cursor_destino)
                destino.commit()

                carregar_staging(cursor_destino, id_execucao, registros)
                destino.commit()

                destino.autocommit = True
                try:
                    cursor_destino.execute(
                        "CALL sp_carga_rpa(%s::uuid)", (str(id_execucao),)
                    )
                finally:
                    destino.autocommit = False
                registrar_pendencias(cursor_destino, id_execucao, pendencias)
                destino.commit()
                mostrar_resultado(cursor_destino, id_execucao)

    except Exception as erro:
        destino.rollback()
        if id_execucao is not None:
            with destino.cursor() as cursor_destino:
                cursor_destino.execute(
                    """
                    UPDATE load_run
                    SET status = 'ERRO', end_time = CURRENT_TIMESTAMP,
                        message = %s
                    WHERE id = %s::uuid
                    """,
                    (str(erro), str(id_execucao)),
                )
            destino.commit()
        raise
    finally:
        origem.close()
        destino.close()

