function fo_bbo(x, template, sepNaves, dca, V_volConSombra, vecAlturas_conSombra, vecVertices_conSombra, matConexionVertices_conSombra, maxOcupación)

    areaBasal, ps_base, ps_baseSeparada = resultConverter(x, template, sepNaves)
    alt = min(x[1] * dca.alturaPiso, maximum(vecAlturas_conSombra))
    psCorte = generaPoligonoCorte(alt, V_volConSombra, vecAlturas_conSombra, vecVertices_conSombra, matConexionVertices_conSombra)
    total_fit = areaBasal*sqrt(alt)

    # Restricciones
    ps_r = polyShape.polyDifference(ps_base, psCorte) #Sector de la base del edificio que sobrepasa el poligono de corte
    area_r = polyShape.polyArea(ps_r) #Area del sector que sobrepasa
    penalizacion_r = area_r^1.1
    penalizacionCoefOcup = max(0.0, areaBasal - maxOcupación) * 0

    total_fit = total_fit - 500*(penalizacion_r + penalizacionCoefOcup)

    return -total_fit
end
