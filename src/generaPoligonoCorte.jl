function generaPoligonoCorte(alt, V, vecAlturas, vecVertices, matConexionVertices)::PolyShape

    idAlt = findfirst(y -> y >= alt, vecAlturas) - 1
    vert_0 = Int.(vecVertices[idAlt])
    vert_1 = Int.(matConexionVertices[vert_0,2])
    V_0 = copy(V[vert_0, 1:2])[:,1,:]
    V_1 = copy(V[vert_1, 1:2])[:,1,:]
    alfa_ = (vecAlturas[idAlt + 1] - alt) / (vecAlturas[idAlt + 1] - vecAlturas[idAlt])
    polyCorte_alt = alfa_ .* V_0 .+ (1 - alfa_) .* V_1
    psCorte = PolyShape([polyCorte_alt], 1)

    return psCorte
end