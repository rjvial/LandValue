using LandValue, Distributed, DotEnv, BlackBoxOptim, Images, ImageBinarization

let

    codigo_predial = [151600217300030, 151600217300048, 151600217300049, 151600217300050, 151600217300051, 151600217300052, 151600217300053]
    # Para cómputos sobre la base de datos usar codigo_predial = []

    tipoOptimizacion = "volumetrica"

    DotEnv.load("secrets.env")
    datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
    datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
    # datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
    # datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

    conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
    conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])

    id_ = 0

    DotEnv.load("secrets.env")
    conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
    db_LandValue_str = datos_LandValue[1]
    query_LandValue_pid = """
                SELECT max(pid)
                FROM pg_stat_activity
                WHERE application_name = 'LibPQ.jl' AND datname = \'$db_LandValue_str\'
            """
    pid_landValue = pg_julia.query(conn_LandValue, query_LandValue_pid)[1, :max]

    conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])
    db_mygis_str = datos_mygis_db[1]
    query_mygis_pid = """
                SELECT max(pid)
                FROM pg_stat_activity
                WHERE application_name = 'LibPQ.jl' AND datname = \'$db_mygis_str\'
            """
    pid_mygis = pg_julia.query(conn_LandValue, query_mygis_pid)[1, :max]


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

    display("Obtiene FlagPlotEdif3D")
    @time df_flagplot = pg_julia.query(conn_LandValue, """SELECT * FROM public."tabla_flagplot_default";""")
    fpe = FlagPlotEdif3D()
    for field_s in fieldnames(FlagPlotEdif3D)
        value_ = df_flagplot[:, field_s][1]
        setproperty!(fpe, field_s, value_)
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

    # Simplifica, corrige orientacion y escala del predio
    ps_predio_db = polyShape.setPolyOrientation(ps_predio_db, 1)
    ps_predio_db, dx, dy = polyShape.ajustaCoordenadas(ps_predio_db)
    ps_predio_db = polyShape.polyUnion(ps_predio_db)
    # ps_predio_db = polyShape.polyExpand(polyShape.polyExpand(ps_predio_db,0.02),-0.02)
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


    buffer_dist = 140

    # Obtiene buffer del predio seleccionado
    display("Obtiene buffer del predio seleccionado")
    @time ps_buffer_predio = queryCabida.query_buffer_predio(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)


    # Obtiene predios contenidos en el buffer del predio y ajusta coordenadas
    display("Obtiene predios contenidos en el buffer del predio y ajusta coordenadas")
    @time ps_predios_buffer = queryCabida.query_predios_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)

    # Obtiene manzanas contenidas en el buffer del predio
    display("Obtiene manzanas contenidas en el buffer del predio")
    @time ps_manzanas_buffer = queryCabida.query_manzanas_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)

    display("Obtención del conjunto de calles en el entorno del predio")
    @time ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle = obtieneCalles(ps_predio, ps_buffer_predio, ps_predios_buffer, ps_manzanas_buffer)
    dcp.ladosConCalle = vecSecConCalle
    dcp.anchoEspacioPublico = vecAnchoCalle

    display("")
    display("Inicio de Optimización Volumétrica: Predio N° " * string(codigo_predial))

    display("Obtención de calles dentro del buffer")
    @time ps_calles_intra_buffer = polyShape.polyIntersect(ps_calles, ps_buffer_predio)

    # Obtiene ejes de calles contenidos al interior del buffer
    display("Obtiene ejes de calles contenidos al interior del buffer")
    @time ls_calles = queryCabida.query_calles_intra_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)

    display("Calcula el espacio publico y bruto")
    superficieTerrenoBrutaCalc = polyShape.polyArea(ps_bruto)
    superficieTerrenoBruta = superficieTerrenoBrutaCalc / superficieTerrenoCalc * superficieTerreno


    # Calcula matriz V_areaEdif asociada a los vértices del area de edificación
    display("Establece el área de edificación")

    vec_edges_predio = polyShape.polyShape2lineVec(ps_predio)
    numLadosPredio = length(vec_edges_predio)
    vecSecTodos = collect(1:numLadosPredio)
    vecSecSinCalle = setdiff(vecSecTodos, vecSecConCalle)

    antejardin = dcn.antejardin[1]
    sepVecinos = dcn.distanciamiento[1]

    vec_edges = vecSecTodos
    vec_dist = Float64.(vec_edges)
    vec_dist .= -antejardin
    vec_dist[vecSecSinCalle] .= -sepVecinos
    ps_areaEdif = polyShape.polyExpandSegmentVec(ps_predio, vec_dist)
    V_areaEdif = ps_areaEdif.Vertices[1]
    sup_areaEdif = polyShape.polyArea(ps_areaEdif)
    rasante = dcn.rasante

    vec_altVolteor = collect(0:0.5:50) .* rasante
    vec_altVolteor = vec_altVolteor[vec_altVolteor.<dcn.alturaMax]
    push!(vec_altVolteor, dcn.alturaMax)
    vec_psVolteor = [polyShape.polyExpand(ps_bruto, -i / rasante) for i in vec_altVolteor]
    vec_psVolteor = [polyShape.polyIntersect(vec_psVolteor[i], ps_areaEdif) for i in eachindex(vec_psVolteor)]


    # Calcula el volumen y sombra teórica 
    display("Calcula el volumen teórico")
    @time matConexionVertices_volTeorico, vecVertices_volTeorico, ps_volTeorico = generaVol3D(vec_psVolteor, vec_altVolteor)
    V_volTeorico = ps_volTeorico.Vertices[1]
    vecAlturas_volTeorico = sort(unique(V_volTeorico[:, end]))

    display("Calcula sombra del Volumen Teórico")
    @time ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s = generaSombraTeor(ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico, ps_publico, ps_calles)

    areaSombra_p = polyShape.polyArea(ps_sombraVolTeorico_p)
    areaSombra_o = polyShape.polyArea(ps_sombraVolTeorico_o)
    areaSombra_s = polyShape.polyArea(ps_sombraVolTeorico_s)


    display("Calcula el volumen sin restricciones")
    rasante_sombra = Float64(dcn.rasanteSombra)
    vec_altVolConSombra = collect(0:0.5:50) .* rasante_sombra
    vec_altVolConSombra = vec_altVolConSombra[vec_altVolConSombra.<dcn.alturaMax]
    push!(vec_altVolConSombra, dcn.alturaMax)
    vec_psVolConSombra = [polyShape.polyExpand(ps_bruto, -i / rasante_sombra) for i in vec_altVolConSombra]
    vec_psVolConSombra = [polyShape.polyIntersect(vec_psVolConSombra[i], ps_areaEdif) for i in eachindex(vec_psVolConSombra)]
    @time matConexionVertices_conSombra, vecVertices_conSombra, ps_volConSombra = generaVol3D(vec_psVolConSombra, vec_altVolConSombra)
    V_volConSombra = ps_volConSombra.Vertices[1]
    vecAlturas_conSombra = sort(unique(V_volConSombra[:, end]))

    sepNaves = 5.# 12.0 #dca.anchoMin - 0
    maxSupConstruida = superficieTerreno * dcn.coefConstructibilidad * (1 + 0.3 * dcp.fusionTerrenos)
    maxOcupación = dcn.coefOcupacion * superficieTerreno
    temp_opt = 2
    template = temp_opt

    min_pisos_bbo = min(4, dcn.maxPisos[1] - 1)
    alt_bbo = min_pisos_bbo * dca.alturaPiso
    obj_bbo = x -> fo_bbo(x, template, sepNaves, dca, V_volConSombra, vecAlturas_conSombra, vecVertices_conSombra, matConexionVertices_conSombra, maxOcupación)

    porcTerraza = 0.15 / 1.075

    largos, angulosExt, angulosInt, largosDiag = polyShape.extraeInfoPoly(ps_areaEdif)
    maxDiagonal = maximum(largosDiag)

    default_min_pisos = 3

    fopt = 10000.0
    flagSeguir = true

    # plan_optimizacion: [template, lb_bbo, ub_bbo]
    lb_bbo, ub_bbo = generaCotas(temp_opt, default_min_pisos, floor(dcn.maxPisos[1]), V_areaEdif, sepNaves, maxDiagonal, dca.anchoMin, dca.anchoMax)
    plan_optimizacion = [[temp_opt, lb_bbo, ub_bbo]]

    flag_penalizacion_residual = true
    flag_penalizacion_coefOcup = true
    flag_penalizacion_constructibilidad = true
    flag_conSombra = true
    flag_divergenciaAncho = false

    #                    0    1    2    3      4    5    6         7    8              9
    vec_template_str = ["I", "L", "C", "lll", "V", "H", "C-flex", "S", "C-superFlex", "Cuña"]


    temp_opt = plan_optimizacion[1][1]
    lb_bbo = plan_optimizacion[1][2]
    ub_bbo = plan_optimizacion[1][3]

    flag_divergenciaAncho = template in [7, 8]
    num_penalizaciones = flag_penalizacion_residual + flag_penalizacion_coefOcup + flag_penalizacion_constructibilidad + flag_conSombra + flag_divergenciaAncho

    display("Template Tipo " * vec_template_str[template+1] * ": Inicio de Optimización BBO. Genera solución inicial.")

    # Obtiene calles al interior del buffer
    ps_calles_intra_buffer = polyShape.polyIntersect(ps_calles, ps_buffer_predio)


    # Obtiene predios contenidos al interior del buffer 
    ps_predios_intra_buffer = queryCabida.query_predios_intra_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)

    # Obtiene manzanas contenidas al interior del buffer 
    ps_manzanas_intra_buffer = queryCabida.query_manzanas_intra_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)


    buffer_dist_ = min(140, 2.7474774194546216 * dcn.maxPisos[1] * dca.alturaPiso[1])
    ps_buffer_predio_ = polyShape.shapeBuffer(ps_predio, buffer_dist_, 20)
    ps_calles_intra_buffer_ = polyShape.shapeBuffer(ps_calles_intra_buffer, buffer_dist_, 20)
    ps_predios_intra_buffer_ = polyShape.polyIntersect(ps_predios_intra_buffer, ps_buffer_predio_)
    ps_manzanas_intra_buffer_ = polyShape.polyIntersect(ps_manzanas_intra_buffer, ps_buffer_predio_)


    # Repetición de optimizaciones bb para encontrar buena solución
    sr = [(lb_bbo[i], ub_bbo[i]) for i in eachindex(lb_bbo)] # Search Region    
    maxSteps = 50000 + 20000

    opt = BlackBoxOptim.bbsetup(obj_bbo; SearchRange=sr, NumDimensions=length(lb_bbo),
        Method=:adaptive_de_rand_1_bin_radiuslimited, MaxSteps=maxSteps, PopulationSize=1 * 500,
        TraceMode=:silent)

    res = BlackBoxOptim.run!(opt)
    xpop = BlackBoxOptim.population(res)

    pop_size = BlackBoxOptim.popsize(xpop)
    num_dims = BlackBoxOptim.numdims(xpop)
    x_mat = xpop[:]
    fit_vec = [BlackBoxOptim.fitness(xpop, i) for i = 1:pop_size]

    vec_pos = collect(1:pop_size)
    vec_pos_ = vec_pos[fit_vec.<=0]
    fit_vec_ = fit_vec[vec_pos_]
    vec_pos__ = vec_pos_[sortperm(fit_vec_, rev=true)]
    fit_vec__ = fit_vec[vec_pos__]
    x_mat__ = x_mat[:, vec_pos__]

    utility_vec = []
    for k in eachindex(vec_pos__)

        if k % 5 == 0
            aux = -fit_vec__[k]
            display("Generando Secuencia Imagen N° $k")
            display("Secuencia tiene fitness = $aux")

            push!(utility_vec, aux)

            xopt = x_mat__[:, k]
            alt = min(xopt[1] * dca.alturaPiso[1], maximum(vecAlturas_conSombra))
            areaBasal, ps_base, ps_baseSeparada = resultConverter(xopt, temp_opt, sepNaves)
            numPisos = Int(round(xopt[1]))
            alturaEdif = numPisos * dca.alturaPiso[1]

            ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s = generaSombraEdificio(ps_baseSeparada, alt, ps_publico, ps_calles)

            display("Obtiene datos necesarios para graficar resultado")


            alturaPiso = dca.alturaPiso[1]


            vec_datos = [ps_predio, ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico, ps_volConSombra,
                matConexionVertices_conSombra, vecVertices_conSombra, ps_publico, ps_calles, ps_base, ps_baseSeparada,
                ps_calles_intra_buffer_, ps_predios_intra_buffer_, ps_manzanas_intra_buffer_, ps_buffer_predio_, dx, dy, ps_areaEdif]

            ps_predio = vec_datos[1]
            ps_volTeorico = vec_datos[2]
            matConexionVertices_volTeorico = vec_datos[3]
            vecVertices_volTeorico = vec_datos[4]
            ps_volConSombra = vec_datos[5]
            matConexionVertices_conSombra = vec_datos[6]
            vecVertices_conSombra = vec_datos[7]
            ps_publico = vec_datos[8]
            ps_calles = vec_datos[9]
            ps_base = vec_datos[10]
            ps_baseSeparada = vec_datos[11]
            ps_calles_intra_buffer = vec_datos[12]
            ps_predios_intra_buffer = vec_datos[13]
            ps_manzanas_intra_buffer = vec_datos[14]
            ps_buffer_predio = vec_datos[15]
            dx = vec_datos[16]
            dy = vec_datos[17]
            ps_areaEdif = vec_datos[18]

            filestr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\secuencia_optimizacion\\____secuencia_optim_" * string(k) * ".png"


            fig, ax, ax_mat = plotBaseEdificio3D(fpe, xopt, alturaPiso, ps_predio, ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico,
                ps_volConSombra, matConexionVertices_conSombra, vecVertices_conSombra, ps_publico, ps_calles, ps_base, ps_baseSeparada)

            fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predios_intra_buffer, 0.0, "green", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
            fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_manzanas_intra_buffer, 0.0, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
            fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_buffer_predio, 0.0, "gray", 0.15, fig=fig, ax=ax, ax_mat=ax_mat, filestr=filestr)

            close("all")

            infileStr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\secuencia_optimizacion\\____secuencia_optim_" * string(k) * ".png"
            outfileStr = "C:\\Users\\rjvia\\Documents\\Land_engines_code\\Julia\\secuencia_optimizacion\\secuencia_optim_" * string(k) * ".png"

            img = load(infileStr)

            img_bn = binarize(Gray.(img), UnimodalRosin()) .< 0.5

            pos_vec = []

            vec_bn_h = sum(img_bn * 1, dims=1)
            for i = 1:length(vec_bn_h)-1
                if (vec_bn_h[i] == 0) && (vec_bn_h[i+1] >= 1) && (length(pos_vec) < 1)
                    pos_vec = push!(pos_vec, i)
                end
            end
            for i = length(vec_bn_h):-1:2
                if (vec_bn_h[i] == 0) && (vec_bn_h[i-1] >= 1) && (length(pos_vec) < 2)
                    pos_vec = push!(pos_vec, i)
                end
            end

            vec_bn_v = sum(img_bn * 1, dims=2)
            for i = 1:length(vec_bn_v)-1
                if (vec_bn_v[i] == 0) && (vec_bn_v[i+1] >= 1) && (length(pos_vec) < 3)
                    pos_vec = push!(pos_vec, i)
                end
            end
            for i = length(vec_bn_v):-1:2
                if (vec_bn_v[i] == 0) && (vec_bn_v[i-1] >= 1) && (length(pos_vec) < 4)
                    pos_vec = push!(pos_vec, i)
                end
            end

            img_cropped = img[pos_vec[3]:pos_vec[4], pos_vec[1]:pos_vec[2]]
            save(outfileStr, img_cropped)

            rm(infileStr)
        end


    end

    print(utility_vec)

    pg_julia.close_db(conn_LandValue)
    pg_julia.close_db(conn_mygis_db)

end