function opti_edificio(alturaPiso, sup_terreno_sii, vecSecTodos, vecSecSinCalle, dict_con_parametros, dcn, dca, dcp, dcc, ps_bruto, ps_calles, ps_predio, ps_publico, vec_pisos, K, ancho_crujia_min, ancho_crujia_max, flag_s, tipo_edificio)


    # display("Establece el área de edificación")

    superficieTerreno = sup_terreno_sii
    superficieTerrenoBruto = polyShape.polyArea(ps_bruto)


    max_ocupacion_suelo = superficieTerreno * dcn.coefOcupacion
    max_constructibilidad = superficieTerreno * dcn.coefConstructibilidad  
    maxConstruccionSNT = max_constructibilidad * .95 + max_constructibilidad * 0.10 + max_constructibilidad * 0.20 # Sup Terraza + Areas comunes
                       # Sup Interior                + Sup Terrazas                 + Areas comunes


    vec_ps_opt, vec_np_opt, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, ps_areaEst = opti_edificio_vol(vecSecTodos, vecSecSinCalle, dcn, dict_con_parametros, vec_pisos, alturaPiso, ps_predio, ps_calles, ps_publico, ps_bruto, max_ocupacion_suelo, maxConstruccionSNT, K, ancho_crujia_min, ancho_crujia_max, flag_s)


    
    if tipo_edificio == "departamento"
        so, sh, status = opti_edificio_deptos(dcn, dca, dcp, dcc, vec_ps_opt, vec_np_opt, superficieTerreno, superficieTerrenoBruto)
        numEst        = so.estacionamientosVendibles + so.estacionamientosVisita
        numBodegas    = so.numBodegas
    else
        area_edif = sum(polyShape.polyArea(vec_ps_opt[i]) * vec_np_opt[i] for i in eachindex(vec_ps_opt))
        numEst_vendible        = Int(ceil(1 * area_edif/100))
        numEst_visitas        = Int(ceil(numEst_vendible * 0.1))
        numEst   = numEst_vendible + numEst_visitas
        numBodegas    = numEst_vendible
    end

    vec_ps_subte, vec_np_subte = opti_vol_estacionamiento(ps_predio, ps_areaEst, numEst, numBodegas, dcn)

    return vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra
end