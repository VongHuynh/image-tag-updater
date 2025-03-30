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
COPY src/image-tag-updater.py /app/image-tag-updater.py

# Make sure the script is executable
RUN chmod +x /app/image-tag-updater.py

# Define entrypoint
ENTRYPOINT ["python3", "/app/image-tag-updater.py"]
