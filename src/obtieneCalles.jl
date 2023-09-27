function obtieneCalles(ps_predio::PolyShape, ps_buffer_predio::PolyShape, ps_predios_buffer::PolyShape, ps_manzanas_buffer::PolyShape)

    # Obtiene calles dentro del buffer

    ps_predios_buffer_union = polyShape.polyUnion(ps_predios_buffer)
    ps_calles = polyShape.polyDifference_v2(ps_buffer_predio, ps_predios_buffer_union)


    # Obtiene espacio público a partir de ps_predio
    numVertices = size(ps_predio.Vertices[1],1)
    ps_extend = polyShape.polyCopy(ps_predio)
    ps_extend = polyShape.polyEliminaColineales(ps_extend)

    vecSecConCalle = Array{Int64,1}()


    # Obtiene vector de secciones con calle y vector de ángulos de los bordes del predio
    ps_buffer_local_predio = polyShape.shapeBuffer(ps_predio, 30, 0)
    ps_calle_predio = polyShape.polyDifference_v2(ps_buffer_local_predio, ps_predios_buffer_union)
    vec_edges_predio, vec_reg_predio = polyShape.polyShape2lineVec(ps_predio)
    ps_calle_predio_ = polyShape.shapeBuffer(ps_calle_predio, 2, 0)
    flag_sec_con_calle = [polyShape.shapeContains(ps_calle_predio_,vec_edges_predio[i]) for i in eachindex(vec_edges_predio)]
    vecSecConCalle = collect(1:length(vec_edges_predio))
    vecSecConCalle = vecSecConCalle[flag_sec_con_calle .== 1]
    vec_edges_predio_con_calle = vec_edges_predio[flag_sec_con_calle .== 1]
    # Obtiene angulos de los segmentos de predio con calle
    vec_angle = polyShape.lineAngle.(vec_edges_predio_con_calle)
    vec_mid_edge = polyShape.midPointSegment.(vec_edges_predio_con_calle)
    vec_box_aux = [polyShape.polyBox(vec_mid_edge[i], 1., 3., vec_angle[i]) for i in eachindex(vec_mid_edge)]
    flag_box_in_calle = [polyShape.shapeContains(ps_calle_predio, vec_box_aux[i]) for i in eachindex(vec_box_aux)]
    vec_angle[flag_box_in_calle .== 0] = vec_angle[flag_box_in_calle .== 0] .- pi
    vec_box = [polyShape.polyBox(vec_mid_edge[i], 1., 20., vec_angle[i]) for i in eachindex(vec_mid_edge)]

    vec_media_calle = []
    vec_toda_calle = []
    vecAnchoCalle = []
    for i in eachindex(vec_box)
        largo_edge_i = polyShape.lineLength(vec_edges_predio_con_calle[i])
        vec_alpha = collect(1:round(largo_edge_i/1) + 1) ./ (round(largo_edge_i/1) + 1)
        vec_points_i = [polyShape.alphaPointSegment(vec_edges_predio_con_calle[i], vec_alpha[j]) for j in eachindex(vec_alpha) ]
        vec_box_prev_i = [polyShape.polyBox(vec_points_i[j], 2., 40., vec_angle[i]) for j in eachindex(vec_points_i)]
        vec_cetroids_i = [polyShape.shapeCentroid(polyShape.polyIntersect(vec_box_prev_i[j], ps_calle_predio)) for j in eachindex(vec_box_prev_i)]
        vec_dist_i = [polyShape.distanceBetweenPoints(vec_cetroids_i[j], vec_points_i[j]) for j in eachindex(vec_cetroids_i)]
        mean_dist_i = sum(vec_dist_i) / length(vec_dist_i)
        vecAnchoCalle = push!(vecAnchoCalle, mean_dist_i * 2)
        vec_box_i = polyShape.polyBox(polyShape.shapeVertex(vec_edges_predio_con_calle[i],1,2), largo_edge_i+0, mean_dist_i, vec_angle[i])
        vec_box_doble_i = polyShape.polyBox(polyShape.shapeVertex(vec_edges_predio_con_calle[i],1,2), largo_edge_i+0, mean_dist_i * 2, vec_angle[i])
        vec_media_calle = push!(vec_media_calle, vec_box_i)
        vec_toda_calle = push!(vec_toda_calle, vec_box_doble_i)
    end
    ps_media_calle = polyShape.polyUnion([polyShape.polyExpand(vec_media_calle[i],.1) for i in eachindex(vec_media_calle)])
    ps_media_calle = polyShape.polyDifference_v2(ps_media_calle, ps_predio)
    ps_toda_calle = polyShape.polyUnion([vec_toda_calle[i] for i in eachindex(vec_toda_calle)])
    ps_toda_calle = polyShape.polyDifference_v2(ps_toda_calle, ps_predios_buffer_union)
    ps_bruto = polyShape.polyExpand(polyShape.polyUnion(ps_predio, ps_media_calle), 0.1)
    ps_publico = polyShape.polyExpand(polyShape.polyUnion(ps_predio, ps_toda_calle), 0.1)

    # fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_predio, "blue", 0.2)
    # fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_calles, "gray", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)
    # fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_media_calle, "green", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)
    # fig, ax, ax_mat = polyShape.plotPolyshape2D.(vec_niveles, "red", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)


    return ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle

end