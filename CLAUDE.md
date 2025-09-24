# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# LandValue

A Julia package for land development optimization and real estate analysis focused on building capacity optimization, geometric analysis, and financial modeling.

## Key Commands

### Development Environment
```bash
# Start Julia in project directory
julia --project=.

# Activate package environment (in Julia REPL)
using Pkg; Pkg.activate(".")

# Install dependencies
Pkg.instantiate()

# Run main optimization script
julia --project=. src/script_2A_optim_volumetrica_indiv.jl
```

### Database Setup
Scripts expect environment variables loaded from `secrets.env` file:
- AWS credentials: `AWS_ACCESS_KEY`, `AWS_SECRET_KEY`, `AWS_REGION`
- PostgreSQL: `PG_AWS_USER`, `PG_AWS_PASSWORD`

## Architecture Overview

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

## Development Rules
- Use exact `module.function()` syntax (e.g., `polyShape.polyArea()`)
- Never use inline comments in code
- Always use the defined data structures: `PolyShape`, `LineShape`, `PointShape`
- Avoid direct library calls - use module wrappers instead
- All optimization uses JuMP framework with CBC or Ipopt solvers
- **Before modifying any code, generate a plan** for user approval
- **Code modifications must be as simple as possible**
- **Change as little code as possible** - prefer minimal, targeted edits
- **Reuse existing functions extensively** - leverage the predefined function library rather than creating new implementations

## Database Integration
The system connects to multiple databases using dedicated modules:
- **PostgreSQL**: Use `pg_julia` module 
- **Neo4j**: Use `neo4j_julia` module 
- **AWS S3**: Use `aws_julia` module

## Codebase Analysis

### System Overview
LandValue is a 36-file Julia platform for real estate optimization combining geometric processing, mathematical optimization, and multi-database integration.

### Key Modules

#### Core Geometry (`polyShape.jl`, `polyGdal.jl`, `polyClipper.jl`)
- **polyShape**: Core operations (`polyArea`, `polyUnion`, `polyDifference`, `polyIntersection`)
- **polyGdal**: GDAL integration (`gdal2shape`, `astext2shape`, `shapeBuffer`, `shapeIntersect`)
- **polyClipper**: High-precision operations (`polyOffset`, boolean operations)

#### Optimization Framework
- **opti_edificio_deptos.jl**: Apartment optimization (JuMP/CBC mixed-integer programming)
- **opti_edificio.jl**: General building optimization
- **optimal_lot_selection.jl**: Multi-lot selection
- Uses MILP with CBC solver, nonlinear with Ipopt, big-M constraints

#### Data Processing
- **obtieneCalles.jl**: Street geometry processing, width calculation, public space generation
- **obtiene_geometrias_combi.jl**: Unified property/street data processing with coordinate standardization
- **generaSombraEdificio.jl** / **generaSombraTeor.jl**: Shadow analysis for regulatory compliance

#### Visualization & Database
- **polyPlot.jl**: 2D/3D plotting with multi-layer building visualization
- **pg_julia.jl**: PostgreSQL integration for spatial data
- **neo4j_julia.jl**: Graph database connectivity
- **aws_julia.jl**: AWS services (S3, EC2 management)

### Processing Workflow
1. Multi-database connection setup (PostgreSQL, Neo4j, AWS)
2. Geometric data extraction and coordinate transformation
3. Regulatory constraint loading (zoning, setbacks, heights)
4. JuMP-based optimization execution
5. Results processing and database persistence

### Technical Patterns
- Empty collection detection in geometric operations
- Integer scaling for Clipper precision
- Error handling with alternative solver fallbacks
- DFL2 housing subsidy calculations
- Batch processing with connection pooling

### Core Dependencies
- **Math/Optimization**: JuMP, CBC, Ipopt, LinearAlgebra
- **Geometry**: ArchGDAL, Clipper, LazySets
- **Data**: LibPQ, AWS/AWSS3, CSV/XLSX
- **Visualization**: PyPlot, Plots.jl

