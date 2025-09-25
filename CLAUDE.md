# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.


## LandValue System Overview
LandValue is a Julia platform for real estate optimization combining geometric processing, mathematical optimization, and multi-database integration.

## Development Rules
- VERY IMPORTANT: **Before modifying any code, generate a plan** for user approval
- VERY IMPORTANT: **Code modifications must be as simple as possible**
- VERY IMPORTANT: **Change as little code as possible** - prefer minimal, targeted edits
- VERY IMPORTANT: **Reuse existing functions extensively** - leverage the predefined function library rather than creating new implementations
- Use exact `module.function()` syntax (e.g., `polyShape.polyArea()`)
- Never use inline comments in code
- Always use the defined data structures: `PolyShape`, `LineShape`, `PointShape`
- Avoid direct library calls - use module wrappers instead
- All optimization uses JuMP framework with CBC or Ipopt solvers



## Module and Architecture Overview

### Core Data Structures
- **PolyShape**: Multi-region polygons with vertices arrays
- **LineShape**: Multi-line geometries
- **PointShape**: Point collections
- **GeomObject**: Union type for all shape types
- **PosDimGeom**: Union type for polygons and lines

### Module Hierarchy
1. **polyShape** - Core geometric operations: `polyBox`, `polyArea`, `polyUnion`, `polyDifference`, `polyIntersection`
2. **polyGdal** - GDAL integration: coordinate transformations, spatial operations
3. **polyClipper** - Polygon offsetting and clipping operations
4. **polyPlot** - 3D visualization and plotting
5. **pg_julia** - PostgreSQL database connectivity
6. **aws_julia** - AWS services integration
7. **neo4j_julia** - Neo4j graph database operations

### Main Processing Scripts
- **script_2A_optim_volumetrica_indiv.jl**: Individual volumetric optimization
- **script_2A_optim_volumetrica_paralela.jl**: Parallel volumetric optimization

### Database Integration
The system connects to multiple databases using dedicated modules:
- **PostgreSQL**: Use `pg_julia` module 
- **Neo4j**: Use `neo4j_julia` module 
- **AWS S3**: Use `aws_julia` module

### Database Setup
Scripts expect environment variables loaded from `secrets.env` file:
- AWS credentials: `AWS_ACCESS_KEY`, `AWS_SECRET_KEY`, `AWS_REGION`
- PostgreSQL: `PG_AWS_USER`, `PG_AWS_PASSWORD`

### Core Geometry (`polyShape.jl`, `polyGdal.jl`, `polyClipper.jl`)
- **polyShape**: Core operations (`polyArea`, `polyUnion`, `polyDifference`, `polyIntersection`)
- **polyGdal**: GDAL integration (`gdal2shape`, `astext2shape`, `shapeBuffer`, `shapeIntersect`)
- **polyClipper**: High-precision operations (`polyOffset`, boolean operations)

### Visualization 
- **polyPlot.jl**: 2D/3D plotting with multi-layer building visualization

### Core Dependencies
- **Math/Optimization**: JuMP, CBC, Ipopt, LinearAlgebra
- **Geometry**: ArchGDAL, Clipper, LazySets
- **Data**: LibPQ, AWS/AWSS3, CSV/XLSX
- **Visualization**: PyPlot, Plots.jl

