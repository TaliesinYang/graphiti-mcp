# Graphiti MCP Standalone

A ready-to-deploy Model Context Protocol (MCP) server for Graphiti - a temporally-aware knowledge graph framework designed for AI agents. This standalone version includes automatic backup functionality and easy configuration for production use.

## 🚀 Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/graphiti-mcp-standalone.git
cd graphiti-mcp-standalone

# 2. Configure your environment
cp .env.example .env
# Edit .env with your Neo4j password and OpenAI API key

# 3. Run the setup script
./setup.sh

# 4. Configure your MCP client (Claude, Cursor, etc.)
# Use the generated MCP configuration from config/mcp.json
```

## ✨ Features

- **🧠 Intelligent Knowledge Graph**: Temporally-aware graph storage with entity relationships
- **🔍 Hybrid Search**: Combines semantic embeddings, keyword search (BM25), and graph traversal
- **📚 Multi-format Support**: Text, JSON, and conversation data ingestion
- **🔄 Automatic Backups**: Scheduled backups via Ofelia with configurable retention
- **🐳 Docker-First**: Complete Docker Compose setup with health checks
- **⚡ Smart Retrieval**: Self-learning query expansion and term association
- **🔧 Easy Configuration**: Environment-based configuration with sensible defaults

## 📋 Prerequisites

- Docker and Docker Compose
- OpenAI API key (for LLM operations)
- At least 2GB RAM for Neo4j

## 🛠️ Installation

### Method 1: Quick Setup (Recommended)

```bash
git clone https://github.com/yourusername/graphiti-mcp-standalone.git
cd graphiti-mcp-standalone
./setup.sh
```

### Method 2: Manual Setup

1. **Clone and configure:**
   ```bash
   git clone https://github.com/yourusername/graphiti-mcp-standalone.git
   cd graphiti-mcp-standalone
   cp .env.example .env
   ```

2. **Edit `.env` file:**
   ```env
   NEO4J_PASSWORD=your_secure_password_here
   OPENAI_API_KEY=sk-your-api-key-here
   ```

3. **Start services:**
   ```bash
   docker-compose up -d
   ```

4. **Configure MCP client:**
   Add the configuration from `config/mcp.json` to your client's MCP settings.

## 🔧 Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NEO4J_URI` | `bolt://localhost:7687` | Neo4j connection URI |
| `NEO4J_USER` | `neo4j` | Neo4j username |
| `NEO4J_PASSWORD` | `password123` | Neo4j password (change this!) |
| `OPENAI_API_KEY` | - | OpenAI API key (required) |
| `MODEL_NAME` | `gpt-4o-mini` | OpenAI model for LLM operations |
| `MCP_GROUP_ID` | `default` | Default group ID for organizing data |
| `BACKUP_SCHEDULE` | `0 0 2,10,20 * * *` | Backup schedule (2am, 10am, 8pm daily) |
| `BACKUP_RETENTION_DAYS` | `7` | Days to retain backups |

### MCP Client Configuration

#### Claude Desktop
Add to `~/.claude/mcp.json`:
```json
{
  "mcpServers": {
    "graphiti": {
      "command": "docker",
      "args": [
        "exec", "-i", "graphiti-mcp",
        "uv", "run", "graphiti_mcp_server.py",
        "--transport", "stdio",
        "--group-id", "your-project"
      ]
    }
  }
}
```

#### Cursor (SSE Transport)
Point to: `http://localhost:8000/sse`

## 📊 Available MCP Tools

### Core Operations
- **`add_memory`**: Store episodes (text, JSON, or messages)
- **`search_memory_facts`**: Find relationships between entities
- **`search_memory_nodes`**: Search entity summaries
- **`smart_search_memory`**: Intelligent dual search with learning

### Data Management  
- **`get_episodes`**: Retrieve recent episodes
- **`get_episode_by_uuid`**: Get specific episode
- **`delete_episode`**: Remove episode
- **`clear_graph`**: Reset entire graph

### Advanced Features
- **`get_learning_stats`**: View search learning statistics
- Entity filtering by type (`Preference`, `Procedure`, etc.)
- Group-based data organization

## 💾 Backup & Restore

### Automatic Backups
- **Schedule**: Configurable via `BACKUP_SCHEDULE` (default: 3x daily)
- **Location**: `./backups/backup-YYYYMMDD.dump`
- **Retention**: Automatic cleanup of old backups
- **No Overlap**: Prevents concurrent backup jobs

### Manual Backup
```bash
./scripts/backup.sh
```

### Restore
```bash
./scripts/restore.sh backup-20241201.dump
```

## 📁 Project Structure

```
graphiti-mcp-standalone/
├── README.md                    # This file
├── LICENSE                      # MIT license
├── .env.example                # Environment template
├── docker-compose.yml          # Main Docker config
├── docker-compose.dev.yml      # Development config
├── setup.sh                    # One-click setup script
├── mcp-server/                 # MCP server implementation
│   ├── graphiti_mcp_server.py # Main MCP server
│   ├── smart_retrieval_mcp.py # Smart search module
│   ├── pyproject.toml          # Python dependencies
│   └── Dockerfile              # Container image
├── scripts/                    # Utility scripts
│   ├── backup.sh               # Manual backup
│   ├── restore.sh              # Data restore
│   ├── health-check.sh         # Service health check
│   └── mcp-config-generator.sh # Generate MCP config
├── config/                     # Configuration templates
│   └── mcp.json.template       # MCP client config template
├── docs/                       # Documentation
│   ├── INSTALLATION.md         # Detailed install guide
│   ├── CONFIGURATION.md        # Advanced configuration
│   ├── API.md                  # API reference
│   └── BACKUP.md               # Backup guide
└── backups/                    # Backup storage (auto-created)
```

## 🔍 Usage Examples

### Storing Knowledge
```python
# Add a procedure
add_memory(
    name="Deploy Docker Application", 
    episode_body='''{"type": "procedure", "steps": [
        {"action": "Build image", "command": "docker build -t app ."},
        {"action": "Run container", "command": "docker run -d app"}
    ]}''',
    source="json"
)

# Add preferences
add_memory(
    name="Technology Preferences",
    episode_body="I prefer using Docker for deployment and PostgreSQL for databases",
    source="text"
)
```

### Intelligent Search
```python
# Smart search with learning
smart_search_memory(
    query="Docker deployment procedures",
    learn=True  # Enables query expansion learning
)

# Search specific entity types
search_memory_nodes(
    query="backup procedures",
    entity="Procedure",
    max_nodes=10
)
```

## 📈 Monitoring

### Service Health
```bash
# Check all services
docker-compose ps

# View logs
docker-compose logs -f graphiti-mcp
docker-compose logs -f neo4j

# Neo4j web interface
open http://localhost:7474
```

### Backup Status
```bash
ls -la backups/
./scripts/health-check.sh
```

## 🐛 Troubleshooting

### Common Issues

**Neo4j connection failed:**
- Check if Neo4j is running: `docker-compose ps neo4j`
- Verify credentials in `.env` file
- Check logs: `docker-compose logs neo4j`

**MCP server not responding:**
- Restart MCP service: `docker-compose restart graphiti-mcp`  
- Check environment variables in `.env`
- Verify OpenAI API key is valid

**Backup failed:**
- Check disk space: `df -h`
- Verify backup directory permissions
- Review Ofelia logs: `docker-compose logs ofelia`

### Performance Tuning

For high-volume usage, adjust Neo4j memory settings in `docker-compose.yml`:
```yaml
environment:
  - NEO4J_server_memory_heap_initial__size=1G
  - NEO4J_server_memory_heap_max__size=2G
  - NEO4J_server_memory_pagecache_size=1G
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Graphiti](https://github.com/getzep/graphiti) - The core knowledge graph framework
- [Model Context Protocol](https://modelcontextprotocol.io/) - The protocol specification
- [Neo4j](https://neo4j.com/) - Graph database platform
- [Ofelia](https://github.com/mcuadros/ofelia) - Docker job scheduler

## 📞 Support

- 📖 [Documentation](docs/)
- 🐛 [Issues](https://github.com/yourusername/graphiti-mcp-standalone/issues)
- 💬 [Discussions](https://github.com/yourusername/graphiti-mcp-standalone/discussions)

---

**Quick Start Reminder**: `./setup.sh` → Edit `.env` → Add MCP config → Ready! 🚀