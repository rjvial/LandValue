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