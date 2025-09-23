function obtieneCalles(calles_data, ps_combi, dx, dy)
    # ============================================================================
    # STREET GEOMETRY PROCESSING AND ANALYSIS
    # ============================================================================

    # ============================================================================
    # 1. DATA VALIDATION AND PREPROCESSING
    # ============================================================================
    if size(calles_data, 1) == 0
        # Return empty results if no street data available
        return PolyShape([], 0), PolyShape([], 0), PolyShape([], 0), Float64[], Int[]
    end
    
    ps_calles_combi = polyGdal.astext2shape(calles_data[:, "calles_combi_wkt"])
    ps_calles_combi = polyShape.setPolyOrientation(ps_calles_combi,1)
    ps_calles_combi = polyShape.shape_4326to32719(ps_calles_combi)
    ps_calles_combi = polyShape.ajustaCoordenadas(ps_calles_combi, dx, dy)

    # ============================================================================
    # 2. STREET-PROPERTY INTERSECTION ANALYSIS
    # ============================================================================ 
    vec_edges_combi, _ = polyShape.shape2vector(ps_combi)

    # vec_combi_calle_intersect_ = [polyGdal.shapeIntersect(polyClipper.polyOffset(ps_calles_combi, .4), vec_edges_combi[i]) for i in eachindex(vec_edges_combi)]
    vec_combi_calle_intersect_ = [polyGdal.shapeIntersect(vec_edges_combi[i], polyClipper.polyOffset(ps_calles_combi, .4)) for i in eachindex(vec_edges_combi)]

    vec_combi_calle_intersect = Vector{LineShape}()
    for j in eachindex(vec_combi_calle_intersect_)
        if !isempty(vec_combi_calle_intersect_[j].Vertices) && 
                size(vec_combi_calle_intersect_[j].Vertices[1], 1) >= 1 &&
                maximum(polyShape.lineLength(vec_combi_calle_intersect_[j])) > 2
            push!(vec_combi_calle_intersect, vec_combi_calle_intersect_[j])
        else
            push!(vec_combi_calle_intersect, LineShape([[0 0]],0))
        end
    end
    flag_sec_con_calle = [false for i in eachindex(vec_edges_combi)]
    for j in eachindex(vec_combi_calle_intersect)
        if !isempty(vec_combi_calle_intersect[j].Vertices) && size(vec_combi_calle_intersect[j].Vertices[1], 1) >= 2
            length_line_j = maximum(polyShape.lineLength(vec_combi_calle_intersect[j]))
            if length_line_j >= 4
                flag_sec_con_calle[j] = true
            end
        end
    end

    vecSecConCalle = collect(1:length(vec_edges_combi))
    vecSecConCalle = vecSecConCalle[flag_sec_con_calle .== 1]
    ps_calles = polyShape.polyIntersection(ps_calles_combi, polyClipper.polyOffset(ps_combi, 30))


    # ============================================================================
    # 3. STREET WIDTH CALCULATION
    # ============================================================================
    vecAnchoCalle = fill(10., length(vecSecConCalle))
    for i in eachindex(vecSecConCalle)
        x_line_i = polyShape.transformLine(vec_combi_calle_intersect[vecSecConCalle[i]], :extend, -2.0)
        ps_box_i = polyShape.line2Box(x_line_i, 60)
        vecAnchoCalle[i] = polyShape.polyHeight(ps_calles, ps_box_i, :minimum, 1.)
    end

    # ============================================================================
    # 4. GEOMETRY GENERATION
    # ============================================================================


    ps_toda_calle = polyShape.polyDifference(polyShape.partialPolyOffset(ps_combi, vecSecConCalle, vecAnchoCalle), ps_combi)
    ps_bruto = polyShape.partialPolyOffset(ps_combi, vecSecConCalle, vecAnchoCalle./2)
    ps_publico = polyClipper.polyOffset(polyShape.polyUnion(ps_combi, ps_toda_calle), 0.1)

    # ============================================================================
    # 5. VISUALIZATION
    # ============================================================================
    # fig, ax, ax_mat = polyPlot.plotPolyshape2D(ps_combi, "blue", 0.2)
    # fig, ax, ax_mat = polyPlot.plotPolyshape2D(ps_calles, "gray", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)
    # fig, ax, ax_mat = polyPlot.plotPolyshape2D(ps_bruto, "green", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)
    # fig, ax, ax_mat = polyPlot.plotPolyshape2D(ps_publico, "green", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)

    return ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle

end