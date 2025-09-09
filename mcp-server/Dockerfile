# Production Dockerfile for Graphiti MCP Server
FROM python:3.11-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast Python package management
RUN pip install uv

# Create app user and directory
RUN useradd --create-home --shell /bin/bash app
WORKDIR /app
RUN chown app:app /app

# Switch to app user
USER app

# Copy dependency files
COPY --chown=app:app pyproject.toml ./

# Install Python dependencies
RUN uv venv && \
    . .venv/bin/activate && \
    uv pip install -e .

# Copy application code
COPY --chown=app:app *.py ./

# Create logs directory
RUN mkdir -p /app/logs

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Set PATH to include uv virtual environment
ENV PATH="/app/.venv/bin:$PATH"

# Default command
CMD ["uv", "run", "graphiti_mcp_server.py", "--transport", "sse", "--host", "0.0.0.0", "--port", "8000"]