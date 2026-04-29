# Changelog

## [1.0.0] — 2026-04-29

### Breaking Changes

- Upgrade the package to Zig 0.16.x and the Zig 0.16-compatible httpz API.

### Features

- Adopt Zig 0.16 `std.process.Init`, `init.gpa`, and `init.io` in examples and documentation.
- Expose explicit `ConfigError` and `InitError` sets for clearer middleware initialization errors.
- Validate configured Vary header names as HTTP field-name tokens and reject duplicate names case-insensitively.

### Other

- Preserve server-lifetime ownership of the precomputed `Vary` value in httpz's middleware arena.
- Update build step style, documentation, design notes, and changelog.

## [0.1.0] — 2026-02-27

### Features

- Vary header middleware for httpz with zero per-request allocation
- Pre-computed header value built once at init time
- Wildcard support (`*`) to indicate response varies on everything
- Duplicate header detection and rejection at init
- Case-insensitive header name handling
- Basic content negotiation example server

### Other

- Add DESIGN.md with problem statement, sequence diagrams, and design decisions
- Add README with usage, configuration examples, and caching diagrams
- Add AGENTS.md with repo conventions for humans and AI
- Add documentation index
