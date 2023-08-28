function resultConverter(x::Array{Float64,1}, template::Int64, sepNaves::Float64)
    
    theta = x[2]
    ps_base = []

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
        anchoLado = x[8]

        ps1 = polyShape.polyBox(pos_x, pos_y, largo1, anchoLado, theta) 
        ps2 = polyShape.polyBox(pos_x, pos_y, anchoLado, largo2, alfa + theta)
        
        ps_base = polyShape.polyUnion(ps1, ps2)
        ps_baseSeparada = PolyShape([ps1.Vertices[1], ps2.Vertices[1]], 2)

    elseif template == 2 #C
        pos_x0 = x[3]
        pos_y0 = x[4]
        phi1 = x[5]
        phi2 = x[6]
        largo0 = max(x[7], sepNaves + 2*x[10])
        largo1 = x[8] 
        largo2 = x[9] 
        anchoLado = x[10]

        cr_theta  = [pos_x0; pos_y0];
        ps0 = polyShape.polyBox(pos_x0, pos_y0, largo0, anchoLado, theta) 

        cr_phi1  = [pos_x0; pos_y0];
        ps1_ = polyShape.polyBox(pos_x0, pos_y0, anchoLado, largo1, phi1, cr_phi1)
        ps1 = polyShape.polyRotate(ps1_, theta, cr_theta)
        
        cr_phi2  = [pos_x0 + largo0; pos_y0];        
        ps2_ = polyShape.polyBox(pos_x0 + largo0 - anchoLado, pos_y0, anchoLado, largo2, phi2, cr_phi2)
        ps2 = polyShape.polyRotate(ps2_, theta, cr_theta)

        ps_base = polyShape.polyUnion(ps0, ps1)
        ps_base = polyShape.polyUnion(ps_base, ps2)
        ps_baseSeparada = PolyShape([ps0.Vertices[1], ps1.Vertices[1], ps2.Vertices[1]], 3)

    elseif template == 3 #III

        pos_x = x[3]
        pos_y = x[4]
        unidades = Int(round(x[5]))
        largo = x[6] 
        var = x[7]
        sep = x[8]
        anchoLado = x[9]

        cr = [pos_x; pos_y]

        ps = PolyShape([],1)
        VV = []
        for k = 1:unidades
            if k == 1
                ps = polyShape.polyBox(pos_x, pos_y, anchoLado, largo, theta)
                VV = [ps.Vertices[1]]
            else
                pos_x_k = pos_x + (anchoLado + sep)*(k-1)
                pos_y_k = pos_y
                largo_k = largo + var*(k-1)
                ps_k = polyShape.polyBox(pos_x_k, pos_y_k, anchoLado, largo_k, theta, cr)
                push!(VV, ps_k.Vertices[1])
                ps = polyShape.polyUnion(ps, ps_k)

            end    
            
        end
        ps_base = ps
        ps_baseSeparada = PolyShape(VV, unidades)

    elseif template == 4 #V

        pos_x = x[3]
        pos_y = x[4]
        alfa = x[5]    
        largo1 = x[6] # 
        largo2 = x[7] #
        anchoLado = x[8] 

        cr = [pos_x; pos_y]
        ps1 = polyShape.polyBox(pos_x, pos_y, theta, largo1, anchoLado)
        ps2 = polyShape.polyBox(pos_x - anchoLado, pos_y, anchoLado, largo2, theta - alfa, cr)
        
        ps_base = polyShape.polyUnion(ps1, ps2)
        ps_baseSeparada = PolyShape([ps1.Vertices[1], ps2.Vertices[1]], 2)


    elseif template == 5 #H

        pos_x = x[3]
        pos_y = x[4]
        largo = x[5]    
        largo1_ = x[6] #
        largo1 = x[7] #
        largo2_ = x[8] #
        largo2 = x[9] #
        anchoLado = x[10] 
    
        cr = [pos_x; pos_y]

        ps1 = polyShape.polyBox(pos_x, pos_y, largo1, anchoLado, theta)        
        ps2 = polyShape.polyBox(pos_x + largo1_, pos_y + anchoLado, anchoLado, largo, theta, cr)
        ps3 = polyShape.polyBox(pos_x + largo1_ - largo2_, pos_y + anchoLado + largo, largo2, anchoLado, theta, cr)

        ps_base = polyShape.polyUnion(ps1, ps2)
        ps_base = polyShape.polyUnion(ps_base, ps3)

        ps_baseSeparada = PolyShape([ps1.Vertices[1], ps2.Vertices[1], ps3.Vertices[1]], 3)

    elseif template == 6 #C-flex
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

    elseif template == 7 #S
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
        
    elseif template == 10 #Z
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

    elseif template == 8 #C-superFlex
        pos_x0 = x[3]
        pos_y0 = x[4]
        phi1 = x[5]
        phi2 = x[6]
        deltax_1 = x[7]
        deltay_1 = x[8]
        deltax_2 = x[9]
        deltay_2 = x[10]
        largo0 = x[11]
        largo1 = x[12] 
        largo2 = x[13] 
        anchoLado0 = x[14]
        anchoLado1 = x[15]
        anchoLado2 = x[16]

        cr_theta  = [pos_x0; pos_y0];
        ps0 = polyShape.polyBox(pos_x0, pos_y0, largo0, anchoLado0, theta) 

        cr_phi1  = [pos_x0 + deltax_1; pos_y0 + deltay_1];
        ps1_ = polyShape.polyBox(pos_x0 + deltax_1, pos_y0 + deltay_1, anchoLado1, largo1, phi1, cr_phi1)
        ps1 = polyShape.polyRotate(ps1_, theta, cr_theta)
        
        cr_phi2  = [pos_x0 + largo0 - deltax_2; pos_y0 + deltay_2];
        ps2_ = polyShape.polyBox(pos_x0 + largo0 - deltax_2, pos_y0 + deltay_2, anchoLado2, largo2, phi2, cr_phi2)
        ps2 = polyShape.polyRotate(ps2_, theta, cr_theta)

        ps_base = polyShape.polyUnion(ps0, ps1)
        ps_base = polyShape.polyUnion(ps_base, ps2)
        ps_baseSeparada = PolyShape([ps0.Vertices[1], ps1.Vertices[1], ps2.Vertices[1]], 3)

    elseif template == 9 #Cuña
        pos_x = x[3]
        pos_y = x[4]
        largo = x[5]
        anchoLado1 = x[6]
        anchoLado2 = x[7]
        
        cr_theta  = [pos_x; pos_y];
        V = [pos_x pos_y-anchoLado1/2; pos_x+largo pos_y-anchoLado2/2; pos_x+largo pos_y+anchoLado2/2; pos_x pos_y+anchoLado1/2]
        ps_base = PolyShape([V],1)
        ps_base = polyShape.polyRotate(ps_base, theta, cr_theta)

        ps_baseSeparada = polyShape.polyCopy(ps_base)

    end
    areaBasal = polyShape.polyArea(ps_base)
    

    return areaBasal, ps_base, ps_baseSeparada


end