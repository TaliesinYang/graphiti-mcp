#!/bin/bash
# Graphiti MCP Health Check Script
# Usage: ./health-check.sh [--json] [--verbose]

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default settings
OUTPUT_FORMAT="text"
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--json] [--verbose]"
            echo ""
            echo "Options:"
            echo "  --json        Output results in JSON format"
            echo "  --verbose     Show detailed information"
            echo "  --help        Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Initialize results
declare -A results
results["timestamp"]=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Utility functions
log_status() {
    local service="$1"
    local status="$2"
    local message="$3"
    local details="$4"
    
    results["${service}_status"]="$status"
    results["${service}_message"]="$message"
    if [ -n "$details" ]; then
        results["${service}_details"]="$details"
    fi
    
    if [ "$OUTPUT_FORMAT" != "json" ]; then
        case "$status" in
            "healthy")
                echo -e "${GREEN}✓${NC} $service: $message"
                ;;
            "unhealthy")
                echo -e "${RED}✗${NC} $service: $message"
                ;;
            "warning")
                echo -e "${YELLOW}⚠${NC} $service: $message"
                ;;
            *)
                echo -e "${BLUE}ℹ${NC} $service: $message"
                ;;
        esac
        
        if [ "$VERBOSE" == "true" ] && [ -n "$details" ]; then
            echo "  Details: $details"
        fi
    fi
}

# Check if Docker is running
check_docker() {
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            log_status "docker" "healthy" "Docker daemon is running"
        else
            log_status "docker" "unhealthy" "Docker daemon is not accessible"
            return 1
        fi
    else
        log_status "docker" "unhealthy" "Docker is not installed"
        return 1
    fi
}

# Check Docker Compose services
check_compose_services() {
    if [ ! -f "$PROJECT_DIR/docker-compose.yml" ]; then
        log_status "compose" "unhealthy" "docker-compose.yml not found"
        return 1
    fi
    
    cd "$PROJECT_DIR" || return 1
    
    # Get service status
    local services
    services=$(docker-compose ps --services 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_status "compose" "unhealthy" "Failed to query docker-compose services"
        return 1
    fi
    
    local total_services=0
    local healthy_services=0
    local service_details=""
    
    for service in $services; do
        total_services=$((total_services + 1))
        local status
        status=$(docker-compose ps -q "$service" | xargs docker inspect --format='{{.State.Status}}' 2>/dev/null)
        
        if [ "$status" == "running" ]; then
            healthy_services=$((healthy_services + 1))
            service_details="${service_details}${service}: running, "
        else
            service_details="${service_details}${service}: ${status:-stopped}, "
        fi
    done
    
    if [ $healthy_services -eq $total_services ]; then
        log_status "compose" "healthy" "All services running ($healthy_services/$total_services)" "$service_details"
    else
        log_status "compose" "warning" "Some services not running ($healthy_services/$total_services)" "$service_details"
    fi
}

# Check Neo4j database
check_neo4j() {
    local neo4j_url="${NEO4J_HTTP_URL:-http://localhost:7474}"
    local neo4j_bolt="${NEO4J_URI:-bolt://localhost:7687}"
    
    # Check HTTP endpoint
    if curl -s --max-time 10 "$neo4j_url" >/dev/null 2>&1; then
        log_status "neo4j_http" "healthy" "Neo4j HTTP interface accessible" "$neo4j_url"
    else
        log_status "neo4j_http" "unhealthy" "Neo4j HTTP interface not accessible" "$neo4j_url"
    fi
    
    # Check database connectivity with cypher-shell if available
    if command -v docker >/dev/null 2>&1; then
        local container_id
        container_id=$(docker ps -q --filter "name=graphiti-neo4j")
        
        if [ -n "$container_id" ]; then
            local node_count
            node_count=$(docker exec "$container_id" cypher-shell -u "${NEO4J_USER:-neo4j}" -p "${NEO4J_PASSWORD:-password123}" "MATCH (n) RETURN count(n) AS total;" --format plain 2>/dev/null | tail -1)
            
            if [ -n "$node_count" ] && [[ "$node_count" =~ ^[0-9]+$ ]]; then
                log_status "neo4j_db" "healthy" "Database accessible" "Nodes: $node_count"
            else
                log_status "neo4j_db" "warning" "Database query failed" "Connection issue or authentication failure"
            fi
        else
            log_status "neo4j_db" "unhealthy" "Neo4j container not found" "Container may be stopped"
        fi
    fi
}

# Check MCP server
check_mcp_server() {
    local mcp_url="${MCP_HTTP_URL:-http://localhost:8000}"
    
    # Check HTTP health endpoint
    if curl -s --max-time 10 "${mcp_url}/health" >/dev/null 2>&1; then
        log_status "mcp_server" "healthy" "MCP server accessible" "$mcp_url"
    else
        log_status "mcp_server" "unhealthy" "MCP server not accessible" "$mcp_url"
    fi
    
    # Check container status
    if command -v docker >/dev/null 2>&1; then
        local container_id
        container_id=$(docker ps -q --filter "name=graphiti-mcp")
        
        if [ -n "$container_id" ]; then
            local container_status
            container_status=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null)
            
            if [ "$container_status" == "running" ]; then
                log_status "mcp_container" "healthy" "MCP container running" "Status: $container_status"
            else
                log_status "mcp_container" "unhealthy" "MCP container not running" "Status: $container_status"
            fi
        else
            log_status "mcp_container" "unhealthy" "MCP container not found" "Container may be stopped"
        fi
    fi
}

# Check backup system
check_backup_system() {
    local backup_dir="$PROJECT_DIR/backups"
    
    if [ ! -d "$backup_dir" ]; then
        log_status "backups" "warning" "Backup directory not found" "$backup_dir"
        return 1
    fi
    
    # Count backup files
    local backup_count
    backup_count=$(find "$backup_dir" -name "backup-*.dump" -type f | wc -l)
    
    if [ $backup_count -gt 0 ]; then
        # Get latest backup info
        local latest_backup
        latest_backup=$(find "$backup_dir" -name "backup-*.dump" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        
        if [ -n "$latest_backup" ]; then
            local backup_age
            backup_age=$(( ($(date +%s) - $(stat -c %Y "$latest_backup")) / 3600 ))
            local backup_size
            backup_size=$(du -h "$latest_backup" | cut -f1)
            
            if [ $backup_age -lt 48 ]; then
                log_status "backups" "healthy" "Recent backup available ($backup_count total)" "Latest: $(basename "$latest_backup"), ${backup_size}, ${backup_age}h ago"
            else
                log_status "backups" "warning" "Latest backup is old ($backup_count total)" "Latest: $(basename "$latest_backup"), ${backup_size}, ${backup_age}h ago"
            fi
        fi
    else
        log_status "backups" "warning" "No backup files found" "$backup_dir"
    fi
    
    # Check Ofelia scheduler
    if command -v docker >/dev/null 2>&1; then
        local ofelia_container
        ofelia_container=$(docker ps -q --filter "name=graphiti-ofelia")
        
        if [ -n "$ofelia_container" ]; then
            log_status "ofelia" "healthy" "Backup scheduler running" "Container: graphiti-ofelia"
        else
            log_status "ofelia" "warning" "Backup scheduler not found" "Automatic backups may not work"
        fi
    fi
}

# Check disk usage
check_disk_usage() {
    local data_dirs=("$PROJECT_DIR/backups" "/var/lib/docker")
    
    for dir in "${data_dirs[@]}"; do
        if [ -d "$dir" ]; then
            local usage
            usage=$(df -h "$dir" | tail -1 | awk '{print $5}' | sed 's/%//')
            local available
            available=$(df -h "$dir" | tail -1 | awk '{print $4}')
            
            if [ "$usage" -lt 80 ]; then
                log_status "disk_$(basename "$dir")" "healthy" "Disk usage OK (${usage}%)" "Available: $available"
            elif [ "$usage" -lt 90 ]; then
                log_status "disk_$(basename "$dir")" "warning" "Disk usage high (${usage}%)" "Available: $available"
            else
                log_status "disk_$(basename "$dir")" "unhealthy" "Disk usage critical (${usage}%)" "Available: $available"
            fi
        fi
    done
}

# Generate JSON output
output_json() {
    echo "{"
    echo "  \"timestamp\": \"${results[timestamp]}\","
    echo "  \"overall_status\": \"$1\","
    echo "  \"services\": {"
    
    local first=true
    for key in "${!results[@]}"; do
        if [[ "$key" == *"_status" ]]; then
            local service_name="${key%_status}"
            if [ "$first" == "true" ]; then
                first=false
            else
                echo ","
            fi
            
            echo -n "    \"$service_name\": {"
            echo -n "\"status\": \"${results[${service_name}_status]}\""
            
            if [ -n "${results[${service_name}_message]}" ]; then
                echo -n ", \"message\": \"${results[${service_name}_message]}\""
            fi
            
            if [ -n "${results[${service_name}_details]}" ]; then
                echo -n ", \"details\": \"${results[${service_name}_details]}\""
            fi
            
            echo -n "}"
        fi
    done
    
    echo ""
    echo "  }"
    echo "}"
}

# Main execution
main() {
    if [ "$OUTPUT_FORMAT" != "json" ]; then
        echo "Graphiti MCP Health Check"
        echo "========================="
        echo ""
    fi
    
    # Load environment variables if available
    if [ -f "$PROJECT_DIR/.env" ]; then
        set -a
        # shellcheck source=/dev/null
        source "$PROJECT_DIR/.env"
        set +a
    fi
    
    # Run all checks
    check_docker
    check_compose_services
    check_neo4j
    check_mcp_server
    check_backup_system
    check_disk_usage
    
    # Determine overall status
    local overall_status="healthy"
    local unhealthy_count=0
    local warning_count=0
    
    for key in "${!results[@]}"; do
        if [[ "$key" == *"_status" ]]; then
            case "${results[$key]}" in
                "unhealthy")
                    unhealthy_count=$((unhealthy_count + 1))
                    overall_status="unhealthy"
                    ;;
                "warning")
                    warning_count=$((warning_count + 1))
                    if [ "$overall_status" == "healthy" ]; then
                        overall_status="warning"
                    fi
                    ;;
            esac
        fi
    done
    
    # Output results
    if [ "$OUTPUT_FORMAT" == "json" ]; then
        output_json "$overall_status"
    else
        echo ""
        echo "========================="
        case "$overall_status" in
            "healthy")
                echo -e "Overall Status: ${GREEN}HEALTHY${NC}"
                ;;
            "warning")
                echo -e "Overall Status: ${YELLOW}WARNING${NC} ($warning_count warnings)"
                ;;
            "unhealthy")
                echo -e "Overall Status: ${RED}UNHEALTHY${NC} ($unhealthy_count failures, $warning_count warnings)"
                ;;
        esac
    fi
    
    # Exit with appropriate code
    case "$overall_status" in
        "healthy")
            exit 0
            ;;
        "warning")
            exit 1
            ;;
        "unhealthy")
            exit 2
            ;;
    esac
}

main "$@"