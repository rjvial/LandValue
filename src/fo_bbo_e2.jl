function fo_bbo_e2(x, template, sepNaves, dca, porcTerraza, flag_penalizacion_residual,
    flag_penalizacion_constructibilidad, flag_divergenciaAncho, vec_psVolteor, vec_altVolteor, maxOcupación, maxSupConstruida)

    alt = min(x[1] * dca.alturaPiso, maximum(vec_altVolteor))
    psCorte = generaPoligonoCorte(alt, vec_psVolteor, vec_altVolteor)

    # alt = min(x[1] * dca.alturaPiso, maximum(vec_altVolConSombra))
    # psCorte = generaPoligonoCorte(alt, vec_psVolConSombra, vec_altVolConSombra)


    areaBasal, ps_base, ps_baseSeparada = resultConverter(x, template, sepNaves)

    numPisos = Int(round(x[1]; digits = 0))
    total_fit = numPisos * areaBasal

    # Restricciones
    constraints = 0
    if flag_penalizacion_residual
        ps_r = polyShape.polyDifference(ps_base, psCorte) #Sector de la base del edificio que sobrepasa el poligono de corte
        area_r = polyShape.polyArea(ps_r) #Area del sector que sobrepasa
        penalizacion_r = (1+area_r)^3 - 1
        constraints = constraints + 100000 * penalizacion_r
    end
    if flag_penalizacion_constructibilidad
        superficieConstruidaSNT = areaBasal * (numPisos-1) + min(areaBasal, maxOcupación)
        penalizacionConstructibilidad = max(0.0, superficieConstruidaSNT / (1 + dca.porcSupComun + 0.5*porcTerraza) - maxSupConstruida)
        constraints = constraints + penalizacionConstructibilidad
    end

    total_fit = total_fit - constraints

    return -total_fit
end

