function obtiene_requerimientos_normativos(codigo_predial, variante_normativa, conn_neo4j)


    # Obtiene los parametros del predio
    display("Obtiene los parametros del predio")

    query = """
        MATCH (p:Predio)-[:SE_UBICA_EN_ZONA]->(z:Zona_Edificacion)-[:TIENE_REQUERIMIENTO]->(r:Requerimiento_Edificacion)
        WHERE p.codigo_predial = $(codigo_predial)
        RETURN
        r.id_requerimiento_edificacion AS id_requerimiento_edificacion,
        r.id_zona_edificacion        AS id_zona_edificacion,
        r.nombre_variante           AS nombre_variante,
        r.nombre_requerimiento     AS nombre_requerimiento,
        r.valor                    AS valor,
        r.unidad                   AS unidad,
        r.tipo_restriccion         AS tipo_restriccion,
        r.unidad_condicional    AS unidad_condicional,
        r.parametro_formula     AS parametro_formula,
        r.formula               AS formula,
        r.nombre_requerimiento  AS nombre_req_condicional;
        """
    df_normativa_raw = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
    lista_requerimientos = sort(unique(skipmissing(df_normativa_raw[!, :nombre_requerimiento])))

    zona_edificacion = 1

    dict_normativa_raw = OrderedDict{String,Any}()

    
    for r in lista_requerimientos
        # 1) filter down to the matching row
        mask = 
        (df_normativa_raw[!, :nombre_variante] .== variante_normativa) .&
        (df_normativa_raw[!, :nombre_requerimiento] .== r)
        df_mask = df_normativa_raw[mask, [:valor, :parametro_formula, :formula]]

        # 2) if there's at least one row for this requisito
        if size(df_mask, 1) ≥ 1
            valor_str      = strip(df_mask[1, :valor])
            parametros_str = strip(df_mask[1, :parametro_formula])
            formula_str    = strip(df_mask[1, :formula])

            if parametros_str == "NULL"
                # ───────── sin parámetros ─────────
                chosen = valor_str != "NULL" ? valor_str : formula_str
                parsed = tryparse(Float64, String(chosen))
                dict_normativa_raw["norm_" * r] = parsed === nothing ? String(chosen) : parsed

            elseif valor_str == "NULL"
                # ───────── con parámetros ─────────
                dict_normativa_raw["norm_" * r] = (
                    "",
                    String(parametros_str),
                    String(formula_str)
                )
            else
                dict_normativa_raw["norm_" * r] = (
                    String(valor_str),
                    String(parametros_str),
                    String(formula_str)
                )
            end
        end
    end

    dict_normativa_raw["norm_rasante_sombra"] = 5.0

    id_zona_edificacion = df_normativa_raw[!,"id_zona_edificacion"][1]

    return dict_normativa_raw, id_zona_edificacion
end



