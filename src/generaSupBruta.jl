function generaSupBruta(ps_predio, conjuntoLadosCalle, anchoEspacioPublico)

    ps_bruto = polyShape.polyExpandSegmentVec(ps_predio, anchoEspacioPublico/2, collect(conjuntoLadosCalle))
    ps_publico = polyShape.polyExpandSegmentVec(ps_predio, anchoEspacioPublico, collect(conjuntoLadosCalle))
    return ps_bruto, ps_publico
end

