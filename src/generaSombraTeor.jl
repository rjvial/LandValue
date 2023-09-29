function generaSombraTeor(vec_psVolteor, vec_altVolteor, ps_publico, ps_calles)

    num_alturas = length(vec_altVolteor)

    ps_sombraVolTeorico_p = []
    ps_sombraVolTeorico_o = []
    ps_sombraVolTeorico_s = []
    for k = 1:num_alturas

        ps_Volteor_k = vec_psVolteor[k]

        ps_sombra_p_k = polyShape.polyProyeccion(ps_Volteor_k, vec_altVolteor[k], "p")
        ps_sombra_o_k = polyShape.polyProyeccion(ps_Volteor_k, vec_altVolteor[k], "o")
        ps_sombra_s_k = polyShape.polyProyeccion(ps_Volteor_k, vec_altVolteor[k], "s")

        if k == 1
            ps_sombraVolTeorico_p = deepcopy(ps_sombra_p_k)
            ps_sombraVolTeorico_o = deepcopy(ps_sombra_o_k)
            ps_sombraVolTeorico_s = deepcopy(ps_sombra_s_k)
        else
            ps_sombraVolTeorico_p = polyShape.polyUnion(ps_sombraVolTeorico_p, ps_sombra_p_k)
            ps_sombraVolTeorico_o = polyShape.polyUnion(ps_sombraVolTeorico_o, ps_sombra_o_k)
            ps_sombraVolTeorico_s = polyShape.polyUnion(ps_sombraVolTeorico_s, ps_sombra_s_k)
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