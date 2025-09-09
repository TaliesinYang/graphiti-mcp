#!/bin/bash
# Graphiti Neo4j Backup Script
# Usage: ./backup.sh [backup-name]

set -e  # Exit on any error

# Configuration
DATE=$(date +%Y%m%d_%H%M%S)
TODAY=$(date +%Y%m%d)
BACKUP_DIR="/backups"
BACKUP_NAME="${1:-backup-${TODAY}}"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.dump"
LOG_FILE="${BACKUP_DIR}/backup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running inside Neo4j container
check_environment() {
    if ! command -v neo4j-admin >/dev/null 2>&1; then
        log_error "neo4j-admin command not found. This script should run inside the Neo4j container."
        exit 1
    fi
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
}

# Check if backup already exists for today
check_existing_backup() {
    if [ -f "$BACKUP_FILE" ] && [ "$1" != "force" ]; then
        log_warning "Backup already exists: $BACKUP_FILE"
        log "Use './backup.sh force' to overwrite or specify a different name"
        exit 0
    fi
}

# Stop external services that might be using the database
stop_external_services() {
    log "Stopping external MCP services..."
    
    # Try to stop graphiti-mcp container gracefully
    if docker ps --format "table {{.Names}}" | grep -q "graphiti-mcp"; then
        docker stop graphiti-mcp 2>/dev/null || log_warning "Could not stop graphiti-mcp container"
        sleep 5
    fi
    
    # Wait for connections to close
    log "Waiting for connections to close..."
    sleep 10
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

# Perform the actual backup
perform_backup() {
    log "Starting Neo4j database backup..."
    
    # Stop Neo4j service
    log "Stopping Neo4j service..."
    neo4j stop
    sleep 10
    
    # Create database dump
    log "Creating database dump..."
    if neo4j-admin database dump neo4j --to-path="$BACKUP_DIR"; then
        
        # Rename the dump file with timestamp
        if [ -f "${BACKUP_DIR}/neo4j.dump" ]; then
            mv "${BACKUP_DIR}/neo4j.dump" "$BACKUP_FILE"
            log_success "Database dump created: $BACKUP_FILE"
            
            # Get backup file size
            BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
            log "Backup file size: $BACKUP_SIZE"
            
            # Verify backup integrity
            log "Verifying backup integrity..."
            if neo4j-admin database load --from-path="$BACKUP_DIR" --info --dry-run "${BACKUP_NAME}.dump" >/dev/null 2>&1; then
                log_success "Backup integrity verified"
            else
                log_warning "Backup integrity check failed, but backup file exists"
            fi
            
        else
            log_error "neo4j.dump file not found after backup"
            return 1
        fi
        
    else
        log_error "Database dump failed"
        return 1
    fi
    
    # Restart Neo4j service
    log "Restarting Neo4j service..."
    neo4j start
    sleep 15
    
    # Wait for Neo4j to be ready
    log "Waiting for Neo4j to be ready..."
    timeout 60 bash -c 'until wget -q -O /dev/null http://localhost:7474; do sleep 1; done'
    
    if [ $? -eq 0 ]; then
        log_success "Neo4j is ready"
    else
        log_warning "Neo4j may not be fully ready yet"
    fi
}

# Clean up old backups
cleanup_old_backups() {
    local retention_days=${BACKUP_RETENTION_DAYS:-7}
    log "Cleaning up backups older than $retention_days days..."
    
    # Find and delete old backup files
    find "$BACKUP_DIR" -name "backup-*.dump" -mtime +$retention_days -type f | while read -r old_backup; do
        log "Removing old backup: $(basename "$old_backup")"
        rm -f "$old_backup"
    done
    
    log "Cleanup completed"
}

# Generate backup summary
generate_summary() {
    log "=== Backup Summary ==="
    log "Backup file: $BACKUP_FILE"
    log "Backup size: $(du -h "$BACKUP_FILE" 2>/dev/null | cut -f1 || echo 'Unknown')"
    log "Total backups: $(find "$BACKUP_DIR" -name "backup-*.dump" -type f | wc -l)"
    log "Disk usage: $(df -h "$BACKUP_DIR" | tail -1 | awk '{print $3 "/" $2 " (" $5 ")"}')"
    log "======================"
}

# Main execution
main() {
    log "Starting Graphiti Neo4j backup process..."
    
    check_environment
    check_existing_backup "$2"
    
    # Set trap to ensure services are restarted even if script fails
    trap 'start_external_services' EXIT
    
    stop_external_services
    
    if perform_backup; then
        cleanup_old_backups
        generate_summary
        log_success "Backup completed successfully!"
    else
        log_error "Backup failed!"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "Usage: $0 [backup-name|force] [force]"
        echo "  backup-name: Custom name for backup (default: backup-YYYYMMDD)"
        echo "  force: Overwrite existing backup"
        echo ""
        echo "Examples:"
        echo "  $0                    # Create backup-20241201.dump"
        echo "  $0 my-backup          # Create my-backup.dump"
        echo "  $0 force              # Overwrite today's backup"
        echo "  $0 my-backup force    # Create/overwrite my-backup.dump"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac