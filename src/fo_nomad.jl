function fo_nomad(x, template, sepNaves, dca, porcTerraza, flag_conSombra, flag_penalizacion_residual, flag_penalizacion_coefOcup, flag_penalizacion_constructibilidad,
    V_volConSombra, vecAlturas_conSombra, vecVertices_conSombra, matConexionVertices_conSombra, 
    V_volTeorico, vecAlturas_volTeorico, vecVertices_volTeorico, matConexionVertices_volTeorico,
    maxOcupación, maxSupConstruida, areaSombra_p, areaSombra_o, areaSombra_s, ps_publico, ps_calles)

    if flag_conSombra
        alt = min(x[1] * dca.alturaPiso, maximum(vecAlturas_conSombra))
        psCorte = generaPoligonoCorte(alt, V_volConSombra, vecAlturas_conSombra, vecVertices_conSombra, matConexionVertices_conSombra)
    else
        alt = min(x[1] * dca.alturaPiso, maximum(vecAlturas_volTeorico))
        psCorte = generaPoligonoCorte(alt, V_volTeorico, vecAlturas_volTeorico, vecVertices_volTeorico, matConexionVertices_volTeorico)
    end

    areaBasal, ps_base, ps_baseSeparada = resultConverter(x, template, sepNaves)

    numPisos = Int(floor(x[1]))
    total_fit = -(numPisos * areaBasal )

    # Restricciones
    constraints = []
    if flag_penalizacion_residual
        ps_r = polyShape.polyDifference(ps_base, psCorte) #Sector de la base del edificio que sobrepasa el poligono de corte
        area_r = polyShape.polyArea(ps_r) #Area del sector que sobrepasa
        penalizacion_r = area_r^1.1
        constraints = push!(constraints, penalizacion_r)
    end
    if flag_penalizacion_coefOcup
        penalizacionCoefOcup = max(0.0, areaBasal - maxOcupación)
        constraints = push!(constraints, penalizacionCoefOcup)
    end
    if flag_penalizacion_constructibilidad
        superficieConstruidaSNT = areaBasal * numPisos
        penalizacionConstructibilidad = max(0.0, superficieConstruidaSNT / (1 + dca.porcSupComun + 0.5*porcTerraza) - maxSupConstruida)
        constraints = push!(constraints, penalizacionConstructibilidad)
    end
    if flag_conSombra
        ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s = generaSombraEdificio(ps_baseSeparada, alt, ps_publico, ps_calles)
        areaSombraEdif_p = polyShape.polyArea(ps_sombraEdif_p)
        areaSombraEdif_o = polyShape.polyArea(ps_sombraEdif_o)
        areaSombraEdif_s = polyShape.polyArea(ps_sombraEdif_s)
        penalizacionSombra_p = max(0.0, areaSombraEdif_p - areaSombra_p)
        penalizacionSombra_o = max(0.0, areaSombraEdif_o - areaSombra_o)
        penalizacionSombra_s = max(0.0, areaSombraEdif_s - areaSombra_s)
        constraints = push!(constraints, penalizacionSombra_p + penalizacionSombra_o + penalizacionSombra_s)
    end

    # Integración Función Objetivo con Restricciones
    bb_outputs = [total_fit; constraints]
    success = true
    count_eval = true

    return (success, count_eval, bb_outputs)
end

