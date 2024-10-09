function funcionPrincipal(tipoOptimizacion, codigo_predial::Union{Array{Int64,1},Int64}, id_, datos_LandValue, datos_mygis_db, datos)

    ##############################################
    # PARTE "1": OBTENCIÓN DE PARÁMETROS         #
    ##############################################

    DotEnv.load("secrets.env")
    conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])

    conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])


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


    buffer_dist = 70 #140

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

    antejardin = dcn.antejardin[1] # 8 # 12 # 
    sepVecinos = dcn.distanciamiento[1] # 7 # dcn.distanciamiento[1] # 10 # 
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
    ps_areaEdif = polyShape.partialPolyOffset(ps_predio, vec_edges, vec_dist)
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

        # [template, flag_viv_eco, pisos]
        # ej.: plan_optimizacion = [[3, 0, [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 ,20]]]

        set_pisos_true_viv_econ = [3, 4]
        plan_optimizacion = [[0, 1, set_pisos_true_viv_econ]]
        push!(plan_optimizacion, [1, 1, set_pisos_true_viv_econ])
        # push!(plan_optimizacion, [2, 1, set_pisos_true_viv_econ])
        # push!(plan_optimizacion, [3, 1, set_pisos_true_viv_econ])
        # push!(plan_optimizacion, [4, 1, set_pisos_true_viv_econ])
        # push!(plan_optimizacion, [5, 1, set_pisos_true_viv_econ])
        # push!(plan_optimizacion, [6, 1, set_pisos_true_viv_econ])
        # push!(plan_optimizacion, [7, 1, set_pisos_true_viv_econ])

        set_pisos_false_viv_econ = collect(5:20) # [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
        push!(plan_optimizacion, [0, 0, set_pisos_false_viv_econ])
        push!(plan_optimizacion, [1, 0, set_pisos_false_viv_econ])
        # push!(plan_optimizacion, [2, 0, set_pisos_false_viv_econ])
        # push!(plan_optimizacion, [3, 0, set_pisos_false_viv_econ])
        # push!(plan_optimizacion, [4, 0, set_pisos_false_viv_econ])
        # push!(plan_optimizacion, [5, 0, set_pisos_false_viv_econ])
        # push!(plan_optimizacion, [6, 0, set_pisos_false_viv_econ])
        # push!(plan_optimizacion, [7, 0, set_pisos_false_viv_econ])

        flag_penalizacion_residual = true
        flag_penalizacion_coefOcup = true
        flag_penalizacion_constructibilidad = true
        flag_penalizacion_constructibilidad = flag_penalizacion_constructibilidad & (dcn.coefConstructibilidad > 0)
        flag_conSombra = true

        #                    0    1    2    3    4    5    6    7
        vec_template_str = ["I", "L", "H", "C", "S", "Z", "T", "II"]
        vec_template_length =[
           #"I", "L",    "H",             "C",       "S",       "Z",       "T",   "II"
            [6], [6, 7], [5, 6, 7, 8, 9], [7, 8, 9], [7, 8, 9], [7, 8, 9], [5, 7], [7,8]
        ] 
        vec_template_ancho =[
           #"I", "L",    "H",          "C",          "S",          "Z",          "T",   "II"
            [5], [8, 9], [10, 11, 12], [10, 11, 12], [10, 11, 12], [10, 11, 12], [8, 9], [11,12]
        ] 

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

                try
                    lb_bbo, ub_bbo = generaCotas(template, default_min_pisos, floor(maxPisos), V_areaEdif, sepNaves, maxDiagonal, dca.anchoMin, dca.anchoMin + .1)
                    obj_bbo = x -> fo_bbo(x, template, sepNaves, ps_areaEdif)

                    display("Optimización BBO con Template Tipo " * vec_template_str[template+1])
                    maxSteps = 20000
                    numIter = 30 #20
                    @time x_bbo, f_bbo = optim_bbo(obj_bbo, lb_bbo, ub_bbo, maxSteps, numIter)
                    if id_ == 0
                        areaBasal, ps_base, ps_baseSeparada = resultConverter(x_bbo, template, sepNaves)
                        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predio, 0.0, "green", 0.1)
                        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_areaEdif, 0.0, "red", 0.15, fig=fig, ax=ax, ax_mat=ax_mat)
                        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_base, 0.0, "blue", 0.15, fig=fig, ax=ax, ax_mat=ax_mat)
                    end

                    # Favorece templates 0 y 1
                    if template in [0, 1]
                        f_bbo = f_bbo * 1.05
                    end

                    display("f_bbo = " * string(f_bbo)) # * "; x_obb = " * string(x_bbo))

                    mat_res = push!(mat_res, [f_bbo, x_bbo, template, flag_viv_eco, sepVecinos, densidadMax, maxPisos, alturaMax, coefConstructibilidad, coefOcupacion])
                catch
                end
            end
        end

        num_res = length(mat_res)
        pos_id = sortperm([mat_res[i][1] for i = 1:num_res])
        mat_res = mat_res[pos_id]

        # Calcula el volumen y sombra teórica
        vec_altVolteor = collect(0:0.1:50) .* rasante
        vec_altVolteor = vec_altVolteor[vec_altVolteor .< alturaMax]
        push!(vec_altVolteor, alturaMax)
        vec_psVolteor = [polyShape.polyOffset(ps_bruto, -i / rasante) for i in vec_altVolteor]
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
        vec_psVolConSombra = [polyShape.polyOffset(ps_bruto, -i / rasante_sombra) for i in vec_altVolConSombra]
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
        flag_divergenciaAncho = template_opt in [1, 2, 3, 4, 5, 6, 7]
        status_optim = ""
        while flag_continuar
            try
                f_bbo_opt = mat_res[cont][1]
                x_bbo_opt = mat_res[cont][2]
                template_opt = mat_res[cont][3]
                flag_viv_eco_opt = mat_res[cont][4]
                sepVecinos_opt = mat_res[cont][5]
                densidadMax_opt = mat_res[cont][6]
                maxPisos_opt = maxPisos #mat_res[cont][7]
                alturaMax_opt = mat_res[cont][8]
                coefConstructibilidad_opt = mat_res[cont][9]
                coefOcupacion_opt = mat_res[cont][10]
                maxOcupación = coefOcupacion_opt > 0 ? coefOcupacion_opt * superficieTerreno : sup_areaEdif
                maxSupConstruida = coefConstructibilidad_opt > 0 ? superficieTerreno * coefConstructibilidad_opt * (1 + 0.3 * dcp.fusionTerrenos) : maxPisos_opt * sup_areaEdif


                display("Template Tipo " * vec_template_str[template_opt+1] * ": Inicio de Optimización BBO-2")
                lb_, ub_ = generaCotas(template_opt, default_min_pisos, floor(maxPisos_opt-1), V_areaEdif, sepNaves, maxDiagonal, dca.anchoMin, dca.anchoMax)
                delta_b = 0.1*(ub_ .- lb_)
                lb = copy(lb_)
                ub = copy(ub_)
                id_vec = vec_template_length[template_opt+1]
                lb[id_vec] = max.(x_bbo_opt[id_vec] .- delta_b[id_vec], lb_[id_vec])
                obj_bbo_e2 = x -> fo_bbo_e2(x, template_opt, sepNaves, dca, porcTerraza, flag_penalizacion_residual, 
                    flag_penalizacion_constructibilidad, flag_divergenciaAncho, vec_psVolteor, vec_altVolteor, maxOcupación, maxSupConstruida)
                display("Optimización BBO-2 con Template Tipo " * vec_template_str[template_opt+1])
                maxSteps = 3*20000
                numIter = 1*20
                @time x_bbo_e2, f_bbo_e2 = optim_bbo(obj_bbo_e2, lb, ub, maxSteps, numIter)
                areaBasal, ps_base, ps_baseSeparada = resultConverter(x_bbo_e2, template_opt, sepNaves)
                if id_ == 0
                    numPisos = Int(round(x_bbo_e2[1]))
                    superficieConstruidaSNT = areaBasal * (numPisos-1) + min(areaBasal, maxOcupación)
                    display([superficieConstruidaSNT / (1 + dca.porcSupComun + 0.5*porcTerraza)  maxSupConstruida])
                    fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predio, 0.0, "green", 0.1)
                    fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_areaEdif, 0.0, "red", 0.15, fig=fig, ax=ax, ax_mat=ax_mat)
                    fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_base, 0.0, "blue", 0.15, fig=fig, ax=ax, ax_mat=ax_mat)
                    display(areaBasal/sup_areaEdif)
                end

                if areaBasal/sup_areaEdif > 0.4
                    display("Template Tipo " * vec_template_str[template_opt+1] * ": Inicio de Optimización NOMAD")

                    lb_, ub_ = generaCotas(template_opt, default_min_pisos, floor(maxPisos_opt), V_areaEdif, sepNaves, maxDiagonal, dca.anchoMin, dca.anchoMax)
                    delta_b = 0.1*(ub_ .- lb_)
                    lb = max.(copy(x_bbo_e2) .- delta_b, lb_)
                    ub = min.(copy(x_bbo_e2) .+ delta_b, ub_)
                    lb[1] = floor(maxPisos_opt) - 1
                    ub[1] = floor(maxPisos_opt)
                    flag_conSombra = true
                    vec_ancho = vec_template_ancho[template_opt+1]
                    vec_largo = vec_template_length[template_opt+1]
                    num_penalizaciones = flag_penalizacion_residual + flag_penalizacion_constructibilidad + flag_conSombra + flag_divergenciaAncho
                    obj_nomad = x -> fo_nomad(x, template_opt, sepNaves, dca, porcTerraza, flag_conSombra, flag_penalizacion_residual, flag_penalizacion_coefOcup,
                        flag_penalizacion_constructibilidad, flag_divergenciaAncho, vec_ancho,
                        vec_psVolConSombra, vec_altVolConSombra, vec_psVolteor, vec_altVolteor,
                        maxOcupación, maxSupConstruida, areaSombra_p, areaSombra_o, areaSombra_s, ps_publico, ps_calles)
                    MaxSteps = 5000
                    initSol = max.(min.(copy(x_bbo_e2), ub), lb)
                    initSol[vec_ancho] = max.(x_bbo_e2[vec_ancho] .- 1, lb[vec_ancho])
                    initSol[vec_largo] = max.(x_bbo_e2[vec_largo] .- 3, lb[vec_largo])
                    initSol[1] = maxPisos
                    @time xopt, fopt, status, mat_bounds, out_vec  = optim_nomad(obj_nomad, num_penalizaciones, lb, ub, MaxSteps, initSol)
                    if status == "opt"
                        status_optim = "Optimo Encontrado"
                    else
                        status_optim = "Infactible"
                    end
                    # display(mat_bounds)
                    # display(out_vec)
                else
                    display("Relación areaBasal/sup_areaEdif = " * string(areaBasal/sup_areaEdif) * " , es menor a 0.6")
                    status_optim = "Baja Ocupacion"
                end

                temp_opt = template_opt
                flag_continuar = false
            catch
                cont += 1
                status_optim = "Error Nomad"
                if cont >= 3
                    flag_continuar = false
                end
            end
        end

        if status_optim == "Optimo Encontrado"
            display("Obtiene datos necesarios para graficar resultado")

            areaBasal, ps_base, ps_baseSeparada = resultConverter(xopt, temp_opt, sepNaves)
            numPisos = Int(round(xopt[1]))
            alturaEdif = numPisos * dca.alturaPiso[1]

            superficieConstruidaSNT = areaBasal * (numPisos-1) + min(areaBasal, maxOcupación)
            display([superficieConstruidaSNT / (1 + dca.porcSupComun + 0.5*porcTerraza)  maxSupConstruida])

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

            vecColumnNames = ["combi_predios",
                "norma_viv_economica",
                "norma_max_num_deptos",
                "norma_max_ocupacion",
                "norma_max_constructibilidad",
                "norma_max_pisos",
                "norma_max_altura",
                "norma_distanciamiento",
                "norma_min_estacionamientos_vendibles",
                "norma_min_estacionamientos_visita",
                "norma_min_estacionamientos_discapacitados",
                "cabida_temp_opt",
                "cabida_tipo_deptos",
                "cabida_num_deptos",
                "cabida_ocupacion",
                "cabida_constructibilidad",
                "cabida_num_pisos",
                "cabida_altura",
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
                "terreno_superficie",
                "terreno_superficie_bruta",
                "terreno_largoFrenteCalle",
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
                "indicador_incidencia_terreno",
                "optimo_solucion",
                "ps_predio",
                "vec_psVolteor",
                "vec_altVolteor",
                "ps_publico",
                "ps_calles",
                "ps_base",
                "ps_baseSeparada",
                "ps_primerPiso",
                "ps_predios_intra_buffer",
                "ps_manzanas_intra_buffer",
                "ps_calles_intra_buffer",
                "dx",
                "dy",
                "id"]

            vecColumnValue = [string(codigo_predial),
                Int(flag_viv_eco_opt),
                densidadMax_opt / 4 * (dcn.flagDensidadBruta ? superficieTerrenoBruta : superficieTerreno) / 10000, #resultados.salidaNormativa.maxNumDeptos,
                maxOcupación, #resultados.salidaNormativa.maxOcupacion,
                maxSupConstruida, #resultados.salidaNormativa.maxConstructibilidad,
                maxPisos_opt, #resultados.salidaNormativa.maxPisos,
                alturaMax_opt, #resultados.salidaNormativa.maxAltura,
                sepVecinos_opt, 
                0, #resultados.salidaNormativa.minEstacionamientosVendibles,
                0, #resultados.salidaNormativa.minEstacionamientosVisita,
                0, #resultados.salidaNormativa.minEstacionamientosDiscapacitados,
                temp_opt,
                "", # tipo_Depto,
                "", # cantidad_Depto,
                0, #resultados.salidaArquitectonica.ocupacion,
                0, #resultados.salidaArquitectonica.constructibilidad,
                numPisos, #resultados.salidaArquitectonica.numPisos,
                numPisos * dca.alturaPiso[1], #resultados.salidaArquitectonica.altura,
                0, #resultados.salidaArquitectonica.superficieInterior,
                0, #resultados.salidaArquitectonica.superficieTerraza,
                0, #resultados.salidaArquitectonica.superficieComun,
                0, #resultados.salidaArquitectonica.superficieEdificadaSNT,
                0, #resultados.salidaArquitectonica.superficiePorPiso,
                0, #resultados.salidaArquitectonica.estacionamientosVendibles,
                0, #resultados.salidaArquitectonica.estacionamientosVisita,
                0, #resultados.salidaArquitectonica.numEstacionamientos,
                0, #resultados.salidaArquitectonica.numBicicleteros,
                0, #resultados.salidaArquitectonica.numBodegas,
                superficieTerreno, #resultados.salidaTerreno.superficieTerreno,
                superficieTerrenoBruta, #resultados.salidaTerreno.superficieBruta,
                sum(polyShape.largoLadosPoly(ps_predio)[vecSecConCalle]),
                0, #resultados.salidaTerreno.costoTerreno,
                0, #resultados.salidaTerreno.costoUnitTerreno,
                0, #resultados.salidaTerreno.costoCorredor,
                0, #resultados.salidaTerreno.costoDemolicion,
                0, #resultados.salidaTerreno.otrosTerreno,
                0, #resultados.salidaTerreno.costoTotalTerreno,
                0, #resultados.salidaTerreno.costoUnitTerrenoTotal,
                0, #resultados.salidaOptimizacion.dualMaxOcupación,
                0, #resultados.salidaOptimizacion.dualMaxConstructibilidad,
                0, #resultados.salidaOptimizacion.dualMaxDensidad,
                0, #resultados.salidaIndicadores.ingresosVentas,
                0, #resultados.salidaIndicadores.costoTotal,
                0, #resultados.salidaIndicadores.margenAntesImpuesto,
                0, #resultados.salidaIndicadores.impuestoRenta,
                0, #resultados.salidaIndicadores.utilidadDespuesImpuesto,
                0, #resultados.salidaIndicadores.rentabilidadTotalBruta,
                0, #resultados.salidaIndicadores.rentabilidadTotalNeta,
                0, #resultados.salidaIndicadores.incidenciaTerreno,
                string(xopt), #string(resultados.xopt),
                string(ps_predio),
                string(vec_psVolteor),
                string(vec_altVolteor),
                string(ps_publico),
                string(ps_calles),
                string(ps_base),
                string(ps_baseSeparada),
                string(ps_primerPiso),
                string(ps_predios_intra_buffer),
                string(ps_manzanas_intra_buffer),
                string(ps_calles_intra_buffer),
                dx,
                dy,
                string(id_)]

            vec_datos = [ps_predio, vec_psVolteor, vec_altVolteor, ps_publico, ps_calles, ps_base, ps_baseSeparada, ps_primerPiso,
                ps_calles_intra_buffer_, ps_predios_intra_buffer_, ps_manzanas_intra_buffer_, ps_buffer_predio_, dx, dy, ps_areaEdif]

        else
            temp_opt = []
            alturaPiso = []
            xopt = []
            vec_datos = []
            vecColumnNames = []
            vecColumnValue = []
        
        end
    
        pg_julia.close_db(conn_LandValue)
        pg_julia.close_db(conn_mygis_db)


        return temp_opt, alturaPiso, xopt, vec_datos, vecColumnNames, vecColumnValue, id_, status_optim

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

        sleep(1)

        return dcc, resultados, xopt, vecColumnNames, vecColumnValue, id_, codigo_predial

    end

end
