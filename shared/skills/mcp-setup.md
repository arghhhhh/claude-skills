# MCP Setup Skill

Use this skill when the user wants to add a new MCP server and create a skill file for it.

## Workflow

### Step 1: Add MCP Server to Config

Add the server to the MCP config file (location varies by editor):

```json
{
  "mcpServers": {
    "server-name": {
      "command": "npx",
      "args": ["-y", "@package/mcp-server"]
    }
  }
}
```

### Step 2: Discover Available Tools

```bash
npx mcporter list <server-name> --all-parameters
```

### Step 3: Test Tools & Discover Hidden Requirements

**IMPORTANT**: Always test a few tools before writing the skill file. MCPs often have undocumented requirements.

```bash
npx mcporter call <server>.<simple_tool>
```

**Common issues to watch for:**
- Missing required parameters (like blender's `user_prompt`)
- Parameter name differences from docs
- Authentication errors

### Step 4: Create Skill File

Create `~/.claude/skills/mcp/<server-name>.md` with:
- When to use / trigger conditions
- Full command syntax for each tool (tested, working)
- Common workflows
- Quirks & gotchas discovered during testing

### Step 5: Update CLAUDE.md Router

Add a brief entry to `~/.claude/CLAUDE.md` with trigger phrases pointing to the skill file.
Keep CLAUDE.md entries to 2-3 lines max — all details go in the skill file.

## Maintenance Tips

- **CLAUDE.md**: Max ~50 lines, just triggers/pointers
- **Skill files**: Can be detailed, only loaded when needed
- **Periodic cleanup**: Remove unused MCP entries
