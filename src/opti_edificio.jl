function opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos)

    tipo_edificio = dict_arquitectura["tipo_edificio"]
    variante_str = dict_arquitectura["variante_normativa"]
    flag_dfl2 = (variante_str == "dfl_2") ? true : false
    flag_economica = (variante_str == "vivienda_economica") ? true : false

    superficieTerreno = dict_geom["sup_terreno_sii"]
    superficieTerrenoBruto = polyShape.polyArea(dict_geom["ps_bruto"])

    # Ocupación de Suelo
    ocupacion_suelo = dict_requerimientos["coeficiente_de_ocupacion_de_suelo"]
    max_ocupacion_suelo = superficieTerreno * ocupacion_suelo
    sup_patio_vivienda_economica = flag_economica ? dict_requerimientos["superficice_min_patio_x_depto"] : 0

    # Constructibilidad
    if typeof(dict_requerimientos["coeficiente_de_constructibilidad"][1]) == Float64
        coefConstructibilidad = dict_requerimientos["coeficiente_de_constructibilidad"][1]
    else
        coeficiente_de_constructibilidad = parse(Float64, dict_requerimientos["coeficiente_de_constructibilidad"][1])
        expr_str = expression_converter.parse_python_expression(dict_requerimientos["coeficiente_de_constructibilidad"][3])
        expr_str = replace(expr_str, "n_predios" => dict_geom["n_predios"])
        expr_str = replace(expr_str, "coeficiente_de_constructibilidad" => coeficiente_de_constructibilidad)
        coefConstructibilidad = eval(Meta.parse(expr_str))
    end
    max_constructibilidad = superficieTerreno * coefConstructibilidad
    max_losa_snt = tipo_edificio == "departamento" && (flag_dfl2 || flag_economica) ? 
                                    (max_constructibilidad * .95 + max_constructibilidad * 0.10 + max_constructibilidad * 0.20) : 
                                    (max_constructibilidad * .95 + max_constructibilidad * 0.10) 
                                        # Sup Interior                + Sup Terrazas                 + Areas comunes

    # Max pisos
    maxPisos = dict_requerimientos["n_pisos"]
    default_min_pisos = max(3, maxPisos - 2)
    vec_pisos = collect(default_min_pisos:maxPisos)

    # Densidad
    flagDensidadBruta = haskey(dict_requerimientos, "densidad_maxima_bruta")
    superficieDensidad = flagDensidadBruta ? superficieTerrenoBruto : superficieTerreno
    max_densidad = flagDensidadBruta ? dict_requerimientos["densidad_maxima_bruta"] : dict_requerimientos["densidad_maxima_neta"]
    max_deptos = flagDensidadBruta ? floor(max_densidad / 4 * superficieDensidad / 10000) :
                                       floor(max_densidad / 4 * superficieDensidad / 10000)

    vec_ps_opt, vec_np_opt, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra = opti_edificio_vol(dict_geom, dict_arquitectura, dict_requerimientos, vec_pisos, max_ocupacion_suelo, max_losa_snt)
    
    # fpe = FlagPlotEdif3D()
    # fpe.predio = true
    # fpe.volTeorico = true
    # fpe.volConSombra = true
    # fpe.edif = true
    # fpe.sombraVolTeorico_p = true
    # fpe.sombraVolTeorico_o = true
    # fpe.sombraVolTeorico_s = true
    # fpe.sombraEdif_p = true
    # fpe.sombraEdif_o = true
    # fpe.sombraEdif_s = true
    # fig, ax, ax_mat = plotBaseEdificio3D(fpe, dict_arquitectura["alturaPiso"], dict_geom["ps_predio"], vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, dict_geom["ps_publico"], dict_geom["ps_calles"], vec_ps_opt, vec_np_opt, [], [], tipo_edificio)


    if tipo_edificio == "departamento"

        dict_edificio_deptos = opti_edificio_deptos(dict_arquitectura, max_constructibilidad, max_deptos, vec_ps_opt, vec_np_opt, flag_dfl2, sup_patio_vivienda_economica, superficieTerreno)

        if flag_economica
            ocupacion_de_suelo_economica = superficieTerreno - dict_edificio_deptos["numDeptos"] * sup_patio_vivienda_economica
            if ocupacion_de_suelo_economica <= polyShape.polyArea(vec_ps_opt[1])
                vec_ps_opt, vec_np_opt, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra = opti_edificio_vol(dict_geom, dict_arquitectura, dict_requerimientos, vec_pisos, ocupacion_de_suelo_economica, max_losa_snt)
            end
        end

        cabida_sup_deptos = string(dict_arquitectura["vecSupUtil"])
        cabida_num_deptos = string(dict_edificio_deptos["numDeptosTipo"])
        cabida_sup_comercio = string(0)
        cabida_num_comercio = string(0)
        cabida_sup_oficinas = string(0)
        cabida_num_oficinas = string(0)
    else
        area_edif = sum(polyShape.polyArea(vec_ps_opt[i]) * vec_np_opt[i] for i in eachindex(vec_ps_opt))

        cabida_sup_deptos = string(0)
        cabida_num_deptos = string(0)
        cabida_sup_comercio = string(0)
        cabida_num_comercio = string(0)
        cabida_sup_oficinas = string(100)
        cabida_num_oficinas = string(ceil(area_edif/100))
    end

    expr_str = expression_converter.parse_python_expression(dict_requerimientos["estacionamientos_autos"][3])
    expr_str = replace(expr_str, "cabida_sup_deptos" => cabida_sup_deptos)
    expr_str = replace(expr_str, "cabida_num_deptos" => cabida_num_deptos)
    expr_str = replace(expr_str, "cabida_sup_comercio" => cabida_sup_comercio)
    expr_str = replace(expr_str, "cabida_num_comercio" => cabida_num_comercio)
    expr_str = replace(expr_str, "cabida_sup_oficinas" => cabida_sup_oficinas)
    expr_str = replace(expr_str, "cabida_num_oficinas" => cabida_num_oficinas)
    dict_estacionamientos = eval(Meta.parse(expr_str))
    estacionamientos_autos_oficina = Float64(dict_estacionamientos["estacionamientos_autos_oficina"])
    estacionamientos_autos_vivienda = Float64(dict_estacionamientos["estacionamientos_autos_vivienda"])
    estacionamientos_autos_comercio = Float64(dict_estacionamientos["estacionamientos_autos_comercio"])
    estacionamientos_autos = estacionamientos_autos_oficina + estacionamientos_autos_vivienda + estacionamientos_autos_comercio
    
    expr_str = expression_converter.parse_python_expression(dict_requerimientos["estacionamientos_visitas"][3])
    expr_str = replace(expr_str, "estacionamientos_autos_vivienda" => string(estacionamientos_autos_vivienda))
    estacionamientos_visitas = Float64(eval(Meta.parse(expr_str)))

    numEst = estacionamientos_autos + estacionamientos_visitas
    numBodegas = tipo_edificio == "departamento" ? sum(dict_edificio_deptos["numDeptosTipo"]) : ceil(0.2*numEst)

    expr_str = expression_converter.parse_python_expression(dict_requerimientos["estacionamientos_discapacitados"][3])    
    expr_str = replace(expr_str, "estacionamientos_autos" => string(numEst))
    estacionamientos_discapacitados = Float64(eval(Meta.parse(expr_str)))

    carga_ocupacion = 100
    expr_str = expression_converter.parse_python_expression(dict_requerimientos["estacionamientos_bicicletas"][3])    
    expr_str = replace(expr_str, "estacionamientos_autos" => string(estacionamientos_autos))
    expr_str = replace(expr_str, "estacionamientos_visitas" => string(estacionamientos_visitas))
    expr_str = replace(expr_str, "carga_ocupacion" => string(carga_ocupacion))
    estacionamientos_bicicletas = Float64(eval(Meta.parse(expr_str)))

    distancia_al_metro = 3000
    expr_str = expression_converter.parse_python_expression(dict_requerimientos["descuento_estacionamientos_x_metro"][3])
    expr_str = replace(expr_str, "estacionamientos_autos_vivienda" => string(estacionamientos_autos_vivienda))
    expr_str = replace(expr_str, "estacionamientos_autos_comercio" => string(estacionamientos_autos_comercio))
    expr_str = replace(expr_str, "estacionamientos_autos_oficina" => string(estacionamientos_autos_oficina))
    expr_str = replace(expr_str, "distancia_al_metro" => string(distancia_al_metro))
    descuento_estacionamientos_x_metro = Float64(eval(Meta.parse(expr_str)))

    expr_str = expression_converter.parse_python_expression(dict_requerimientos["descuento_estacionamientos_x_bici"][3])
    expr_str = replace(expr_str, "estacionamientos_autos" => string(estacionamientos_autos))
    expr_str = replace(expr_str, "estacionamientos_visitas" => string(estacionamientos_visitas))
    expr_str = replace(expr_str, "descuento_estacionamientos_x_metro" => string(descuento_estacionamientos_x_metro))
    expr_str = replace(expr_str, "estacionamientos_bicicletas" => string(estacionamientos_bicicletas))
    dict_descuento_estacionamientos_x_bici = eval(Meta.parse(expr_str))
    descuento_estacionamientos_x_bici_t1 = Float64(dict_descuento_estacionamientos_x_bici["descuento_estacionamientos_x_bici_t1"])
    descuento_estacionamientos_x_bici_t2 = Float64(dict_descuento_estacionamientos_x_bici["descuento_estacionamientos_x_bici_t2"])
    descuento_estacionamientos_x_bici = Float64(dict_descuento_estacionamientos_x_bici["descuento_estacionamientos_x_bici"])

    expr_str = expression_converter.parse_python_expression(dict_requerimientos["aumento_bici_x_descuento_estacionamientos"][3])
    expr_str = replace(expr_str, "descuento_estacionamientos_x_bici_t2" => string(descuento_estacionamientos_x_bici_t2))
    aumento_bici_x_descuento_estacionamientos = eval(Meta.parse(expr_str))

    estacionamientos_autos_final = estacionamientos_autos + estacionamientos_visitas - descuento_estacionamientos_x_metro - descuento_estacionamientos_x_bici
    estacionamientos_bicicletas_final = estacionamientos_bicicletas + aumento_bici_x_descuento_estacionamientos

    supPorEstacionamiento = dict_arquitectura["supPorEstacionamiento"]
    supPorBodega = dict_arquitectura["supPorBodega"]
    supPorBicicleta = dict_arquitectura["supPorBicicleta"]

    areaReq       = estacionamientos_autos_final * supPorEstacionamiento + 
                    estacionamientos_bicicletas_final * supPorBicicleta + 
                    numBodegas * supPorBodega

    vecSecTodos = dict_geom["vecSecTodos"]
    vecSecSinCalle = dict_geom["vecSecSinCalle"]
    vec_dist = Float64.(copy(vecSecTodos))
    vec_dist .= -dict_requerimientos["subterraneo_antejardin"]
    vec_dist[vecSecSinCalle] .= -dict_requerimientos["subterraneo_distanciamiento"]
    ps_predio = dict_geom["ps_predio"]
    ps_areaEst = polyShape.partialPolyOffset(ps_predio, vecSecTodos, vec_dist)
    coefOcupacionEst = 1 #0.7
    vec_ps_subte, vec_np_subte = opti_vol_estacionamiento(ps_predio, ps_areaEst, coefOcupacionEst, areaReq)

    dict_resultados = OrderedDict(
    "tipo_edificio" => tipo_edificio,
    "variante_normativa" => variante_str,
    "flag_sombra" => dict_arquitectura["flag_sombra"],
    "sup_edificada_snt" => max_sol,
    "vec_ps_opt" => vec_ps_opt,
    "vec_np_opt" => vec_np_opt,
    "vec_ps_subte" => vec_ps_subte, 
    "vec_np_subte" => vec_np_subte,
    "vec_psVolteor" => vec_psVolteor,
    "vec_altVolteor" => vec_altVolteor,
    "vec_psVolConSombra" => vec_psVolConSombra, 
    "vec_altVolConSombra" => vec_altVolConSombra,
    "cabida_sup_deptos" => cabida_sup_deptos,
    "cabida_num_deptos" => cabida_num_deptos,
    "cabida_sup_comercio" => cabida_sup_comercio,
    "cabida_num_comercio" => cabida_num_comercio,
    "cabida_sup_oficinas" => cabida_sup_oficinas,
    "cabida_num_oficinas" => cabida_num_oficinas,
    "estacionamientos_autos_oficina" => estacionamientos_autos_oficina,
    "estacionamientos_autos_vivienda" => estacionamientos_autos_vivienda,
    "estacionamientos_autos_comercio" => estacionamientos_autos_comercio,
    "estacionamientos_autos" => estacionamientos_autos_oficina + estacionamientos_autos_vivienda + estacionamientos_autos_comercio,
    "estacionamientos_visitas" => estacionamientos_visitas,
    "estacionamientos_discapacitados" => estacionamientos_discapacitados,
    "estacionamientos_bicicletas" => estacionamientos_bicicletas,
    "descuento_estacionamientos_x_metro" => descuento_estacionamientos_x_metro,
    "descuento_estacionamientos_x_bici_t1" => descuento_estacionamientos_x_bici_t1,
    "descuento_estacionamientos_x_bici_t2" => descuento_estacionamientos_x_bici_t2,
    "descuento_estacionamientos_x_bici" => descuento_estacionamientos_x_bici,
    "aumento_bici_x_descuento_estacionamientos" => aumento_bici_x_descuento_estacionamientos,
    "estacionamientos_autos_final" => estacionamientos_autos_final,
    "estacionamientos_bicicletas_final" => estacionamientos_bicicletas_final,
    "bodegas" => numBodegas,
    "dict_edificio_deptos" => tipo_edificio == "departamento" ? dict_edificio_deptos : 0
    )

    dict_proyecto_vs_normativa = OrderedDict(
        "densidad_proyecto" => sum(eval(Meta.parse(cabida_num_deptos))),
        "densidad_normativa" => max_deptos,
        "losa_proyecto" => sum(polyShape.polyArea(vec_ps_opt[i]) * vec_np_opt[i] for i in eachindex(vec_ps_opt)),
        "losa_normativa" => flag_economica ? 999999 : max_losa_snt,
        "constructibilidad_proyecto" => dict_edificio_deptos["supUtil"],
        "constructibilidad_normativa" => flag_economica ? 999999 : max_constructibilidad,
        "ocupacion_suelo_proyecto" => polyShape.polyArea(vec_ps_opt[1]),
        "ocupacion_suelo_normativa" => flag_economica ? superficieTerreno - sum(eval(Meta.parse(cabida_num_deptos))) * sup_patio_vivienda_economica : max_ocupacion_suelo,
        "pisos_proyecto" => sum(vec_np_opt[i] for i in eachindex(vec_ps_opt)),
        "pisos_normativa" => dict_requerimientos["n_pisos"]
        )

    return dict_resultados, dict_proyecto_vs_normativa
end