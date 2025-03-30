# Use an official Python image as a base
FROM python:3.10-slim

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /usr/share/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy the Python script into the container
COPY src/script.py /app/git_update_script.py

# Make sure the script is executable
RUN chmod +x /app/git_update_script.py

# Fix Git ownership issue
RUN git config --global --add safe.directory /github/workspace

# Define entrypoint
ENTRYPOINT ["python3", "/app/git_update_script.py"]
