function opti_edificio_oficina(dcn, ps_predio, ps_areaEst, vec_psVolteor, vec_altVolteor, vec_pisos, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K; ancho_crujia_edificio)

    vec_ps_opt, vec_np_opt = opti_vol_edificio(vec_psVolteor, vec_altVolteor, vec_pisos, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K, ancho_crujia_edificio = ancho_crujia_edificio, flag_reverse = false)
    
    area_edif = sum(polyShape.polyArea(ps) for ps in vec_ps_opt)

    numEst_vendible        = Int(ceil(1.5 * area_edif/100))
    numEst_visitas        = Int(ceil(numEst_vendible * 0.1))
    numEst   = numEst_vendible + numEst_visitas
    numBodegas    = numEst_vendible

    vec_ps_subte, vec_np_subte = opti_vol_estacionamiento(ps_predio, ps_areaEst, numEst, numBodegas, dcn)

    return vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte 
end