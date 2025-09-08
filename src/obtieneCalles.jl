function obtieneCalles(calles_data, ps_combi_, dx, dy)
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
    vec_edges_combi, _ = polyShape.shape2vector(ps_combi_)

    vec_combi_calle_intersect_ = [polyGdal.shapeIntersect(polyGdal.shapeBuffer(ps_calles_combi, .4, 0), vec_edges_combi[i]) for i in eachindex(vec_edges_combi)]
    vec_combi_calle_intersect = Vector{LineShape}()
    for j in eachindex(vec_combi_calle_intersect_)
        if !isempty(vec_combi_calle_intersect_[j].Vertices) && 
                size(vec_combi_calle_intersect_[j].Vertices[1], 1) >= 1 &&
                polyShape.lineLength(vec_combi_calle_intersect_[j]) > 2
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
    ps_calles = polyShape.polyIntersection(ps_calles_combi, polyShape.partialPolyOffset(ps_combi_, vecSecConCalle, 30))

    # ============================================================================
    # 3. STREET WIDTH CALCULATION
    # ============================================================================
    vecAnchoCalle = fill(10., length(vecSecConCalle))
    for i in eachindex(vecSecConCalle)
        ps_calle_lado_i = polyShape.polyIntersection(ps_calles, polyShape.partialPolyOffset(ps_combi_, [vecSecConCalle[i]], [30]))

        ancho_i = 10
        delta = .25
        ps_box_ant = polyShape.line2Box(vec_combi_calle_intersect[vecSecConCalle[i]], ancho_i)
        area_box_ant = polyGdal.shapeArea(ps_box_ant)
        ps_inter_ant = polyShape.polyIntersection(ps_calles_combi, ps_box_ant)
        area_inter_ant = polyGdal.shapeArea(ps_inter_ant)
        for k = 1:Int(50/delta)
            ancho_i += delta
            ps_box = polyShape.line2Box(vec_combi_calle_intersect[vecSecConCalle[i]], ancho_i)
            area_box = polyGdal.shapeArea(ps_box)
            ps_inter = polyShape.polyIntersection(ps_calles_combi, ps_box)
            area_inter = polyGdal.shapeArea(ps_inter)
            delta_box = area_box - area_box_ant
            delta_inter = area_inter - area_inter_ant
            if delta_inter / delta_box < .8 
                break
            else
                area_box_ant = area_box
                area_inter_ant = area_inter
            end
        end
        vecAnchoCalle[i] = ancho_i
    end

    # ============================================================================
    # 4. GEOMETRY GENERATION
    # ============================================================================
    ps_toda_calle = polyShape.polyDifference(polyShape.partialPolyOffset(ps_combi_, vecSecConCalle, vecAnchoCalle), ps_combi_)
    ps_bruto = polyShape.partialPolyOffset(ps_combi_, vecSecConCalle, vecAnchoCalle./2)
    ps_publico = polyClipper.polyOffset(polyShape.polyUnion(ps_combi_, ps_toda_calle), 0.1)

    # ============================================================================
    # 5. VISUALIZATION
    # ============================================================================
    fig, ax, ax_mat = polyPlot.plotPolyshape2D(ps_combi_, "blue", 0.2)
    fig, ax, ax_mat = polyPlot.plotPolyshape2D(ps_calles, "gray", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)
    fig, ax, ax_mat = polyPlot.plotPolyshape2D(ps_bruto, "green", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)
    fig, ax, ax_mat = polyPlot.plotPolyshape2D(ps_publico, "green", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)

    return ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle

end