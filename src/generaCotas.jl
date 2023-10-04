function generaCotas(template, minPisos, maxPisos, V_areaEdif, sepNaves, maxDiagonal, anchoMin, anchoMax)

    # min_pisos = min(minPisos, maxPisos - 1) 
    # max_ancho = anchoMax #6 #
    min_pisos = min(minPisos, maxPisos - 1); max_pisos = maxPisos

    if template == 0 #I
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_ancho, min_largo]
        ub = [max_pisos, max_theta, xmax, ymax, max_ancho, max_largo]

    elseif template == 1 #L
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_alfa = 0; max_alfa = pi/2
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_alfa, min_largo, min_largo, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_alfa, max_largo, max_largo, max_ancho]

    elseif template == 2 #C
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi1 = 0; max_phi1 = pi/2
        min_phi2 = -pi/2; max_phi2 = 0
        min_largo0 = sepNaves + 2*anchoMin; max_largo0 = max(min_largo0, maxDiagonal)
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo0, min_largo, min_largo, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo0, max_largo, max_largo, max_ancho]

    elseif template == 3 #III
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_unidades = 0.5001; max_unidades = 5.4999
        min_largo = anchoMin; max_largo = maxDiagonal
        min_var = -50; max_var = 50
        min_sep = sepNaves; max_sep = 100
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_unidades, min_largo, min_var, min_sep, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_unidades, max_largo, max_var, max_sep, max_ancho]

    elseif template == 4 #V
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_alfa = 0; max_alfa = pi/2
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_alfa, min_largo, min_largo, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_alfa, max_largo, max_largo, max_ancho]

    elseif template == 5 #H-Flex
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_largo, min_largo, min_largo, min_largo, min_largo, min_ancho, min_ancho, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_largo, max_largo, max_largo, max_largo, max_largo, max_ancho, max_ancho, max_ancho]

    elseif template == 6 #C-flex
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi1 = 0; max_phi1 = pi / 2
        min_phi2 = -pi/2; max_phi2 = 0
        min_largo0 = sepNaves + 2*anchoMin; max_largo0 = max(min_largo0, maxDiagonal)
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo0, min_largo, min_largo, min_ancho, min_ancho, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo0, max_largo, max_largo, max_ancho, max_ancho, max_ancho]

    elseif template == 7 #S
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi = 0; max_phi = pi/2
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi, min_phi, min_largo, min_largo, min_largo, min_ancho, min_ancho, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi, max_phi, max_largo, max_largo, max_largo, max_ancho, max_ancho, max_ancho]
    
    elseif template == 10 #Z
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi = 0; max_phi = pi/2
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi, min_phi, min_largo, min_largo, min_largo, min_ancho, min_ancho, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi, max_phi, max_largo, max_largo, max_largo, max_ancho, max_ancho, max_ancho]
    
    elseif template == 8 #C-superFlex
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1]); ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi1 = 0; max_phi1 = pi/2; min_phi2 = -pi/2; max_phi2 = 0
        min_delta = 0; max_delta = anchoMax
        min_largo0 = sepNaves + 2*anchoMin; max_largo0 = max(min_largo0, maxDiagonal)
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi1, min_phi2, min_delta, min_delta, min_delta, min_delta, min_largo0, min_largo, min_largo, min_ancho, min_ancho, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_delta, max_delta, max_delta, max_delta, max_largo0, max_largo, max_largo, max_ancho, max_ancho, max_ancho]

    elseif template == 9 #Cuña
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_ancho = anchoMin; max_ancho = anchoMax
        min_largo = anchoMin; max_largo = maxDiagonal
        lb = [min_pisos, min_theta, xmin, ymin, min_largo, min_ancho, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_largo, max_ancho, max_ancho]

    end

    return lb, ub
end