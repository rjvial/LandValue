function plotBaseEdificio3D(fpe, x::Array{Float64,1}, alturaPiso::Float64, ps_predio::PolyShape,
                             ps_volTeorico::PolyShape, matConexionVertices::Array{Float64,2}, vecVertices::Array{Any,1}, 
                            ps_volConSombra::PolyShape, matConexionVertices_restSombra::Array{Float64,2}, vecVertices_restSombra::Array{Any,1}, 
                            ps_publico::PolyShape, ps_calles::PolyShape, ps_base::PolyShape, ps_baseSeparada::PolyShape; flagV = false)

    f_predio = fpe.predio
    f_volTeorico = fpe.volTeorico
    f_volConSombra = fpe.volConSombra
    f_edif = fpe.edif

    f_sombraVolTeorico_p = fpe.sombraVolTeorico_p
    f_sombraVolTeorico_o = fpe.sombraVolTeorico_o
    f_sombraVolTeorico_s = fpe.sombraVolTeorico_s
    
    f_sombraEdif_p = fpe.sombraEdif_p
    f_sombraEdif_o = fpe.sombraEdif_o
    f_sombraEdif_s = fpe.sombraEdif_s

    alt = x[1]*alturaPiso

    fig=nothing
    ax=nothing
    ax_mat=nothing
    
    if f_predio
        # Grafica Predio
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predio, 0.0, "green", .3)
    end

    if f_volTeorico
        # Grafica Volumen Teórico
        fig, ax, ax_mat = polyShape.plotPolyshape3D(ps_volTeorico, matConexionVertices, vecVertices, fig=fig, ax=ax, ax_mat=ax_mat)
    end

    if f_volConSombra
        # Grafica Volumen Teórico
        fig, ax, ax_mat = polyShape.plotPolyshape3D(ps_volConSombra, matConexionVertices_restSombra, vecVertices_restSombra, "gray", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
    end

    #ps_calles = polyShape.polyUnion_v2(ps_calles, ps_calles)
    #fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_calles, 0, "grey", 0.25, fig=fig, ax=ax, ax_mat=ax_mat)

    if f_edif
        # Grafica cabida óptima
        numPisos = Int(round(alt/alturaPiso))
        numVertices = size(ps_base.Vertices[1],1)
        V_edif3D = zeros((numPisos+1)*numVertices,3)    
        V_edif3D = zeros((numPisos+1)*numVertices, 3)
        V_edif3D[1:numVertices,:] = [ps_base.Vertices[1] zeros(numVertices,1)]
        for k = 1:numPisos
            for j=1:ps_base.NumRegions
                V_base_j = ps_base.Vertices[j]
                numVerticesBase_j = size(V_base_j,1)
                V_kj = [V_base_j alturaPiso * (k - 1) * ones(numVerticesBase_j,1);
                        V_base_j alturaPiso * k * ones(numVerticesBase_j,1)]
                fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(PolyShape([V_kj],1), alturaPiso * (k - 1), "teal", 1.0, fig=fig, ax=ax, ax_mat=ax_mat)
            end
            V_edif3D[k*numVertices+1:(k+1)*numVertices,:] = [ps_base.Vertices[1] alturaPiso*k*ones(numVertices,1)]
            fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_base, alturaPiso * k, "teal", 1.0, fig=fig, ax=ax, ax_mat=ax_mat)
        end
    end

    
    ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s = generaSombraTeor(ps_volTeorico, matConexionVertices, vecVertices, ps_publico, ps_calles)
    if f_sombraVolTeorico_p
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_sombraVolTeorico_p, 0, "gold", 0.3, fig=fig, ax=ax, ax_mat=ax_mat)
    end
    if f_sombraVolTeorico_o
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_sombraVolTeorico_o, 0, "gold", 0.3, fig=fig, ax=ax, ax_mat=ax_mat)
    end
    if f_sombraVolTeorico_s
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_sombraVolTeorico_s, 0, "gold", 0.3, fig=fig, ax=ax, ax_mat=ax_mat)
    end

    

    ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s = generaSombraEdificio(ps_baseSeparada, alt, ps_publico, ps_calles)
    if f_sombraEdif_p
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_sombraEdif_p, 0, "red", 0.25, fig=fig, ax=ax, ax_mat=ax_mat)
    end
    if f_sombraEdif_o
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_sombraEdif_o, 0, "red", 0.25, fig=fig, ax=ax, ax_mat=ax_mat)
    end
    if f_sombraEdif_s
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_sombraEdif_s, 0, "red", 0.25, fig=fig, ax=ax, ax_mat=ax_mat)
    end
    
    if flagV == false
        return fig, ax, ax_mat
    else
        return fig, ax, ax_mat, V_edif3D
    end
end