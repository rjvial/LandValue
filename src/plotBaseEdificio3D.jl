function plotBaseEdificio3D(
    fpe, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor,
    vec_psVolConSombra, vec_altVolConSombra, ps_publico, ps_calles,
    ps_base1, ps_base2, np1, np2
)
    # Unpack flags from input
    f_predio = fpe.predio
    f_volTeorico = fpe.volTeorico
    f_volConSombra = fpe.volConSombra
    f_edif = fpe.edif

    f_sombraVolTeorico_p = fpe.sombraVolTeorico_p
    f_sombraVolTeorico_o = fpe.sombraVolTeorico_o
    f_sombraVolTeorico_s = fpe.sombraVolTeorico_s

    # Initialize plot handles
    fig = nothing
    ax = nothing
    ax_mat = nothing

    # Plot predio base
    if f_predio
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predio, 0.0, "green", 0.3)
    end

    # Plot optimal building (cabida óptima)
    if f_edif
        alt1 = np1 * alturaPiso
        alt2 = (np1 + np2) * alturaPiso

        # First volume base (np1 floors)
        for k = 1:np1
            V_base = ps_base1.Vertices[1]
            z_low = alturaPiso * (k - 1)
            z_high = alturaPiso * k
            numVerts = size(V_base, 1)

            V_k = [V_base z_low * ones(numVerts, 1); V_base z_high * ones(numVerts, 1)]
            fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(PolyShape([V_k], 1), z_low, "teal", 1.0, fig=fig, ax=ax, ax_mat=ax_mat)
            fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_base1, z_high, "teal", 1.0, fig=fig, ax=ax, ax_mat=ax_mat)
        end

        # Second volume base (np2 floors)
        if np2 >= 1
            for k = np1+1 : np1+np2
                V_base = ps_base2.Vertices[1]
                z_low = alturaPiso * (k - 1)
                z_high = alturaPiso * k
                numVerts = size(V_base, 1)

                V_k = [V_base z_low * ones(numVerts, 1); V_base z_high * ones(numVerts, 1)]
                fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(PolyShape([V_k], 1), z_low, "teal", 1.0, fig=fig, ax=ax, ax_mat=ax_mat)
                fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_base2, z_high, "teal", 1.0, fig=fig, ax=ax, ax_mat=ax_mat)
            end
        end
    end

    # Shadow of theoretical volume
    if f_sombraVolTeorico_p + f_sombraVolTeorico_o + f_sombraVolTeorico_s >= 1
        ps_p, ps_o, ps_s = generaSombraTeor(vec_psVolteor, vec_altVolteor, ps_publico, ps_calles)

        if f_sombraVolTeorico_p
            fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_p, 0, "gold", 0.3, fig=fig, ax=ax, ax_mat=ax_mat)
        end
        if f_sombraVolTeorico_o
            fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_o, 0, "gold", 0.3, fig=fig, ax=ax, ax_mat=ax_mat)
        end
        if f_sombraVolTeorico_s
            fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_s, 0, "gold", 0.3, fig=fig, ax=ax, ax_mat=ax_mat)
        end
    end

    # Shadow of actual building
    ps1_p, ps1_o, ps1_s = generaSombraEdificio(ps_base1, alt1, ps_publico, ps_calles)

    if np2 >= 1
        ps2_p, ps2_o, ps2_s = generaSombraEdificio(ps_base2, alt2, ps_publico, ps_calles)
        ps_sombraEdif_p = polyShape.polyUnion(ps1_p, ps2_p)
        ps_sombraEdif_o = polyShape.polyUnion(ps1_o, ps2_o)
        ps_sombraEdif_s = polyShape.polyUnion(ps1_s, ps2_s)
    else
        ps_sombraEdif_p = deepcopy(ps1_p)
        ps_sombraEdif_o = deepcopy(ps1_o)
        ps_sombraEdif_s = deepcopy(ps1_s)
    end

    for sombra in [(ps_sombraEdif_p, "red"), (ps_sombraEdif_o, "red"), (ps_sombraEdif_s, "red")]
        fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(sombra[1], 0, sombra[2], 0.25, fig=fig, ax=ax, ax_mat=ax_mat)
    end

    # Plot theoretical and actual volumes
    if f_volTeorico
        fig, ax, ax_mat = polyShape.plotPolyshape2DVecin3D(vec_psVolteor, vec_altVolteor, "red", 0.001,
                                                           fig=fig, ax=ax, ax_mat=ax_mat,
                                                           edge_color="red", line_width=0.05)
        fig, ax, ax_mat = polyShape.plotPolyshape2DVecin3D(vec_psVolConSombra, vec_altVolConSombra, "gray", 0.01,
                                                           fig=fig, ax=ax, ax_mat=ax_mat,
                                                           edge_color="gray", line_width=0.1)
    end

    return fig, ax, ax_mat
end
