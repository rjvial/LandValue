function resultConverter(x::Array{Float64,1}, template::Int64, sepNaves::Float64)
    
    theta = x[2]
    ps_base = []
    
    #                      0    1    2       
    # vec_template_str = ["I", "L", "C"]

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


    elseif template == 2 #C
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
    end
    areaBasal = polyShape.polyArea(ps_base)
    

    return areaBasal, ps_base, ps_baseSeparada

end