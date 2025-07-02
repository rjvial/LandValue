function opti_edificio_oficina(alturaPiso, areaSombra_o, areaSombra_p, areaSombra_s, centroidSombra_o, centroidSombra_p, centroidSombra_s, dca, dcc, dcn, dcp, max_ocupacion_suelo, maxConstruccionSNT, ps_areaEdif, ps_areaEst, ps_bruto, ps_calles, ps_predio, ps_publico, sup_areaEdif, superficieTerreno, superficieTerrenoBruto, vec_altVolConSombra, vec_altVolteor, vec_pisos, vec_psVolConSombra, vec_psVolteor; K, ancho_crujia_edificio = 0, flag_sombra = false)

    if flag_sombra
        vec_ps_opt, vec_np_opt = opti_vol_edificio_sombra(vec_psVolConSombra, vec_altVolConSombra, vec_pisos, alturaPiso, ps_areaEdif, ps_calles, ps_publico, ps_bruto, areaSombra_p, areaSombra_o, areaSombra_s, max_ocupacion_suelo, maxConstruccionSNT, K, centroidSombra_p, centroidSombra_o, centroidSombra_s, ancho_crujia_edificio = ancho_crujia_edificio)
    else
        vec_ps_opt, vec_np_opt = opti_vol_edificio(vec_psVolteor, vec_altVolteor, vec_pisos, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K, ancho_crujia_edificio = ancho_crujia_edificio, flag_reverse = false)
    end

    area_edif = sum(polyShape.polyArea(vec_ps_opt[i]) * vec_np_opt[i] for i in eachindex(vec_ps_opt))

    numEst_vendible        = Int(ceil(1 * area_edif/100))
    numEst_visitas        = Int(ceil(numEst_vendible * 0.1))
    numEst   = numEst_vendible + numEst_visitas
    numBodegas    = numEst_vendible

    vec_ps_subte, vec_np_subte = opti_vol_estacionamiento(ps_predio, ps_areaEst, numEst, numBodegas, dcn)

    return vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte 
end