function funcionPrincipal(conn_neo4j, codigo_predial, dict_arquitectura)


    ##############################################
    # PARTE "1": OBTENCIÓN DE PARÁMETROS         #
    ##############################################


    # Obtiene los parametros del predio
    display("Obtiene los parametros del predio")

    query = """
    MATCH (p:Predio)-[:SE_UBICA_EN_ZONA]->(z:Zona_Edificacion)-[:TIENE_REQUERIMIENTO]->(r:Requerimiento_Edificacion)
    WHERE p.codigo_predial = '$(codigo_predial[1])'
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
    df_normativa = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
    lista_requerimientos = sort(unique(skipmissing(df_normativa[!, :nombre_requerimiento])))


    dict_requerimientos = Dict{String,Any}()

    variante_str = dict_arquitectura["variante_normativa"]
    flag_dfl2 = variante_str == "dfl_2" ? true : false
    
    for r in lista_requerimientos
        # 1) filter down to the matching row
        mask = 
        (df_normativa[!, :nombre_variante] .== variante_str) .&
        (df_normativa[!, :nombre_requerimiento] .== r)
        df_mask = df_normativa[mask, [:valor, :parametro_formula, :formula]]

        # 2) if there's at least one row for this requisito
        if size(df_mask, 1) ≥ 1
            valor_str      = strip(df_mask[1, :valor])
            parametros_str = strip(df_mask[1, :parametro_formula])
            formula_str    = strip(df_mask[1, :formula])

            if parametros_str == "NULL"
                # ───────── sin parámetros ─────────
                chosen = valor_str != "NULL" ? valor_str : formula_str
                parsed = tryparse(Float64, String(chosen))
                dict_requerimientos[r] = parsed === nothing ? String(chosen) : parsed

            elseif valor_str == "NULL"
                # ───────── con parámetros ─────────
                dict_requerimientos[r] = (
                    "",
                    String(parametros_str),
                    String(formula_str)
                )
            else
                dict_requerimientos[r] = (
                    String(valor_str),
                    String(parametros_str),
                    String(formula_str)
                )
            end
        end
    end

    dict_requerimientos["rasante_sombra"] = 5.0

    # Obtiene desde Neo4j las geometrias de los predios
    display("Obtiene desde Neo4j las geometrias de los predios")

    quoted_list = "[" * join(["'" * string(c) * "'" for c in codigo_predial], ",") * "]"
    query = """
        MATCH (gp:Geom_Predio)-[]-(p:Predio)
        WHERE p.codigo_predial IN $quoted_list
        RETURN DISTINCT p.codigo_predial AS codigo_predial, p.sup_terreno_sii AS sup_terreno_sii, gp.geom_wkt AS geom_wkt
        ORDER BY codigo_predial
    """
    df_predios = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
    sup_terreno_sii = sum(df_predios[!,"sup_terreno_sii"])
    ps_predio_db = polyShape.astext2polyshape(df_predios[:, "geom_wkt"])
    ps_predio_db = polyShape.setPolyOrientation(ps_predio_db,1)
    ps_predio_db = polyShape.reproject_polyshape(ps_predio_db)
    ps_predio_db, dx, dy = polyShape.ajustaCoordenadas(ps_predio_db)
    ps_predio_db = polyShape.polyUnion(ps_predio_db)
    simplify_value = 1.0 #1. #.1
    ps_predio = polyShape.shapeSimplify(ps_predio_db, simplify_value)
    ps_predio = polyShape.polyEliminaColineales(ps_predio)


    #################################
    # Obtiene predios y calles contenidos en el buffer del predio y ajusta coordenadas
    #################################

    buffer_dist = 70.0 #140

    # Obtiene buffer del predio seleccionado
    display("Obtiene buffer del predio seleccionado")
    ps_buffer_predio = polyShape.shapeBuffer(ps_predio, buffer_dist, 30)

    # Obtiene predios contenidos en el buffer del predio y ajusta coordenadas
    display("Obtiene predios contenidos en el buffer del predio y ajusta coordenadas")
    query = """
    MATCH (p:Predio)-[]-(m:Manzana)
    WHERE p.codigo_predial IN $quoted_list
    MATCH (m_:Manzana)-[:ES_VECINA_A]-(m)
    WITH m, m_
    UNWIND [m, m_] AS m2
    MATCH (gp:Geom_Predio)-[]-(p2:Predio)-[:SE_UBICA_EN_MANZANA]-(m2)
    RETURN DISTINCT gp.geom_wkt AS geom_wkt
    """
    df_predios_manzanas_vecinas = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
    ps_predios_manzanas_vecinas = polyShape.astext2polyshape(df_predios_manzanas_vecinas[:, "geom_wkt"])
    ps_predios_manzanas_vecinas = polyShape.setPolyOrientation(ps_predios_manzanas_vecinas,1)
    ps_predios_manzanas_vecinas = polyShape.reproject_polyshape(ps_predios_manzanas_vecinas)
    ps_predios_manzanas_vecinas = polyShape.ajustaCoordenadas(ps_predios_manzanas_vecinas, dx, dy)
    ps_predios_buffer = polyShape.polyIntersect(ps_predios_manzanas_vecinas, ps_buffer_predio)


    # Obtiene areas verdes en el buffer del predio y ajusta coordenadas
    display("Obtiene areas verdes contenidos en el buffer del predio y ajusta coordenadas")
    query = """
    MATCH (cat:Poi_Category)-[]-(poi:Poi)
    WHERE cat.poi_category in ['park', 'garden'] AND poi.comuna = 'vitacura'
    RETURN poi.geom_wkt AS geom_wkt
    """
    df_areas_verdes = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
    ps_areas_verdes = polyShape.astext2polyshape(df_areas_verdes[:, "geom_wkt"])
    ps_areas_verdes = polyShape.setPolyOrientation(ps_areas_verdes,1)
    ps_areas_verdes = polyShape.reproject_polyshape(ps_areas_verdes)
    ps_areas_verdes = polyShape.ajustaCoordenadas(ps_areas_verdes, dx, dy)
    ps_areas_verdes_buffer = polyShape.polyIntersect(ps_areas_verdes, ps_buffer_predio)

    ps_predios_buffer = polyShape.polyUnion(ps_predios_buffer, ps_areas_verdes_buffer)

    # Obtiene manzanas contenidas en el buffer del predio
    display("Obtiene manzanas contenidas en el buffer del predio")
    query = """
    MATCH (p:Predio)-[]-(m:Manzana)
    WHERE p.codigo_predial IN $quoted_list
    MATCH (m_:Manzana)-[:ES_VECINA_A]-(m)
    WITH m, m_
    UNWIND [m, m_] AS m2
    RETURN DISTINCT m2.geom_wkt AS geom_wkt
    """
    df_manzanas_vecinas = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
    ps_manzanas_vecinas = polyShape.astext2polyshape(df_manzanas_vecinas[:, "geom_wkt"])
    ps_manzanas_vecinas = polyShape.setPolyOrientation(ps_manzanas_vecinas,1)
    ps_manzanas_vecinas = polyShape.reproject_polyshape(ps_manzanas_vecinas)
    ps_manzanas_vecinas = polyShape.ajustaCoordenadas(ps_manzanas_vecinas, dx, dy)
    ps_manzanas_buffer = polyShape.polyIntersect(ps_manzanas_vecinas, ps_buffer_predio)

    ps_predios_buffer = polyShape.polyUnion(ps_predios_buffer, ps_areas_verdes_buffer)


    display("Obtención del conjunto de calles en el entorno del predio")
    @time ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle = obtieneCalles(ps_predio, ps_buffer_predio, ps_predios_buffer, ps_manzanas_buffer)


    vec_edges_predio, aux = polyShape.polyShape2lineVec(ps_predio)
    numLadosPredio = length(vec_edges_predio)
    vecSecTodos = collect(1:numLadosPredio)
    vecSecSinCalle = setdiff(vecSecTodos, vecSecConCalle)

    display("Obtención de calles dentro del buffer")
    @time ps_calles_intra_buffer = polyShape.polyIntersect(ps_calles, ps_buffer_predio)

####################################################################################

    # Calcula matriz V_areaEdif asociada a los vértices del area de edificación

    n_predios = length(codigo_predial)


    # K = 3; ancho_crujia_min = 0; ancho_crujia_max = 0; flag_sombra = false; tipo_edificio = "oficina"
    # dict_resultados = opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos)
    # fig, ax, ax_mat = plotBaseEdificio3D(fpe, dict_arquitectura["alturaPiso"], ps_predio, dict_resultados["vec_psVolteor"], dict_resultados["vec_altVolteor"], dict_resultados["vec_psVolConSombra"], dict_resultados["vec_altVolConSombra"], ps_publico, ps_calles, dict_resultados["vec_ps_opt"], dict_resultados["vec_np_opt"], dict_resultados["vec_ps_subte"], dict_resultados["vec_np_subte"], dict_resultados["tipo_edificio"])

    # K = 3; ancho_crujia_min = 0; ancho_crujia_max = 0; flag_sombra = true; tipo_edificio = "oficina"
    # dict_resultados = opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos)
    # fig, ax, ax_mat = plotBaseEdificio3D(fpe, dict_arquitectura["alturaPiso"], ps_predio, dict_resultados["vec_psVolteor"], dict_resultados["vec_altVolteor"], dict_resultados["vec_psVolConSombra"], dict_resultados["vec_altVolConSombra"], ps_publico, ps_calles, dict_resultados["vec_ps_opt"], dict_resultados["vec_np_opt"], dict_resultados["vec_ps_subte"], dict_resultados["vec_np_subte"], dict_resultados["tipo_edificio"])

    dict_geom = Dict(
        "ps_predio" => ps_predio,
        "ps_calles" => ps_calles,
        "ps_publico" => ps_publico,
        "ps_bruto" => ps_bruto,
        "n_predios" => n_predios,
        "vecSecTodos" => vecSecTodos,
        "vecSecSinCalle" => vecSecSinCalle,
        "vecSecConCalle" => vecSecConCalle,
        "vecAnchoCalle" => vecAnchoCalle,
        "sup_terreno_sii" => sup_terreno_sii
    )

    dict_resultados = opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos)

    return dict_resultados, dict_arquitectura, dict_geom
end



