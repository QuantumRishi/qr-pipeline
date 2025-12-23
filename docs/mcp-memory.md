# MCP Server & Memory Binding

Guide for setting up Model Context Protocol (MCP) server for persistent agent memory.

## Overview

The MCP server provides:
- **Persistent Context**: Long-term architecture decisions and patterns
- **Semantic Search**: Find relevant context from past work
- **Knowledge Graph**: Relationships between components
- **Agent Memory**: Shared context for Copilot Agents

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    MCP Memory Server                      │
├─────────────────────────────────────────────────────────┤
│  Tools:                                                   │
│  - recall: Search past decisions and context              │
│  - store: Save new decisions and learnings                │
│  - relate: Link entities in knowledge graph               │
├─────────────────────────────────────────────────────────┤
│  Storage:                                                 │
│  - Vector DB (embeddings for semantic search)             │
│  - SQLite (structured metadata)                           │
│  - File index (repo content hashes)                       │
└─────────────────────────────────────────────────────────┘
```

## Indexed Content

### qr.dev (Orchestrator)
- Architecture Decision Records (ADRs)
- Package interfaces and APIs
- Agent configurations
- Monorepo structure

### qr-db (Database)
- Migration history and schema changes
- RLS policy patterns
- Vault secret paths
- Service configurations

### qr-mail (Email)
- MTA configuration patterns
- Template structure
- DNS requirements
- Security policies

### qr-pipeline (CI/CD)
- Reusable workflow patterns
- Action SHA references
- Secret schemas
- Deployment patterns

## Configuration

### VS Code Settings

```json
{
  "github.copilot.chat.mcp.enabled": true,
  "github.copilot.chat.mcp.servers": {
    "qr-memory": {
      "command": "npx",
      "args": ["-y", "@qr/mcp-memory-server"],
      "env": {
        "QR_MEMORY_PATH": "${workspaceFolder}/.qr-memory",
        "QR_ORG": "QuantumRishi"
      }
    }
  }
}
```

### MCP Server Implementation

```typescript
// packages/mcp-memory-server/src/index.ts
import { Server } from '@modelcontextprotocol/sdk/server';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio';

const server = new Server({
  name: 'qr-memory',
  version: '0.1.0',
});

// Register tools
server.tool('recall', {
  description: 'Search past decisions and architecture context',
  parameters: {
    query: { type: 'string', description: 'Search query' },
    scope: { type: 'string', enum: ['adr', 'schema', 'workflow', 'all'] },
  },
  handler: async ({ query, scope }) => {
    // Semantic search implementation
  },
});

server.tool('store', {
  description: 'Save a new decision or learning',
  parameters: {
    type: { type: 'string', enum: ['adr', 'pattern', 'decision'] },
    title: { type: 'string' },
    content: { type: 'string' },
    tags: { type: 'array', items: { type: 'string' } },
  },
  handler: async ({ type, title, content, tags }) => {
    // Store in vector DB + SQLite
  },
});

// Start server
new StdioServerTransport(server).listen();
```

## ADR Discipline

### When to Create ADR

- New architectural patterns
- Technology choices
- Breaking changes
- Security policies
- Integration decisions

### ADR Template

```markdown
# ADR-NNNN: Title

## Status
Proposed | Accepted | Deprecated | Superseded

## Context
What is the issue that we're seeing?

## Decision
What is the change that we're proposing?

## Consequences
What becomes easier or harder?

## References
- Related ADRs
- External documentation
```

### Location

- Each repo: `docs/adr/NNNN-title.md`
- Centralized index: `qr.dev/docs/adr/`

## Usage Examples

### Recall Past Decisions

```
Agent: "Before implementing auth, let me check our past decisions..."

[Uses MCP recall tool]
Query: "authentication JWT RBAC"
Scope: "adr"

Results:
- ADR-0001: Foundation architecture (JWT with jose, RBAC middleware)
- ADR-0003: Multi-tenant isolation (RLS policies)
```

### Store New Learning

```
Agent: "This pattern worked well, I should record it..."

[Uses MCP store tool]
Type: "pattern"
Title: "Worker rate limiting"
Content: "Use sliding window with CF Durable Objects..."
Tags: ["cloudflare", "rate-limiting", "workers"]
```

## Maintenance

### Index Refresh

```bash
# Refresh index for all repos
npx @qr/mcp-memory-server index --org QuantumRishi

# Refresh specific repo
npx @qr/mcp-memory-server index --repo qr.dev
```

### Prune Old Context

```bash
# Remove context older than 90 days (except ADRs)
npx @qr/mcp-memory-server prune --days 90 --preserve adr
```
