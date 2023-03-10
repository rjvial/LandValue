function funcionPrincipal(tipoOptimizacion, codigo_predial::Union{Array{Int64,1}, Int64}, id_)

    ##############################################
    # PARTE "1": OBTENCIÓN DE PARÁMETROS         #
    ##############################################

    # conn_LandValue = pg_julia.connection("LandValue", "postgres", "postgres")
    # conn_mygis_db = pg_julia.connection("mygis_db", "postgres", "postgres")

    conn_LandValue = pg_julia.connection("landengines", ENV["USER"], ENV["PW"], ENV["HOST"])
    conn_mygis_db = pg_julia.connection("gis_data", ENV["USER"], ENV["PW"], ENV["HOST"])


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


    codPredialStr = replace(replace(string(codigo_predial),"[" => "("),"]" => ")")

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
    ps_predio_db = polyShape.setPolyOrientation(ps_predio_db,1)
    ps_predio_db, dx, dy = polyShape.ajustaCoordenadas(ps_predio_db)
    ps_predio_db = polyShape.polyUnion(ps_predio_db)
    simplify_value = 1. #1. #.1
    ps_predio = polyShape.shapeSimplify(ps_predio_db, simplify_value)
    ps_predio = polyShape.polyEliminaColineales(ps_predio)
    V_predio = ps_predio.Vertices[1]
    superficieTerreno = sup_terreno_sii[1]
    superficieTerrenoCalc = polyShape.polyArea(ps_predio)
    dcp = DatosCabidaPredio(V_predio[:,1], V_predio[:,2], [], [], 0, 200)
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


        # Calcula matriz V_areaEdif asociada a los vértices del area de edificación
        display("Establece el área de edificación")
        V_areaEdif = copy(V_predio)
        numLadosPredio = size(V_areaEdif, 1)
        conjuntoLados = 1:numLadosPredio
        conjuntoLadosCalle = dcp.ladosConCalle
        conjuntoLadosVecinos = setdiff(conjuntoLados, conjuntoLadosCalle)
        sepVecinos = dcn.distanciamiento
        rasante = dcn.rasante
        antejardin = dcn.antejardin
        vecDist = fill(1.0, numLadosPredio)
        vecDist[conjuntoLadosCalle] .= -antejardin[1]
        vecDist[conjuntoLadosVecinos] .= -sepVecinos[1]
        ps_areaEdif = PolyShape([V_predio], 1)
        ps_areaEdif = polyShape.polyExpandSegmentVec(ps_areaEdif, vecDist, collect(conjuntoLados))
        ps_areaEdif = polyShape.polySimplify(polyShape.polySimplify(ps_areaEdif))
        V_areaEdif = ps_areaEdif.Vertices[1]
        sup_areaEdif = polyShape.polyArea(ps_areaEdif)


        # Calcula el volumen y sombra teórica 
        display("Calcula el volumen teórico")
        @time matConexionVertices_volTeorico, vecVertices_volTeorico, ps_volTeorico = generaVol3D(ps_predio, ps_bruto, rasante, dcn, dcp)
        V_volTeorico = ps_volTeorico.Vertices[1]
        vecAlturas_volTeorico = sort(unique(V_volTeorico[:, end]))

        display("Calcula sombra del Volumen Teórico")
        @time ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s = generaSombraTeor(ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico, ps_publico, ps_calles)
        rasante_sombra = Float64(dcn.rasanteSombra)

        display("Calcula el volumen sin restricciones")
        @time matConexionVertices_conSombra, vecVertices_conSombra, ps_volConSombra = generaVol3D(ps_predio, ps_bruto, rasante_sombra, dcn, dcp)
        V_volConSombra = ps_volConSombra.Vertices[1]
        vecAlturas_conSombra = sort(unique(V_volConSombra[:, end]))

        areaSombra_p = polyShape.polyArea(ps_sombraVolTeorico_p)
        areaSombra_o = polyShape.polyArea(ps_sombraVolTeorico_o)
        areaSombra_s = polyShape.polyArea(ps_sombraVolTeorico_s)


        sepNaves = dca.anchoMin - 3

        maxSupConstruida = superficieTerreno * dcn.coefConstructibilidad * (1 + 0.3 * dcp.fusionTerrenos)
        maxOcupación = dcn.coefOcupacion * superficieTerreno
        flag_penalizacion_residual = true
        flag_penalizacion_coefOcup = true
        flag_penalizacion_constructibilidad = true
        flag_conSombra = true
        num_penalizaciones = flag_penalizacion_residual + flag_penalizacion_coefOcup + flag_penalizacion_constructibilidad + flag_conSombra


        min_pisos_bbo = min(4, dcn.maxPisos[1] - 1)
        alt_bbo = min_pisos_bbo * dca.alturaPiso
        obj_bbo = x -> fo_bbo(x, template, sepNaves, dca, V_volConSombra, vecAlturas_conSombra, vecVertices_conSombra, matConexionVertices_conSombra, maxOcupación)

        porcTerraza = 0.15/1.075
        obj_nomad = x -> fo_nomad(x, template, sepNaves, dca, porcTerraza, flag_conSombra, flag_penalizacion_residual, flag_penalizacion_coefOcup, flag_penalizacion_constructibilidad,
        V_volConSombra, vecAlturas_conSombra, vecVertices_conSombra, matConexionVertices_conSombra, 
        V_volTeorico, vecAlturas_volTeorico, vecVertices_volTeorico, matConexionVertices_volTeorico,
        maxOcupación, maxSupConstruida, areaSombra_p, areaSombra_o, areaSombra_s, ps_publico, ps_calles)


        largos, angulosExt, angulosInt, largosDiag = polyShape.extraeInfoPoly(ps_areaEdif)
        maxDiagonal = maximum(largosDiag)

        default_min_pisos = 3

        fopt = 10000.
        xopt = []
        flagSeguir = true
        template = 0 # [0:I, 1:L, 2:C, 3:lll, 4:V, 5:H]
        intento = 1
        maxIntentos = 1
        temp_opt = template

        function chequeaSolucion(x, f, fopt, template, intento)
            alt = min(x[1] * dca.alturaPiso, maximum(vecAlturas_conSombra))
            areaBasal, ps_base, ps_baseSeparada = resultConverter(x, template, sepNaves)
            numPisos = Int(round(alt / dca.alturaPiso))

            superficieConstruidaSNT = numPisos * areaBasal
            constructibilidad = superficieConstruidaSNT / (1 + dca.porcSupComun + 0.5*porcTerraza)
    
            holgura_constructibilidad = (maxSupConstruida - constructibilidad)/maxSupConstruida 
            holgura_ocupacion = (maxOcupación - areaBasal)/maxOcupación
            holgura_superficie = (sup_areaEdif - areaBasal)/sup_areaEdif
    
            ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s = generaSombraEdificio(ps_baseSeparada, alt, ps_publico, ps_calles)
            areaSombraEdif_p = polyShape.polyArea(ps_sombraEdif_p)
            areaSombraEdif_o = polyShape.polyArea(ps_sombraEdif_o)
            areaSombraEdif_s = polyShape.polyArea(ps_sombraEdif_s)
            deltaSombra_p = abs(areaSombra_p - areaSombraEdif_p)
            deltaSombra_o = abs(areaSombra_o - areaSombraEdif_o)
            deltaSombra_s = abs(areaSombra_s - areaSombraEdif_s)
            holgura_sombra = minimum([deltaSombra_p, deltaSombra_o, deltaSombra_s])
            flagSeguir = true

            if f < 99990

                display("Template N° " * string(template) * "  - f: " * string(f) * "  - constructibilidad: " * string(constructibilidad))
                display("Holgura Constructibilidad: " * string(holgura_constructibilidad) )
                display("Holgura Ocupación: " * string(holgura_ocupacion) )
                display("Holgura Superficie: " * string(holgura_superficie) )
                display("Holgura Sombra: " * string(holgura_sombra) )
                if f < fopt
                    temp_opt = template
                    fopt = f
                    xopt = x
                    display("Template N° " * string(template) * " - Intento N° " * string(intento) * ": Se obtuvo una solución mejor." )
                else
                    display("Template N° " * string(template) * " - Intento N° " * string(intento) * ": No se obtuvo una solución mejor.")
                end
        
                optiTol = 0.0015
                if (holgura_constructibilidad <= optiTol) || (holgura_ocupacion <= optiTol &&  numPisos == dcn.maxPisos[1]) 
                    display("Template N° " * string(template) * " - Intento N° " * string(intento) * ": Solución óptima encontrada. ")
                    flagSeguir = false
                elseif intento == maxIntentos
                    display("Template N° " * string(template) * " - Intento N° " * string(intento) * ": No se encontró una solución óptima. Se procederá con el Template N° "  * string(template + 1))
                    template += 1
                    intento = 1
                else
                    display("Template N° " * string(template) * " - Intento N° " * string(intento) * ": No se encontró una solución óptima. Se realizará un nuevo intento.")
                    intento += 1
                end
            else
                display("Template N° " * string(template) * " - Intento N° " * string(intento) * ": Solución Infactible. ")
                template += 1
            end

            return fopt, template, intento, flagSeguir
        end

        while flagSeguir

            lb, ub = generaCotas(template, default_min_pisos, floor(dcn.maxPisos[1]), V_areaEdif, sepNaves, maxDiagonal, dca.anchoMin, dca.anchoMax)

            display("Template N° " * string(template) * " - Intento N° " * string(intento) * ": Inicio de Optimización BBO. Genera solución inicial.")
            x_bbo, f_bbo = optim_bbo(obj_bbo, lb, ub)

            display("Template N° " * string(template) * " - Intento N° " * string(intento) * ": Inicio de Optimización NOMAD")
            MaxSteps = 8000
            initSol = max.(min.(copy(x_bbo),ub),lb)
            initSol[1] = floor(dcn.maxPisos[1])
            x_nomad, f_nomad = optim_nomad(obj_nomad, num_penalizaciones, lb, ub, MaxSteps, initSol)

            fopt, template, intento, flagSeguir = chequeaSolucion(x_nomad, f_nomad, fopt, template, intento) 

            if template > 2
                display("Template N° " * string(template) * " es superior al template máximo (= 2). Optimización se dentendrá.")
                flagSeguir = false
            end
            
        end

        alt = min(xopt[1] * dca.alturaPiso[1], maximum(vecAlturas_conSombra))
        areaBasal, ps_base, ps_baseSeparada = resultConverter(xopt, temp_opt, sepNaves)
        numPisos = Int(round(xopt[1]))
        alturaEdif = numPisos * dca.alturaPiso[1]

        ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s = generaSombraEdificio(ps_baseSeparada, alt, ps_publico, ps_calles)

        display("Obtiene datos necesarios para graficar resultado")

        # Obtiene calles al interior del buffer
        ps_calles_intra_buffer = polyShape.polyIntersect(ps_calles, ps_buffer_predio)


        # Obtiene predios contenidos al interior del buffer 
        ps_predios_intra_buffer = queryCabida.query_predios_intra_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)

        # Obtiene manzanas contenidas al interior del buffer 
        ps_manzanas_intra_buffer = queryCabida.query_manzanas_intra_buffer(conn_mygis_db, "vitacura", codPredialStr, buffer_dist, dx, dy)


        vecColumnNames = ["combi_predios",
        "norma_max_num_deptos",
        "norma_max_ocupacion",
        "norma_max_constructibilidad",
        "norma_max_pisos",
        "norma_max_altura",
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
        "ps_vol_teorico", 
        "mat_conexion_vertices_vol_teorico", 
        "vecVertices_volTeorico", 
        "ps_volConSombra", 
        "mat_conexion_vertices_con_sombra",
        "vec_vertices_con_sombra", 
        "ps_publico", 
        "ps_calles", 
        "ps_base", 
        "ps_baseSeparada",
        "ps_predios_intra_buffer", 
        "ps_manzanas_intra_buffer", 
        "ps_calles_intra_buffer",
        "dx",
        "dy",
        "id"]


        vecColumnValue = [string(codigo_predial),
        dcn.densidadMax / 4 * (dcn.flagDensidadBruta ? superficieTerrenoBruta : superficieTerreno) / 10000, #resultados.salidaNormativa.maxNumDeptos,
        superficieTerreno*dcn.coefOcupacion, #resultados.salidaNormativa.maxOcupacion,
        superficieTerreno*dcn.coefConstructibilidad*(1 + 0.3 * dcp.fusionTerrenos), #resultados.salidaNormativa.maxConstructibilidad,
        dcn.maxPisos[1], #resultados.salidaNormativa.maxPisos,
        dcn.alturaMax[1], #resultados.salidaNormativa.maxAltura,
        0, #resultados.salidaNormativa.minEstacionamientosVendibles,
        0, #resultados.salidaNormativa.minEstacionamientosVisita,
        0, #resultados.salidaNormativa.minEstacionamientosDiscapacitados,
        temp_opt,
        "", # tipo_Depto,
        "", # cantidad_Depto,
        0, #resultados.salidaArquitectonica.ocupacion,
        0, #resultados.salidaArquitectonica.constructibilidad,
        numPisos, #resultados.salidaArquitectonica.numPisos,
        numPisos*dca.alturaPiso[1], #resultados.salidaArquitectonica.altura,
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
        string(ps_volTeorico), 
        string(matConexionVertices_volTeorico), 
        string(vecVertices_volTeorico), 
        string(ps_volConSombra), 
        string(matConexionVertices_conSombra),
        string(vecVertices_conSombra), 
        string(ps_publico), 
        string(ps_calles), 
        string(ps_base), 
        string(ps_baseSeparada),
        string(ps_predios_intra_buffer), 
        string(ps_manzanas_intra_buffer), 
        string(ps_calles_intra_buffer),
        dx,
        dy,
        string(id_)]
        if id_ > 0
            pg_julia.insertRow!(conn_LandValue, "tabla_resultados_cabidas", vecColumnNames, vecColumnValue, :id)
        end
    
        alturaPiso = dca.alturaPiso[1]

        buffer_dist_ = min(140, 2.7474774194546216 * xopt[1] * alturaPiso)
        ps_buffer_predio_ = polyShape.shapeBuffer(ps_predio, buffer_dist_, 20)
        ps_calles_intra_buffer_ = polyShape.shapeBuffer(ps_calles_intra_buffer, buffer_dist_, 20)
        ps_predios_intra_buffer_ = polyShape.polyIntersect(ps_predios_intra_buffer, ps_buffer_predio_)
        ps_manzanas_intra_buffer_ = polyShape.polyIntersect(ps_manzanas_intra_buffer, ps_buffer_predio_)

        vec_datos = [ps_predio, ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico, ps_volConSombra, 
                    matConexionVertices_conSombra, vecVertices_conSombra, ps_publico, ps_calles, ps_base, ps_baseSeparada,
                    ps_calles_intra_buffer_, ps_predios_intra_buffer_, ps_manzanas_intra_buffer_, ps_buffer_predio_, dx, dy, ps_areaEdif]
                    
        return fpe, temp_opt, alturaPiso, xopt, vec_datos
    
    elseif tipoOptimizacion == "economica" 

        display("Obtiene DatosCabidaComercial")
        query_str = """
        SELECT * FROM tabla_cabida_comercial
        WHERE codigo_predial = \'codigo_predial_\'
        """
        query_str = replace(query_str, "codigo_predial_" => string(codigo_predial))
        @time df_comercial = pg_julia.query(conn_LandValue, query_str)
    
        dcc = DatosCabidaComercial()
        for field_s in fieldnames(DatosCabidaComercial)
            value_ = df_comercial[:, field_s]
            setproperty!(dcc, field_s, value_)
        end
        porcTerraza = sum(dcc.supTerraza ./ dcc.supDeptoUtil) / length(dcc.supTerraza)
    
        dcr = DatosCabidaRentabilidad(1.2)

        display("")
        display("Inicio de Optimización Económica: Predio N° " * string(codigo_predial))

        queryStr = """
        SELECT cabida_altura, ps_base, optimo_solucion, terreno_superficie, terreno_superficie_bruta FROM tabla_resultados_cabidas WHERE cond_
        """
        condStr = "combi_predios " * "= \'" * string(codigo_predial) * "\'" 
        queryStr = replace(queryStr, "cond_" => condStr)
        df_ = pg_julia.query(conn_LandValue, queryStr)
        alturaEdif = df_[1,"cabida_altura"]
        ps_base = eval(Meta.parse(df_[1, "ps_base"]))
        superficieTerreno = df_[1,"terreno_superficie"]
        superficieTerrenoBruta = df_[1,"terreno_superficie_bruta"]
        xopt = eval(Meta.parse(df_[1, "optimo_solucion"]))

        sn, sa, si, st, so, sm, sf = optiEdificio(dcn, dca, dcp, dcc, dcu, dcr, alturaEdif, ps_base, superficieTerreno, superficieTerrenoBruta)
        #xopt[1] = numPisos #sa.altura 
        #numPisos = sa.numPisos[1]
        resultados = ResultadoCabida(sn, sa, si, st, sm, so, xopt)

        tipo_Depto = ""
        cantidad_Depto = ""
        for i in eachindex(dcc.tipoUnidad[resultados.salidaArquitectonica.numDeptosTipo .> 0.1])
            tipo_Depto = tipo_Depto * string(replace(dcc.tipoUnidad[resultados.salidaArquitectonica.numDeptosTipo .> 0.1][i],"Tipo_" => "")) * ", "
            cantidad_Depto = cantidad_Depto * string(resultados.salidaArquitectonica.numDeptosTipo[resultados.salidaArquitectonica.numDeptosTipo .> 0.1][i]) * ", "
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

        if id_ > 0
            pg_julia.modifyRow!(conn_LandValue, "tabla_resultados_cabidas", vecColumnNames, vecColumnValue, "combi_predios", "= \'" * string(codigo_predial) * "\'")
        end

        
        return dcc, resultados, xopt
        
    end    

end