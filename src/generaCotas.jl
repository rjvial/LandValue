function generaCotas(template, minPisos, maxPisos, V_areaEdif, sepNaves, maxDiagonal, anchoMin, anchoMax)

    #                      0    1   2    3    4    5    6    7      
    # vec_template_str = ["I", "L","H", "C", "S", "Z", "T", "II"]
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
        lb = [min_pisos, min_theta, xmin, ymin, min_alfa, min_largo, min_largo, min_ancho, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_alfa, max_largo, max_largo, max_ancho, max_ancho]

    elseif template == 2 #H
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
                                                #5:largo0  #6:d_izq_1  #7:d_der_1 #8:d_izq_2 #9:d_der_2 #10:anchoLado0 #11:anchoLado1 #12:anchoLado2
        lb = [min_pisos, min_theta, xmin, ymin, sepNaves,  min_largo,  min_largo, min_largo, min_largo, min_ancho,     min_ancho,     min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_largo, max_largo,  max_largo, max_largo, max_largo, max_ancho,     max_ancho,     max_ancho]

    elseif template == 3 #C
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

    elseif template == 4 #S
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi = 0; max_phi = pi/2
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi, min_phi, min_largo, min_largo, min_largo, min_ancho, min_ancho, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi, max_phi, max_largo, max_largo, max_largo, max_ancho, max_ancho, max_ancho]
    
    elseif template == 5 #Z
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi = 0; max_phi = pi/2
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi, min_phi, min_largo, min_largo, min_largo, min_ancho, min_ancho, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi, max_phi, max_largo, max_largo, max_largo, max_ancho, max_ancho, max_ancho]
    
    elseif template == 6 #T
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
                                                #5 largo0 #6 delta_1 #7 largo1  #8 anchoLado0 #9 anchoLado1 
        lb = [min_pisos, min_theta, xmin, ymin, min_largo,-max_largo, min_largo, min_ancho,   min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_largo, max_largo, max_largo, max_ancho,   max_ancho]

    elseif template == 7 #II
        min_theta = -pi; max_theta = pi
        xmin = minimum(V_areaEdif[:, 1]); xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2]); ymax = maximum(V_areaEdif[:, 2])
        min_phi1 = 0; max_phi1 = pi/2
        min_phi2 = -pi/2; max_phi2 = 0
        min_largo = anchoMin; max_largo = maxDiagonal
        min_ancho = anchoMin; max_ancho = anchoMax
                                                #5:phi1   #6:phi2   #7:largo1  #8:largo2  #9:h12     #10:v12     #11:anchoLado1 #12:anchoLado2
        lb = [min_pisos, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo, min_largo, sepNaves, -max_largo , min_ancho,     min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo, max_largo, max_largo, max_largo,  max_ancho,     max_ancho]
                                        
                                        
    end

    return lb, ub
end