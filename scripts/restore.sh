#!/bin/bash
# Graphiti Neo4j Restore Script
# Usage: ./restore.sh <backup-file> [--force]

set -e  # Exit on any error

# Configuration
BACKUP_DIR="/backups"
LOG_FILE="${BACKUP_DIR}/restore.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Show usage
show_usage() {
    echo "Usage: $0 <backup-file> [--force]"
    echo ""
    echo "Arguments:"
    echo "  backup-file    Name of backup file to restore (without path)"
    echo "  --force        Skip confirmation prompt"
    echo ""
    echo "Examples:"
    echo "  $0 backup-20241201.dump"
    echo "  $0 my-backup.dump --force"
    echo ""
    echo "Available backups:"
    if [ -d "$BACKUP_DIR" ] && [ "$(find "$BACKUP_DIR" -name "*.dump" -type f | wc -l)" -gt 0 ]; then
        find "$BACKUP_DIR" -name "*.dump" -type f -printf "%f\t%TY-%Tm-%Td %TH:%TM\t%s bytes\n" | sort -r | head -10
    else
        echo "  No backup files found in $BACKUP_DIR"
    fi
    exit 1
}

# Check if running inside Neo4j container
check_environment() {
    if ! command -v neo4j-admin >/dev/null 2>&1; then
        log_error "neo4j-admin command not found. This script should run inside the Neo4j container."
        exit 1
    fi
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
}

# Validate backup file
validate_backup() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        log_error "No backup file specified"
        show_usage
    fi
    
    # Add .dump extension if not present
    if [[ "$backup_file" != *.dump ]]; then
        backup_file="${backup_file}.dump"
    fi
    
    local full_path="${BACKUP_DIR}/${backup_file}"
    
    if [ ! -f "$full_path" ]; then
        log_error "Backup file not found: $full_path"
        echo ""
        show_usage
    fi
    
    log_info "Found backup file: $full_path"
    log_info "File size: $(du -h "$full_path" | cut -f1)"
    log_info "File date: $(date -r "$full_path" '+%Y-%m-%d %H:%M:%S')"
    
    echo "$full_path"
}

# Create pre-restore backup
create_pre_restore_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local pre_backup_name="pre-restore-backup-${timestamp}"
    
    log_info "Creating pre-restore backup: ${pre_backup_name}.dump"
    
    # Stop external services
    stop_external_services
    
    # Stop Neo4j and create backup
    neo4j stop
    sleep 10
    
    if neo4j-admin database dump neo4j --to-path="$BACKUP_DIR"; then
        if [ -f "${BACKUP_DIR}/neo4j.dump" ]; then
            mv "${BACKUP_DIR}/neo4j.dump" "${BACKUP_DIR}/${pre_backup_name}.dump"
            log_success "Pre-restore backup created: ${pre_backup_name}.dump"
        else
            log_warning "Pre-restore backup file not found, continuing anyway"
        fi
    else
        log_warning "Pre-restore backup failed, continuing anyway"
    fi
    
    neo4j start
    sleep 15
}

# Stop external services that might be using the database
stop_external_services() {
    log "Stopping external MCP services..."
    
    # Stop graphiti-mcp container gracefully
    if docker ps --format "table {{.Names}}" | grep -q "graphiti-mcp"; then
        docker stop graphiti-mcp 2>/dev/null || log_warning "Could not stop graphiti-mcp container"
        sleep 5
    fi
}

# Start external services
start_external_services() {
    log "Starting external MCP services..."
    
    # Restart graphiti-mcp container
    if docker ps -a --format "table {{.Names}}" | grep -q "graphiti-mcp"; then
        docker start graphiti-mcp 2>/dev/null || log_warning "Could not start graphiti-mcp container"
    fi
    
    # Wait for services to be ready
    log "Waiting for services to be ready..."
    sleep 15
}

# Perform the actual restore
perform_restore() {
    local backup_file="$1"
    local backup_name=$(basename "$backup_file" .dump)
    
    log "Starting Neo4j database restore from: $backup_file"
    
    # Stop Neo4j service
    log "Stopping Neo4j service..."
    neo4j stop
    sleep 10
    
    # Remove existing database
    log_warning "Removing existing database..."
    rm -rf /data/databases/neo4j
    rm -rf /data/transactions/neo4j
    
    # Load the backup
    log "Loading backup: $backup_name"
    if neo4j-admin database load --from-path="$BACKUP_DIR" --overwrite-destination=true neo4j "${backup_name}.dump"; then
        log_success "Database restore completed"
    else
        log_error "Database restore failed"
        return 1
    fi
    
    # Start Neo4j service
    log "Starting Neo4j service..."
    neo4j start
    sleep 15
    
    # Wait for Neo4j to be ready
    log "Waiting for Neo4j to be ready..."
    timeout 90 bash -c 'until wget -q -O /dev/null http://localhost:7474; do sleep 2; done'
    
    if [ $? -eq 0 ]; then
        log_success "Neo4j is ready"
        
        # Test database connectivity
        log "Testing database connectivity..."
        if echo "MATCH (n) RETURN count(n) AS total_nodes;" | cypher-shell -u neo4j -p "${NEO4J_PASSWORD:-password123}" --format plain 2>/dev/null | grep -q "total_nodes"; then
            log_success "Database connectivity test passed"
        else
            log_warning "Database connectivity test failed, but Neo4j appears to be running"
        fi
    else
        log_warning "Neo4j may not be fully ready yet"
        return 1
    fi
}

# Generate restore summary
generate_summary() {
    local backup_file="$1"
    
    log "=== Restore Summary ==="
    log "Restored from: $(basename "$backup_file")"
    log "Restore completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Try to get database stats
    if command -v cypher-shell >/dev/null 2>&1; then
        log "Database statistics:"
        echo "MATCH (n) RETURN count(n) AS nodes;" | cypher-shell -u neo4j -p "${NEO4J_PASSWORD:-password123}" --format plain 2>/dev/null | grep -E "nodes|^[0-9]+" || log "Could not retrieve node count"
        echo "MATCH ()-[r]->() RETURN count(r) AS relationships;" | cypher-shell -u neo4j -p "${NEO4J_PASSWORD:-password123}" --format plain 2>/dev/null | grep -E "relationships|^[0-9]+" || log "Could not retrieve relationship count"
    fi
    
    log "========================"
}

# Confirmation prompt
confirm_restore() {
    local backup_file="$1"
    local force="$2"
    
    if [ "$force" == "true" ]; then
        log_warning "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    echo -e "${RED}WARNING: This will completely replace your current database!${NC}"
    echo -e "${YELLOW}Current database will be backed up as 'pre-restore-backup-TIMESTAMP.dump'${NC}"
    echo ""
    echo "Restore from: $(basename "$backup_file")"
    echo "File size: $(du -h "$backup_file" | cut -f1)"
    echo "File date: $(date -r "$backup_file" '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo -n "Are you sure you want to continue? (yes/no): "
    read -r response
    
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log "Restore cancelled by user"
            exit 0
            ;;
    esac
}

# Main execution
main() {
    local backup_file="$1"
    local force_flag="$2"
    local force=false
    
    if [ "$force_flag" == "--force" ] || [ "$backup_file" == "--force" ]; then
        force=true
    fi
    
    if [ "$backup_file" == "--force" ]; then
        backup_file="$2"
    fi
    
    log "Starting Graphiti Neo4j restore process..."
    
    check_environment
    backup_file=$(validate_backup "$backup_file")
    confirm_restore "$backup_file" "$force"
    
    # Set trap to ensure services are restarted even if script fails
    trap 'start_external_services' EXIT
    
    create_pre_restore_backup
    stop_external_services
    
    if perform_restore "$backup_file"; then
        generate_summary "$backup_file"
        log_success "Restore completed successfully!"
        log_info "You can now restart your MCP services if needed"
    else
        log_error "Restore failed!"
        log_info "Your original database backup should be available as pre-restore-backup-*.dump"
        exit 1
    fi
}

# Handle command line arguments
if [ $# -eq 0 ] || [ "$1" == "help" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_usage
fi

main "$@"