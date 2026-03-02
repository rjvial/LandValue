module polyShape

using LandValue, ArchGDAL, LazySets, DataFrames, LinearAlgebra, Proj, Combinatorics, JSON

include("polyShape_core.jl")
include("polyShape_serializer.jl")

export isPolyConvex,
    polyArea, polyDifference, polyOrientation, polyUnion, polyIntersection, polyIntersects, polyOffset, polyLargestRect,
    polyEliminaColineales, subShape, shapeVertex, numVertices,
    polyBox, polyRotate, polyReverse, setPolyOrientation, polyCopy, intersectLines,
    lineAngle, halfspaceSignOfPointToLine, lineVec2polyShape, ajustaCoordenadas, polyBoxFromEdge,
    createLine, convHull, midPointSegment, lineLength, isLineLineParallel, partialPolyOffset,
    line2Box, lines2Polygons, poly2Constraints, constraints2poly, rotate_to_first_ccw,
    calculateDistance, shape2vector, transformLine, polySimplify,
    ajustaCoordenadasInversa, shape_32719to4326, shape_4326to32719, polyshape2wkt, dividePoly,
    polyHasnan, sampleEdgePoints, polyShapeLayers2json, threejs2json,
    polyShape2json, building2json, subterraneo2json,
    planta2svg
end
