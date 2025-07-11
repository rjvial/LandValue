function opti_edificio(alturaPiso, sup_terreno_sii, vecSecTodos, vecSecSinCalle, dict_con_parametros, dcn, dca, dcp, dcc, ps_bruto, ps_calles, ps_predio, ps_publico, vec_pisos, K; ancho_crujia_min = 0, ancho_crujia_max = 0, flag_sombra = true, tipo_edificio = "departamento")


    display("Establece el área de edificación")
    superficieTerreno = sup_terreno_sii
    superficieTerrenoBruto = polyShape.polyArea(ps_bruto)

    antejardin = dcn.antejardin[1] # 8 # 12 # 
    sepVecinos = dcn.distanciamiento[1] # 7 #  10 # 
    alturaMax = dcn.alturaMax
    rasante = dcn.rasante

    vec_dist = Float64.(copy(vecSecTodos))
    vec_dist .= -antejardin
    vec_dist[vecSecSinCalle] .= -sepVecinos
    ps_areaEdif = polyShape.partialPolyOffset(ps_predio, vecSecTodos, vec_dist)
    sup_areaEdif = polyShape.polyArea(ps_areaEdif)

    vec_dist = Float64.(copy(vecSecTodos))
    vec_dist .= -antejardin
    vec_dist[vecSecSinCalle] .= -dcn.sepEstMin
    ps_areaEst = polyShape.partialPolyOffset(ps_predio, vecSecTodos, vec_dist)


    display("Calcula el espacio publico y bruto")

    # Calcula el Volumen Teórico
    vec_altVolteor = collect(0:0.5:alturaMax)
    vec_psVolteor = [polyShape.polyOffset(ps_bruto, -i / rasante) for i in vec_altVolteor]
    vec_psVolteor = [polyShape.polyIntersect(vec_psVolteor[i], ps_areaEdif) for i in eachindex(vec_psVolteor)]

    # Calcula sombra del Volumen Teórico
    @time ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s = generaSombraTeor(vec_psVolteor, vec_altVolteor, ps_publico, ps_calles)

    areaSombra_p = polyShape.polyArea(ps_sombraVolTeorico_p)
    areaSombra_o = polyShape.polyArea(ps_sombraVolTeorico_o)
    areaSombra_s = polyShape.polyArea(ps_sombraVolTeorico_s)

    centroidSombra_p = polyShape.shapeCentroid(ps_sombraVolTeorico_p)
    centroidSombra_o = polyShape.shapeCentroid(ps_sombraVolTeorico_o)
    centroidSombra_s = polyShape.shapeCentroid(ps_sombraVolTeorico_s)

    # Calcula el volumen sin restricciones
    rasante_sombra = Float64(dcn.rasanteSombra)
    vec_altVolConSombra = collect(0:0.5:alturaMax)
    vec_psVolConSombra = [polyShape.polyOffset(ps_predio, - alt/rasante_sombra) for alt in vec_altVolConSombra]
    vec_psVolConSombra = [polyShape.polyIntersect(vec_psVolConSombra[i], ps_areaEdif) for i in eachindex(vec_psVolConSombra)]

    max_ocupacion_suelo = superficieTerreno * dcn.coefOcupacion
    max_constructibilidad = superficieTerreno * dcn.coefConstructibilidad  
    maxConstruccionSNT = max_constructibilidad * .95 + max_constructibilidad * 0.10 + max_constructibilidad * 0.20 # Sup Terraza + Areas comunes
                       # Sup Interior                + Sup Terrazas                 + Areas comunes


    vec_ps_opt, vec_np_opt, max_sol = opti_vol_edificio(vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, vec_pisos, alturaPiso, ps_areaEdif, ps_calles, ps_publico, ps_bruto, areaSombra_p, areaSombra_o, areaSombra_s, max_ocupacion_suelo, maxConstruccionSNT, K, centroidSombra_p, centroidSombra_o, centroidSombra_s, ancho_crujia_min = ancho_crujia_min, ancho_crujia_max = ancho_crujia_max, flag_sombra = flag_sombra)
    
    if tipo_edificio == "departamento"
        so, sh, status = opti_deptos(dcn, dca, dcp, dcc, vec_ps_opt, vec_np_opt, superficieTerreno, superficieTerrenoBruto, sup_areaEdif)
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