function obtiene_geometrias_combi(id_combi, conn_neo4j)
    # Obtiene desde Neo4j las geometrias de los predios
    display("Obtiene desde Neo4j las geometrias de los predios")

    query = """
        MATCH (c:Combi)
        WHERE c.id_combi = '$id_combi'
        RETURN DISTINCT c.id_combi AS id_combi, c.sup_combi_sii AS sup_terreno_sii, 
                c.geom_combi AS geom_wkt, c.num_predios AS num_predios
        ORDER BY id_combi
    """
    df_combi = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
    sup_terreno_sii = sum(df_combi[!,"sup_terreno_sii"])
    ps_combi = polyGdal.astext2shape(df_combi[:, "geom_wkt"])
    ps_combi = polyShape.setPolyOrientation(ps_combi,1)
    ps_combi = polyShape.shape_4326to32719(ps_combi)
    ps_combi, dx, dy = polyShape.ajustaCoordenadas(ps_combi)
    ps_combi = polyShape.polyUnion(ps_combi)
    ps_combi = polyGdal.shapeSimplify(ps_combi, 1.0)
    ps_combi = polyShape.polyEliminaColineales(ps_combi)


    #################################
    # Obtiene predios y calles contenidos en el buffer del predio y ajusta coordenadas
    #################################
    
    display("Obtención del conjunto de calles en el entorno del predio")
    @time ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle = obtieneCalles(id_combi, ps_combi, dx, dy, conn_neo4j)


    vec_edges_predio, aux = polyShape.shape2vector(ps_combi)
    numLadosPredio = length(vec_edges_predio)
    vecSecTodos = collect(1:numLadosPredio)
    vecSecSinCalle = setdiff(vecSecTodos, vecSecConCalle)

    dict_geom = Dict(
        "ps_predio" => ps_combi,
        "ps_calles" => ps_calles,
        "ps_publico" => ps_publico,
        "ps_bruto" => ps_bruto,
        "n_predios" => df_combi[1,"num_predios"][1],
        "vecSecTodos" => vecSecTodos,
        "vecSecSinCalle" => vecSecSinCalle,
        "vecSecConCalle" => vecSecConCalle,
        "vecAnchoCalle" => vecAnchoCalle,
        "sup_terreno_sii" => sup_terreno_sii
    )

    return dict_geom

end

