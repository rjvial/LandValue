function obtiene_geometrias_combi(df_combined)
    # Unified query to get both Combi and Calle_Combi data in single database call

    
    # Extract Combi data (first row contains all combi info)
    sup_terreno_sii = df_combined[1,"sup_terreno_sii"]
    ps_combi = polyGdal.astext2shape([df_combined[1, "geom_wkt"]])
    ps_combi = polyShape.setPolyOrientation(ps_combi,1)
    ps_combi = polyShape.shape_4326to32719(ps_combi)
    ps_combi, dx, dy = polyShape.ajustaCoordenadas(ps_combi)
    ps_combi = polyShape.polyUnion(ps_combi)
    ps_combi = polyGdal.shapeSimplify(ps_combi, 1.0)
    ps_combi = polyShape.polyEliminaColineales(ps_combi)

    ps_calles_contexto = polyGdal.astext2shape([df_combined[1, "calles_contexto_wkt"]])
    ps_calles_contexto = polyShape.setPolyOrientation(ps_calles_contexto,1)
    ps_calles_contexto = polyShape.shape_4326to32719(ps_calles_contexto)
    ps_calles_contexto = polyShape.ajustaCoordenadas(ps_calles_contexto, dx, dy)

    # Extract Calle_Combi data from the combined result
    calles_data = filter(row -> !ismissing(row.calles_combi_wkt), df_combined)
    
    #################################
    # Process streets using data already obtained from unified query
    #################################
    
    display("Procesamiento del conjunto de calles en el entorno del predio")
    @time ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle = obtieneCalles(calles_data, ps_combi, dx, dy)


    vec_edges_predio, aux = polyShape.shape2vector(ps_combi)
    numLadosPredio = length(vec_edges_predio)
    vecSecTodos = collect(1:numLadosPredio)
    vecSecSinCalle = setdiff(vecSecTodos, vecSecConCalle)

    dict_geom = Dict(
        "ps_combi" => ps_combi,
        "ps_calles" => ps_calles,
        "ps_publico" => ps_publico,
        "ps_bruto" => ps_bruto,
        "ps_calles_contexto" => ps_calles_contexto,
        "n_predios" => df_combined[1,"num_predios"],
        "vecSecTodos" => vecSecTodos,
        "vecSecSinCalle" => vecSecSinCalle,
        "vecSecConCalle" => vecSecConCalle,
        "vecAnchoCalle" => vecAnchoCalle,
        "sup_terreno_sii" => sup_terreno_sii,
        "dx" => dx,
        "dy" => dy
    )

    return dict_geom

end

