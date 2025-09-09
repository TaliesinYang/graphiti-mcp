#!/bin/bash
# Graphiti MCP Standalone Setup Script
# One-click installation and configuration

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="Graphiti MCP Standalone"
MIN_DOCKER_VERSION="20.10.0"
MIN_COMPOSE_VERSION="2.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Unicode symbols
CHECK_MARK="✓"
CROSS_MARK="✗"
WARNING="⚠"
INFO="ℹ"
ROCKET="🚀"
GEAR="⚙️"
FOLDER="📁"

# Print colored output
print_header() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}  $PROJECT_NAME Setup${NC}"
    echo -e "${CYAN}================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}${CHECK_MARK} $1${NC}"
}

print_error() {
    echo -e "${RED}${CROSS_MARK} $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}${WARNING} $1${NC}"
}

print_info() {
    echo -e "${BLUE}${INFO} $1${NC}"
}

print_step() {
    echo -e "${CYAN}${GEAR} $1${NC}"
}

# Version comparison function
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check system requirements
check_system_requirements() {
    print_step "Checking system requirements..."
    
    local requirements_met=true
    
    # Check Docker
    if command_exists docker; then
        local docker_version
        docker_version=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        
        if version_gt "$docker_version" "$MIN_DOCKER_VERSION"; then
            print_success "Docker $docker_version (minimum $MIN_DOCKER_VERSION required)"
        else
            print_error "Docker version $docker_version is too old (minimum $MIN_DOCKER_VERSION required)"
            requirements_met=false
        fi
        
        # Check if Docker daemon is running
        if docker info >/dev/null 2>&1; then
            print_success "Docker daemon is running"
        else
            print_error "Docker daemon is not running. Please start Docker and try again."
            requirements_met=false
        fi
    else
        print_error "Docker is not installed. Please install Docker first."
        requirements_met=false
    fi
    
    # Check Docker Compose
    if command_exists docker-compose; then
        local compose_version
        compose_version=$(docker-compose --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        
        if version_gt "$compose_version" "$MIN_COMPOSE_VERSION"; then
            print_success "Docker Compose $compose_version (minimum $MIN_COMPOSE_VERSION required)"
        else
            print_error "Docker Compose version $compose_version is too old (minimum $MIN_COMPOSE_VERSION required)"
            requirements_met=false
        fi
    elif docker compose version >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker compose version | grep -oP '\d+\.\d+\.\d+' | head -1)
        print_success "Docker Compose $compose_version (plugin version)"
    else
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        requirements_met=false
    fi
    
    # Check available disk space (at least 2GB)
    local available_space
    available_space=$(df -BG "$SCRIPT_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
    
    if [ "$available_space" -ge 2 ]; then
        print_success "Available disk space: ${available_space}GB (minimum 2GB required)"
    else
        print_warning "Available disk space: ${available_space}GB (minimum 2GB recommended)"
    fi
    
    # Check available memory
    if command_exists free; then
        local available_memory
        available_memory=$(free -g | awk '/^Mem:/{print $7}')
        
        if [ "$available_memory" -ge 1 ]; then
            print_success "Available memory: ${available_memory}GB (minimum 1GB required)"
        else
            print_warning "Available memory: ${available_memory}GB (minimum 1GB recommended for Neo4j)"
        fi
    fi
    
    if [ "$requirements_met" = false ]; then
        echo ""
        print_error "Some system requirements are not met. Please fix the issues above and try again."
        exit 1
    fi
    
    echo ""
}

# Create environment file
setup_environment() {
    print_step "Setting up environment configuration..."
    
    if [ -f "$SCRIPT_DIR/.env" ]; then
        print_warning ".env file already exists. Backing up to .env.backup"
        cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env.backup"
    fi
    
    if [ ! -f "$SCRIPT_DIR/.env.example" ]; then
        print_error ".env.example file not found. Creating default configuration..."
        create_default_env_example
    fi
    
    # Copy example to .env
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    print_success "Created .env file from template"
    
    # Prompt for essential configuration
    echo ""
    print_info "Please provide the following essential configuration:"
    echo ""
    
    # Neo4j password
    while true; do
        echo -n "Neo4j password (leave empty for 'password123'): "
        read -r neo4j_password
        if [ -z "$neo4j_password" ]; then
            neo4j_password="password123"
        fi
        
        if [ ${#neo4j_password} -ge 8 ]; then
            sed -i "s/NEO4J_PASSWORD=.*/NEO4J_PASSWORD=$neo4j_password/" "$SCRIPT_DIR/.env"
            break
        else
            print_warning "Password must be at least 8 characters long"
        fi
    done
    
    # OpenAI API key
    while true; do
        echo -n "OpenAI API key (required): "
        read -r openai_key
        
        if [ -n "$openai_key" ] && [[ "$openai_key" =~ ^sk- ]]; then
            sed -i "s/OPENAI_API_KEY=.*/OPENAI_API_KEY=$openai_key/" "$SCRIPT_DIR/.env"
            break
        else
            print_warning "Please provide a valid OpenAI API key (starts with 'sk-')"
        fi
    done
    
    # Optional: Group ID
    echo -n "MCP Group ID (leave empty for 'default'): "
    read -r group_id
    if [ -n "$group_id" ]; then
        sed -i "s/MCP_GROUP_ID=.*/MCP_GROUP_ID=$group_id/" "$SCRIPT_DIR/.env"
    fi
    
    print_success "Environment configuration completed"
    echo ""
}

# Create default .env.example if missing
create_default_env_example() {
    cat > "$SCRIPT_DIR/.env.example" << 'EOF'
# Neo4j Configuration
NEO4J_URI=bolt://localhost:7687
NEO4J_HTTP_URL=http://localhost:7474
NEO4J_USER=neo4j
NEO4J_PASSWORD=password123
NEO4J_HTTP_PORT=7474
NEO4J_BOLT_PORT=7687

# Neo4j Memory Settings (adjust based on available RAM)
NEO4J_HEAP_INITIAL=512m
NEO4J_HEAP_MAX=1G
NEO4J_PAGECACHE=512m

# OpenAI Configuration (Required)
OPENAI_API_KEY=sk-your-api-key-here
OPENAI_BASE_URL=
MODEL_NAME=gpt-4o-mini
SMALL_MODEL_NAME=gpt-4o-mini
LLM_TEMPERATURE=0.1

# Azure OpenAI (Optional - if using Azure instead of OpenAI)
AZURE_OPENAI_ENDPOINT=
AZURE_OPENAI_DEPLOYMENT_NAME=
AZURE_OPENAI_API_VERSION=
AZURE_OPENAI_EMBEDDING_API_KEY=
AZURE_OPENAI_EMBEDDING_ENDPOINT=
AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME=

# MCP Server Configuration
MCP_HTTP_PORT=8000
MCP_HTTP_URL=http://localhost:8000
MCP_GROUP_ID=default
SEMAPHORE_LIMIT=10

# Backup Configuration
BACKUP_SCHEDULE=0 0 2,10,20 * * *
BACKUP_RETENTION_DAYS=7

# Timezone
TIMEZONE=UTC

# Optional: Slack notifications for Watchtower
SLACK_WEBHOOK_URL=
EOF
}

# Create necessary directories
create_directories() {
    print_step "Creating project directories..."
    
    local directories=("backups" "logs" "config")
    
    for dir in "${directories[@]}"; do
        if [ ! -d "$SCRIPT_DIR/$dir" ]; then
            mkdir -p "$SCRIPT_DIR/$dir"
            print_success "Created directory: $dir"
        else
            print_info "Directory already exists: $dir"
        fi
    done
    
    echo ""
}

# Generate MCP configuration
generate_mcp_config() {
    print_step "Generating MCP client configuration..."
    
    # Load environment variables
    set -a
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/.env" 2>/dev/null || true
    set +a
    
    local mcp_config_file="$SCRIPT_DIR/config/mcp.json"
    
    cat > "$mcp_config_file" << EOF
{
  "mcpServers": {
    "graphiti": {
      "command": "docker",
      "args": [
        "exec", "-i", "graphiti-mcp",
        "uv", "run", "graphiti_mcp_server.py",
        "--transport", "stdio",
        "--group-id", "${MCP_GROUP_ID:-default}"
      ],
      "env": {
        "NEO4J_URI": "${NEO4J_URI:-bolt://localhost:7687}",
        "NEO4J_USER": "${NEO4J_USER:-neo4j}",
        "NEO4J_PASSWORD": "${NEO4J_PASSWORD:-password123}",
        "OPENAI_API_KEY": "${OPENAI_API_KEY}",
        "MODEL_NAME": "${MODEL_NAME:-gpt-4o-mini}"
      }
    }
  }
}
EOF
    
    print_success "MCP configuration generated: config/mcp.json"
    
    # Also create SSE transport configuration
    cat > "$SCRIPT_DIR/config/mcp-sse.json" << EOF
{
  "mcpServers": {
    "graphiti": {
      "url": "${MCP_HTTP_URL:-http://localhost:8000}/sse"
    }
  }
}
EOF
    
    print_success "SSE configuration generated: config/mcp-sse.json"
    echo ""
}

# Build and start services
start_services() {
    print_step "Building and starting services..."
    
    cd "$SCRIPT_DIR" || exit 1
    
    # Build images first
    print_info "Building Docker images..."
    if docker-compose build --parallel; then
        print_success "Docker images built successfully"
    else
        print_error "Failed to build Docker images"
        exit 1
    fi
    
    # Start services
    print_info "Starting services..."
    if docker-compose up -d; then
        print_success "Services started successfully"
    else
        print_error "Failed to start services"
        exit 1
    fi
    
    # Wait for services to be ready
    print_info "Waiting for services to be ready..."
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s --max-time 5 "http://localhost:7474" >/dev/null 2>&1; then
            print_success "Neo4j is ready"
            break
        fi
        
        attempt=$((attempt + 1))
        if [ $((attempt % 10)) -eq 0 ]; then
            print_info "Still waiting for Neo4j... (${attempt}/${max_attempts})"
        fi
        sleep 2
    done
    
    if [ $attempt -eq $max_attempts ]; then
        print_warning "Neo4j may not be ready yet, but continuing..."
    fi
    
    # Wait for MCP server
    attempt=0
    while [ $attempt -lt 30 ]; do
        if curl -s --max-time 5 "http://localhost:8000/health" >/dev/null 2>&1; then
            print_success "MCP server is ready"
            break
        fi
        
        attempt=$((attempt + 1))
        if [ $((attempt % 5)) -eq 0 ]; then
            print_info "Still waiting for MCP server... (${attempt}/30)"
        fi
        sleep 2
    done
    
    echo ""
}

# Show final instructions
show_final_instructions() {
    print_header
    print_success "Setup completed successfully!"
    echo ""
    
    print_info "Services Status:"
    docker-compose ps
    echo ""
    
    print_info "Access Information:"
    echo "  • Neo4j Browser: http://localhost:7474"
    echo "  • MCP Server: http://localhost:8000"
    echo "  • Health Check: ./scripts/health-check.sh"
    echo ""
    
    print_info "MCP Client Configuration:"
    echo "  For stdio transport: Use config/mcp.json"
    echo "  For SSE transport: Use config/mcp-sse.json"
    echo ""
    
    print_info "Backup System:"
    echo "  • Automatic backups: Every day at 2am, 10am, 8pm"
    echo "  • Manual backup: ./scripts/backup.sh"
    echo "  • Restore backup: ./scripts/restore.sh <backup-file>"
    echo ""
    
    print_info "Useful Commands:"
    echo "  • View logs: docker-compose logs -f"
    echo "  • Stop services: docker-compose down"
    echo "  • Start services: docker-compose up -d"
    echo "  • Health check: ./scripts/health-check.sh"
    echo ""
    
    echo -e "${CYAN}${ROCKET} Your Graphiti MCP server is ready to use!${NC}"
    echo ""
    
    # Show next steps
    print_warning "Next Steps:"
    echo "1. Add the MCP configuration to your AI client (Claude, Cursor, etc.)"
    echo "2. Test the connection with your MCP client"
    echo "3. Start using Graphiti to build your knowledge graph!"
    echo ""
    
    print_info "For detailed documentation, see the docs/ directory"
}

# Handle script arguments
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-checks    Skip system requirements check"
    echo "  --dev            Set up development environment"
    echo "  --help          Show this help message"
    echo ""
    echo "This script will:"
    echo "1. Check system requirements"
    echo "2. Create environment configuration"
    echo "3. Generate MCP client configuration"
    echo "4. Build and start Docker services"
    echo "5. Provide access information and next steps"
}

# Main execution
main() {
    local skip_checks=false
    local dev_mode=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-checks)
                skip_checks=true
                shift
                ;;
            --dev)
                dev_mode=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Start setup
    print_header
    
    if [ "$skip_checks" = false ]; then
        check_system_requirements
    fi
    
    setup_environment
    create_directories
    generate_mcp_config
    start_services
    show_final_instructions
    
    print_success "Setup completed! ${ROCKET}"
}

# Run main function with all arguments
main "$@"