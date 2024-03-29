function generaPoligonoCorte(alt, vec_psVolteor, vec_altVolteor)::PolyShape

    idAlt = findfirst(y -> y >= alt, vec_altVolteor) - 1
    vert_0 = vec_psVolteor[idAlt].Vertices[:]
    vert_1 = vec_psVolteor[idAlt+1].Vertices[:]
    alfa_ = (vec_altVolteor[idAlt + 1] - alt) / (vec_altVolteor[idAlt + 1] - vec_altVolteor[idAlt])
    if length(vert_0) == length(vert_1)
        polyCorte_alt = [alfa_ .* vert_0 .+ (1 - alfa_) .* vert_1][1]
    else
        polyCorte_alt = vert_0
    end
    psCorte = PolyShape(polyCorte_alt, length(polyCorte_alt))

    return psCorte
end