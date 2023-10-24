function fo_bbo(x, template, sepNaves, ps_areaEdif)

    areaBasal, ps_base, ps_baseSeparada = resultConverter(x, template, sepNaves)

    # Restricciones
    ps_r = polyShape.polyDifference(ps_base, ps_areaEdif) #Sector de la base del edificio que sobrepasa el poligono de corte
    area_r = polyShape.polyArea(ps_r) #Area del sector que sobrepasa
    penalizacion_r = area_r^1.1

    total_fit = areaBasal - 2000*penalizacion_r

    return -total_fit
end
