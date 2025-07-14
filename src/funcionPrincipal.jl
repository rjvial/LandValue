function funcionPrincipal(codigo_predial::Union{Array{Int64,1},Int64}, id_, datos_LandValue, datos_mygis_db, datos)

    my_env = DotEnv.config("secrets.env")
    conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
    
    conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])
    

    ec2_user   = "ec2-user"
    key_pair   = "neo4j-key-pair.pem"
    folder = "/usr/bin/cypher-shell"
    neo4j_host = "bolt://localhost:7687"
    neo4j_user = "neo4j"
    neo4j_password = "x67y1332"

    instance_info = aws_julia.find_instance_by_name("Neo4j-EC2", conn_aws)
    public_dns = instance_info["dnsName"]
    conn_neo4j = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)

    instance_info = aws_julia.find_instance_by_name("Neo4j-EC2_JLV", conn_aws)
    public_dns = instance_info["dnsName"]
    conn_neo4j_jlv = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)

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


    # Obtiene los parametros del predio
    display("Obtiene los parametros del predio")
    codPredialStr = replace(replace(string(codigo_predial), "[" => "("), "]" => ")")
    
    query = """
    MATCH (p:Predio {codigo_predial:'$(codigo_predial[1])'})
    MATCH (p)-[:PERTENECE_A|PERTENECE_A_USO]->(z)
    OPTIONAL MATCH (z)-[:TIENE_VARIANTE_NORMATIVA]->(vn)
    OPTIONAL MATCH (vn)-[:TIENE_REQ_NORMATIVO]->(r:Requerimiento_Normativo)
    OPTIONAL MATCH (r)-[:TIENE_REQ_CONDICIONAL]->(rc:Requerimiento_Condicional)
    WITH
    vn, r, collect(rc) AS condiciones
    WITH
    vn, r, CASE WHEN condiciones = [] THEN [null] ELSE condiciones END AS condiciones
    UNWIND condiciones AS cond
    RETURN
    vn.variante_norm_id        AS variante_norm_id,
    vn.nombre                  AS nombre_variante,
    r.requerimiento_norm_id    AS requerimiento_norm_id,
    r.nombre_requerimiento     AS nombre_requerimiento,
    r.valor                    AS valor,
    r.unidad                   AS unidad,
    r.tipo_restriccion         AS tipo_restriccion,
    cond.requerimiento_cond_id AS requerimiento_cond_id,
    cond.unidad                AS unidad_condicional,
    cond.parametro_formula     AS parametro_formula,
    cond.formula               AS formula,
    cond.nombre_requerimiento  AS nombre_req_condicional;
    """
    df_normativa = neo4j_julia.cypher_to_dataframe(query, conn_neo4j_jlv)
    lista_requerimientos = sort(unique(skipmissing(df_normativa[!, :nombre_requerimiento])))


    dict_sin_parametros = Dict{String,Any}()
    dict_con_parametros = Dict{String, NamedTuple{(:valor, :parametro_formula, :formula),Tuple{String,String,String}}}()

    for r in lista_requerimientos
        # 1) filter down to the matching row
        mask = 
        (df_normativa[!, :nombre_variante] .== "dfl_2") .&
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
                dict_sin_parametros[r] = parsed === nothing ? String(chosen) : parsed

            elseif valor_str == "NULL"
                # ───────── con parámetros ─────────
                dict_con_parametros[r] = (
                    valor = "",
                    parametro_formula = String(parametros_str),
                    formula           = String(formula_str)
                )
            else
                dict_con_parametros[r] = (
                    valor = String(valor_str),
                    parametro_formula = String(parametros_str),
                    formula           = String(formula_str)
                )
            end
        end
    end


    dcn = DatosCabidaNormativa()
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
    dcn.sepEstMin = dict_sin_parametros["subterraneo_antejardin"]
    dcn.reduccionEstPorDistMetro = false

    dcn.distanciamiento = 6 #3 #
    dcn.antejardin = dict_sin_parametros["antejardin"] #7 #4 #
    dcn.rasante = tan(dict_sin_parametros["rasante"]*pi/180) #1.7320508075688767
    dcn.alturaMax = dict_sin_parametros["altura_max"] #10 * 2.55 #17.5
    dcn.maxPisos = dict_sin_parametros["n_pisos"]
    dcn.coefOcupacion = dict_sin_parametros["coeficiente_de_ocupacion_de_suelo"] #.4
    dcn.supPredialMin = dict_sin_parametros["subdivision_predial_minima"]#800
    dcn.densidadMax = dict_sin_parametros["densidad_maxima_bruta"] #360*4
    n_predios = length(codigo_predial)
    coeficiente_de_constructibilidad = parse(Float64, dict_con_parametros["coeficiente_de_constructibilidad"][1])
    expr = Meta.parse(expression_converter.parse_python_expression( dict_con_parametros["coeficiente_de_constructibilidad"][3]))
    dcn.coefConstructibilidad = eval(expr)


    dcc = DatosCabidaComercial()
    # dcc.tipoUnidad = 
    dcc.supInterior = [25, 65, 85, 120, 240]
    dcc.supTerraza = [10, 20, 30, 40, 40]
    dcc.supDeptoUtil = dcc.supInterior .+ 0.5 * dcc.supTerraza
    dcc.estacionamientosPorViv = 1.5 #2
    dcc.bodegasPorViv = 1


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



    vec_edges_predio, aux = polyShape.polyShape2lineVec(ps_predio)
    numLadosPredio = length(vec_edges_predio)
    vecSecTodos = collect(1:numLadosPredio)
    vecSecSinCalle = setdiff(vecSecTodos, vecSecConCalle)

    display("Obtención de calles dentro del buffer")
    @time ps_calles_intra_buffer = polyShape.polyIntersect(ps_calles, ps_buffer_predio)

####################################################################################

    # Calcula matriz V_areaEdif asociada a los vértices del area de edificación


    maxPisos = round(dcn.maxPisos)
    default_min_pisos = maxPisos-2
    vec_pisos = collect(default_min_pisos:maxPisos)

    alturaPiso = 2.55

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


    K = 3; ancho_crujia_min = 0; ancho_crujia_max = 0; flag_sombra = false; tipo_edificio = "oficina"
    vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra = opti_edificio(alturaPiso, sup_terreno_sii, vecSecTodos, vecSecSinCalle, dict_con_parametros, dcn, dca, dcp, dcc, ps_bruto, ps_calles, ps_predio, ps_publico, vec_pisos, K, ancho_crujia_min, ancho_crujia_max, flag_sombra, tipo_edificio)
    fig, ax, ax_mat = plotBaseEdificio3D(fpe, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, ps_publico, ps_calles, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, tipo_edificio)

    K = 3; ancho_crujia_min = 0; ancho_crujia_max = 0; flag_sombra = true; tipo_edificio = "oficina"
    vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra = opti_edificio(alturaPiso, sup_terreno_sii, vecSecTodos, vecSecSinCalle, dict_con_parametros, dcn, dca, dcp, dcc, ps_bruto, ps_calles, ps_predio, ps_publico, vec_pisos, K, ancho_crujia_min, ancho_crujia_max, flag_sombra, tipo_edificio)
    fig, ax, ax_mat = plotBaseEdificio3D(fpe, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, ps_publico, ps_calles, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, tipo_edificio)


    K = 2; ancho_crujia_min = 12; ancho_crujia_max = 18; flag_sombra = false; tipo_edificio = "departamento"
    vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra = opti_edificio(alturaPiso, sup_terreno_sii, vecSecTodos, vecSecSinCalle, dict_con_parametros, dcn, dca, dcp, dcc, ps_bruto, ps_calles, ps_predio, ps_publico, vec_pisos, K, ancho_crujia_min, ancho_crujia_max, flag_sombra, tipo_edificio)
    fig, ax, ax_mat = plotBaseEdificio3D(fpe, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, ps_publico, ps_calles, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, tipo_edificio)
    
    K = 3; ancho_crujia_min = 12; ancho_crujia_max = 18; flag_sombra = true; tipo_edificio = "departamento"
    vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra = opti_edificio(alturaPiso, sup_terreno_sii, vecSecTodos, vecSecSinCalle, dict_con_parametros, dcn, dca, dcp, dcc, ps_bruto, ps_calles, ps_predio, ps_publico, vec_pisos, K, ancho_crujia_min, ancho_crujia_max, flag_sombra, tipo_edificio)
    fig, ax, ax_mat = plotBaseEdificio3D(fpe, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, ps_publico, ps_calles, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, tipo_edificio)


end



