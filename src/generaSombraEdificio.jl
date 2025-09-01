function generaSombraEdificio(
    ps_bases::Vector{PolyShape},
    alts::Vector{Float64},
    ps_publico::PolyShape,
    ps_calles_contexto::PolyShape
)
    # Inner helper for one block
    function generaSombraBox(ps_baseBox::PolyShape, alt::Float64,
                              ps_publico::PolyShape, ps_calles_contexto::PolyShape)
        ps_SombraBox_p = PolyShape([],0)
        ps_SombraBox_o = PolyShape([],0)
        ps_SombraBox_s = PolyShape([],0)
        numBoxes = ps_baseBox.NumRegions
        for e = 1:numBoxes
            V_base_e = ps_baseBox.Vertices[e]
            V_baseBox_e = [V_base_e zeros(size(V_base_e,1),1);
                           V_base_e alt .* ones(size(V_base_e,1),1)]
            numV = size(V_baseBox_e,1)
            V_SombraBox_p = V_baseBox_e[:,1:2]
            V_SombraBox_o = V_baseBox_e[:,1:2]
            V_SombraBox_s = V_baseBox_e[:,1:2]
            for i = 1:numV
                alt_i = V_baseBox_e[i,3]
                V_SombraBox_p[i,1] -= alt_i / 0.49
                V_SombraBox_o[i,1] += alt_i / 0.49
                V_SombraBox_s[i,2] -= alt_i / 1.54
            end
            V_SombraBox_p = polyShape.convHull(V_SombraBox_p)
            V_SombraBox_o = polyShape.convHull(V_SombraBox_o)
            V_SombraBox_s = polyShape.convHull(V_SombraBox_s)
            if e == 1
                push!(ps_SombraBox_p.Vertices, V_SombraBox_p)
                push!(ps_SombraBox_o.Vertices, V_SombraBox_o)
                push!(ps_SombraBox_s.Vertices, V_SombraBox_s)
                ps_SombraBox_p.NumRegions = length(ps_SombraBox_p.Vertices)
                ps_SombraBox_o.NumRegions = length(ps_SombraBox_o.Vertices)
                ps_SombraBox_s.NumRegions = length(ps_SombraBox_s.Vertices)
            else
                ps_SombraBox_p = polyShape.polyUnion(ps_SombraBox_p, PolyShape([V_SombraBox_p],1))
                ps_SombraBox_o = polyShape.polyUnion(ps_SombraBox_o, PolyShape([V_SombraBox_o],1))
                ps_SombraBox_s = polyShape.polyUnion(ps_SombraBox_s, PolyShape([V_SombraBox_s],1))
            end
        end
        # Subtract public spaces
        p_p = polyShape.polyDifference(ps_SombraBox_p, ps_publico)
        ps_sombraBox_p = length(p_p.Vertices) > 0 ? PolyShape(p_p.Vertices, length(p_p.Vertices)) : PolyShape([],0)
        p_o = polyShape.polyDifference(ps_SombraBox_o, ps_publico)
        ps_sombraBox_o = length(p_o.Vertices) > 0 ? PolyShape(p_o.Vertices, length(p_o.Vertices)) : PolyShape([],0)
        p_s = polyShape.polyDifference(ps_SombraBox_s, ps_publico)
        ps_sombraBox_s = length(p_s.Vertices) > 0 ? PolyShape(p_s.Vertices, length(p_s.Vertices)) : PolyShape([],0)
        # Subtract streets
        ps_sombraBox_p = polyShape.polyDifference(ps_sombraBox_p, ps_calles_contexto)
        ps_sombraBox_o = polyShape.polyDifference(ps_sombraBox_o, ps_calles_contexto)
        ps_sombraBox_s = polyShape.polyDifference(ps_sombraBox_s, ps_calles_contexto)
        return ps_sombraBox_p, ps_sombraBox_o, ps_sombraBox_s
    end

    # Process first block unconditionally
    ps1_p, ps1_o, ps1_s = generaSombraBox(ps_bases[1], alts[1], ps_publico, ps_calles_contexto)
    ps_sombraEdif_p = deepcopy(ps1_p)
    ps_sombraEdif_o = deepcopy(ps1_o)
    ps_sombraEdif_s = deepcopy(ps1_s)

    # Union shadows of remaining blocks if height ≥ 1
    for i in 2:length(ps_bases)
        if alts[i] >= 1
            psi_p, psi_o, psi_s = generaSombraBox(ps_bases[i], alts[i], ps_publico, ps_calles_contexto)
            ps_sombraEdif_p = polyShape.polyUnion(ps_sombraEdif_p, psi_p)
            ps_sombraEdif_o = polyShape.polyUnion(ps_sombraEdif_o, psi_o)
            ps_sombraEdif_s = polyShape.polyUnion(ps_sombraEdif_s, psi_s)
        end
    end

    return ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s
end