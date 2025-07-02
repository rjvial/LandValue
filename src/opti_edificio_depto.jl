function opti_edificio_depto(alturaPiso, areaSombra_o, areaSombra_p, areaSombra_s, centroidSombra_o, centroidSombra_p, centroidSombra_s, dca, dcc, dcn, dcp, max_ocupacion_suelo, maxConstruccionSNT, ps_areaEdif, ps_areaEst, ps_bruto, ps_calles, ps_predio, ps_publico, sup_areaEdif, superficieTerreno, superficieTerrenoBruto, vec_altVolConSombra, vec_altVolteor, vec_pisos, vec_psVolConSombra, vec_psVolteor; K, ancho_crujia_edificio = 0, flag_sombra = true)

    if flag_sombra
        vec_ps_opt, vec_np_opt = opti_vol_edificio_sombra(vec_psVolConSombra, vec_altVolConSombra, vec_pisos, alturaPiso, ps_areaEdif, ps_calles, ps_publico, ps_bruto, areaSombra_p, areaSombra_o, areaSombra_s, max_ocupacion_suelo, maxConstruccionSNT, K, centroidSombra_p, centroidSombra_o, centroidSombra_s, ancho_crujia_edificio = ancho_crujia_edificio)
    else
        vec_ps_opt, vec_np_opt = opti_vol_edificio(vec_psVolteor, vec_altVolteor, vec_pisos, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K, ancho_crujia_edificio = ancho_crujia_edificio, flag_reverse = false)
    end

    so, sh, status = opti_deptos(dcn, dca, dcp, dcc, vec_ps_opt, vec_np_opt, superficieTerreno, superficieTerrenoBruto, sup_areaEdif)
    numEst        = so.estacionamientosVendibles + so.estacionamientosVisita
    numBodegas    = so.numBodegas
    vec_ps_subte, vec_np_subte = opti_vol_estacionamiento(ps_predio, ps_areaEst, numEst, numBodegas, dcn)

    return vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte
end