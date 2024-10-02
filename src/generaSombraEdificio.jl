function generaSombraEdificio(ps_baseEdificio::PolyShape, alt::Float64, ps_publico::PolyShape, ps_calles::PolyShape)::Tuple{PolyShape, PolyShape, PolyShape}

    ps_SombraEdif_p = PolyShape([],0)
    ps_SombraEdif_o = PolyShape([],0)
    ps_SombraEdif_s = PolyShape([],0)
    numEdificios = ps_baseEdificio.NumRegions
    for e = 1:numEdificios
        V_baseEdif_e = [ps_baseEdificio.Vertices[e] zeros(size(ps_baseEdificio.Vertices[e],1),1); 
                      ps_baseEdificio.Vertices[e] alt .*ones(size(ps_baseEdificio.Vertices[e],1),1)]
        numVerticesEdif_e = size(V_baseEdif_e,1)
        V_SombraEdif_p = V_baseEdif_e[:,1:2]
        V_SombraEdif_o = V_baseEdif_e[:,1:2]
        V_SombraEdif_s = V_baseEdif_e[:,1:2]
        for i = 1:numVerticesEdif_e
            alt_i = V_baseEdif_e[i,3]
            V_SombraEdif_p[i,1] = V_SombraEdif_p[i,1] - alt_i / 0.49
            V_SombraEdif_o[i,1] = V_SombraEdif_o[i,1] + alt_i / 0.49
            V_SombraEdif_s[i,2] = V_SombraEdif_s[i,2] - alt_i / 1.54
        end

        V_SombraEdif_p = poly2D.convHull(V_SombraEdif_p)
        V_SombraEdif_o = poly2D.convHull(V_SombraEdif_o)
        V_SombraEdif_s = poly2D.convHull(V_SombraEdif_s)

        if e == 1
            ps_SombraEdif_p.Vertices = push!(ps_SombraEdif_p.Vertices, V_SombraEdif_p)
            ps_SombraEdif_o.Vertices = push!(ps_SombraEdif_o.Vertices, V_SombraEdif_o)
            ps_SombraEdif_s.Vertices = push!(ps_SombraEdif_s.Vertices, V_SombraEdif_s)
            ps_SombraEdif_p.NumRegions = length(ps_SombraEdif_p.Vertices)
            ps_SombraEdif_o.NumRegions = length(ps_SombraEdif_o.Vertices)
            ps_SombraEdif_s.NumRegions = length(ps_SombraEdif_s.Vertices)
        else
            ps_SombraEdif_p = polyShape.polyUnion(ps_SombraEdif_p, PolyShape([V_SombraEdif_p],1))
            ps_SombraEdif_o = polyShape.polyUnion(ps_SombraEdif_o, PolyShape([V_SombraEdif_o],1))
            ps_SombraEdif_s = polyShape.polyUnion(ps_SombraEdif_s, PolyShape([V_SombraEdif_s],1))
        end
    end

    
    p_p = polyShape.polyDifference(ps_SombraEdif_p, ps_publico)
    if length(p_p.Vertices) > 0
        ps_sombraEdif_p = PolyShape(p_p.Vertices, length(p_p.Vertices))
    else
        ps_sombraEdif_p = PolyShape([],0)
    end
    p_o = polyShape.polyDifference(ps_SombraEdif_o, ps_publico)
    if length(p_o.Vertices)>0
        ps_sombraEdif_o = PolyShape(p_o.Vertices, length(p_o.Vertices))
    else
        ps_sombraEdif_o = PolyShape([],0)
    end
    p_s = polyShape.polyDifference(ps_SombraEdif_s, ps_publico)
    if length(p_s.Vertices)>0
        ps_sombraEdif_s = PolyShape(p_s.Vertices, length(p_s.Vertices))
    else
        ps_sombraEdif_s = PolyShape([],0)
    end

    ps_sombraEdif_p = polyShape.polyDifference(ps_sombraEdif_p, ps_calles)
    ps_sombraEdif_o = polyShape.polyDifference(ps_sombraEdif_o, ps_calles)
    ps_sombraEdif_s = polyShape.polyDifference(ps_sombraEdif_s, ps_calles)

    return ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s
end


