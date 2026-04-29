# Changelog

## Unreleased

### Changed

- Require Zig 0.16.x and update the pinned httpz dependency to a Zig 0.16-compatible revision.
- Update the example server to use Zig 0.16's `std.process.Init` entry point and httpz's `init.io`/`.address` server configuration.
- Validate configured header names as HTTP field-name tokens and reject duplicates case-insensitively during initialization.
- Preserve server-lifetime ownership of the pre-computed `Vary` value in httpz's middleware arena.
- Expose explicit `ConfigError` and `InitError` sets for better API ergonomics.
- Make the example's `Accept: application/json` matching case-insensitive.

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
