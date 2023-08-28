function generaCotas(template, minPisos, maxPisos, V_areaEdif, sepNaves, maxDiagonal, anchoMin, anchoMax)

    # min_pisos = min(minPisos, maxPisos - 1) 
    # max_ancho = anchoMax #6 #

    if template == 0 #I
        min_pisos = min(minPisos, maxPisos - 1); max_pisos = maxPisos
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_ancho, min_largo]
        ub = [max_pisos, max_theta, xmax, ymax, max_ancho, max_largo]

    elseif template == 1 #L
        min_pisos = min(minPisos, maxPisos - 1); max_pisos = maxPisos
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_alfa = 0; max_alfa = pi/2
        min_largo1 = anchoMin; max_largo1 = maxDiagonal
        min_largo2 = anchoMin; max_largo2 = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_alfa, min_largo1, min_largo2, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_alfa, max_largo1, max_largo2, max_ancho]

    elseif template == 2 #C
        min_pisos = min(minPisos, maxPisos - 1); max_pisos = maxPisos
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi1 = 0; max_phi1 = pi/2
        min_phi2 = -pi/2; max_phi2 = 0
        min_largo0 = sepNaves + 2*anchoMin; max_largo0 = max(min_largo0, maxDiagonal)
        min_largo1 = anchoMin; max_largo1 = maxDiagonal
        min_largo2 = anchoMin; max_largo2 = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo0, min_largo1, min_largo2, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo0, max_largo1, max_largo2, max_ancho]

    elseif template == 3 #III
        min_pisos = min(minPisos, maxPisos - 1); max_pisos = maxPisos
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
        min_pisos = min(minPisos, maxPisos - 1); max_pisos = maxPisos
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_alfa = 0; max_alfa = pi/2
        min_largo1 = anchoMin; max_largo1 = maxDiagonal
        min_largo2 = anchoMin; max_largo2 = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_alfa, min_largo1, min_largo2, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_alfa, max_largo1, max_largo2, max_ancho]

    elseif template == 5 #H
        min_pisos = min(minPisos, maxPisos - 1); max_pisos = maxPisos
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_largo = anchoMin; max_largo = maxDiagonal
        min_largo1_ = anchoMin; max_largo1_ = maxDiagonal
        min_largo1 = anchoMin; max_largo1 = maxDiagonal
        min_largo2_ = anchoMin; max_largo2_ = maxDiagonal
        min_largo2 = anchoMin; max_largo2 = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_largo, min_largo1_, min_largo1, min_largo2_, min_largo2, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_largo, max_largo1_, max_largo1, max_largo2_, max_largo2, max_ancho]

    elseif template == 6 #C-flex
        min_pisos = min(minPisos, maxPisos - 1); max_pisos = maxPisos
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi1 = 0; max_phi1 = pi / 2
        min_phi2 = -pi/2; max_phi2 = 0
        min_largo0 = sepNaves + 2*anchoMin; max_largo0 = max(min_largo0, maxDiagonal)
        min_largo1 = anchoMin; max_largo1 = maxDiagonal
        min_largo2 = anchoMin; max_largo2 = maxDiagonal
        min_ancho0 = anchoMin; max_ancho0 = anchoMax
        min_ancho1 = anchoMin; max_ancho1 = anchoMax
        min_ancho2 = anchoMin; max_ancho2 = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo0, min_largo1, min_largo2, min_ancho0, min_ancho1, min_ancho2]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo0, max_largo1, max_largo2, max_ancho0, max_ancho1, max_ancho2]

    elseif template == 7 #S
        min_pisos = min(minPisos, maxPisos - 1); max_pisos = maxPisos
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi1 = 0; max_phi1 = pi/2
        min_phi2 = 0; max_phi2 = pi/2
        min_largo0 = anchoMin; max_largo0 = maxDiagonal
        min_largo1 = anchoMin; max_largo1 = maxDiagonal
        min_largo2 = anchoMin; max_largo2 = maxDiagonal
        min_ancho0 = anchoMin; max_ancho0 = anchoMax
        min_ancho1 = anchoMin; max_ancho1 = anchoMax
        min_ancho2 = anchoMin; max_ancho2 = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo0, min_largo1, min_largo2, min_ancho0, min_ancho1, min_ancho2]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo0, max_largo1, max_largo2, max_ancho0, max_ancho1, max_ancho2]
    
    elseif template == 10 #S
        min_pisos = min(minPisos, maxPisos - 1); max_pisos = maxPisos
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi1 = 0; max_phi1 = pi/2
        min_phi2 = 0; max_phi2 = pi/2
        min_largo0 = anchoMin; max_largo0 = maxDiagonal
        min_largo1 = anchoMin; max_largo1 = maxDiagonal
        min_largo2 = anchoMin; max_largo2 = maxDiagonal
        min_ancho0 = anchoMin; max_ancho0 = anchoMax
        min_ancho1 = anchoMin; max_ancho1 = anchoMax
        min_ancho2 = anchoMin; max_ancho2 = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo0, min_largo1, min_largo2, min_ancho0, min_ancho1, min_ancho2]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo0, max_largo1, max_largo2, max_ancho0, max_ancho1, max_ancho2]

    elseif template == 8 #C-superFlex
        min_pisos = min(minPisos, maxPisos - 1); max_pisos = maxPisos; min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1]); ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi1 = 0; max_phi1 = pi/2; min_phi2 = -pi/2; max_phi2 = 0
        min_deltax_1 = 0; max_deltax_1 = anchoMax
        min_deltay_1 = 0; max_deltay_1 = anchoMax
        min_deltax_2 = 0; max_deltax_2 = anchoMax
        min_deltay_2 = 0; max_deltay_2 = anchoMax
        min_largo0 = sepNaves + 2*anchoMin; max_largo0 = max(min_largo0, maxDiagonal)
        min_largo1 = anchoMin; max_largo1 = maxDiagonal
        min_largo2 = anchoMin; max_largo2 = maxDiagonal
        min_ancho0 = anchoMin; max_ancho0 = anchoMax
        min_ancho1 = anchoMin; max_ancho1 = anchoMax
        min_ancho2 = anchoMin; max_ancho2 = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi1, min_phi2, min_deltax_1, min_deltay_1, min_deltax_2, min_deltay_2, min_largo0, min_largo1, min_largo2, min_ancho0, min_ancho1, min_ancho2]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_deltax_1, max_deltay_1, max_deltax_2, max_deltay_2, max_largo0, max_largo1, max_largo2, max_ancho0, max_ancho1, max_ancho2]

    elseif template == 9 #Cuña
        min_pisos = min(minPisos, maxPisos - 1); max_pisos = maxPisos
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