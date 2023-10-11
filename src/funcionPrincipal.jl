function funcionPrincipal(tipoOptimizacion, codigo_predial::Union{Array{Int64,1},Int64}, id_, datos_LandValue, datos_mygis_db, datos)

    ##############################################
    # PARTE "1": OBTENCIÓN DE PARÁMETROS         #
    ##############################################

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

    # Calcula matriz V_areaEdif asociada a los vértices del area de edificación
    display("Establece el área de edificación")

    vec_edges_predio, aux = polyShape.polyShape2lineVec(ps_predio)
    numLadosPredio = length(vec_edges_predio)
    vecSecTodos = collect(1:numLadosPredio)
    vecSecSinCalle = setdiff(vecSecTodos, vecSecConCalle)

    antejardin = dcn.antejardin[1]
    sepVecinos = dcn.distanciamiento[1]
    densidadMax = dcn.densidadMax
    maxPisos = round(dcn.maxPisos)
    alturaMax = dcn.alturaMax
    rasante = dcn.rasante
    coefConstructibilidad = dcn.coefConstructibilidad
    coefOcupacion = dcn.coefOcupacion
    
    vec_edges = vecSecTodos
    vec_dist = Float64.(vec_edges)
    vec_dist .= -antejardin
    vec_dist[vecSecSinCalle] .= -sepVecinos
    ps_areaEdif = polyShape.polyExpandSegmentVec(ps_predio, vec_dist)
    area_max_region = 0
    id_max = 1
    if ps_areaEdif.NumRegions >= 2
        for i = 1:ps_areaEdif.NumRegions
            ps_areaEdif_i = polyShape.subShape(ps_areaEdif, i)
            area_i = polyShape.polyArea(ps_areaEdif_i)
            if area_i > area_max_region
                area_max_region = area_i
                id_max = i
            end
        end
    end
    V_areaEdif = ps_areaEdif.Vertices[id_max]
    sup_areaEdif = polyShape.polyArea(ps_areaEdif)


    if tipoOptimizacion == "volumetrica"
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


        sepNaves = 18.0 #5.# 12.0 #dca.anchoMin - 0
        porcTerraza = 0.15 / 1.075

        default_min_pisos = 3

        fopt = 10000.0
        xopt = []
        flagSeguir = true
        temp_opt = 0

        # plan_optimizacion = [[5, 0, [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 ,20]]]

        # [template, flag_viv_eco, pisos]
        set_pisos_true_viv_econ = [3, 4]
        plan_optimizacion = [[0, 1, set_pisos_true_viv_econ]]
        push!(plan_optimizacion, [1, 1, set_pisos_true_viv_econ])
        push!(plan_optimizacion, [5, 1, set_pisos_true_viv_econ])
        push!(plan_optimizacion, [6, 1, set_pisos_true_viv_econ])
        push!(plan_optimizacion, [7, 1, set_pisos_true_viv_econ])
        push!(plan_optimizacion, [10, 1, set_pisos_true_viv_econ])

        set_pisos_false_viv_econ = [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
        push!(plan_optimizacion, [0, 0, set_pisos_false_viv_econ])
        push!(plan_optimizacion, [1, 0, set_pisos_false_viv_econ])
        push!(plan_optimizacion, [5, 0, set_pisos_false_viv_econ])
        push!(plan_optimizacion, [6, 0, set_pisos_false_viv_econ])
        push!(plan_optimizacion, [7, 0, set_pisos_false_viv_econ])
        push!(plan_optimizacion, [10, 0, set_pisos_false_viv_econ])

        flag_penalizacion_residual = true
        flag_penalizacion_coefOcup = true
        flag_penalizacion_constructibilidad = true
        flag_penalizacion_constructibilidad = flag_penalizacion_constructibilidad & (dcn.coefConstructibilidad > 0)
        flag_conSombra = true
        flag_divergenciaAncho = false

        #                    0    1    2    3      4    5         6         7    8              9       10
        vec_template_str = ["I", "L", "C", "lll", "V", "H-flex", "C-flex", "S", "C-superFlex", "Cuña", "Z"]

        

        largos, angulosExt, angulosInt, largosDiag = polyShape.extraeInfoPoly(ps_areaEdif)
        maxDiagonal = maximum(largosDiag)


        mat_res = []
        for r in eachindex(plan_optimizacion)

            # template: [0:I, 1:L, 2:C, 3:lll, 4:V, 5:H]
            template = plan_optimizacion[r][1]
            flag_viv_eco = plan_optimizacion[r][2]
            set_pisos = plan_optimizacion[r][3]

            if maxPisos in set_pisos
                if flag_viv_eco == 1 && maxPisos == 3
                    sepVecinos = 10.0
                    densidadMax = dcn.densidadMax * 1.25
                    maxPisos = 4
                    alturaMax = 14.0
                    coefConstructibilidad = -1 #5
                    coefOcupacion = -1
                elseif flag_viv_eco == 1 && maxPisos == 4
                    densidadMax = dcn.densidadMax * 1.25
                    maxPisos = 4
                    alturaMax = 14.0
                    coefConstructibilidad = -1 #5
                    coefOcupacion = -1
                elseif flag_viv_eco == 1 && maxPisos == 5
                    densidadMax = dcn.densidadMax * 1.25
                    maxPisos = 4
                    alturaMax = 14.0
                    coefConstructibilidad = -1 #5
                    coefOcupacion = -1
                end

                lb_bbo, ub_bbo = generaCotas(template, default_min_pisos, floor(maxPisos), V_areaEdif, sepNaves, maxDiagonal, dca.anchoMin, dca.anchoMin + 0.1)
                obj_bbo = x -> fo_bbo(x, template, sepNaves, ps_areaEdif)

                display("Optimización BBO con Template Tipo " * vec_template_str[template+1])
                x_bbo, f_bbo = optim_bbo(obj_bbo, lb_bbo, ub_bbo)

                # Favorece templates 0 y 1 
                if template in [0, 1]
                    f_bbo = f_bbo * 1.05
                end

                display("f_bbo = " * string(f_bbo) * "; x_obb = " * string(x_bbo))

                mat_res = push!(mat_res, [f_bbo, x_bbo, template, flag_viv_eco, sepVecinos, densidadMax, maxPisos, alturaMax, coefConstructibilidad, coefOcupacion])
            end
        end

        num_res = length(mat_res)
        pos_id = sortperm([mat_res[i][1] for i = 1:num_res])
        mat_res = mat_res[pos_id]

        # Calcula el volumen y sombra teórica 
        vec_altVolteor = collect(0:0.1:50) .* rasante
        vec_altVolteor = vec_altVolteor[vec_altVolteor.<alturaMax]
        push!(vec_altVolteor, alturaMax)
        vec_psVolteor = [polyShape.polyExpand(ps_bruto, -i / rasante) for i in vec_altVolteor]
        vec_psVolteor = [polyShape.polyIntersect(vec_psVolteor[i], ps_areaEdif) for i in eachindex(vec_psVolteor)]


        display("Calcula sombra del Volumen Teórico")
        @time ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s = generaSombraTeor(vec_psVolteor, vec_altVolteor, ps_publico, ps_calles)

        areaSombra_p = polyShape.polyArea(ps_sombraVolTeorico_p)
        areaSombra_o = polyShape.polyArea(ps_sombraVolTeorico_o)
        areaSombra_s = polyShape.polyArea(ps_sombraVolTeorico_s)


        display("Calcula el volumen sin restricciones")
        rasante_sombra = Float64(dcn.rasanteSombra)
        vec_altVolConSombra = collect(0:0.5:50) .* rasante_sombra
        vec_altVolConSombra = vec_altVolConSombra[vec_altVolConSombra.<alturaMax]
        push!(vec_altVolConSombra, alturaMax)
        vec_psVolConSombra = [polyShape.polyExpand(ps_bruto, -i / rasante_sombra) for i in vec_altVolConSombra]
        vec_psVolConSombra = [polyShape.polyIntersect(vec_psVolConSombra[i], ps_areaEdif) for i in eachindex(vec_psVolConSombra)]
        @time verts_conSombra, vecAlturas_conSombra = generaVol3D(vec_psVolConSombra, vec_altVolConSombra)

        x_bbo_opt = []
        f_bbo_opt = 10000
        template_opt = 0
        flag_viv_eco_opt = []
        sepVecinos_opt = []
        maxPisos_opt = []
        alturaMax_opt = []
        densidadMax_opt = []
        maxOcupación = []
        maxSupConstruida = []
        cont = 1
        flag_continuar = true
        while flag_continuar
            try
                f_bbo_opt = mat_res[cont][1]
                x_bbo_opt = mat_res[cont][2]
                template_opt = mat_res[cont][3]
                flag_viv_eco_opt = mat_res[cont][4]
                sepVecinos_opt = mat_res[cont][5]
                densidadMax_opt = mat_res[cont][6]
                maxPisos_opt = mat_res[cont][7]
                alturaMax_opt = mat_res[cont][8]
                coefConstructibilidad_opt = mat_res[cont][9]
                coefOcupacion_opt = mat_res[cont][10]

                maxOcupación = coefOcupacion_opt > 0 ? coefOcupacion_opt * superficieTerreno : sup_areaEdif
                maxSupConstruida = coefConstructibilidad_opt > 0 ? superficieTerreno * coefConstructibilidad_opt * (1 + 0.3 * dcp.fusionTerrenos) : maxPisos_opt * sup_areaEdif
        
                flag_divergenciaAncho = template_opt in [5, 6, 7, 8, 10]
                num_penalizaciones = flag_penalizacion_residual + flag_penalizacion_constructibilidad + flag_conSombra + flag_divergenciaAncho

                obj_nomad = x -> fo_nomad(x, template_opt, sepNaves, dca, porcTerraza, flag_conSombra, flag_penalizacion_residual, flag_penalizacion_coefOcup,
                    flag_penalizacion_constructibilidad, flag_divergenciaAncho,
                    vec_psVolConSombra, vec_altVolConSombra, vec_psVolteor, vec_altVolteor,
                    maxOcupación, maxSupConstruida, areaSombra_p, areaSombra_o, areaSombra_s, ps_publico, ps_calles)

                display("Template Tipo " * vec_template_str[template_opt+1] * ": Inicio de Optimización NOMAD")
                MaxSteps = 8000
                lb, ub = generaCotas(template_opt, default_min_pisos, floor(maxPisos_opt), V_areaEdif, sepNaves, maxDiagonal, dca.anchoMin, dca.anchoMax)
                initSol = max.(min.(copy(x_bbo_opt), ub), lb)
                initSol[1] = floor(maxPisos_opt)
                x_nomad, f_nomad = optim_nomad(obj_nomad, num_penalizaciones, lb, ub, MaxSteps, initSol)

                fopt = f_nomad
                xopt = copy(x_nomad)
                temp_opt = template_opt
        

                flag_continuar = false
            catch
                cont += 1                end
        end

        display("Obtiene datos necesarios para graficar resultado")

        areaBasal, ps_base, ps_baseSeparada = resultConverter(xopt, temp_opt, sepNaves)
        numPisos = Int(round(xopt[1]))
        alturaEdif = numPisos * dca.alturaPiso[1]

        # Obtiene calles al interior del buffer
        ps_calles_intra_buffer = polyShape.polyIntersect(ps_calles, ps_buffer_predio)

        # Obtiene predios contenidos al interior del buffer 
        ps_predios_intra_buffer = queryCabida.query_predios_intra_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)

        # Obtiene manzanas contenidas al interior del buffer 
        ps_manzanas_intra_buffer = queryCabida.query_manzanas_intra_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)

        alturaPiso = dca.alturaPiso[1]

        buffer_dist_ = min(140, 2.7474774194546216 * xopt[1] * alturaPiso)
        ps_buffer_predio_ = polyShape.shapeBuffer(ps_predio, buffer_dist_, 20)
        ps_calles_intra_buffer_ = polyShape.shapeBuffer(ps_calles_intra_buffer, buffer_dist_, 20)
        ps_predios_intra_buffer_ = polyShape.polyIntersect(ps_predios_intra_buffer, ps_buffer_predio_)
        ps_manzanas_intra_buffer_ = polyShape.polyIntersect(ps_manzanas_intra_buffer, ps_buffer_predio_)

        areaOcupacion = min(areaBasal, maxOcupación)
        razon_ocupacion_basal = areaOcupacion / areaBasal

        ps_primerPiso = polyShape.polyShrink(ps_base, razon_ocupacion_basal)

        vec_datos = [ps_predio, vec_psVolteor, vec_altVolteor, ps_publico, ps_calles, ps_base, ps_baseSeparada, ps_primerPiso,
            ps_calles_intra_buffer_, ps_predios_intra_buffer_, ps_manzanas_intra_buffer_, ps_buffer_predio_, dx, dy, ps_areaEdif]


        pg_julia.close_db(conn_LandValue)
        pg_julia.close_db(conn_mygis_db)

        sleep(3)


        return fpe, temp_opt, alturaPiso, xopt, vec_datos, superficieTerreno, superficieTerrenoBruta

    else
        display("Obtiene DatosCabidaComercial")

        if tipoOptimizacion == "economica"
            query_str = """
            SELECT * FROM tabla_cabida_comercial
            WHERE codigo_predial = \'codigo_predial_\'
            """
            query_str = replace(query_str, "codigo_predial_" => string(codigo_predial))
            @time df_comercial = pg_julia.query(conn_LandValue, query_str)
        elseif tipoOptimizacion == "provisoria"
            query_str = """
            SELECT * FROM tabla_tipo_deptos
            """
            @time df_comercial = pg_julia.query(conn_LandValue, query_str)
        end


        dcc = DatosCabidaComercial()
        for field_s in fieldnames(DatosCabidaComercial)
            value_ = df_comercial[:, field_s]
            setproperty!(dcc, field_s, value_)
        end
        porcTerraza = sum(dcc.supTerraza ./ dcc.supDeptoUtil) / length(dcc.supTerraza)

        dcr = DatosCabidaRentabilidad(1.2)

        display("")
        display("Inicio de Optimización Económica: Predio N° " * string(codigo_predial))

        if isempty(datos) # Si datos está vacío, se obtiene la info. de la tabla_resultados_cabidas
            
            queryStr = """
            SELECT cabida_altura, ps_base, optimo_solucion, terreno_superficie, 
            terreno_superficie_bruta, norma_viv_economica, norma_max_num_deptos, norma_max_ocupacion,
            norma_max_constructibilidad, norma_max_pisos FROM tabla_resultados_cabidas WHERE cond_
            """
            condStr = "combi_predios " * "= \'" * string(codigo_predial) * "\'"
            queryStr = replace(queryStr, "cond_" => condStr)
            df_ = pg_julia.query(conn_LandValue, queryStr)

            alturaEdif = df_[1, "cabida_altura"]
            ps_base = eval(Meta.parse(df_[1, "ps_base"]))
            superficieTerreno = df_[1, "terreno_superficie"]
            superficieTerrenoBruta = df_[1, "terreno_superficie_bruta"]
            xopt = eval(Meta.parse(df_[1, "optimo_solucion"]))

            flag_viv_eco_opt = df_[1, "norma_viv_economica"]
            maxDeptos_opt = df_[1, "norma_max_num_deptos"]
            maxOcupación_opt = df_[1, "norma_max_ocupacion"]
            maxSupConstruida_opt = df_[1, "norma_max_constructibilidad"]
            maxPisos_opt = df_[1, "norma_max_pisos"]

            mat_dcn_opt = [flag_viv_eco_opt, maxDeptos_opt, maxOcupación_opt, maxSupConstruida_opt, maxPisos_opt]
            
        else # Si datos contiene información predefinida, se utiliza esa info.
            alturaEdif = datos[1]
            ps_base = datos[2]
            superficieTerreno = datos[3]
            superficieTerrenoBruta = datos[4]
            xopt = datos[5]
            ps_areaEdif = datos[6]
        end

       
        sn, sa, si, st, so, sm, sf = optiEdificio(dcn, dca, dcp, dcc, dcu, dcr, mat_dcn_opt, alturaEdif, ps_base, superficieTerreno, superficieTerrenoBruta, sup_areaEdif)
        resultados = ResultadoCabida(sn, sa, si, st, sm, so, xopt)

        tipo_Depto = ""
        cantidad_Depto = ""
        for i in eachindex(dcc.tipoUnidad[resultados.salidaArquitectonica.numDeptosTipo.>0.1])
            tipo_Depto = tipo_Depto * string(replace(dcc.tipoUnidad[resultados.salidaArquitectonica.numDeptosTipo.>0.1][i], "Tipo_" => "")) * ", "
            cantidad_Depto = cantidad_Depto * string(resultados.salidaArquitectonica.numDeptosTipo[resultados.salidaArquitectonica.numDeptosTipo.>0.1][i]) * ", "
        end

        vecColumnNames = [
            "norma_min_estacionamientos_vendibles",
            "norma_min_estacionamientos_visita",
            "norma_min_estacionamientos_discapacitados",
            "cabida_tipo_deptos",
            "cabida_num_deptos",
            "cabida_ocupacion",
            "cabida_constructibilidad",
            "cabida_superficie_interior",
            "cabida_superficie_terraza",
            "cabida_superficie_comun",
            "cabida_superficie_edificada_snt",
            "cabida_superficie_por_piso",
            "cabida_estacionamientos_vendibles",
            "cabida_estacionamientos_visita",
            "cabida_num_estacionamientos",
            "cabida_num_bicicleteros",
            "cabida_num_bodegas",
            "terreno_costo",
            "terreno_costo_unit",
            "terreno_costo_corredor",
            "terreno_costo_demolicion",
            "terreno_otros",
            "terreno_costo_total",
            "terreno_costo_unit_total",
            "holgura_ocupacion",
            "holgura_constructibilidad",
            "holgura_densidad",
            "indicador_ingresos_ventas",
            "indicador_costo_total",
            "indicador_margen_antes_impuesto",
            "indicador_impuesto_renta",
            "indicador_utilidad_despues_impuesto",
            "indicador_rentabilidad_total_bruta",
            "indicador_rentabilidad_total_neta",
            "indicador_incidencia_terreno"]

        vecColumnValue = [
            resultados.salidaNormativa.minEstacionamientosVendibles,
            resultados.salidaNormativa.minEstacionamientosVisita,
            resultados.salidaNormativa.minEstacionamientosDiscapacitados,
            "\'[" * string(tipo_Depto) * "]\'",
            "\'[" * string(cantidad_Depto) * "]\'",
            resultados.salidaArquitectonica.ocupacion,
            resultados.salidaArquitectonica.constructibilidad,
            resultados.salidaArquitectonica.superficieInterior,
            resultados.salidaArquitectonica.superficieTerraza,
            resultados.salidaArquitectonica.superficieComun,
            resultados.salidaArquitectonica.superficieEdificadaSNT,
            resultados.salidaArquitectonica.superficiePorPiso,
            resultados.salidaArquitectonica.estacionamientosVendibles,
            resultados.salidaArquitectonica.estacionamientosVisita,
            resultados.salidaArquitectonica.numEstacionamientos,
            resultados.salidaArquitectonica.numBicicleteros,
            resultados.salidaArquitectonica.numBodegas,
            resultados.salidaTerreno.costoTerreno,
            resultados.salidaTerreno.costoUnitTerreno,
            resultados.salidaTerreno.costoCorredor,
            resultados.salidaTerreno.costoDemolicion,
            resultados.salidaTerreno.otrosTerreno,
            resultados.salidaTerreno.costoTotalTerreno,
            resultados.salidaTerreno.costoUnitTerrenoTotal,
            resultados.salidaOptimizacion.dualMaxOcupación,
            resultados.salidaOptimizacion.dualMaxConstructibilidad,
            resultados.salidaOptimizacion.dualMaxDensidad,
            resultados.salidaIndicadores.ingresosVentas,
            resultados.salidaIndicadores.costoTotal,
            resultados.salidaIndicadores.margenAntesImpuesto,
            resultados.salidaIndicadores.impuestoRenta,
            resultados.salidaIndicadores.utilidadDespuesImpuesto,
            resultados.salidaIndicadores.rentabilidadTotalBruta,
            resultados.salidaIndicadores.rentabilidadTotalNeta,
            resultados.salidaIndicadores.incidenciaTerreno]

        pg_julia.close_db(conn_LandValue)
        pg_julia.close_db(conn_mygis_db)

        sleep(3)

        return dcc, resultados, xopt, vecColumnNames, vecColumnValue, id_, codigo_predial

    end

end
