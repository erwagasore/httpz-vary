# Changelog

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
