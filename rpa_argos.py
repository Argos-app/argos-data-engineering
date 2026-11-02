import hashlib
import json
import os
from decimal import Decimal

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

UNIDADES = {
    "ml": "ml",
    "mililitro": "ml",
    "mililitros": "ml",
    "mg": "mg",
    "miligrama": "mg",
    "miligramas": "mg",
    "g": "g",
    "grama": "g",
    "gramas": "g",
    "ui": "UI",
    "unidade internacional": "UI",
    "dose": "dose",
    "doses": "dose",
}


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


def validar_animal(linha):
    if not (linha["ear_tag"] or "").strip():
        return "Brinco do animal nao informado."
    if not (linha["exception_reason"] or "").strip():
        return "Motivo da excecao nao informado."
    inicio = linha["exception_date"]
    fim = linha["exception_end_date"]
    nascimento = linha["birth_date"]
    if inicio is None:
        return "Data de inicio da excecao nao informada."
    if nascimento is not None and nascimento > inicio:
        return "Data de nascimento posterior ao inicio da excecao."
    if fim is not None and fim < inicio:
        return "Data de fim anterior ao inicio da excecao."
    if linha["current_weight"] is not None and linha["current_weight"] <= 0:
        return "Peso do animal deve ser maior que zero."
    return None


def validar_aplicacao(linha, lotes_por_id, lotes_medicamento_por_id):
    if linha["source_lot_id"] not in lotes_por_id:
        return "Lote da aplicacao nao encontrado no legado."
    lote_medicamento = lotes_medicamento_por_id.get(linha["source_batch_id"])
    if lote_medicamento is None:
        return "Lote de medicamento nao encontrado no legado."
    if linha["date_time"] is None:
        return "Data da aplicacao nao informada."
    if linha["dose"] is None or linha["dose"] <= 0:
        return "Dose da aplicacao deve ser maior que zero."
    if linha["head_count_applied"] is None or linha["head_count_applied"] <= 0:
        return "Quantidade de animais da aplicacao deve ser maior que zero."
    fabricacao = lote_medicamento["manufacture_date"]
    validade = lote_medicamento["expiry_date"]
    if fabricacao is None or validade is None:
        return "Datas de fabricacao e validade do medicamento sao necessarias."
    data_aplicacao = linha["date_time"].date()
    if data_aplicacao < fabricacao or data_aplicacao > validade:
        return "Aplicacao fora do periodo de fabricacao e validade do medicamento."
    return None


def validar_medicamento(linha):
    if not (linha["brand_name"] or "").strip():
        return "Nome do medicamento nao informado."
    if not (linha["active_ingredient"] or "").strip():
        return "Principio ativo do medicamento nao informado."
    if not (linha["indication"] or "").strip():
        return "Indicacao do medicamento nao informada."
    if linha["meat_withdrawal_days"] is None or linha["meat_withdrawal_days"] < 0:
        return "Carencia do medicamento nao informada ou invalida."
    if linha["dose"] is None or linha["dose"] <= 0:
        return "Dose do medicamento deve ser maior que zero."
    if (linha["unit"] or "").strip().lower() not in UNIDADES:
        return "Unidade do medicamento desconhecida ou nao informada."
    return None


def validar_lote_medicamento(linha):
    if not (linha["batch_number"] or "").strip():
        return "Numero do lote de medicamento nao informado."
    if linha["manufacture_date"] is None or linha["expiry_date"] is None:
        return "Fabricacao e validade do lote de medicamento sao necessarias."
    if linha["expiry_date"] <= linha["manufacture_date"]:
        return "Validade do medicamento deve ser posterior a fabricacao."
    if linha["delivery_date"] is None:
        return "Data de entrega do lote de medicamento nao informada."
    if linha["initial_quantity"] is None or linha["initial_quantity"] <= 0:
        return "Quantidade inicial do medicamento deve ser maior que zero."
    if (
        linha["inventory_count"] == 0
        or linha["inventory_count"] != linha["known_quantity_count"]
    ):
        return "Estoque do lote de medicamento ausente ou incompleto."
    if linha["available_quantity"] < 0:
        return "Estoque disponivel do medicamento nao pode ser negativo."
    return None


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
        categoria_original = (linha["category"] or "").strip().upper()
        if categoria_original not in CATEGORIAS_LOTE:
            pendencias.append(
                ("lot", linha, "Categoria de lote desconhecida ou nao informada.")
            )
            continue
        linha["category"] = CATEGORIAS_LOTE[categoria_original]
        registros.append({"tabela": "lot", **linha})

    lotes_validos = {
        linha["source_id"] for linha in registros if linha["tabela"] == "lot"
    }
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
        erro = validar_animal(linha)
        if erro:
            pendencias.append(("animal", linha, erro))
            continue
        desfecho = (linha["notes"] or "").strip().upper()
        if not linha["source_origin_lot_id"]:
            pendencias.append(
                ("animal", linha, "Lote de origem não informado. Animal não importado.")
            )
        elif (
            linha["source_origin_lot_id"] not in lotes_validos
            or linha["source_lot_id"] not in lotes_validos
        ):
            pendencias.append(
                ("animal", linha, "Lote atual ou de origem nao passou pela validacao.")
            )
        elif not linha["current_property_id"] or not linha["origin_property_id"]:
            pendencias.append(
                (
                    "animal",
                    linha,
                    "Propriedade dos lotes não identificada. Animal não importado.",
                )
            )
        elif linha["current_property_id"] != linha["origin_property_id"]:
            pendencias.append(
                (
                    "animal",
                    linha,
                    "Lotes em propriedades diferentes; verificar histórico. Animal não importado.",
                )
            )
        elif (
            desfecho == "RECUPERADO"
            and linha["source_lot_id"] != linha["source_origin_lot_id"]
        ):
            pendencias.append(
                (
                    "animal",
                    linha,
                    "Animal recuperado fora do lote de origem. Animal não importado.",
                )
            )
        elif linha["active"] is True and linha["exception_end_date"] is None:
            if desfecho in STATUS_ENCERRADOS:
                pendencias.append(
                    (
                        "animal",
                        linha,
                        "Desfecho encerrado sem data de fim. Animal não importado.",
                    )
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
        erro = validar_medicamento(linha)
        if erro:
            pendencias.append(("medicine", linha, erro))
            continue
        registros.append({"tabela": "medicine", **linha})

    medicamentos_validos = {
        linha["source_id"] for linha in registros if linha["tabela"] == "medicine"
    }
    lotes_medicamento = consultar_dados(
        cursor,
        """
        SELECT b.id_medication_batch AS source_id,
               b.id_medicine AS source_medicine_id,
               b.batch_number, b.manufacture_date, b.expiry_date,
               b.delivery_date, b.initial_quantity,
               COALESCE(SUM(i.available_quantity), 0) AS available_quantity,
               COUNT(i.id_medication_inventory) AS inventory_count,
               COUNT(i.available_quantity) AS known_quantity_count,
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
        if linha["source_medicine_id"] not in medicamentos_validos:
            pendencias.append(
                ("medicine_batch", linha, "Medicamento nao passou pela validacao.")
            )
            continue
        erro = validar_lote_medicamento(linha)
        if erro:
            pendencias.append(("medicine_batch", linha, erro))
            continue
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
    lotes_por_id = {
        linha["source_id"]: linha for linha in registros if linha["tabela"] == "lot"
    }
    lotes_medicamento_por_id = {
        linha["source_id"]: linha
        for linha in registros
        if linha["tabela"] == "medicine_batch"
    }
    for linha in aplicacoes:
        erro = validar_aplicacao(linha, lotes_por_id, lotes_medicamento_por_id)
        if erro:
            pendencias.append(("application", linha, erro))
            continue
        rota_original = (linha["route"] or "").strip().upper()
        if rota_original not in VIAS_APLICACAO:
            pendencias.append(
                (
                    "application",
                    linha,
                    "Via de aplicacao desconhecida ou nao informada.",
                )
            )
            continue
        linha["route"] = VIAS_APLICACAO[rota_original]
        data_hora = linha.pop("date_time")
        linha["application_date"] = data_hora.date()
        linha["application_time"] = data_hora.time()
        # Não enviamos source_user_id: a procedure atribui o usuário técnico.
        registros.append({"tabela": "application", **linha})

    return registros, pendencias


def preparar_json(registro):
    # default=str converte UUID, data e Decimal para texto aceito pelo JSON.
    return json.dumps(registro, ensure_ascii=False, sort_keys=True, default=str)


def conferir_historico(cursor, registros, pendencias):
    cursor.execute(
        "SELECT table_name, source_id, target_id FROM load_mapping "
        "WHERE table_name IN ('lot', 'medicine', 'medicine_batch')"
    )
    mapeamentos = {
        (tabela, str(origem)): str(destino)
        for tabela, origem, destino in cursor.fetchall()
    }
    cursor.execute(
        "SELECT source_id, origin_lot_id FROM animal_exception "
        "WHERE source_id IS NOT NULL"
    )
    animais = {str(origem): str(lote) for origem, lote in cursor.fetchall()}
    cursor.execute(
        "SELECT source_id, lot_id, medicine_batch_id, application_date, "
        "application_time, dose, unit, route, head_count_applied "
        "FROM application WHERE source_id IS NOT NULL"
    )
    aplicacoes = {str(linha[0]): linha[1:] for linha in cursor.fetchall()}

    aceitos = []
    for linha in registros:
        origem = str(linha["source_id"])
        erro = None
        if linha["tabela"] == "animal_exception":
            if origem not in animais and not linha.get("category"):
                erro = "Categoria do animal ausente; nao atribuir BOI sem confirmacao."
            elif origem in animais:
                lote_origem = mapeamentos.get(
                    ("lot", str(linha["source_origin_lot_id"]))
                )
                if lote_origem != animais[origem]:
                    erro = "Lote de origem do animal existente foi alterado no legado."
        elif linha["tabela"] == "medicine" and ("medicine", origem) not in mapeamentos:
            if linha.get("needs_prescription") is None:
                erro = "Necessidade de receita ausente; medicamento nao importado."
        elif linha["tabela"] == "application" and origem in aplicacoes:
            lote = mapeamentos.get(("lot", str(linha["source_lot_id"])))
            frasco = mapeamentos.get(("medicine_batch", str(linha["source_batch_id"])))
            anterior = aplicacoes[origem]
            atual = (
                lote,
                frasco,
                linha["application_date"],
                linha["application_time"],
                linha["dose"],
                UNIDADES.get((linha["unit"] or "").strip().lower()),
                linha["route"],
                linha["head_count_applied"],
            )
            valores_salvos = (str(anterior[0]), str(anterior[1]), *anterior[2:])
            if atual != valores_salvos:
                erro = "Dados historicos protegidos da aplicacao mudaram no legado."
        if erro:
            pendencias.append((linha["tabela"], linha, erro))
        else:
            aceitos.append(linha)
    return aceitos


def proteger_dados_atualizados(cursor, registros, pendencias):
    tabelas = (
        "property",
        "herd",
        "lot",
        "animal_exception",
        "supplier",
        "medicine",
        "medicine_batch",
        "application",
    )
    consultas = [
        "SELECT '" + tabela + "', m.source_id, t.updated_at "
        "FROM " + tabela + " t JOIN load_mapping m ON m.target_id = t.id "
        "WHERE m.table_name = '" + tabela + "'"
        for tabela in tabelas
    ]
    cursor.execute(" UNION ALL ".join(consultas))
    atualizacoes = {
        (tabela, str(origem)): atualizado
        for tabela, origem, atualizado in cursor.fetchall()
    }
    cursor.execute(
        """
        SELECT DISTINCT ON (s.source_columns::jsonb ->> 'tabela',
                            s.source_columns::jsonb ->> 'source_id')
            s.source_columns::jsonb ->> 'tabela',
            s.source_columns::jsonb ->> 'source_id',
            r.end_time,
            s.source_columns::jsonb ->> 'available_quantity'
        FROM load_staging s JOIN load_run r ON r.id = s.load_run_id
        WHERE s.processed AND r.status IN ('SUCESSO', 'PARCIAL')
          AND r.end_time IS NOT NULL
        ORDER BY s.source_columns::jsonb ->> 'tabela',
                 s.source_columns::jsonb ->> 'source_id', r.end_time DESC
        """
    )
    anteriores = {
        (tabela, str(origem)): (fim, saldo)
        for tabela, origem, fim, saldo in cursor.fetchall()
    }
    nomes_categoria = sorted(
        {
            linha.get("therapeutic_category") or ""
            for linha in registros
            if linha["tabela"] == "medicine"
        }
    )
    categorias = {}
    if nomes_categoria:
        cursor.execute(
            "SELECT nome, EXISTS (SELECT 1 FROM therapeutic_category c "
            "WHERE c.name_norm = fn_norm_texto(nome)) "
            "FROM unnest(%s::text[]) AS nomes(nome)",
            (nomes_categoria,),
        )
        categorias = dict(cursor.fetchall())

    bloqueados = {
        (tabela, str(linha["source_id"]))
        for tabela, linha, _ in pendencias
        if tabela in tabelas and "source_id" in linha
    }
    aceitos = []
    for linha in registros:
        tabela = linha["tabela"]
        chave = (tabela, str(linha["source_id"]))
        erro = None
        if tabela == "medicine" and not categorias.get(
            linha.get("therapeutic_category") or ""
        ):
            erro = "Categoria do medicamento sem correspondencia no Argos."
        if not erro and chave in atualizacoes:
            anterior = anteriores.get(chave)
            if anterior is None:
                erro = "Registro existente sem referencia segura da ultima carga."
            elif atualizacoes[chave] > anterior[0]:
                erro = "Registro alterado no Argos depois da ultima carga."
            elif tabela == "medicine_batch":
                saldo_anterior = anterior[1]
                if (
                    saldo_anterior is None
                    or Decimal(saldo_anterior) != linha["available_quantity"]
                ):
                    erro = "Saldo do legado mudou; conferir antes de sincronizar."

        dependencias = {
            "herd": (("property", "source_property_id"),),
            "lot": (("herd", "source_herd_id"),),
            "animal_exception": (
                ("lot", "source_origin_lot_id"),
                ("lot", "source_lot_id"),
            ),
            "medicine": (("supplier", "source_supplier_id"),),
            "medicine_batch": (("medicine", "source_medicine_id"),),
            "application": (
                ("lot", "source_lot_id"),
                ("medicine_batch", "source_batch_id"),
            ),
        }
        if not erro:
            for tabela_pai, campo in dependencias.get(tabela, ()):
                if (tabela_pai, str(linha.get(campo))) in bloqueados:
                    erro = "Dependencia com pendencia; registro nao sincronizado."
                    break
        if erro:
            pendencias.append((tabela, linha, erro))
            bloqueados.add(chave)
        else:
            aceitos.append(linha)
    return aceitos


def conferir_usuario_tecnico(cursor):
    cursor.execute("SELECT id FROM app_user WHERE cpf = '00000000000'")
    resultado = cursor.fetchone()
    if resultado is None:
        raise RuntimeError("O usuário técnico da RPA não existe no Argos.")
    return resultado[0]


def garantir_execucao_unica(cursor):
    cursor.execute("SELECT pg_try_advisory_lock(hashtext('argos_rpa'))")
    if not cursor.fetchone()[0]:
        raise RuntimeError("Outra execucao da RPA ja esta em andamento.")


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
    resultado = cursor.fetchone()
    print("Resultado da carga:", resultado)
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
    return resultado[0]


if __name__ == "__main__":
    load_dotenv()
    origem = conectar_banco("LEGACY_")
    destino = conectar_banco("")
    id_execucao = None
    status_final = None

    try:
        # O banco legado fica protegido contra INSERT, UPDATE e DELETE.
        origem.set_session(readonly=True, isolation_level="REPEATABLE READ")
        with origem.cursor(cursor_factory=RealDictCursor) as cursor_origem:
            registros, pendencias = extrair_dados(cursor_origem)

        with destino.cursor() as cursor_destino:
            if os.getenv("CONFIRMAR_CARGA") == "SIM":
                garantir_execucao_unica(cursor_destino)
            registros = conferir_historico(cursor_destino, registros, pendencias)
            registros = proteger_dados_atualizados(
                cursor_destino, registros, pendencias
            )
            print(f"Registros preparados: {len(registros)}")
            print(f"Registros sem conversão segura: {len(pendencias)}")
            print("Histórico de carência individual fora do escopo da migração.")
            print("Novos animais sem categoria confirmada ficam em pendencia.")
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

                if registros:
                    carregar_staging(cursor_destino, id_execucao, registros)
                    destino.commit()

                    destino.autocommit = True
                    try:
                        cursor_destino.execute(
                            "CALL sp_carga_rpa(%s::uuid)", (str(id_execucao),)
                        )
                    finally:
                        destino.autocommit = False
                else:
                    cursor_destino.execute(
                        "UPDATE load_run SET end_time = CURRENT_TIMESTAMP, "
                        "status = 'SUCESSO' WHERE id = %s::uuid",
                        (str(id_execucao),),
                    )
                registrar_pendencias(cursor_destino, id_execucao, pendencias)
                destino.commit()
                status_final = mostrar_resultado(cursor_destino, id_execucao)

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

    if status_final is not None and status_final != "SUCESSO":
        raise SystemExit(1)
