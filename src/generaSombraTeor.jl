function generaSombraTeor(verts, ps_publico, ps_calles)

    # V_ = ps_volteor.Vertices[1]
    # numVerticesTotales, numDim = size(V_);

    # conjuntoAlturas = unique(V_[:,3])
    # numAlturas = length(conjuntoAlturas)

    # numVerticesBase = Int(round(numVerticesTotales / numAlturas));
    ps_sombraVolTeorico_p = PolyShape([],0)
    ps_sombraVolTeorico_o = PolyShape([],0)
    ps_sombraVolTeorico_s = PolyShape([],0)

    num_caras_vol = length(verts)

    for k = 1:num_caras_vol
        x1 = verts[k][1][1]; y1 = verts[k][1][2]; z1 = verts[k][1][3];
        x2 = verts[k][2][1]; y2 = verts[k][2][2]; z2 = verts[k][2][3];
        x3 = verts[k][3][1]; y3 = verts[k][3][2]; z3 = verts[k][3][3];
        x4 = verts[k][4][1]; y4 = verts[k][4][2]; z4 = verts[k][4][3];
     
            verts_p = [[x1 - z1/0.49  y1];
                       [x2 - z2/0.49  y2]; 
                       [x3 - z3/0.49  y3]; 
                       [x4 - z4/0.49  y4]]

            verts_o = [[x1 + z1/0.49  y1];
                       [x2 + z2/0.49  y2]; 
                       [x3 + z3/0.49  y3]; 
                       [x4 + z4/0.49  y4]]

            verts_s = [[x1  y1 - z1/1.54];
                       [x2  y2 - z2/1.54]; 
                       [x3  y3 - z3/1.54]; 
                       [x4  y4 - z4/1.54]]

            if ps_sombraVolTeorico_p.NumRegions == 0
                ps_sombraVolTeorico_p.Vertices = push!(ps_sombraVolTeorico_p.Vertices, verts_p)
                ps_sombraVolTeorico_p.NumRegions = 1
                ps_sombraVolTeorico_o.Vertices = push!(ps_sombraVolTeorico_o.Vertices, verts_o)
                ps_sombraVolTeorico_o.NumRegions = 1
                ps_sombraVolTeorico_s.Vertices = push!(ps_sombraVolTeorico_s.Vertices, verts_s)
                ps_sombraVolTeorico_s.NumRegions = 1
            else
                ps_sombraVolTeorico_p = polyShape.polyUnion(ps_sombraVolTeorico_p, PolyShape([verts_p],1))
                ps_sombraVolTeorico_o = polyShape.polyUnion(ps_sombraVolTeorico_o, PolyShape([verts_o],1))
                ps_sombraVolTeorico_s = polyShape.polyUnion(ps_sombraVolTeorico_s, PolyShape([verts_s],1))
            end

    end


    p_p = polyShape.polyDifference(ps_sombraVolTeorico_p, ps_publico)
    if length(p_p.Vertices) > 0
        ps_sombraVolTeorico_p = PolyShape(p_p.Vertices, length(p_p.Vertices))
    else
        ps_sombraVolTeorico_p = PolyShape([], 0)
    end
    p_o = polyShape.polyDifference(ps_sombraVolTeorico_o, ps_publico)
    if length(p_o.Vertices) > 0
        ps_sombraVolTeorico_o = PolyShape(p_o.Vertices, length(p_o.Vertices))
    else
        ps_sombraVolTeorico_o = PolyShape([], 0)
    end
    p_s = polyShape.polyDifference(ps_sombraVolTeorico_s, ps_publico)
    if length(p_s.Vertices) > 0
        ps_sombraVolTeorico_s = PolyShape(p_s.Vertices, length(p_s.Vertices))
    else
        ps_sombraVolTeorico_s = PolyShape([], 0)
    end
        
    ps_sombraVolTeorico_p = polyShape.polyDifference(ps_sombraVolTeorico_p, ps_calles)
    ps_sombraVolTeorico_o = polyShape.polyDifference(ps_sombraVolTeorico_o, ps_calles)
    ps_sombraVolTeorico_s = polyShape.polyDifference(ps_sombraVolTeorico_s, ps_calles)

    return ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s
end