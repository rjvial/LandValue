function generaVol3D(vec_psVolteor, vec_altVolteor)

    # Determina las alturas en las cuales hay cambios
    vec_psVolteor_ = deepcopy(vec_psVolteor)
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

