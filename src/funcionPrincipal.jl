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

    display("Obtiene DatosCabidaUnit")
    @time df_costosunitarios = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_costosunitarios_default";""")
    dcu = DatosCabidaUnit()
    for field_s in fieldnames(DatosCabidaUnit)
        value_ = df_costosunitarios[:, field_s][1]
        setproperty!(dcu, field_s, value_)
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
    dcn.coefOcupacionEst = 0.8
    dcn.sepEstMin = 7.0
    dcn.reduccionEstPorDistMetro = false

    # Datos inventados  
    dcn.distanciamiento = 3 #6
    dcn.antejardin = 4 #7
    dcn.rasante = 1.7320508075688767
    dcn.alturaMax = 17.5
    dcn.maxPisos = 5
    dcn.coefOcupacion = .4
    dcn.supPredialMin = 800
    dcn.densidadMax = 360
    dcn.coefConstructibilidad = 3


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
    # @time ps_buffer_predio = queryCabida.query_buffer_predio(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)
    ps_buffer_predio = polyShape.shapeBuffer(ps_predio, buffer_dist, 30)

    # Obtiene predios contenidos en el buffer del predio y ajusta coordenadas
    display("Obtiene predios contenidos en el buffer del predio y ajusta coordenadas")
    # @time ps_predios_buffer = queryCabida.query_predios_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)
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

    # Obtiene manzanas contenidas en el buffer del predio
    display("Obtiene manzanas contenidas en el buffer del predio")
    # @time ps_manzanas_buffer = queryCabida.query_manzanas_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)
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


    display("Obtención del conjunto de calles en el entorno del predio")
    @time ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle = obtieneCalles(ps_predio, ps_buffer_predio, ps_predios_buffer, ps_manzanas_buffer)
    dcp.ladosConCalle = vecSecConCalle
    dcp.anchoEspacioPublico = vecAnchoCalle

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
    coefConstructibilidad = dcn.coefConstructibilidad
    coefOcupacion = dcn.coefOcupacion

    vec_edges = vecSecTodos
    vec_dist = Float64.(vec_edges)
    vec_dist .= -antejardin
    vec_dist[vecSecSinCalle] .= -sepVecinos
    ps_areaEdif = polyShape.partialPolyOffset(ps_predio, vec_edges, vec_dist)


    display("Obtención de calles dentro del buffer")
    @time ps_calles_intra_buffer = polyShape.polyIntersect(ps_calles, ps_buffer_predio)

    display("Calcula el espacio publico y bruto")
    # sup_areaEdif = polyShape.polyArea(ps_areaEdif)
    # superficieTerrenoBrutaCalc = polyShape.polyArea(ps_bruto)
    # superficieTerrenoBruta = superficieTerrenoBrutaCalc / superficieTerrenoCalc * superficieTerreno

    porcTerraza = 0.15 / 1.075
    default_min_pisos = 3
    vec_pisos = collect(default_min_pisos:maxPisos)
    
    # Calcula el volumen y sombra teórica
    vec_altVolteor = collect(0:0.1:50) .* rasante
    vec_altVolteor = vec_altVolteor[vec_altVolteor .< alturaMax]
    push!(vec_altVolteor, alturaMax)
    vec_psVolteor = [polyShape.polyOffset(ps_bruto, -i / rasante) for i in vec_altVolteor]
    vec_psVolteor = [polyShape.polyIntersect(vec_psVolteor[i], ps_areaEdif) for i in eachindex(vec_psVolteor)]

    alturaPiso = 2.55
    ps_opt, sup_opt, np_opt = optimal_box_volume(vec_psVolteor, vec_altVolteor, vec_pisos, alturaPiso)

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
    fig, ax, ax_mat = polyShape.plotBaseEdificio3D(fpe, [np_opt], alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, ps_publico, ps_calles, ps_opt, ps_opt, ps_opt)


end
