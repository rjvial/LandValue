function opti_edificio(alturaPiso, sup_terreno_sii, vecSecTodos, vecSecSinCalle, dict_con_parametros, dcn, dca, dcp, dcc, ps_bruto, ps_calles, ps_predio, ps_publico, vec_pisos, K, ancho_crujia_min, ancho_crujia_max, flag_sombra, flag_dfl2, tipo_edificio)


    # display("Establece el área de edificación")

    superficieTerreno = sup_terreno_sii
    superficieTerrenoBruto = polyShape.polyArea(ps_bruto)


    max_ocupacion_suelo = superficieTerreno * dcn.coefOcupacion
    max_constructibilidad = superficieTerreno * dcn.coefConstructibilidad  
    maxConstruccionSNT = max_constructibilidad * .95 + max_constructibilidad * 0.10 + max_constructibilidad * 0.20 # Sup Terraza + Areas comunes
                       # Sup Interior                + Sup Terrazas                 + Areas comunes


    vec_ps_opt, vec_np_opt, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, ps_areaEst = opti_edificio_vol(vecSecTodos, vecSecSinCalle, dcn, dict_con_parametros, vec_pisos, alturaPiso, ps_predio, ps_calles, ps_publico, ps_bruto, max_ocupacion_suelo, maxConstruccionSNT, K, ancho_crujia_min, ancho_crujia_max, flag_sombra)


    
    if tipo_edificio == "departamento"
        so, sh, status = opti_edificio_deptos(dcn, dca, dcp, dcc, vec_ps_opt, vec_np_opt, superficieTerreno, superficieTerrenoBruto, flag_dfl2)
        
        cabida_sup_deptos = string(dcc.supDeptoUtil)
        cabida_num_deptos = string(so.numDeptosTipo)
        cabida_sup_comercio = string(0)
        cabida_num_comercio = string(0)
        cabida_sup_oficinas = string(0)
        cabida_num_oficinas = string(0)
        expr_str = expression_converter.parse_python_expression(dict_con_parametros["estacionamientos_autos"][3])
        expr_str = replace(expr_str, "cabida_sup_deptos" => cabida_sup_deptos)
        expr_str = replace(expr_str, "cabida_num_deptos" => cabida_num_deptos)
        expr_str = replace(expr_str, "cabida_sup_comercio" => cabida_sup_comercio)
        expr_str = replace(expr_str, "cabida_num_comercio" => cabida_num_comercio)
        expr_str = replace(expr_str, "cabida_sup_oficinas" => cabida_sup_oficinas)
        expr_str = replace(expr_str, "cabida_num_oficinas" => cabida_num_oficinas)
        dict_estacionamientos = eval(Meta.parse(expr_str))
        estacionamientos_autos_vivienda = Float64(dict_estacionamientos["estacionamientos_autos_vivienda"])

        expr_str = expression_converter.parse_python_expression(dict_con_parametros["estacionamientos_visitas"][3])
        expr_str = replace(expr_str, "estacionamientos_autos_vivienda" => string(estacionamientos_autos_vivienda))
        estacionamientos_visitas = Float64(eval(Meta.parse(expr_str)))

        numEst = estacionamientos_autos_vivienda + estacionamientos_visitas
        numBodegas = sum(so.numDeptosTipo)
    else
        area_edif = sum(polyShape.polyArea(vec_ps_opt[i]) * vec_np_opt[i] for i in eachindex(vec_ps_opt))

        cabida_sup_deptos = string(0)
        cabida_num_deptos = string(0)
        cabida_sup_comercio = string(0)
        cabida_num_comercio = string(0)
        cabida_sup_oficinas = string(100)
        cabida_num_oficinas = string(ceil(area_edif/100))
        expr_str = expression_converter.parse_python_expression(dict_con_parametros["estacionamientos_autos"][3])
        expr_str = replace(expr_str, "cabida_sup_deptos" => cabida_sup_deptos)
        expr_str = replace(expr_str, "cabida_num_deptos" => cabida_num_deptos)
        expr_str = replace(expr_str, "cabida_sup_comercio" => cabida_sup_comercio)
        expr_str = replace(expr_str, "cabida_num_comercio" => cabida_num_comercio)
        expr_str = replace(expr_str, "cabida_sup_oficinas" => cabida_sup_oficinas)
        expr_str = replace(expr_str, "cabida_num_oficinas" => cabida_num_oficinas)
        dict_estacionamientos = eval(Meta.parse(expr_str))
        estacionamientos_autos_oficina = Float64(dict_estacionamientos["estacionamientos_autos_oficina"])

        expr_str = expression_converter.parse_python_expression(dict_con_parametros["estacionamientos_visitas"][3])
        expr_str = replace(expr_str, "estacionamientos_autos_vivienda" => string(estacionamientos_autos_oficina))
        estacionamientos_visitas = Float64(eval(Meta.parse(expr_str)))

        numEst = estacionamientos_autos_oficina + estacionamientos_visitas
        numBodegas = ceil(0.2 * estacionamientos_autos_oficina)
    end

    expr_str = expression_converter.parse_python_expression(dict_con_parametros["estacionamientos_discapacitados"][3])    
    expr_str = replace(expr_str, "estacionamientos_autos" => string(numEst))
    estacionamientos_discapacitados = Float64(eval(Meta.parse(expr_str)))

    expr_str = expression_converter.parse_python_expression(dict_con_parametros["estacionamientos_bicicletas"][3])    
    expr_str = replace(expr_str, "estacionamientos_autos + estacionamientos_visitas" => string(numEst))
    expr_str = replace(expr_str, "carga_ocupacion" => string(100))
    estacionamientos_bicicletas = Float64(eval(Meta.parse(expr_str)))

    vec_ps_subte, vec_np_subte = opti_vol_estacionamiento(ps_predio, ps_areaEst, numEst, numBodegas, dcn)

    return vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra
end