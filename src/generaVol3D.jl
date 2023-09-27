function generaVol3D(vec_psVolteor, vec_altVolteor)

    # Genera matriz de lineas agrupadas por caras
    num_alturas = length(vec_altVolteor)
    line_vec_1, reg_vec_1 = polyShape.polyShape2lineVec(vec_psVolteor[1])
    mat_lines = fill(LineShape([],0), (num_alturas, length(line_vec_1))) #Array{LineShape,2}(LineShape([],1), num_alturas, length(line_vec_1))
    for i = 1:num_alturas
        vec_psVolteor_i = vec_psVolteor[i]
        line_vec_i, reg_vec_i = polyShape.polyShape2lineVec(vec_psVolteor_i)
        num_lines_i = length(line_vec_i)
        if i == 1
            for j = 1:num_lines_i
                line_ij = line_vec_i[j]
                mat_lines[i,j] = line_ij
            end
        else
            for j = 1:num_lines_i
                line_ij = line_vec_i[j]
                mid_point_ij = polyShape.midPointSegment(line_ij)
                min_dist = 10000
                min_pos = 0
                for l in eachindex(mat_lines[i-1,:])
                    line = mat_lines[i-1,l]
                    mid_point = polyShape.midPointSegment(line)
                    if line.NumLines >= 1
                        dist_ij = polyShape.distanceBetweenLines(line, line_ij)
                        if dist_ij < min_dist && polyShape.isLineLineParallel(line, line_ij) && polyShape.shapeDistance(mid_point, mid_point_ij) <= 5
                            min_dist = dist_ij
                            min_pos = l
                        end
                    end
                end
                if min_pos >= 1
                    mat_lines[i,min_pos] = line_ij
                end
            end 
        end
    end

    # Selecciona sólo las líneas principales 
    mat_lineas_principales = [[mat_lines[1,j]] for j = 1:length(line_vec_1)]
    mat_alturas_principales = [[0.] for j = 1:length(line_vec_1)]
    vec_alturas = []
    for j = 1:length(line_vec_1)
        
        for i = 2:num_alturas-1
            try
                line_ij_ant = mat_lines[i-1,j]
                line_ij = mat_lines[i,j]
                line_ij_post = mat_lines[i+1,j]
                alt_ij = vec_altVolteor[i]

                size_ij_ant = polyShape.lineLength(line_ij_ant)
                size_ij = polyShape.lineLength(line_ij)
                size_ij_post = polyShape.lineLength(line_ij_post)
                cambio_ant = abs(size_ij - size_ij_ant)
                cambio_post = abs(size_ij_post - size_ij)

                dist_ant = polyShape.distanceBetweenLines(line_ij_ant, line_ij)
                dist_post = polyShape.distanceBetweenLines(line_ij, line_ij_post)

                if abs(cambio_ant - cambio_post) > .1 || abs(dist_ant - dist_post) > .1
                    push!(mat_lineas_principales[j], line_ij)
                    push!(mat_alturas_principales[j], alt_ij)
                end
            catch
            end
        end
        push!(mat_lineas_principales[j], mat_lines[end,j])
        push!(mat_alturas_principales[j], vec_altVolteor[end])

        vec_alturas = vcat(vec_alturas, mat_alturas_principales[j])
    end

    vec_alturas = unique(vec_alturas)

    verts = []
    for j in eachindex(mat_lineas_principales)
        
        for i = 2:length(mat_alturas_principales[j])
            try
                x1 = mat_lineas_principales[j][i-1].Vertices[1][2,1]
                y1 = mat_lineas_principales[j][i-1].Vertices[1][2,2]
                z1 = mat_alturas_principales[j][i-1]
                x2 = mat_lineas_principales[j][i-1].Vertices[1][1,1]
                y2 = mat_lineas_principales[j][i-1].Vertices[1][1,2]
                z2 = mat_alturas_principales[j][i-1]

                x3 = mat_lineas_principales[j][i].Vertices[1][1,1]
                y3 = mat_lineas_principales[j][i].Vertices[1][1,2]
                z3 = mat_alturas_principales[j][i]
                x4 = mat_lineas_principales[j][i].Vertices[1][2,1]
                y4 = mat_lineas_principales[j][i].Vertices[1][2,2]
                z4 = mat_alturas_principales[j][i]

                vert = [[x1, y1, z1],
                        [x2, y2, z2],
                        [x3, y3, z3],
                        [x4, y4, z4]]

                push!(verts, vert)
            catch
            end
        end
    end

    return verts, vec_alturas

end