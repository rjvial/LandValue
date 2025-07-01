function funcionPrincipal(codigo_predial::Union{Array{Int64,1},Int64}, id_, datos_LandValue, datos_mygis_db, datos)

    my_env = DotEnv.config("secrets.env")
    conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
    conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])
    
    conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])
    instance_info = aws_julia.find_instance_by_name("Neo4j-EC2", conn_aws)

    key_pair   = "neo4j-key-pair.pem"
    ec2_user   = "ec2-user"
    public_dns = instance_info["dnsName"]

    folder = "/usr/bin/cypher-shell"
    neo4j_host = "bolt://localhost:7687"
    neo4j_user = "neo4j"
    neo4j_password = "x67y1332"

    conn_neo4j = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)


    ##############################################
    # PARTE "1": OBTENCIÓN DE PARÁMETROS         #
    ##############################################

    display("Obtiene DatosCabidaArquitectura")
    @time df_arquitectura = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_arquitectura_default";""")
    dca = DatosCabidaArquitectura()
    for field_s in fieldnames(DatosCabidaArquitectura)
        value_ = df_arquitectura[:, field_s][1]
        setproperty!(dca, field_s, value_)
    end

    codPredialStr = replace(replace(string(codigo_predial), "[" => "("), "]" => ")")

    # Obtiene desde la base de datos los parametros del predio
    display("Obtiene desde la base de datos los parametros del predio")
    @time dcn, sup_terreno_sii, ps_predio_db = queryCabida.query_datos_predio(conn_mygis_db, "vitacura", codPredialStr)

    dcn.rasanteSombra = 5.0
    dcn.flagDensidadBruta = true
    dcn.estacionamientosPorViv = 1.0
    dcn.porcAdicEstacVisitas = 0.15
    dcn.supPorEstacionamiento = 30.0
    dcn.supPorBodega = 5.0
    dcn.estBicicletaPorEst = 0.5
    dcn.bicicletasPorEst = 3.0
    dcn.flagCambioEstPorBicicleta = true
    dcn.maxSubte = 7.0
    dcn.coefOcupacionEst = 0.7
    dcn.sepEstMin = 1.5
    dcn.reduccionEstPorDistMetro = false

    dcn.distanciamiento = 6 #3 #
    dcn.antejardin = 7 #4 #
    dcn.rasante = 1.7320508075688767
    dcn.alturaMax = 10 * 2.55 #17.5
    dcn.maxPisos = 10
    dcn.coefOcupacion = .4
    dcn.supPredialMin = 800
    dcn.densidadMax = 360*2
    dcn.coefConstructibilidad = 2


    dcc = DatosCabidaComercial()
    # dcc.tipoUnidad = 
    dcc.supInterior = [25, 65, 85, 120]
    dcc.supTerraza = [10, 20, 30, 40]
    dcc.supDeptoUtil = dcc.supTerraza .+ 0.5 * dcc.supTerraza
    dcc.estacionamientosPorViv = 1.5 #2
    dcc.bodegasPorViv = 1

    porcTerraza = sum(dcc.supTerraza ./ dcc.supDeptoUtil) / length(dcc.supTerraza)


    # Obtiene desde Neo4j las geometrias de los predios
    display("Obtiene desde Neo4j las geometrias de los predios")

    quoted_list = "[" * join(["'" * string(c) * "'" for c in codigo_predial], ",") * "]"
    query = """
        MATCH (gp:Geom_Predio)-[]-(p:Predio)
        WHERE p.codigo_predial IN $quoted_list
        RETURN DISTINCT p.codigo_predial AS codigo_predial, gp.geom_wkt AS geom_wkt
        ORDER BY codigo_predial
    """
    df_predios = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
    ps_predio_db = polyShape.astext2polyshape(df_predios[:, "geom_wkt"])
    ps_predio_db = polyShape.setPolyOrientation(ps_predio_db,1)
    ps_predio_db = polyShape.reproject_polyshape(ps_predio_db)
    ps_predio_db, dx, dy = polyShape.ajustaCoordenadas(ps_predio_db)
    ps_predio_db = polyShape.polyUnion(ps_predio_db)
    simplify_value = 1.0 #1. #.1
    ps_predio = polyShape.shapeSimplify(ps_predio_db, simplify_value)
    ps_predio = polyShape.polyEliminaColineales(ps_predio)

    V_predio = ps_predio.Vertices[1]
    superficieTerreno = sup_terreno_sii[1]
    superficieTerrenoCalc = polyShape.polyArea(ps_predio)
    dcp = DatosCabidaPredio(V_predio[:, 1], V_predio[:, 2], [], [], 0, 200)
    numLotes = length(codigo_predial)
    dcp.fusionTerrenos = numLotes >= 2 ? 1 : 0

    #################################
    # Obtiene predios y calles contenidos en el buffer del predio y ajusta coordenadas
    #################################

    buffer_dist = 70.0 #140

    # Obtiene buffer del predio seleccionado
    display("Obtiene buffer del predio seleccionado")
    ps_buffer_predio = polyShape.shapeBuffer(ps_predio, buffer_dist, 30)

    # Obtiene predios contenidos en el buffer del predio y ajusta coordenadas
    display("Obtiene predios contenidos en el buffer del predio y ajusta coordenadas")
    # query = """
    # MATCH (p:Predio)-[]-(m:Manzana)
    # WHERE p.codigo_predial IN $quoted_list
    # MATCH (m_:Manzana)-[:ES_VECINA_A]-(m)
    # WITH m, m_
    # UNWIND [m, m_] AS m2
    # MATCH (gp:Geom_Predio)-[]-(p2:Predio)-[:SE_UBICA_EN_MANZANA]-(m2)
    # RETURN DISTINCT gp.geom_wkt AS geom_wkt
    # """
    query = """
    MATCH (m:Manzana)
    WHERE m.manzent IN ['13132011001009','13132011001006','13132011001008','13132011003019','13132011003023','13132011003024','13132011003028','13132011001013','13132011001012']
    WITH m
    MATCH (gp:Geom_Predio)-[]-(p:Predio)-[:SE_UBICA_EN_MANZANA]-(m)
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
    # query = """
    # MATCH (p:Predio)-[]-(m:Manzana)
    # WHERE p.codigo_predial IN $quoted_list
    # MATCH (m_:Manzana)-[:ES_VECINA_A]-(m)
    # WITH m, m_
    # UNWIND [m, m_] AS m2
    # RETURN DISTINCT m2.geom_wkt AS geom_wkt
    # """
    query = """
    MATCH (m:Manzana)
    WHERE m.manzent IN ['13132011001009','13132011001006','13132011001008','13132011003019','13132011003023','13132011003024','13132011003028','13132011001013','13132011001012']    
    WITH m
    RETURN DISTINCT m.geom_wkt AS geom_wkt
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
    dcp.ladosConCalle = vecSecConCalle
    dcp.anchoEspacioPublico = vecAnchoCalle

    superficieTerrenoBruto = polyShape.polyArea(ps_bruto)

    # Calcula matriz V_areaEdif asociada a los vértices del area de edificación
    display("Establece el área de edificación")

    vec_edges_predio, aux = polyShape.polyShape2lineVec(ps_predio)
    numLadosPredio = length(vec_edges_predio)
    vecSecTodos = collect(1:numLadosPredio)
    vecSecSinCalle = setdiff(vecSecTodos, vecSecConCalle)

    antejardin = dcn.antejardin[1] # 8 # 12 # 
    sepVecinos = dcn.distanciamiento[1] # 7 # dcn.distanciamiento[1] # 10 # 
    # densidadMax = dcn.densidadMax
    maxPisos = round(dcn.maxPisos)
    alturaMax = dcn.alturaMax
    rasante = dcn.rasante


    vec_edges = vecSecTodos
    vec_dist = Float64.(vec_edges)
    vec_dist .= -antejardin
    vec_dist[vecSecSinCalle] .= -sepVecinos
    ps_areaEdif = polyShape.partialPolyOffset(ps_predio, vec_edges, vec_dist)

    sup_areaEdif = polyShape.polyArea(ps_areaEdif)

    vec_dist = Float64.(vec_edges)
    vec_dist .= -antejardin
    vec_dist[vecSecSinCalle] .= -dcn.sepEstMin
    ps_areaEst = polyShape.partialPolyOffset(ps_predio, vec_edges, vec_dist)

    display("Obtención de calles dentro del buffer")
    @time ps_calles_intra_buffer = polyShape.polyIntersect(ps_calles, ps_buffer_predio)

    display("Calcula el espacio publico y bruto")

    porcTerraza = 0.15 / 1.075
    default_min_pisos = 3
    vec_pisos = collect(default_min_pisos:maxPisos)
    
    # Calcula el Volumen Teórico
    vec_altVolteor = collect(0:0.1:50) .* rasante
    vec_altVolteor = vec_altVolteor[vec_altVolteor .< alturaMax]
    push!(vec_altVolteor, alturaMax)
    vec_psVolteor = [polyShape.polyOffset(ps_bruto, -i / rasante) for i in vec_altVolteor]
    vec_psVolteor = [polyShape.polyIntersect(vec_psVolteor[i], ps_areaEdif) for i in eachindex(vec_psVolteor)]

    # Calcula sombra del Volumen Teórico
    @time ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s = generaSombraTeor(vec_psVolteor, vec_altVolteor, ps_publico, ps_calles)

    areaSombra_p = polyShape.polyArea(ps_sombraVolTeorico_p)
    areaSombra_o = polyShape.polyArea(ps_sombraVolTeorico_o)
    areaSombra_s = polyShape.polyArea(ps_sombraVolTeorico_s)

    centroidSombra_p = polyShape.shapeCentroid(ps_sombraVolTeorico_p)
    centroidSombra_o = polyShape.shapeCentroid(ps_sombraVolTeorico_o)
    centroidSombra_s = polyShape.shapeCentroid(ps_sombraVolTeorico_s)

    # Calcula el volumen sin restricciones
    rasante_sombra = Float64(dcn.rasanteSombra)
    vec_altVolConSombra = collect(0:0.1:50) .* rasante_sombra
    vec_altVolConSombra = vec_altVolConSombra[vec_altVolConSombra .< alturaMax]
    push!(vec_altVolConSombra, alturaMax)
    vec_psVolConSombra = [polyShape.polyOffset(ps_bruto, -i / rasante_sombra) for i in vec_altVolConSombra]
    vec_psVolConSombra = [polyShape.polyIntersect(vec_psVolConSombra[i], ps_areaEdif) for i in eachindex(vec_psVolConSombra)]


    alturaPiso = 2.55
    max_ocupacion_suelo = 1000 # dcn.coefOcupacion > 0 ? dcn.coefOcupacion * superficieTerreno : sup_areaEdif
    max_constructibilidad = superficieTerreno * dcn.coefConstructibilidad * (1 + 0.3 * dcp.fusionTerrenos) 
    maxConstruccionSNT = max_constructibilidad * .95 + max_constructibilidad * 0.10 + max_constructibilidad * 0.20 # Sup Terraza + Areas comunes
                       # Sup Interior                + Sup Terrazas                 + Areas comunes

    fpe = FlagPlotEdif3D()
    fpe.predio = true
    fpe.volTeorico = true
    fpe.volConSombra = true
    fpe.edif = true
    fpe.sombraVolTeorico_p = true
    fpe.sombraVolTeorico_o = true
    fpe.sombraVolTeorico_s = true
    fpe.sombraEdif_p = true
    fpe.sombraEdif_o = true
    fpe.sombraEdif_s = true


    K = 4
    ancho_crujia_edificio = 0 #16
    so, sh, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte = opti_edificio(dcn, dca, dcp, dcc, superficieTerreno, superficieTerrenoBruto, sup_areaEdif, ps_predio, ps_areaEst, vec_psVolteor, vec_altVolteor, vec_pisos, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K; ancho_crujia_edificio = 0)
    fig, ax, ax_mat = plotBaseEdificio3D(fpe, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, ps_publico, ps_calles, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte)

    K = 1
    ancho_crujia_edificio = 16
    so, sh, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte = opti_edificio_sombra(dcn, dca, dcp, dcc, superficieTerreno, superficieTerrenoBruto, sup_areaEdif, vec_psVolConSombra, vec_altVolConSombra, vec_pisos, alturaPiso, ps_areaEdif, ps_predio, ps_areaEst, ps_calles, ps_publico, ps_bruto, 
        areaSombra_p, areaSombra_o, areaSombra_s, max_ocupacion_suelo, maxConstruccionSNT, K, centroidSombra_p, centroidSombra_o, centroidSombra_s; ancho_crujia_edificio = ancho_crujia_edificio)
    fig, ax, ax_mat = plotBaseEdificio3D(fpe, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, ps_publico, ps_calles, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte)


end
