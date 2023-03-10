function generaSombraTeor(ps_volteor, matConexionVertices, vecVertices, ps_publico, ps_calles)

    V_ = ps_volteor.Vertices[1]
    numVerticesTotales, numDim = size(V_);

    conjuntoAlturas = unique(V_[:,3])
    numAlturas = length(conjuntoAlturas)

    numVerticesBase = Int(round(numVerticesTotales / numAlturas));
    ps_sombraVolTeorico_p = PolyShape([],0)
    ps_sombraVolTeorico_o = PolyShape([],0)
    ps_sombraVolTeorico_s = PolyShape([],0)

    for k = 1:numAlturas-1
        for j = 1:length(vecVertices[k])
            if j == length(vecVertices[k])
                jl0 = Int.(vecVertices[k][j])
                jl1 = Int.(vecVertices[k][1])
            else
                jl0 = Int.(vecVertices[k][j])
                jl1 = Int.(vecVertices[k][j + 1])
            end
            x1 = V_[jl0,1]; y1 = V_[jl0,2]; z1 = V_[jl0,3];
            x2 = V_[jl1,1]; y2 = V_[jl1,2]; z2 = V_[jl1,3];
            ju0 = Int.(matConexionVertices[matConexionVertices[:,1] .== jl0,2])[1]
            ju1 = Int.(matConexionVertices[matConexionVertices[:,1] .== jl1,2])[1]

            x3 = V_[ju1,1]; y3 = V_[ju1,2]; z3 = V_[ju1,3];
            x4 = V_[ju0,1]; y4 = V_[ju0,2]; z4 = V_[ju0,3];
    
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