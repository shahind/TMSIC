# Using TMSIC with an AI assistant

The folder `skills/tmsic` is a skill: instructions that teach an AI assistant how to set up and use TMSIC, so that
it writes correct code with the real function names. It follows the open Agent Skills format (a folder with a
`SKILL.md` file), which Claude and OpenAI Codex both read.

| File | Contents |
|---|---|
| `tmsic/SKILL.md` | What TMSIC is, setup, workflow, the core calls, and the rules that avoid errors. |
| `tmsic/references/api.md` | Every public class, property and function in one list. |
| `tmsic/references/recipes.md` | Tested code for common tasks. |
| `chatgpt-instructions.md` | A short version of the instructions for a ChatGPT custom GPT. |
| `../AGENTS.md`, `../CLAUDE.md` | Always-on guidance for coding assistants that work inside this repository. |

## Install

Run these from the toolbox folder in MATLAB. Each command copies the skill folder, so you can also copy it by hand.

```matlab
setup
install_ai_skill('claude')     % Claude Code: ~/.claude/skills/tmsic
install_ai_skill('codex')      % OpenAI Codex: ~/.agents/skills/tmsic
install_ai_skill('zip')        % writes tmsic-skill.zip for Claude.ai
```

| Assistant | How to add the skill |
|---|---|
| **Claude Code** | `install_ai_skill('claude')`, or copy `skills/tmsic` to `~/.claude/skills/tmsic` (all projects) or `.claude/skills/tmsic` inside a project. Claude uses the skill when your request matches its description, or when you type `/tmsic`. Inside this repository, `CLAUDE.md` loads `AGENTS.md` automatically. |
| **Claude.ai and Claude Desktop** | `install_ai_skill('zip')`, then upload `tmsic-skill.zip` in your Claude settings, under Capabilities and Skills (custom skills need a plan that supports them). The zip is also attached to each GitHub release. |
| **OpenAI Codex** | `install_ai_skill('codex')`, or copy `skills/tmsic` to `~/.agents/skills/tmsic` (or `.agents/skills/tmsic` in a project). Restart Codex if the skill does not appear, and invoke it with `$tmsic` or by describing the task. Codex also reads `AGENTS.md`. |
| **ChatGPT** | Create a custom GPT. Paste `chatgpt-instructions.md` into its Instructions, and upload `tmsic/references/api.md`, `tmsic/references/recipes.md` and the pages in `docs/` as Knowledge. ChatGPT cannot run MATLAB, so it writes scripts for you to run. |
| **Other tools** (Cursor, GitHub Copilot, and others) | Point the tool at `AGENTS.md`, or paste `tmsic/SKILL.md` into its rules or custom instructions. |

## Let the assistant run MATLAB

An assistant that can run MATLAB checks its own code, which is much more reliable. MathWorks publishes a
[MATLAB MCP Core Server](https://github.com/matlab/matlab-mcp-core-server) that connects assistants such as Claude
and Codex to your local MATLAB. Install it as its README describes, start the assistant in the toolbox folder, and
the skill tells it to run `setup` and test each script.

## Try it

After installing, ask for something concrete:

> Build a two-zone RC model with a wall, a window and a partition, heat one zone from 08:00 to 18:00, simulate
> three days and plot both zone temperatures.

> Create a district heating system with one gas boiler and two buildings on a trunk. Hold each building at 21 degC
> with a PID on its substation valve, run one week and report the energy balance.

If the assistant invents a function that is not in `references/api.md`, point it to that file.

## Keeping the skill current

The skill describes version 1.x of the toolbox. When you change a public class or function, update
`skills/tmsic/references/api.md` and the recipes in the same commit.
