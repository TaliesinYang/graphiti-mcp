# Configuration Guide

This guide covers advanced configuration options for Graphiti MCP Standalone.

## Environment Variables

### Core Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `NEO4J_URI` | `bolt://localhost:7687` | Neo4j connection URI |
| `NEO4J_USER` | `neo4j` | Neo4j username |
| `NEO4J_PASSWORD` | `password123` | Neo4j password |
| `OPENAI_API_KEY` | - | OpenAI API key (required) |
| `MODEL_NAME` | `gpt-4o-mini` | Primary LLM model |
| `MCP_GROUP_ID` | `default` | Default group for organizing data |

### Neo4j Configuration

**Memory Settings:**
```env
# Heap size - for general operations
NEO4J_HEAP_INITIAL=512m
NEO4J_HEAP_MAX=1G

# Page cache - for data caching
NEO4J_PAGECACHE=512m
```

**Memory Recommendations:**
- **Development**: 512m heap, 256m page cache
- **Production (< 1M nodes)**: 1G heap, 1G page cache  
- **Production (> 1M nodes)**: 2G+ heap, 2G+ page cache

**Network Configuration:**
```env
NEO4J_HTTP_PORT=7474
NEO4J_BOLT_PORT=7687
NEO4J_HTTP_URL=http://localhost:7474
```

**Advanced Neo4j Settings:**
```env
# Enable plugins (requires Enterprise license)
NEO4J_PLUGINS=["graph-data-science"]

# Configure procedures
NEO4J_dbms_security_procedures_unrestricted=gds.*
NEO4J_dbms_security_procedures_allowlist=gds.*

# Logging level
NEO4J_dbms_logs_debug_level=INFO
```

### OpenAI Configuration

**Basic Configuration:**
```env
OPENAI_API_KEY=sk-your-api-key-here
OPENAI_BASE_URL=https://api.openai.com/v1
MODEL_NAME=gpt-4o-mini
SMALL_MODEL_NAME=gpt-4o-mini
LLM_TEMPERATURE=0.1
```

**Model Selection Guide:**

| Model | Use Case | Cost | Speed | Quality |
|-------|----------|------|-------|---------|
| `gpt-4o-mini` | Recommended | Low | Fast | High |
| `gpt-4o` | High-quality tasks | High | Medium | Highest |
| `gpt-3.5-turbo` | Basic operations | Lowest | Fastest | Good |

**Advanced Settings:**
```env
# Custom timeout (seconds)
OPENAI_TIMEOUT=30

# Request retry settings
OPENAI_MAX_RETRIES=3
OPENAI_RETRY_DELAY=1
```

### Azure OpenAI Configuration

Use Azure OpenAI instead of OpenAI directly:

```env
# Azure OpenAI LLM
AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com/
AZURE_OPENAI_DEPLOYMENT_NAME=gpt-4
AZURE_OPENAI_API_VERSION=2024-02-01

# Azure OpenAI Embeddings (optional, separate resource)
AZURE_OPENAI_EMBEDDING_ENDPOINT=https://your-embedding-resource.openai.azure.com/
AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME=text-embedding-ada-002
AZURE_OPENAI_EMBEDDING_API_KEY=your-embedding-key
```

### MCP Server Configuration

**Basic Settings:**
```env
MCP_HTTP_PORT=8000
MCP_HTTP_URL=http://localhost:8000
MCP_GROUP_ID=default
SEMAPHORE_LIMIT=10
```

**Performance Tuning:**
```env
# Increase for high-throughput
SEMAPHORE_LIMIT=20

# Reduce if hitting rate limits
SEMAPHORE_LIMIT=5

# Enable debug logging
LOG_LEVEL=DEBUG
DEBUG=true
```

**Group ID Strategy:**

Group IDs organize your knowledge graph data:

- `project-alpha` - Separate by project
- `user-john` - Separate by user
- `domain-engineering` - Separate by domain
- `temporal-2024` - Separate by time period

### Backup Configuration

**Scheduling:**
```env
# Cron format: second minute hour day month weekday
BACKUP_SCHEDULE=0 0 2,10,20 * * *  # 2am, 10am, 8pm daily

# Alternative schedules:
# BACKUP_SCHEDULE=0 0 2 * * *        # Daily at 2am
# BACKUP_SCHEDULE=0 0 2 * * 0        # Weekly on Sunday at 2am
# BACKUP_SCHEDULE=0 */6 * * * *      # Every 6 hours
```

**Retention:**
```env
BACKUP_RETENTION_DAYS=7    # Keep 7 days
BACKUP_RETENTION_DAYS=30   # Keep 30 days
BACKUP_RETENTION_DAYS=0    # Keep forever (not recommended)
```

**Custom Backup Directory:**
```env
# Inside container
BACKUP_DIR=/backups

# For external storage, mount volume:
# volumes:
#   - /external/backups:/backups
```

### System Configuration

**Timezone:**
```env
TIMEZONE=UTC               # Coordinated Universal Time
TIMEZONE=America/New_York  # Eastern Time
TIMEZONE=Europe/London     # British Time
TIMEZONE=Asia/Tokyo        # Japan Time
```

**Logging:**
```env
LOG_LEVEL=INFO     # INFO, DEBUG, WARNING, ERROR
DEBUG=false        # Enable debug features
VERBOSE_LOGGING=false
```

## Docker Configuration

### Port Mapping

Default ports can be changed:

```yaml
# docker-compose.yml
services:
  neo4j:
    ports:
      - "${NEO4J_HTTP_PORT:-7474}:7474"
      - "${NEO4J_BOLT_PORT:-7687}:7687"
      
  graphiti-mcp:
    ports:
      - "${MCP_HTTP_PORT:-8000}:8000"
```

### Volume Configuration

**Persistent Data:**
```yaml
volumes:
  neo4j_data:
    name: graphiti-neo4j-data
    driver: local
    
  # For external storage:
  neo4j_data:
    driver_opts:
      type: none
      o: bind
      device: /path/to/external/storage
```

**Backup Storage:**
```yaml
services:
  neo4j:
    volumes:
      - ./backups:/backups
      # Or external:
      - /external/backups:/backups
```

### Resource Limits

**Memory Limits:**
```yaml
services:
  neo4j:
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G
          
  graphiti-mcp:
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M
```

**CPU Limits:**
```yaml
services:
  neo4j:
    deploy:
      resources:
        limits:
          cpus: '2.0'
        reservations:
          cpus: '1.0'
```

## MCP Client Configuration

### Claude Desktop

**Basic Configuration:**
```json
{
  "mcpServers": {
    "graphiti": {
      "command": "docker",
      "args": [
        "exec", "-i", "graphiti-mcp",
        "uv", "run", "graphiti_mcp_server.py",
        "--transport", "stdio",
        "--group-id", "my-project"
      ],
      "env": {
        "NEO4J_URI": "bolt://localhost:7687",
        "NEO4J_USER": "neo4j",
        "NEO4J_PASSWORD": "your-password",
        "OPENAI_API_KEY": "sk-your-key",
        "MODEL_NAME": "gpt-4o-mini"
      }
    }
  }
}
```

**Multiple Groups:**
```json
{
  "mcpServers": {
    "graphiti-work": {
      "command": "docker",
      "args": ["exec", "-i", "graphiti-mcp", "uv", "run", "graphiti_mcp_server.py", "--transport", "stdio", "--group-id", "work-projects"],
      "env": { "..." }
    },
    "graphiti-personal": {
      "command": "docker",
      "args": ["exec", "-i", "graphiti-mcp", "uv", "run", "graphiti_mcp_server.py", "--transport", "stdio", "--group-id", "personal"],
      "env": { "..." }
    }
  }
}
```

### Cursor

**SSE Configuration:**
```json
{
  "mcpServers": {
    "graphiti": {
      "url": "http://localhost:8000/sse"
    }
  }
}
```

**With Authentication (if configured):**
```json
{
  "mcpServers": {
    "graphiti": {
      "url": "http://localhost:8000/sse",
      "headers": {
        "Authorization": "Bearer your-token"
      }
    }
  }
}
```

## Advanced Configuration

### Custom Entity Types

Define custom entity types in your MCP server:

```python
# In graphiti_mcp_server.py
class CustomProcedure(BaseModel):
    """Custom procedure with additional fields"""
    project_name: str = Field(..., description="Project name")
    priority: str = Field(..., description="Priority level")
    steps: List[str] = Field(..., description="Implementation steps")
```

### Search Configuration

**Hybrid Search Settings:**
```python
# Adjust search weights
search_config = {
    "node_search_config": NODE_HYBRID_SEARCH_RRF,
    "edge_search_config": None,
    "semantic_weight": 0.7,
    "keyword_weight": 0.3
}
```

### Multi-Database Setup

**Separate databases by environment:**
```env
# Development
NEO4J_DATABASE=graphiti_dev

# Production  
NEO4J_DATABASE=graphiti_prod

# Testing
NEO4J_DATABASE=graphiti_test
```

### SSL/TLS Configuration

**Enable SSL for production:**
```env
# Neo4j SSL
NEO4J_URI=neo4j+s://localhost:7687
NEO4J_dbms_connector_bolt_tls_level=REQUIRED

# Custom certificates
NEO4J_dbms_ssl_policy_bolt_enabled=true
NEO4J_dbms_ssl_policy_bolt_base_directory=/ssl
```

**SSL Certificate volumes:**
```yaml
services:
  neo4j:
    volumes:
      - ./ssl:/ssl:ro
```

### Monitoring Configuration

**Health Check Settings:**
```yaml
services:
  neo4j:
    healthcheck:
      test: ["CMD", "wget", "-O", "/dev/null", "-q", "http://localhost:7474"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 30s
      
  graphiti-mcp:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
```

**Watchtower for Auto-updates:**
```yaml
services:
  watchtower:
    image: containrrr/watchtower
    profiles: ["monitoring"]
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 0 4 * * 0  # Weekly updates
      - WATCHTOWER_NOTIFICATIONS=slack
      - WATCHTOWER_NOTIFICATION_SLACK_HOOK_URL=${SLACK_WEBHOOK_URL}
```

## Security Configuration

### Basic Security

**Change Default Passwords:**
```env
# Strong Neo4j password
NEO4J_PASSWORD=your-very-secure-password-here

# Rotate API keys regularly
OPENAI_API_KEY=sk-new-rotated-key
```

**Network Security:**
```yaml
# Bind to localhost only
services:
  neo4j:
    ports:
      - "127.0.0.1:7474:7474"
      - "127.0.0.1:7687:7687"
```

### Advanced Security

**User Access Control:**
```cypher
# Create read-only user in Neo4j
CREATE USER reader
SET PASSWORD 'secure-password' CHANGE NOT REQUIRED
GRANT ROLE reader TO reader
```

**Firewall Rules:**
```bash
# Only allow local access
sudo ufw allow from 127.0.0.1 to any port 7474
sudo ufw allow from 127.0.0.1 to any port 7687
sudo ufw allow from 127.0.0.1 to any port 8000
```

## Performance Optimization

### Neo4j Performance

**Index Configuration:**
```cypher
# Create indexes for better performance
CREATE INDEX entity_name FOR (n:EntityNode) ON (n.name)
CREATE INDEX episode_created FOR (n:EpisodicNode) ON (n.created_at)
CREATE TEXT INDEX entity_summary FOR (n:EntityNode) ON (n.summary)
```

**Query Optimization:**
```cypher
# Monitor slow queries
CALL dbms.queryJmx("org.neo4j:instance=kernel#0,name=Queries")
```

### System Performance

**Docker Resource Allocation:**
```bash
# Increase Docker resources
# In Docker Desktop: Settings > Resources
# Memory: 4GB+
# CPU: 2+ cores
# Disk: 20GB+
```

**System Tuning:**
```bash
# Increase file limits
echo 'fs.file-max = 65535' >> /etc/sysctl.conf

# Increase virtual memory
echo 'vm.max_map_count = 262144' >> /etc/sysctl.conf

# Apply changes
sysctl -p
```

## Troubleshooting Configuration

### Common Configuration Issues

**Environment Variables Not Loading:**
```bash
# Check .env file syntax
cat .env | grep -v '^#' | grep -v '^$'

# Test variable loading
docker-compose config
```

**Port Conflicts:**
```bash
# Check port usage
netstat -tlnp | grep -E ':(7474|7687|8000)'

# Change ports in .env
NEO4J_HTTP_PORT=17474
NEO4J_BOLT_PORT=17687
MCP_HTTP_PORT=18000
```

**Memory Issues:**
```bash
# Check available memory
free -h

# Reduce Neo4j memory
NEO4J_HEAP_MAX=512m
NEO4J_PAGECACHE=256m
```

### Validation Tools

**Configuration Validation:**
```bash
# Validate Docker Compose
docker-compose config

# Validate environment
./scripts/health-check.sh --verbose

# Test MCP configuration
./scripts/mcp-config-generator.sh --output /tmp/test-config.json
```

**Performance Testing:**
```bash
# Neo4j performance test
docker exec graphiti-neo4j cypher-shell -u neo4j -p password "CALL db.stats.retrieve('GRAPH COUNTS')"

# MCP server performance test
time curl -s http://localhost:8000/health
```

## Next Steps

After configuring your system:

1. **Test Configuration** - Run health checks and verify all services
2. **Optimize Performance** - Adjust memory and concurrency settings
3. **Set Up Monitoring** - Configure logging and health checks
4. **Plan Backup Strategy** - Test backup and restore procedures
5. **Document Changes** - Keep track of your custom configurations

For operational guidance, see:
- [Installation Guide](INSTALLATION.md)
- [API Reference](API.md)
- [Backup Guide](BACKUP.md)