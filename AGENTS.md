# TMSIC: guidance for AI coding assistants

TMSIC is a MATLAB toolbox for thermal models of buildings and district heating systems. `+RCBS` builds
resistance-capacitance (RC) building models. `+DHS` assembles a gas plant, a pipe network, substations and
buildings and simulates them with controllers. It is plain MATLAB, with no Simulink.

## Using the toolbox for a user

- Load the skill in `skills/tmsic/SKILL.md` if your tool supports skills. Otherwise read it, then
  `skills/tmsic/references/api.md` and `skills/tmsic/references/recipes.md`.
- Use only calls that exist in the API reference. Do not invent function names or arguments.
- Run `setup` from the toolbox folder before using the packages.
- If you can run MATLAB (for example through the MATLAB MCP server), run your code and check the output. If you
  cannot, write a script and ask the user to run it and report the output.
- Start from `examples/rcbs_tutorial.m`, `examples/dhs_tutorial.m` or `examples/dhs_internal_loop_tutorial.m`.

## Layout

| Path | Contents |
|---|---|
| `+RCBS/` | `Building`, `Storey`, `Zone`, `Part`, `Simulation` |
| `+DHS/` | `System`, `CentralHeatPlant`, `Boiler`, `HydraulicNetwork`, `Building`, `Radiator`, the heat exchangers, `Weather`, `Solar`, `Schedule` |
| `+DHS/+Hydraulic/` | `Pipe`, `Valve`, pumps, `Junction`, `TJunction`, `Link`, `Port` |
| `+DHS/+controllers/` | `Controller`, `PID`, `LQR`, `Relay`, `Callback` |
| `docs/` | One page per part, `examples.md`, `references.md` |
| `examples/`, `tests/`, `validation/` | Example scripts, unit tests, accuracy checks with a report |

## Changing the toolbox

- Run `runtests('tests')` and `run_all_validation` after a change. Both must pass.
- Keep MATLAB comments short: one help block per file (what it does, its call, its units) and a comment only where
  the code is not obvious. Put explanations in `docs/`.
- Keep `docs/` consistent with the code: every public class, property and function appears in its page with the
  same name, and every example in a page runs as written.
- Examples are teaching material. Prefer long names, one call per line and a comment per step over compact code.
- Version 1.x keeps the API of the published paper. Make a breaking change only in a new major version.
