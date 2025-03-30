# Use a lightweight base image
FROM alpine:3.21

# Install necessary packages
RUN apk add --no-cache \
    git \
    bash \
    gawk \
    sed \
    github-cli \
    python3 

# Set working directory
WORKDIR /app

# Copy the Python script into the container
COPY src/script.py /app/git_update_script.py

# Make sure the script is executable
RUN chmod +x /app/git_update_script.py

# Define entrypoint
ENTRYPOINT ["python3", "/app/git_update_script.py"]
