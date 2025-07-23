function opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos)


    tipo_edificio = dict_arquitectura["tipo_edificio"]
    variante_str = dict_arquitectura["variante_normativa"]
    flag_dfl2 = variante_str == "dfl_2" ? true : false

    superficieTerreno = dict_geom["sup_terreno_sii"]
    superficieTerrenoBruto = polyShape.polyArea(dict_geom["ps_bruto"])

    ocupacion_suelo = dict_requerimientos["coeficiente_de_ocupacion_de_suelo"]
    max_ocupacion_suelo = superficieTerreno * ocupacion_suelo


    coeficiente_de_constructibilidad = parse(Float64, dict_requerimientos["coeficiente_de_constructibilidad"][1])
    expr_str = expression_converter.parse_python_expression(dict_requerimientos["coeficiente_de_constructibilidad"][3])
    expr_str = replace(expr_str, "n_predios" => dict_geom["n_predios"])
    expr_str = replace(expr_str, "coeficiente_de_constructibilidad" => coeficiente_de_constructibilidad)
    coefConstructibilidad = eval(Meta.parse(expr_str))
    max_constructibilidad = superficieTerreno * coefConstructibilidad
    losaSNT = max_constructibilidad * .95 + max_constructibilidad * 0.10 + max_constructibilidad * 0.20 # Sup Terraza + Areas comunes
                # Sup Interior                + Sup Terrazas                 + Areas comunes


    maxPisos = dict_requerimientos["n_pisos"]
    default_min_pisos = maxPisos - 2
    vec_pisos = collect(default_min_pisos:maxPisos)

    vec_ps_opt, vec_np_opt, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, ps_areaEst = opti_edificio_vol(dict_geom, dict_arquitectura, dict_requerimientos, vec_pisos, max_ocupacion_suelo, losaSNT)

    
    if tipo_edificio == "departamento"
        
        densidadMax = dict_requerimientos["densidad_maxima_bruta"]
        # maxOcupacion = dict_requerimientos["coeficiente_de_ocupacion_de_suelo"] * superficieTerreno
        dict_edificio_deptos = opti_edificio_deptos(dict_arquitectura, coefConstructibilidad, densidadMax, vec_ps_opt, vec_np_opt, superficieTerreno, superficieTerrenoBruto, flag_dfl2)

        cabida_sup_deptos = string(dict_arquitectura["supDeptoUtil"])
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
    coefOcupacionEst = 0.7
    ps_predio = dict_geom["ps_predio"]
    vec_ps_subte, vec_np_subte = opti_vol_estacionamiento(ps_predio, ps_areaEst, estacionamientos_autos_final, estacionamientos_bicicletas_final, numBodegas, coefOcupacionEst, supPorEstacionamiento, supPorBicicleta, supPorBodega)

    dict_resultados = Dict(
    "tipo_edificio" => tipo_edificio,
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

    return dict_resultados
end