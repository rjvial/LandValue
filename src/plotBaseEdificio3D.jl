function plotBaseEdificio3D(
        fpe,
        alturaPiso,
        ps_predio,
        vec_psVolteor, vec_altVolteor,
        vec_psVolConSombra, vec_altVolConSombra,
        ps_publico, ps_calles,
        vec_ps_opt, vec_np_opt,
        vec_ps_subte, vec_np_subte, tipo_edificio
    )

    # Flags
    f_predio = fpe.predio
    f_volTeorico = fpe.volTeorico
    f_volConSombra = fpe.volConSombra
    f_edif = fpe.edif
    f_st_p = fpe.sombraVolTeorico_p
    f_st_o = fpe.sombraVolTeorico_o
    f_st_s = fpe.sombraVolTeorico_s

    # init plot
    fig = nothing; ax = nothing; ax_mat = nothing

    # plot predio
    if f_predio
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predio, 0.0, "green", 0.3,
            fig=fig, ax=ax, ax_mat=ax_mat)
    end

    # plot each building block
    if f_edif
        cum_floors = 0
        K_edif = length(vec_ps_opt)
        for i in 1:K_edif
            base = vec_ps_opt[i]
            n_f = vec_np_opt[i]
            for k in 1:n_f
                z_low = alturaPiso * (cum_floors + k - 1)
                z_high= alturaPiso * (cum_floors + k)
                V = base.Vertices[1]
                nV = size(V,1)
                # side faces
                if tipo_edificio == "departamento"
                    color = "teal"
                elseif tipo_edificio == "oficina"
                    color = "darkgray"
                end

                V_k = [V z_low*ones(nV,1); V z_high*ones(nV,1)]
                fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(
                    PolyShape([V_k],1), z_low, color, 1.0,
                    fig=fig, ax=ax, ax_mat=ax_mat)
                # top face
                fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(
                    base, z_high, color, 1.0,
                    fig=fig, ax=ax, ax_mat=ax_mat)
            end
            cum_floors += n_f
        end


        cum_floors = 0
        K_subte = length(vec_np_subte)
        for i in 1:K_subte
            base = vec_ps_subte[i]
            n_f = vec_np_subte[i]
            for k in 1:abs(n_f)
                z_low = -alturaPiso * (cum_floors + k)
                z_high= -alturaPiso * (cum_floors + k - 1)
                V = base.Vertices[1]
                nV = size(V,1)
                # side faces
                V_k = [V z_low*ones(nV,1); V z_high*ones(nV,1)]
                fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(
                    PolyShape([V_k],1), z_low, "black", .2,
                    fig=fig, ax=ax, ax_mat=ax_mat)
                # top face
                fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(
                    base, z_high, "black", .2,
                    fig=fig, ax=ax, ax_mat=ax_mat)
            end
            cum_floors += abs(n_f)
        end

    end

    # theoretical shadows
    if f_st_p || f_st_o || f_st_s
        ps_p, ps_o, ps_s = generaSombraTeor(vec_psVolteor, vec_altVolteor,
                                           ps_publico, ps_calles)
        if f_st_p
            fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_p, 0, "gold", 0.3,
                fig=fig, ax=ax, ax_mat=ax_mat)
        end
        if f_st_o
            fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_o, 0, "gold", 0.3,
                fig=fig, ax=ax, ax_mat=ax_mat)
        end
        if f_st_s
            fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_s, 0, "gold", 0.3,
                fig=fig, ax=ax, ax_mat=ax_mat)
        end
    end

    # actual building shadow per block
    ps_p, ps_o, ps_s = generaSombraEdificio(vec_ps_opt, cumsum(vec_np_opt).*alturaPiso, ps_publico, ps_calles)
    vec_sombra = [ps_p, ps_o, ps_s]
    for ps_sombra in vec_sombra 
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(
            ps_sombra, 0, "red", 0.25,
            fig=fig, ax=ax, ax_mat=ax_mat)
    end

    # theoretical and shadowed volume outlines
    if f_volTeorico
        fig, ax, ax_mat = polyShape.plotPolyshape2DVecin3D(
            vec_psVolteor, vec_altVolteor, "red", 0.001,
            fig=fig, ax=ax, ax_mat=ax_mat,
            edge_color="red", line_width=0.05)
        fig, ax, ax_mat = polyShape.plotPolyshape2DVecin3D(
            vec_psVolConSombra, vec_altVolConSombra, "gray", 0.01,
            fig=fig, ax=ax, ax_mat=ax_mat,
            edge_color="gray", line_width=0.1)
    end

    return fig, ax, ax_mat
end