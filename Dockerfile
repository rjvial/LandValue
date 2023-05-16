# Use the official Julia Docker image as the base
FROM julia:latest

# Set the working directory for the Julia code
# WORKDIR /app

# Install the Julia packages
RUN julia -e 'using Pkg;' 
# \
#              Pkg.add(url="https://github.com/PainterQubits/Devices.jl.git"); \
#              Pkg.add(url="https://github.com/rjvial/LandValue.git")'

# Copy the rest of your code into the container
COPY /src/ /app/src/
COPY script.jl /script.jl


# List the copied files in the container
RUN ls -la /app

# Set the entry point for the container
CMD ["julia", "/script.jl"]


# Use the official Julia Docker image as the base
#cd C:\Users\rjvia\Documents\Land_engines_code\Julia\LandValue
#docker build -t myimagename .
#docker run myimagename

