#!/bin/bash
# MCP Configuration Generator Script
# Usage: ./mcp-config-generator.sh [--transport stdio|sse] [--output file]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
TRANSPORT="stdio"
OUTPUT_FILE=""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_help() {
    echo "MCP Configuration Generator"
    echo "=========================="
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --transport TYPE    Transport type: stdio or sse (default: stdio)"
    echo "  --output FILE       Output file path (default: print to stdout)"
    echo "  --group-id ID       MCP group ID (default: from .env file)"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Generate stdio config to stdout"
    echo "  $0 --transport sse                   # Generate SSE config to stdout"
    echo "  $0 --output ~/.claude/mcp.json       # Save stdio config to Claude"
    echo "  $0 --transport sse --output config.json  # Save SSE config to file"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --transport)
            TRANSPORT="$2"
            if [[ "$TRANSPORT" != "stdio" && "$TRANSPORT" != "sse" ]]; then
                echo "Error: Transport must be 'stdio' or 'sse'"
                exit 1
            fi
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --group-id)
            MCP_GROUP_ID_OVERRIDE="$2"
            shift 2
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

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$PROJECT_DIR/.env"
    set +a
fi

# Use override if provided
if [ -n "$MCP_GROUP_ID_OVERRIDE" ]; then
    MCP_GROUP_ID="$MCP_GROUP_ID_OVERRIDE"
fi

# Set defaults
NEO4J_URI=${NEO4J_URI:-bolt://localhost:7687}
NEO4J_USER=${NEO4J_USER:-neo4j}
NEO4J_PASSWORD=${NEO4J_PASSWORD:-password123}
MCP_GROUP_ID=${MCP_GROUP_ID:-default}
MODEL_NAME=${MODEL_NAME:-gpt-4o-mini}
MCP_HTTP_URL=${MCP_HTTP_URL:-http://localhost:8000}

# Validate required variables
if [ -z "$OPENAI_API_KEY" ] || [ "$OPENAI_API_KEY" = "sk-your-api-key-here" ]; then
    echo -e "${YELLOW}Warning: OPENAI_API_KEY not set or using placeholder value${NC}" >&2
    echo "Please update your .env file with a valid OpenAI API key" >&2
fi

# Generate configuration based on transport type
generate_config() {
    if [ "$TRANSPORT" = "stdio" ]; then
        cat << EOF
{
  "mcpServers": {
    "graphiti": {
      "command": "docker",
      "args": [
        "exec", "-i", "graphiti-mcp",
        "uv", "run", "graphiti_mcp_server.py",
        "--transport", "stdio",
        "--group-id", "$MCP_GROUP_ID"
      ],
      "env": {
        "NEO4J_URI": "$NEO4J_URI",
        "NEO4J_USER": "$NEO4J_USER",
        "NEO4J_PASSWORD": "$NEO4J_PASSWORD",
        "OPENAI_API_KEY": "$OPENAI_API_KEY",
        "MODEL_NAME": "$MODEL_NAME"
      }
    }
  }
}
EOF
    else
        cat << EOF
{
  "mcpServers": {
    "graphiti": {
      "url": "$MCP_HTTP_URL/sse"
    }
  }
}
EOF
    fi
}

# Generate and output configuration
config_content=$(generate_config)

if [ -n "$OUTPUT_FILE" ]; then
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    
    # Write to file
    echo "$config_content" > "$OUTPUT_FILE"
    echo -e "${GREEN}MCP configuration written to: $OUTPUT_FILE${NC}" >&2
    echo -e "${BLUE}Transport: $TRANSPORT${NC}" >&2
    echo -e "${BLUE}Group ID: $MCP_GROUP_ID${NC}" >&2
    
    # Show client-specific instructions
    case "$OUTPUT_FILE" in
        *claude*)
            echo "" >&2
            echo -e "${BLUE}Instructions for Claude Desktop:${NC}" >&2
            echo "1. Restart Claude Desktop" >&2
            echo "2. The Graphiti MCP server should appear in your tools" >&2
            ;;
        *cursor*)
            echo "" >&2
            echo -e "${BLUE}Instructions for Cursor:${NC}" >&2
            echo "1. Restart Cursor" >&2
            echo "2. The Graphiti MCP server should be available" >&2
            ;;
    esac
else
    # Output to stdout
    echo "$config_content"
fi