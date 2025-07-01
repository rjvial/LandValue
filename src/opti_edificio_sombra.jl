function opti_edificio_sombra(dcn, dca, dcp, dcc, superficieTerreno, superficieTerrenoBruto, sup_areaEdif, 
        vec_psVolConSombra, vec_altVolConSombra, vec_pisos, alturaPiso, ps_areaEdif, ps_predio, ps_areaEst, ps_calles, ps_publico, ps_bruto, 
        areaSombra_p, areaSombra_o, areaSombra_s, max_ocupacion_suelo, maxConstruccionSNT, K, 
        centroidSombra_p, centroidSombra_o, centroidSombra_s; ancho_crujia_edificio = ancho_crujia_edificio)

    vec_ps_opt, vec_np_opt = opti_vol_edificio_sombra(vec_psVolConSombra, vec_altVolConSombra, vec_pisos, alturaPiso, ps_areaEdif, ps_calles, ps_publico, ps_bruto,
        areaSombra_p, areaSombra_o, areaSombra_s, max_ocupacion_suelo, maxConstruccionSNT, K, centroidSombra_p, centroidSombra_o, centroidSombra_s;
        ancho_crujia_edificio = ancho_crujia_edificio
    )

    so, sh, status = opti_deptos_edificio(dcn, dca, dcp, dcc, vec_ps_opt, vec_np_opt, superficieTerreno, superficieTerrenoBruto, sup_areaEdif)
    vec_ps_subte, vec_np_subte = opti_vol_estacionamiento(ps_predio, ps_areaEst, vec_ps_opt, so, dcn)

    return so, sh, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte
end