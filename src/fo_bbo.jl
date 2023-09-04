function fo_bbo(x, template, sepNaves, dca, V_volConSombra, vecAlturas_conSombra, vecVertices_conSombra, matConexionVertices_conSombra, maxOcupación, porcTerraza, maxSupConstruida)

    numPisos = Int(floor(x[1]))

    areaBasal, ps_base, ps_baseSeparada = resultConverter(x, template, sepNaves)
    alt = min(numPisos * dca.alturaPiso, maximum(vecAlturas_conSombra))
    psCorte = generaPoligonoCorte(alt, V_volConSombra, vecAlturas_conSombra, vecVertices_conSombra, matConexionVertices_conSombra)
    total_fit = areaBasal*numPisos

    # Restricciones
    ps_r = polyShape.polyDifference(ps_base, psCorte) #Sector de la base del edificio que sobrepasa el poligono de corte
    area_r = polyShape.polyArea(ps_r) #Area del sector que sobrepasa
    penalizacion_r = area_r^1.1

    superficieConstruidaSNT = areaBasal * (numPisos-1) + min(areaBasal, maxOcupación)
    penalizacionConstructibilidad = max(0.0, superficieConstruidaSNT / (1 + dca.porcSupComun + 0.5*porcTerraza) - maxSupConstruida)

    total_fit = total_fit - 500*(penalizacion_r + penalizacionConstructibilidad)

    return -total_fit
end
