function opti_edificio(dcn, dca, dcp, dcc, superficieTerreno, superficieTerrenoBruto, sup_areaEdif, ps_predio, ps_areaEst, vec_psVolteor, vec_altVolteor, vec_pisos, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K; ancho_crujia_edificio)

    vec_ps_opt, vec_np_opt = opti_vol_edificio(vec_psVolteor, vec_altVolteor, vec_pisos, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K, ancho_crujia_edificio = ancho_crujia_edificio, flag_reverse = false)
    so, sh, status = opti_deptos_edificio(dcn, dca, dcp, dcc, vec_ps_opt, vec_np_opt, superficieTerreno, superficieTerrenoBruto, sup_areaEdif)
    vec_ps_subte, vec_np_subte = opti_vol_estacionamiento(ps_predio, ps_areaEst, vec_ps_opt, so, dcn)

    return so, sh, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte 
end