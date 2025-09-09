# Installation Guide

This guide provides detailed installation instructions for the Graphiti MCP Standalone server.

## Prerequisites

### System Requirements

- **Operating System**: Linux, macOS, or Windows with WSL2
- **Memory**: Minimum 2GB RAM (4GB+ recommended for production)
- **Storage**: At least 5GB free disk space
- **Docker**: Version 20.10.0 or higher
- **Docker Compose**: Version 2.0.0 or higher

### Required Accounts/Keys

- **OpenAI API Key**: Required for LLM operations
  - Get your key from: https://platform.openai.com/api-keys
  - Alternative: Azure OpenAI endpoint (see Azure configuration below)

## Quick Installation

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/graphiti-mcp-standalone.git
cd graphiti-mcp-standalone
```

### 2. Run Setup Script

```bash
./setup.sh
```

The setup script will:
1. Check system requirements
2. Create environment configuration
3. Generate MCP client configuration
4. Build and start Docker services
5. Provide access information

### 3. Configure MCP Client

Add the generated configuration to your MCP client:

**For Claude Desktop:**
```bash
# The setup script generates config/mcp.json
# Copy this to your Claude configuration file
cp config/mcp.json ~/.claude/mcp.json
```

**For Cursor (SSE transport):**
Use the URL: `http://localhost:8000/sse`

## Manual Installation

If you prefer manual setup or need customization:

### 1. Environment Configuration

```bash
# Copy environment template
cp .env.example .env

# Edit with your configuration
nano .env
```

**Essential settings to configure:**
```env
NEO4J_PASSWORD=your_secure_password_here
OPENAI_API_KEY=sk-your-actual-api-key-here
MCP_GROUP_ID=your-project-name
```

### 2. Build and Start Services

```bash
# Build Docker images
docker-compose build

# Start services
docker-compose up -d

# Verify services are running
docker-compose ps
```

### 3. Generate MCP Configuration

```bash
# Generate stdio configuration
./scripts/mcp-config-generator.sh --output config/mcp.json

# Or generate SSE configuration
./scripts/mcp-config-generator.sh --transport sse --output config/mcp-sse.json
```

### 4. Health Check

```bash
# Run health check
./scripts/health-check.sh

# Check service status
docker-compose logs -f
```

## Service Configuration

### Neo4j Configuration

Neo4j stores your knowledge graph data.

**Memory Settings:**
```env
# For development
NEO4J_HEAP_INITIAL=512m
NEO4J_HEAP_MAX=1G
NEO4J_PAGECACHE=512m

# For production
NEO4J_HEAP_INITIAL=1G
NEO4J_HEAP_MAX=2G
NEO4J_PAGECACHE=1G
```

**Access:**
- Browser: http://localhost:7474
- Username: `neo4j`
- Password: Set in `.env` file

### MCP Server Configuration

The MCP server provides the interface for AI clients.

**Transport Options:**
- **stdio**: Direct execution (recommended for Claude Desktop)
- **sse**: HTTP server (recommended for Cursor)

**Configuration:**
```env
MCP_HTTP_PORT=8000
MCP_GROUP_ID=your-project
SEMAPHORE_LIMIT=10  # Concurrent operations
```

### Backup Configuration

Automatic backups are scheduled via Ofelia.

**Backup Settings:**
```env
BACKUP_SCHEDULE=0 0 2,10,20 * * *  # 2am, 10am, 8pm daily
BACKUP_RETENTION_DAYS=7            # Keep 7 days of backups
```

**Manual Backup:**
```bash
# Create backup
./scripts/backup.sh

# Create backup with custom name
./scripts/backup.sh my-backup

# Restore from backup
./scripts/restore.sh backup-20241201.dump
```

## Client Integration

### Claude Desktop

1. **Add Configuration:**
   ```bash
   # Copy generated configuration
   cp config/mcp.json ~/.claude/mcp.json
   ```

2. **Restart Claude Desktop**

3. **Verify Integration:**
   - Look for Graphiti tools in Claude
   - Test with: "Search my knowledge graph for recent information"

### Cursor

1. **Add SSE Configuration:**
   - In Cursor settings, add MCP server URL: `http://localhost:8000/sse`

2. **Restart Cursor**

3. **Verify Integration:**
   - Check that Graphiti MCP appears in available tools

### Other MCP Clients

For other MCP clients, use the appropriate configuration format:

**stdio transport:**
```json
{
  "mcpServers": {
    "graphiti": {
      "command": "docker",
      "args": ["exec", "-i", "graphiti-mcp", "uv", "run", "graphiti_mcp_server.py", "--transport", "stdio"]
    }
  }
}
```

**SSE transport:**
```json
{
  "mcpServers": {
    "graphiti": {
      "url": "http://localhost:8000/sse"
    }
  }
}
```

## Development Setup

For development with live code reloading:

```bash
# Start development environment
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# Enable development tools
docker-compose --profile dev-tools up -d

# Access development tools:
# - Neo4j Browser: http://localhost:7475
# - Log Viewer: http://localhost:8080
```

## Verification

### 1. Service Health Check

```bash
./scripts/health-check.sh
```

Expected output:
```
✓ docker: Docker daemon is running
✓ compose: All services running (4/4)
✓ neo4j_http: Neo4j HTTP interface accessible
✓ neo4j_db: Database accessible
✓ mcp_server: MCP server accessible
✓ backups: Recent backup available (3 total)
✓ ofelia: Backup scheduler running
```

### 2. Test MCP Connection

Test with your MCP client:

```
Add some test knowledge:
"Remember that I prefer using Docker for deployments"

Search the knowledge:
"What are my deployment preferences?"
```

### 3. Manual Database Connection

```bash
# Connect to Neo4j
docker exec -it graphiti-neo4j cypher-shell -u neo4j -p your_password

# Check node count
MATCH (n) RETURN count(n) AS total_nodes;

# Check recent episodes
MATCH (e:EpisodicNode) RETURN e.name, e.created_at ORDER BY e.created_at DESC LIMIT 5;
```

## Troubleshooting

### Common Issues

**Docker services not starting:**
```bash
# Check Docker daemon
sudo systemctl status docker

# Check logs
docker-compose logs -f

# Restart services
docker-compose down && docker-compose up -d
```

**Neo4j connection failed:**
```bash
# Check Neo4j container
docker-compose ps neo4j

# Check Neo4j logs
docker-compose logs neo4j

# Verify credentials in .env
grep NEO4J_PASSWORD .env
```

**MCP server not accessible:**
```bash
# Check MCP server status
curl http://localhost:8000/health

# Check container logs
docker-compose logs graphiti-mcp

# Verify OpenAI API key
grep OPENAI_API_KEY .env
```

**Backup failed:**
```bash
# Check Ofelia scheduler
docker-compose logs ofelia

# Check backup directory permissions
ls -la backups/

# Run manual backup
./scripts/backup.sh
```

### Getting Help

1. **Check Health Status:** `./scripts/health-check.sh --verbose`
2. **Review Logs:** `docker-compose logs -f`
3. **Verify Configuration:** Check `.env` file for correct values
4. **Port Conflicts:** Ensure ports 7474, 7687, and 8000 are available
5. **Memory Issues:** Reduce Neo4j memory settings if system has limited RAM

### Performance Tuning

**For High-Volume Usage:**

1. **Increase Neo4j Memory:**
   ```env
   NEO4J_HEAP_INITIAL=2G
   NEO4J_HEAP_MAX=4G
   NEO4J_PAGECACHE=2G
   ```

2. **Adjust Concurrent Operations:**
   ```env
   SEMAPHORE_LIMIT=20
   ```

3. **Optimize Backup Schedule:**
   ```env
   BACKUP_SCHEDULE=0 0 2 * * *  # Once daily at 2am
   ```

**For Low-Resource Systems:**

1. **Reduce Memory Usage:**
   ```env
   NEO4J_HEAP_INITIAL=256m
   NEO4J_HEAP_MAX=512m
   NEO4J_PAGECACHE=256m
   ```

2. **Limit Concurrent Operations:**
   ```env
   SEMAPHORE_LIMIT=5
   ```

## Next Steps

After successful installation:

1. **Configure Your MCP Client** - Add the generated configuration
2. **Test Basic Operations** - Store and retrieve some test knowledge
3. **Set Up Monitoring** - Run periodic health checks
4. **Plan Your Knowledge Structure** - Design your group IDs and entity types
5. **Backup Strategy** - Verify automatic backups are working

For advanced configuration and usage, see:
- [Configuration Guide](CONFIGURATION.md)
- [API Reference](API.md)
- [Backup Guide](BACKUP.md)