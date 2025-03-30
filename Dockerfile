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
COPY src/image-tag-updater.py /app/image-tag-updater.py
RUN chmod +x /app/image-tag-updater.py

ENTRYPOINT ["python3", "/app/image-tag-updater.py"]
