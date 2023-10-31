function create_scr(xopt, ps_predio, ps_base, alturaPiso, ps_volTeorico, matConexionVertices_volTeorico, vecVertices_volTeorico, file_str)

    numPisos = Int(xopt[1])
    V_base = ps_base.Vertices[1]
    numVerticesBase = size(V_base,1)
    V_predio = ps_predio.Vertices[1]
    numVerticesPredio = size(V_predio,1)

    V_volteor = ps_volTeorico.Vertices[1]
    conjuntoAlturas = unique(V_volteor[:, 3])
    numAlturas = length(conjuntoAlturas)

    function generaPatchs(numAlturas, V_volteor, vecVertices, matConexionVertices)
        verts = []
        for k = 1:numAlturas-1
            for j = 1:length(vecVertices[k])
                if j == length(vecVertices[k])
                    jl0 = Int.(vecVertices[k][j])
                    jl1 = Int.(vecVertices[k][1])
                else
                    jl0 = Int.(vecVertices[k][j])
                    jl1 = Int.(vecVertices[k][j+1])
                end
                x1 = V_volteor[jl0, 1]
                y1 = V_volteor[jl0, 2]
                z1 = V_volteor[jl0, 3]
                x2 = V_volteor[jl1, 1]
                y2 = V_volteor[jl1, 2]
                z2 = V_volteor[jl1, 3]
                ju0 = Int.(matConexionVertices[matConexionVertices[:, 1].==jl0, 2])[1]
                ju1 = Int.(matConexionVertices[matConexionVertices[:, 1].==jl1, 2])[1]

                x3 = V_volteor[ju1, 1]
                y3 = V_volteor[ju1, 2]
                z3 = V_volteor[ju1, 3]
                x4 = V_volteor[ju0, 1]
                y4 = V_volteor[ju0, 2]
                z4 = V_volteor[ju0, 3]

                vert = [[x1, y1, z1],
                    [x2, y2, z2],
                    [x3, y3, z3],
                    [x4, y4, z4]]

                push!(verts, vert)

            end
        end
        return verts
    end

    verts = generaPatchs(numAlturas, V_volteor, vecVertices_volTeorico, matConexionVertices_volTeorico)
    numVerts = length(verts)

    open(file_str, "w") do f
        write(f, "_COLOR\nGREEN\n3dpoly\n")
        for i in 1:numVerticesBase
            line_base_i = string(V_base[i,1]) * "," * string(V_base[i,2]) * "," * string(0.0) * "\n"
            write(f, line_base_i)
        end
        line_base_1 = string(V_base[1,1]) * "," * string(V_base[1,2]) * "," * string(0.0) * "\n"
        write(f, line_base_1)
        write(f, "\n_extrude \n\nall\n\n" * string(alturaPiso) * "\n_copym\nall\n\n")
        for np in 1:numPisos
            line_base_i = string(0.0) * "," * string(0.0) * "," * string(np*alturaPiso) * "\n"
            write(f, line_base_i)
        end
        write(f, "\n_COLOR\nRED\n3dpoly\n")
        for i in 1:numVerticesPredio
            line_predio_i = string(V_predio[i,1]) * "," * string(V_predio[i,2]) * "," * string(0.0) * "\n"
            write(f, line_predio_i)
        end
        line_predio_1 = string(V_predio[1,1]) * "," * string(V_predio[1,2]) * "," * string(0.0) * "\n"
        write(f, line_predio_1)
        write(f, "\n_COLOR\nBLUE\n")
        
        for nv in 1:numVerts
            write(f, "_3DFACE\n")
            for j in 1:4
                line_verts_nvj = string(verts[nv][j][1]) * "," * string(verts[nv][j][2]) * "," * string(verts[nv][j][3]) * "\n"
                write(f, line_verts_nvj)
            end
            write(f, "\n")
        end
        write(f, "_zoom a\n")
    end

end