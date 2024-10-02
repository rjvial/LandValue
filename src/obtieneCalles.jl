function obtieneCalles(ps_predio::PolyShape, ps_buffer_predio::PolyShape, ps_predios_buffer::PolyShape, ps_manzanas_buffer::PolyShape)

    # Obtiene calles dentro del buffer
    ps_predios_buffer_union = polyShape.polyUnion(ps_predios_buffer)
    ps_predios_buffer_union = polyShape.polyOffset(polyShape.polyOffset(ps_predios_buffer_union,.1),-.1)
    ps_calles = polyShape.polyDifference(ps_buffer_predio, ps_predios_buffer_union)

    # Obtiene vector de secciones del predio con calle 
    ps_buffer_local_predio = polyShape.shapeBuffer(ps_predio, 30, 0)
    ps_calle_predio = polyShape.polyDifference(ps_buffer_local_predio, ps_predios_buffer_union)
    vec_edges_predio, _ = polyShape.polyShape2lineVec(ps_predio)

    vec_predio_calle_intersect_ = [polyShape.shapeIntersect(polyShape.shapeBuffer(ps_calle_predio, .4, 0), vec_edges_predio[i]) for i in eachindex(vec_edges_predio)] 
    vec_predio_calle_intersect = Vector{LineShape}()
    for j in eachindex(vec_predio_calle_intersect_)
        if size(vec_predio_calle_intersect_[j].Vertices[1], 1) >= 1
            push!(vec_predio_calle_intersect, vec_predio_calle_intersect_[j])
        else
            push!(vec_predio_calle_intersect, LineShape([[0 0]],0))
        end
    end
    flag_sec_con_calle = [false for i in eachindex(vec_edges_predio)]
    for j in eachindex(vec_predio_calle_intersect)
        if size(vec_predio_calle_intersect[j].Vertices[1], 1) >= 2
            length_line_j = maximum(polyShape.lineLength(vec_predio_calle_intersect[j]))
            if length_line_j >= 4
                flag_sec_con_calle[j] = true
            end
        end
    end

    vecSecConCalle = collect(1:length(vec_edges_predio))
    vecSecConCalle = vecSecConCalle[flag_sec_con_calle .== 1]
    ps_calle = polyShape.polyIntersect(ps_calle_predio, polyShape.partialPolyOffset(ps_predio, vecSecConCalle, 30))

    vecAnchoCalle = fill(10., length(vecSecConCalle))
    for i in eachindex(vecSecConCalle)
        ps_calle_lado_i = polyShape.polyIntersect(ps_calle, polyShape.partialPolyOffset(ps_predio, [vecSecConCalle[i]], [30]))

        ancho_i = 10
        delta = .25
        ps_box_ant = polyShape.line2Box(vec_predio_calle_intersect[vecSecConCalle[i]], ancho_i)
        area_box_ant = polyShape.shapeArea(ps_box_ant)
        ps_inter_ant = polyShape.polyIntersect(ps_calle_lado_i, ps_box_ant)
        area_inter_ant = polyShape.shapeArea(ps_inter_ant)
        for k = 1:Int(50/delta)
            ancho_i += delta
            ps_box = polyShape.line2Box(vec_predio_calle_intersect[vecSecConCalle[i]], ancho_i)
            area_box = polyShape.shapeArea(ps_box)
            ps_inter = polyShape.polyIntersect(ps_calle_lado_i, ps_box)
            area_inter = polyShape.shapeArea(ps_inter)
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

    ps_toda_calle = polyShape.polyDifference(polyShape.partialPolyOffset(ps_predio, vecSecConCalle, vecAnchoCalle), ps_predio)
    ps_bruto = polyShape.partialPolyOffset(ps_predio, vecSecConCalle, vecAnchoCalle./2)
    ps_publico = polyShape.polyOffset(polyShape.polyUnion(ps_predio, ps_toda_calle), 0.1)


    fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_predio, "blue", 0.2)
    fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_calles, "gray", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)
    fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_bruto, "green", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)
    fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_publico, "green", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)

    return ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle

end