# AGENTS — httpz-vary

Operating rules for humans + AI.

## Workflow

- Never commit to `main`/`master`.
- Always start on a new branch.
- Only push after the user approves.
- Merge via PR.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/).

- fix → patch
- feat → minor
- feat! / BREAKING CHANGE → major
- chore, docs, refactor, test, ci, style, perf → no version change

## Releases

- Semantic versioning.
- Versions derived from Conventional Commits.
- Release performed locally via `/create-release` (no CI required).
- Manifest (if present) is source of truth.
- Tags: vX.Y.Z

## Repo map

```
httpz-vary/
├── src/
│   └── root.zig              — Middleware implementation (Config, init, execute) + 16 tests
├── examples/
│   └── basic_server.zig      — Content negotiation demo server (Accept header)
├── build.zig                  — Build config: library module, example executable, test step
├── build.zig.zon              — Package manifest; httpz dependency pinned to specific commit
├── DESIGN.md                  — Problem statement, sequence diagrams, design decisions, rejected alternatives
├── README.md                  — Usage, configuration examples, caching diagrams
├── AGENTS.md                  — This file — repo conventions for humans + AI
├── LICENSE                    — MIT
└── docs/
    └── index.md               — Documentation index
```

## Merge strategy

- Prefer squash merge.
- PR title must be a valid Conventional Commit.

## Definition of done

- Works locally.
- Tests updated if behaviour changed.
- CHANGELOG updated when user-facing.
- No secrets committed.

## Orientation

- **Entry point**: `src/root.zig` — the entire middleware is a single file.
- **Domain**: Vary HTTP response header middleware for the [httpz](https://github.com/karlseguin/http.zig) web framework.
- **Tech**: Zig 0.15.2, httpz. Zero per-request allocation — header value pre-computed at init.
