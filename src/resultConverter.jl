function resultConverter(x::Array{Float64,1}, template::Int64, sepNaves::Float64)
    
    theta = x[2]
    ps_base = []

    #                      0    1   2    3    4    5    6    7      
    # vec_template_str = ["I", "L","H", "C", "S", "Z", "T", "II"]

    if template == 0 #I
        pos_x = x[3]
        pos_y = x[4]
        anchoLado = x[5]
        largo = x[6]
        
        ps_base = polyShape.polyBox(pos_x, pos_y, anchoLado, largo, theta) 
        
        ps_baseSeparada = polyShape.polyCopy(ps_base)

    elseif template == 1 #L

        pos_x = x[3]
        pos_y = x[4]
        alfa = x[5]
        largo1 = x[6] 
        largo2 = x[7]
        anchoLado1 = x[8]
        anchoLado2 = x[9]

        ps1 = polyShape.polyBox(pos_x, pos_y, largo1, anchoLado1, theta) 
        ps2 = polyShape.polyBox(pos_x, pos_y, anchoLado2, largo2, alfa + theta)
        
        ps_base = polyShape.polyUnion(ps1, ps2)
        ps_baseSeparada = PolyShape([ps1.Vertices[1], ps2.Vertices[1]], 2)

    elseif template == 2 #H

        pos_x = x[3]
        pos_y = x[4]
        largo0 = x[5]    
        d_izq_1 = x[6] #
        d_der_1 = x[7] #
        d_izq_2 = x[8] #
        d_der_2 = x[9] #
        anchoLado0 = x[10]
        anchoLado1 = x[11]
        anchoLado2 = x[12]

        cr = [pos_x; pos_y]

        ps1 = polyShape.polyBox(pos_x, pos_y, anchoLado0, largo0, theta)        
        ps2 = polyShape.polyBox(pos_x - d_izq_1, pos_y - anchoLado1, d_izq_1 + anchoLado0 + d_der_1, anchoLado1, theta, cr)
        ps3 = polyShape.polyBox(pos_x - d_izq_2, pos_y + largo0, d_izq_2 + anchoLado0 + d_der_2, anchoLado2, theta, cr)

        ps_base = polyShape.polyUnion(ps1, ps2)
        ps_base = polyShape.polyUnion(ps_base, ps3)

        ps_baseSeparada = PolyShape([ps1.Vertices[1], ps2.Vertices[1], ps3.Vertices[1]], 3)

    elseif template == 3 #C
        pos_x0 = x[3]
        pos_y0 = x[4]
        phi1 = x[5]
        phi2 = x[6]
        largo0 = max(x[7], sepNaves + x[11] + x[12])
        largo1 = x[8] 
        largo2 = x[9] 
        anchoLado0 = x[10]
        anchoLado1 = x[11]
        anchoLado2 = x[12]

        cr_theta  = [pos_x0; pos_y0];
        ps0 = polyShape.polyBox(pos_x0, pos_y0, largo0, anchoLado0, theta) 

        cr_phi1  = [pos_x0; pos_y0];
        ps1_ = polyShape.polyBox(pos_x0, pos_y0, anchoLado1, largo1, phi1, cr_phi1)
        ps1 = polyShape.polyRotate(ps1_, theta, cr_theta)
        
        cr_phi2  = [pos_x0 + largo0; pos_y0];        
        ps2_ = polyShape.polyBox(pos_x0 + largo0 - anchoLado2, pos_y0, anchoLado2, largo2, phi2, cr_phi2)
        ps2 = polyShape.polyRotate(ps2_, theta, cr_theta)

        ps_base = polyShape.polyUnion(ps0, ps1)
        ps_base = polyShape.polyUnion(ps_base, ps2)
        ps_baseSeparada = PolyShape([ps0.Vertices[1], ps1.Vertices[1], ps2.Vertices[1]], 3)

    elseif template == 4 #S
        pos_x0 = x[3]
        pos_y0 = x[4]
        phi1 = x[5]
        phi2 = x[6]
        largo0 = max(x[7], sepNaves + 2*x[10])
        largo1 = x[8] 
        largo2 = x[9] 
        anchoLado0 = x[10]
        anchoLado1 = x[11]
        anchoLado2 = x[12]

        cr_theta  = [pos_x0; pos_y0];
        ps0 = polyShape.polyBox(pos_x0, pos_y0, anchoLado0, largo0, theta) 

        cr_phi1  = [pos_x0; pos_y0 + largo0];
        ps1_ = polyShape.polyBox(pos_x0, pos_y0 + largo0, anchoLado1, largo1, phi1 - pi/2, cr_phi1)
        ps1 = polyShape.polyRotate(ps1_, theta, cr_theta)
        
        cr_phi2  = [pos_x0 + anchoLado0; pos_y0];        
        ps2_ = polyShape.polyBox(pos_x0 + anchoLado0, pos_y0, anchoLado2, largo2, phi2 + pi/2, cr_phi2)
        ps2 = polyShape.polyRotate(ps2_, theta, cr_theta)

        ps_base = polyShape.polyUnion(ps0, ps1)
        ps_base = polyShape.polyUnion(ps_base, ps2)
        ps_baseSeparada = PolyShape([ps0.Vertices[1], ps1.Vertices[1], ps2.Vertices[1]], 3)

    elseif template == 5 #Z
        pos_x0 = x[3]
        pos_y0 = x[4]
        phi1 = x[5]
        phi2 = x[6]
        largo0 = max(x[7], sepNaves + 2*x[10])
        largo1 = x[8] 
        largo2 = x[9] 
        anchoLado0 = x[10]
        anchoLado1 = x[11]
        anchoLado2 = x[12]

        cr_theta  = [pos_x0; pos_y0];
        ps0 = polyShape.polyBox(pos_x0, pos_y0, anchoLado0, largo0, theta) 

        cr_phi1  = [pos_x0; pos_y0];
        ps1_ = polyShape.polyBox(pos_x0, pos_y0, largo1, anchoLado1, -phi1, cr_phi1)
        ps1 = polyShape.polyRotate(ps1_, theta, cr_theta)
        
        cr_phi2  = [pos_x0 + anchoLado0; pos_y0 + largo0];        
        ps2_ = polyShape.polyBox(pos_x0 + anchoLado0, pos_y0 + largo0, largo2, anchoLado2, pi - phi2, cr_phi2)
        ps2 = polyShape.polyRotate(ps2_, theta, cr_theta)

        ps_base = polyShape.polyUnion(ps0, ps1)
        ps_base = polyShape.polyUnion(ps_base, ps2)
        ps_baseSeparada = PolyShape([ps0.Vertices[1], ps1.Vertices[1], ps2.Vertices[1]], 3)

    elseif template == 6 #T

        pos_x = x[3]
        pos_y = x[4]
        largo0 = x[5]    
        delta1 = x[6] #
        largo1 = x[7] #
        anchoLado0 = x[8]
        anchoLado1 = x[9]

        cr = [pos_x; pos_y]

        ps1 = polyShape.polyBox(pos_x, pos_y, anchoLado0, largo0, theta, cr)        
        ps2 = polyShape.polyBox(pos_x + anchoLado0, pos_y + delta1, largo1, anchoLado1, theta, cr)
       
        ps_base = polyShape.polyUnion(ps1, ps2)
        
        ps_baseSeparada = PolyShape([ps1.Vertices[1], ps2.Vertices[1]], 2)

    elseif template == 7 #II

        pos_x = x[3]
        pos_y = x[4]
        phi1 = x[5]
        phi2 = x[6]
        largo1 = x[7]    
        largo2 = x[8] #
        h12 = x[9] #
        v12 = x[10] #
        anchoLado1 = x[11]
        anchoLado2 = x[12]

        cr_theta = [pos_x; pos_y]

        cr_phi1  = [pos_x + anchoLado1; pos_y];
        ps1_ = polyShape.polyBox(pos_x, pos_y, anchoLado1, largo1, phi1, cr_phi1)
        ps1 = polyShape.polyRotate(ps1_, theta, cr_theta)
        
        cr_phi2  = [pos_x + anchoLado1 + h12; pos_y - v12];
        ps2_ = polyShape.polyBox(pos_x + anchoLado1 + h12, pos_y - v12, anchoLado2, largo2, phi2, cr_phi2)
        ps2 = polyShape.polyRotate(ps2_, theta, cr_theta)

        ps_base = polyShape.polyUnion(ps1, ps2)

        ps_baseSeparada = PolyShape([ps1.Vertices[1], ps2.Vertices[1]], 2)

    end
    areaBasal = polyShape.polyArea(ps_base)
    

    return areaBasal, ps_base, ps_baseSeparada


end