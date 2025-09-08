module LandValue

using JuMP, Cbc, Ipopt, ArchGDAL, DotEnv, LinearAlgebra, Optim, OrderedCollections
            # NonconvexBayesian, NonconvexIpopt, NonconvexNLopt, Distributions    
    

    mutable struct PolyShape
        Vertices::Array{Array{Float64,2},1}
        NumRegions::Int64
    end

    mutable struct LineShape 
        Vertices::Array{Array{Float64,2},1}
        NumLines::Int64
    end

    mutable struct PointShape
        Vertices::Array{Float64,2}
        NumPoints::Int64
    end

    function Base.:+(p1::PointShape, p2::PointShape)::PointShape
        V1 = deepcopy(p1.Vertices)
        numPoints_1 = p1.NumPoints
        V2 = deepcopy(p2.Vertices)
        V = deepcopy(V1)
        for i = 1:numPoints_1
            V[i,:] = V1[i,:] + V2[1,:]
        end
        p = PointShape(V, numPoints_1)
        return p
    end
    function Base.:+(l1::LineShape, p2::PointShape)::LineShape
        V1 = deepcopy(l1.Vertices)
        numLines_1 = l1.NumLines
        V2 = deepcopy(p2.Vertices)
        V = deepcopy(V1)
        for i = 1:numLines_1
            V[i][1,:] = V[i][1,:] + V2[1,:]
            V[i][2,:] = V[i][2,:] + V2[1,:]
        end
        l = LineShape(V, numLines_1)
        return l
    end
    function Base.:-(l1::LineShape, p2::PointShape)::LineShape
        V1 = deepcopy(l1.Vertices)
        numLines_1 = l1.NumLines
        V2 = deepcopy(p2.Vertices)
        V = deepcopy(V1)
        for i = 1:numLines_1
            V[i][1,:] = V[i][1,:] - V2[1,:]
            V[i][2,:] = V[i][2,:] - V2[1,:]
        end
        l = LineShape(V, numLines_1)
        return l
    end
    function Base.:-(p1::PointShape, p2::PointShape)::PointShape
        V1 = deepcopy(p1.Vertices)
        numPoints_1 = p1.NumPoints
        V2 = deepcopy(p2.Vertices)
        V = deepcopy(V1)
        for i = 1:numPoints_1
            V[i,:] = V[i,:] - V2[1,:]
        end
        p = PointShape(V, numPoints_1)
        return p
    end

    function Base.:*(l::LineShape, f::Union{Int64,Float64})::LineShape
        numLines = l.NumLines
        V = deepcopy(l.Vertices)
        for i = 1:numLines
            dvec = [V[i][2,:] - V[i][1,:]] * f
            V[i][2,:] = V[i][1,:] + dvec[1]
        end
        l = LineShape(V, numLines)
        return l
    end
    function Base.:*(p::PointShape, f::Union{Int64,Float64})::PointShape
        numPoints = p.NumPoints
        V = deepcopy(p.Vertices)
        for i = 1:numPoints
            V[i,:] = V[i,:] * f
        end
        p = PointShape(V, numPoints)
        return p
    end


    GeomObject = Union{PolyShape,LineShape,PointShape}

    PosDimGeom = Union{PolyShape,LineShape}

    mutable struct FlagPlotEdif3D
        predio::Bool
        volTeorico::Bool
        volConSombra::Bool
        edif::Bool
        sombraVolTeorico_p::Bool
        sombraVolTeorico_o::Bool
        sombraVolTeorico_s::Bool
        sombraEdif_p::Bool
        sombraEdif_o::Bool
        sombraEdif_s::Bool
        FlagPlotEdif3D() = new()
    end


    mutable struct DatosCabidaPredio
        x::Array{Float64,1}
        y::Array{Float64,1}
        ladosConCalle::Array{Int64,1}
        anchoEspacioPublico::Array{Float64,1}
        fusionTerrenos::Int64
        distanciaMetro::Int64
    end

    mutable struct DatosCabidaArquitectura
        alturaPiso::Float64
        porcSupComun::Float64
        porcTerraza::Float64
        anchoMin::Float64
        anchoMax::Float64
        DatosCabidaArquitectura() = new()
    end

    mutable struct DatosCabidaComercial
        tipoUnidad::Array{String,1}
        supDeptoUtil::Array{Float64,1}
        supInterior::Array{Float64,1}
        supTerraza::Array{Float64,1}
        estacionamientosPorViv#::Array{Float64,1}
        bodegasPorViv#::Array{Float64,1}
        Precio_Estimado::Array{Float64,1}
        DatosCabidaComercial() = new()
    end

    mutable struct DatosCabidaUnit
        duracionProyecto::Float64
        costoTerreno::Float64
        comisionCorredor::Float64
        demolicion::Float64
        otrosTerreno::Float64
        losaSNT::Float64
        losaBNT::Float64
        ito::Float64 # por mes
        ivaConstruccion::Float64
        creditoIvaConstruccion::Float64
        arquitectura::Float64
        calculo::Float64
        mecanicaSuelo::Float64
        topografia::Float64
        proyectosEspecialidades::Float64
        empalmes::Float64
        aportesUrbanos::Float64
        mitigacionesViales::Float64
        derechosPermisosMunicipales::Float64
        marketing::Float64
        habilitacionSalaVentaComunes::Float64
        gestionAdministracion
        contabilidad::Float64 # por mes
        legales::Float64
        seguros::Float64
        postVentaInmobiliaria::Float64
        seguroVentaEnVerde::Float64   
        variosVentas::Float64
        costoFinanciero::Float64
        imprevistos::Float64
        DatosCabidaUnit() = new()
    end


    # Rentabilidad exigida
    mutable struct DatosCabidaRentabilidad
        retornoExigido::Float64
    end

    
    export DatosCabidaPredio, DatosCabidaNormativa, DatosCabidaArquitectura, DatosCabidaComercial, DatosCabidaUnit,
            DatosCabidaRentabilidad, SalidaArquitectonica, SalidaIndicadores, SalidaMonetaria,
            SalidaTerreno, GeomObject, PosDimGeom, PolyShape, LineShape, PointShape, 
            FlagPlotEdif3D, ResultadoCabida


    include("obtiene_requerimientos_normativos.jl")
    include("generaSombraEdificio.jl")
    include("opti_edificio_deptos.jl")
    include("plotBaseEdificio3D.jl")
    include("polyShape.jl")
    include("polyPlot.jl")
    include("polyGdal.jl")
    include("polyClipper.jl")
    include("graphMod.jl")
    include("resultConverter.jl")
    include("generaSombraTeor.jl")
    include("pg_julia.jl")
    include("obtieneCalles.jl")
    include("generaPoligonoCorte.jl")
    include("create_scr.jl")
    include("create_edificio_geojson.jl")
    include("optimal_pricing.jl")
    include("optimal_lot_selection.jl")
    include("aws_julia.jl")
    include("neo4j_julia.jl")
    include("quad_opti_vol.jl")
    include("quad_opti_sol_ini.jl")
    include("opti_edificio_vol.jl")
    include("opti_edificio.jl")
    include("opti_vol_estacionamiento.jl")
    include("expression_converter.jl")
    include("obtiene_geometrias_combi.jl")

    export obtiene_requerimientos_normativos, generaSombraEdificio, opti_edificio_deptos, 
        polyShape, polyPlot, polyGdal, polyClipper, graphMod, resultConverter, plotBaseEdificio3D, generaSombraTeor, 
        pg_julia, aws_julia, neo4j_julia, obtieneCalles, generaPoligonoCorte, create_scr, create_edificio_geojson,
        optimal_pricing, optimal_lot_selection, quad_opti_vol, quad_opti_sol_ini, opti_edificio_vol, 
        opti_edificio, opti_vol_estacionamiento, expression_converter, obtiene_geometrias_combi

end
