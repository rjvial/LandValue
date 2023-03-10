function generaVol3D(ps_predio::PolyShape, ps_bruto::PolyShape, rasante::Float64, dcn::DatosCabidaNormativa, dcp::DatosCabidaPredio)

    numLadosPredio = size(ps_predio.Vertices[1], 1);
    conjuntoLados = collect(1:numLadosPredio)
    conjuntoLadosCalle = dcp.ladosConCalle;
    numCalles = length(conjuntoLadosCalle)
    conjuntoLadosVecinos = setdiff(conjuntoLados, conjuntoLadosCalle);
    alturaMax = dcn.alturaMax
    sepVecinos = dcn.distanciamiento
    antejardin = dcn.antejardin
    anchoEspacioPublico = dcp.anchoEspacioPublico


    # Genera vector de separaciones entre el comienzo de la rasante (separacion predial o eje esp. público) 
    # y la línea de edificación
    vecSeparacion = zeros(numLadosPredio)
    for i in conjuntoLadosVecinos
        vecSeparacion[i] = sepVecinos[1]
    end
    numCalles = length(conjuntoLadosCalle)
    for i= 1:numCalles
        vecSeparacion[conjuntoLadosCalle[i]] = anchoEspacioPublico[i]/2 + antejardin[1]
    end
    conjSepDist = collect(1:.1:alturaMax[1]/rasante)
    numSepDistintas = length(conjSepDist)

    
    # Genera Volumen Teórico a partir de múltiples cortes a distintas alturas 
    function volumenPorCortes(numSepDistintas::Int64, vecSeparacion::Vector{Float64}, conjSepDist::Vector{Float64}, ps_bruto::PolyShape, conjuntoLados::Vector{Int64}, rasante::Float64)
        vec_psVolteor = Array{PolyShape, 1}(undef, numSepDistintas)
        vec_altVolteor = zeros(numSepDistintas,1)
        id = 1
        pos_area_chica = numSepDistintas
        flag_area_chica = false
        for j = 1:numSepDistintas # Para cada una de las separaciones distintas 
            if flag_area_chica == false
                vecDelta_j = max.(0,vecSeparacion .- conjSepDist[j])
                ps_corte = polyShape.polyCopy(ps_bruto)
                ps_corte = polyShape.polyExpandSegmentVec(ps_corte, -vecDelta_j, collect(conjuntoLados))
                ps_corte = polyShape.polyExpand(ps_corte, -conjSepDist[j])
                ps_corte = polyShape.polyEliminaColineales(ps_corte)
                if polyShape.polyArea(ps_corte) <= 4 && pos_area_chica == numSepDistintas
                    pos_area_chica = j
                    flag_area_chica = true
                end
                if ps_corte.NumRegions >= 1
                    vec_psVolteor[id] = ps_corte
                    vec_altVolteor[id] = conjSepDist[j]*rasante
                    id += 1
                end
            end

        end
        vec_psVolteor = vec_psVolteor[1:pos_area_chica-1]
        vec_psVolteor = [vec_psVolteor[1]; vec_psVolteor]

        vec_altVolteor = vec_altVolteor[1:pos_area_chica-1]
        vec_altVolteor = [0.; vec_altVolteor]
    
        return vec_psVolteor, vec_altVolteor
    end

    display("Calcula volumenPorCortes")
    @time vec_psVolteor, vec_altVolteor = volumenPorCortes(numSepDistintas, vecSeparacion, conjSepDist, ps_bruto, conjuntoLados, rasante)


    # Determina las alturas en las cuales hay cambios
    vec_psVolteor_ = copy(vec_psVolteor)
    vec_altVolteor_ = copy(vec_altVolteor)
    flagAlt = zeros(length(vec_altVolteor),1)
    flagAlt[1] = 1
    for i = 3:length(vec_altVolteor_)
        ps_i = vec_psVolteor_[i]
        ps_i1 = vec_psVolteor_[i-1]
        ps_i2 = vec_psVolteor_[i-2]
        n_i = size(vec_psVolteor_[i].Vertices[1],1)
        n_i1 = size(vec_psVolteor_[i-1].Vertices[1],1)
        n_i2 = size(vec_psVolteor_[i-2].Vertices[1],1)
        if n_i < n_i1 
            flagAlt[i-1] = 1
            flagAlt[i] = 1
        elseif n_i == n_i1 && n_i1 == n_i2
            vec_dist_01 = [polyShape.shapeDistance(polyShape.shapeVertex(ps_i,1,v), polyShape.shapeVertex(ps_i1,1,v)) for v=1:n_i] #sqrt.(sum((vec_pos_i .- vec_pos_i1).^2, dims=2))
            vec_dist_12 = [polyShape.shapeDistance(polyShape.shapeVertex(ps_i1,1,v), polyShape.shapeVertex(ps_i2,1,v)) for v=1:n_i]  #sqrt.(sum((vec_pos_i1 .- vec_pos_i2).^2, dims=2))
            for j in eachindex(vec_dist_01)
                if vec_dist_01[j] > 0.01*5 && vec_dist_12[j] < 0.01*5
                    flagAlt[i] = 1
                end
            end
        end
    end
    flagAlt[end] = 1
    vec_psVolteor_ = vec_psVolteor_[flagAlt[:] .== 1]
    vec_altVolteor_ = vec_altVolteor_[flagAlt[:] .== 1]


    # Genera ids unicos para cada uno de los vertices
    vecVertices = []
    cont = 0
    for i in eachindex(vec_psVolteor_)
        vecAux = zeros(size(vec_psVolteor_[i].Vertices[1],1),1)
        for j = 1:size(vec_psVolteor_[i].Vertices[1],1)
            cont += 1
            vecAux[j] = Int(cont)
        end
        vecVertices = push!(vecVertices, vecAux)
    end

    
    # Genera matriz de conexiones entre vertices
    max_vertices = maximum([size(vec_psVolteor_[r].Vertices[1],1)  for r in eachindex(vec_psVolteor_)])
    num_polyShapes = size(vec_psVolteor_,1)
    matConexionVertices = zeros(num_polyShapes * max_vertices, 2)
    cont = 0
    for i = 1:length(vec_psVolteor_)-1
        ps_il = vec_psVolteor_[i] # poligono capa low
        N_il = size(ps_il.Vertices[1],1)
        ps_iu = vec_psVolteor_[i+1] # poligono capa up
        N_iu = size(ps_iu.Vertices[1],1)
        for j = 1:N_il
            min_dist = 10000.
            cont += 1
            for k = 1:N_iu # Busca el vertice k (capa up) más cercano al vertice j (capa low)
                pt_l_j = polyShape.shapeVertex(ps_il, 1, j) # coordenadas vertice j de la capa low
                pt_u_k = polyShape.shapeVertex(ps_iu, 1, k) # coordenadas vertice k de la capa up
                dist_jk = polyShape.shapeDistance(pt_l_j, pt_u_k)
                id_l_j = vecVertices[i][j] # id vertice j de la capa low
                id_u_k = vecVertices[i+1][k] # id vertice k de la capa up
                if dist_jk < min_dist - 1
                    matConexionVertices[cont,:] = [id_l_j id_u_k]
                    min_dist = dist_jk
                end
            end
        end
    end
    matConexionVertices = matConexionVertices[matConexionVertices[:,1] .>= 1,:]

    matVolteor = [0. 0. 0.]
    for i in eachindex(vec_psVolteor_)
        matVolteor = [matVolteor; vec_psVolteor_[i].Vertices[1] vec_altVolteor_[i]*ones(size(vec_psVolteor_[i].Vertices[1],1),1)]
    end
    matVolteor = matVolteor[2:end, :]
    ps_volteor = PolyShape([matVolteor],1)

    return matConexionVertices, vecVertices, ps_volteor

end

