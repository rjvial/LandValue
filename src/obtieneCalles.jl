function obtieneCalles(ps_predio::PolyShape, ps_buffer_predio::PolyShape, ps_predios_buffer::PolyShape, ps_manzanas_buffer::PolyShape)

    # Obtiene calles dentro del buffer
    ps_calles = polyShape.polyDifference_v2(ps_buffer_predio, ps_manzanas_buffer)
    ps_calles_ = polyShape.polyExpand(ps_calles, 15)
    ps_calles_ = polyShape.polyDifference_v2(ps_calles_, ps_predios_buffer)
    ps_calles = polyShape.polyUnion(ps_calles_)


    # Obtiene espacio público a partir de ps_predio
    numVertices = size(ps_predio.Vertices[1],1)
    ps_extend = polyShape.polyCopy(ps_predio)
    ps_extend = polyShape.polyEliminaColineales(ps_extend)
    cont = 0
    condSigue = true
    vecAnchoCalles = zeros(numVertices,1)
    vecSecConCalle = Array{Int64,1}()
    delta = .1*5
    
    setCalles = 1:numVertices

    ##################

    function ladosConCalle(ps_predios_buffer_union, vec_edges_predio, vecSecConCalle)
        vec_angle = []
        for i in setCalles
            edge_i = vec_edges_predio[i]
            p_midEdge_i = polyShape.midPointSegment(edge_i)
            angle_i = polyShape.lineAngle(edge_i)
            ps_box_i = polyShape.polyBox(p_midEdge_i, 1., 5., angle_i)
            point_box = polyShape.subShape(polyShape.shapeVertex(ps_box_i),3)
            signo = polyShape.shapeContains(ps_predio, point_box)
            if signo
                angle_i = angle_i - pi
            end
            ps_box_i = polyShape.polyBox(p_midEdge_i, 1., 5., angle_i)
            area_inter_box_predios = polyShape.polyArea(polyShape.polyIntersect(ps_predios_buffer_union,ps_box_i))
            if area_inter_box_predios < .5
                vecSecConCalle = push!(vecSecConCalle, i)
            end
            push!(vec_angle, angle_i)
        end
        return vecSecConCalle, vec_angle
    end


    function callesPredio(ps_predio, vecSecConCalle, vec_edges_predio, ps_predios_buffer_union)
        ps_aux = []
        for i in vecSecConCalle
            edge_i = vec_edges_predio[i]
            p_start_i = polyShape.shapeVertex(edge_i, 1, 1)
            len_i = polyShape.lineLength(edge_i)
            angle_i = vec_angle[i] + pi/2
            box_i = polyShape.polyBox(p_start_i, 30., len_i,angle_i)
            if i == vecSecConCalle[1]
                ps_aux = deepcopy(box_i)
            else
                ps_aux = polyShape.polyUnion(ps_aux, box_i)
            end
        end
        ps_predio_extendido = polyShape.polyUnion(ps_predio, ps_aux)
        ps_calles_predio = polyShape.polyDifference(ps_predio_extendido, ps_predios_buffer_union)

        return ps_calles_predio
    end

    # Obtiene vector de secciones con calle y vector de ángulos de los bordes del predio
    ps_predios_buffer_union = polyShape.polyUnion(ps_predios_buffer)
    vec_edges_predio = polyShape.polyShape2lineVec(ps_predio)
    vecSecConCalle, vec_angle = ladosConCalle(ps_predios_buffer_union, vec_edges_predio, vecSecConCalle)
    
    # Genera polyShape de calles del predio 
    ps_calles_predio = callesPredio(ps_predio, vecSecConCalle, vec_edges_predio, ps_predios_buffer_union)

    # Obtiene vector de boxes y vector de vertices de la calle que limitan con el predio
    vec_box = []
    vec_semi_calle = []
    for i in vecSecConCalle
        edge_predio_i = vec_edges_predio[i]
        p_start_i = polyShape.shapeVertex(edge_predio_i,1,1)
        p_end_i = polyShape.shapeVertex(edge_predio_i,1,2)
        p_1 = p_start_i * 0.9 + p_end_i * 0.1
        if i == vecSecConCalle[1]
            box_1 = polyShape.polyBox(p_1, 1., 40., vec_angle[i])
            push!(vec_box, box_1)
            push!(vec_semi_calle, p_start_i)
        end
        push!(vec_semi_calle, p_end_i)
        angle_i = i < vecSecConCalle[end] ? 0.5*vec_angle[i] + 0.5*vec_angle[i+1] : vec_angle[i]
        box_3 = polyShape.polyBox(p_end_i, 1., 40., angle_i)
        push!(vec_box, box_3)
    end
    vec_semi_calle = reverse(vec_semi_calle)

    # Obtiene los vertices del eje de la semi calle y los agrega a vec_semi_calle
    for i in eachindex(vec_box)
        inter_box_calles_i = polyShape.polyIntersect(vec_box[i], ps_calles_predio)
        push!(vec_semi_calle, polyShape.shapeCentroid(inter_box_calles_i))
    end
    # fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_calles_predio, 0, "green", 0.2)
    # fig, ax, ax_mat = polyShape.plotPolyshape2Din3D.(vec_semi_calle, 0., "red", 0.5, fig=fig, ax=ax, ax_mat=ax_mat)

    # Convierte los vertices de la semi calle en un polyShape
    V_semi_calle = [0 0]
    for i in eachindex(vec_semi_calle)
        V_semi_calle = [V_semi_calle; vec_semi_calle[i].Vertices[:]']
    end
    ps_semi_calle = PolyShape([V_semi_calle[2:end,:]],1)
    # fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_calles_predio, 0, "green", 0.2)
    # fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_semi_calle, 0., "red", 0.8, fig=fig, ax=ax, ax_mat=ax_mat)    


    ps_union = polyShape.polyUnion(ps_predio, ps_semi_calle)
    vec_niveles = [polyShape.polyExpand(ps_union, -i) for i = 2:2:30]
    num_niveles = length(vec_niveles)
    vec_altura = [3*i for i=1:14]
    vec_niveles_ = [polyShape.polyDifference(vec_niveles[i], ps_calles_predio) for i = 1:14]
    # fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predio, 0, "green", 0.2)
    # fig, ax, ax_mat = polyShape.plotPolyshape2DVecin3D(vec_niveles_, vec_altura, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
    # fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_calles_predio, 0., "black", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
    # fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_semi_calle, 0., "black", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
    # ##################


    while condSigue
        cont += 1
        cont_i = 0
        delta_ = (cont == 1) ? 1. : delta
        
        for i in setCalles
            #display("cont = " *string(cont) * "   i = " * string(i))
            
            ps_extend_i = polyShape.polyExpandSegmentVec(ps_extend, [delta_], [i])
            ps_siguiente_i = polyShape.polyExpandSegmentVec(ps_extend, [delta_], [i])
            ps_delta_i = polyShape.polyDifference(ps_siguiente_i, ps_extend)
            area_delta_i = polyShape.polyArea(ps_delta_i)
            area_interCalle_i = 0
            if area_delta_i > .0001
                ps_interCalle_i = polyShape.polyIntersect(polyShape.polyEliminaSpikes(ps_delta_i), ps_calles)
                area_interCalle_i = polyShape.polyArea(ps_interCalle_i)
                vec_deltaPorcCalle_i = area_interCalle_i / area_delta_i
            else
                vec_deltaPorcCalle_i = 0
            end
            if cont == 1 && area_interCalle_i > 1
                ps_extend_i = polyShape.polyEliminaSpikes(ps_extend_i)
                ps_extend = polyShape.polyCopy(ps_extend_i)
                cont_i += 1
                vecAnchoCalles[i] += delta_
                vecSecConCalle = push!(vecSecConCalle, i)
            elseif (vecAnchoCalles[i] + delta_ < 5 && vec_deltaPorcCalle_i >= .30) || vec_deltaPorcCalle_i >= .70
                ps_extend_i = polyShape.polyEliminaSpikes(ps_extend_i)
                ps_extend = polyShape.polyCopy(ps_extend_i)
                cont_i += 1
                vecAnchoCalles[i] += delta_
            else
                setCalles = setdiff(setCalles, i)
            end 
        end
        if cont_i == 0 || cont >= 46 #1000
            condSigue = false
        end
    end
    ps_publico = polyShape.polySimplify(ps_extend)
    vecAnchoCalle = vecAnchoCalles[vecSecConCalle]
    vecSecConCalle_si = Int.(vecSecConCalle[vecAnchoCalle .>= 2.])
    vecAnchoCalle_si = vecAnchoCalle[vecAnchoCalle .>= 2.]
    vecSecConCalle_no = Int.(vecSecConCalle[vecAnchoCalle .< 2.])
    vecAnchoCalle_no = vecAnchoCalle[vecAnchoCalle .< 2.]
    ps_publico = polyShape.polyExpandSegmentVec(ps_publico, -vecAnchoCalle_no, vecSecConCalle_no)

    ps_bruto = polyShape.polyExpandSegmentVec(ps_predio, vecAnchoCalle_si/2, collect(vecSecConCalle_si))

    return ps_calles, ps_publico, ps_bruto, vecAnchoCalle_si, vecSecConCalle_si

end