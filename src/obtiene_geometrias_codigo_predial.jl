function obtiene_geometrias_codigo_predial(id_combi, conn_neo4j)
    # Obtiene desde Neo4j las geometrias de los predios
    display("Obtiene desde Neo4j las geometrias de los predios")

    query = """
        MATCH (c:Combi)
        WHERE c.id_combi = '$id_combi'
        RETURN DISTINCT c.id_combi AS id_combi, c.sup_combi_sii AS sup_terreno_sii, 
                c.geom_combi AS geom_wkt, c.num_predios AS num_predios
        ORDER BY id_combi
    """
    df_predios = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
    sup_terreno_sii = sum(df_predios[!,"sup_terreno_sii"])
    ps_predio_db = polyGdal.astext2shape(df_predios[:, "geom_wkt"])
    ps_predio_db = polyShape.setPolyOrientation(ps_predio_db,1)
    ps_predio_db = polyShape.shape_4326to32719(ps_predio_db)
    ps_predio_db, dx, dy = polyShape.ajustaCoordenadas(ps_predio_db)
    ps_predio_db = polyShape.polyUnion(ps_predio_db)
    simplify_value = 1.0 #1. #.1
    ps_predio = polyGdal.shapeSimplify(ps_predio_db, simplify_value)
    ps_predio = polyShape.polyEliminaColineales(ps_predio)


    #################################
    # Obtiene predios y calles contenidos en el buffer del predio y ajusta coordenadas
    #################################

    buffer_dist = 70.0 #140

    # Obtiene buffer del predio seleccionado
    display("Obtiene buffer del predio seleccionado")
    ps_buffer_predio = polyGdal.shapeBuffer(ps_predio, buffer_dist, 30)

    # Obtiene predios contenidos en el buffer del predio y ajusta coordenadas
    display("Obtiene predios contenidos en el buffer del predio y ajusta coordenadas")
    query = """
    MATCH (c:Combi)<-[:CONFORMA_COMBI]-(p:Predio)-[:SE_UBICA_EN_MANZANA]->(m:Manzana)
    WHERE c.id_combi = '$id_combi'
    MATCH (m_:Manzana)-[:ES_VECINA_A]-(m)
    WITH m, m_
    UNWIND [m, m_] AS m2
    MATCH (gp:Geom_Predio)<-[:TIENE_GEOM]-(p2:Predio)-[:SE_UBICA_EN_MANZANA]->(m2)
    RETURN DISTINCT gp.geom_wkt AS geom_wkt
    """
    df_predios_manzanas_vecinas = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
    ps_predios_manzanas_vecinas = polyGdal.astext2shape(df_predios_manzanas_vecinas[:, "geom_wkt"])
    ps_predios_manzanas_vecinas = polyShape.setPolyOrientation(ps_predios_manzanas_vecinas,1)
    ps_predios_manzanas_vecinas = polyShape.shape_4326to32719(ps_predios_manzanas_vecinas)
    ps_predios_manzanas_vecinas = polyShape.ajustaCoordenadas(ps_predios_manzanas_vecinas, dx, dy)
    ps_predios_buffer = polyShape.polyIntersect(ps_predios_manzanas_vecinas, ps_buffer_predio)


    # Obtiene areas verdes en el buffer del predio y ajusta coordenadas
    display("Obtiene areas verdes contenidos en el buffer del predio y ajusta coordenadas")
    query = """
    MATCH (cat:Poi_Category)<-[:ES_POI_TIPO]-(poi:Poi)
    WHERE cat.poi_category in ['park', 'garden'] AND poi.comuna = 'vitacura'
    RETURN poi.geom_wkt AS geom_wkt
    """
    df_areas_verdes = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
    ps_areas_verdes = polyGdal.astext2shape(df_areas_verdes[:, "geom_wkt"])
    ps_areas_verdes = polyShape.setPolyOrientation(ps_areas_verdes,1)
    ps_areas_verdes = polyShape.shape_4326to32719(ps_areas_verdes)
    ps_areas_verdes = polyShape.ajustaCoordenadas(ps_areas_verdes, dx, dy)
    ps_areas_verdes_buffer = polyShape.polyIntersect(ps_areas_verdes, ps_buffer_predio)

    ps_predios_buffer = polyShape.polyUnion(ps_predios_buffer, ps_areas_verdes_buffer)


    # Obtiene manzanas contenidas en el buffer del predio


    display("Obtención del conjunto de calles en el entorno del predio")
    @time ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle = obtieneCalles(ps_predio, ps_buffer_predio, ps_predios_buffer)


    vec_edges_predio, aux = polyShape.shape2vector(ps_predio)
    numLadosPredio = length(vec_edges_predio)
    vecSecTodos = collect(1:numLadosPredio)
    vecSecSinCalle = setdiff(vecSecTodos, vecSecConCalle)

    display("Obtención de calles dentro del buffer")
    @time ps_calles_intra_buffer = polyShape.polyIntersect(ps_calles, ps_buffer_predio)

    dict_geom = Dict(
        "ps_predio" => ps_predio,
        "ps_calles" => ps_calles,
        "ps_publico" => ps_publico,
        "ps_bruto" => ps_bruto,
        "n_predios" => df_predios[1,"num_predios"][1],
        "vecSecTodos" => vecSecTodos,
        "vecSecSinCalle" => vecSecSinCalle,
        "vecSecConCalle" => vecSecConCalle,
        "vecAnchoCalle" => vecAnchoCalle,
        "sup_terreno_sii" => sup_terreno_sii
    )

    return dict_geom

end

