# httpz-vary

Vary header middleware for [httpz](https://github.com/karlseguin/http.zig).

Ensures caches store separate entries for responses that differ by request headers — content negotiation, encoding, language, or any custom header.

## Quickstart

```bash
git clone git@github.com:erwagasore/httpz-vary.git
cd httpz-vary
zig build              # build library + example
zig build test         # run unit tests
zig build run          # run example server on :8080
```

### As a dependency

Add to `build.zig.zon`:

```zig
.httpz_vary = .{
    .url = "git+https://github.com/erwagasore/httpz-vary#v0.1.0",
    .hash = "...",
},
```

Add to `build.zig`:

```zig
const httpz_vary = b.dependency("httpz_vary", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("httpz_vary", httpz_vary.module("httpz_vary"));
```

## Usage

```zig
const std = @import("std");
const httpz = @import("httpz");
const Vary = @import("httpz_vary");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try httpz.Server(void).init(allocator, .{ .port = 8080 }, {});
    defer server.deinit();
    defer server.stop();

    const vary = try server.middleware(Vary, .{
        .headers = &.{"Accept"},
    });

    var router = try server.router(.{ .middlewares = &.{vary} });
    router.get("/", handleIndex, .{});

    try server.listen();
}
```

## Configuration

```zig
// Content negotiation
const vary = try server.middleware(Vary, .{
    .headers = &.{"Accept"},
});

// Multiple headers
const vary = try server.middleware(Vary, .{
    .headers = &.{ "Accept", "Accept-Encoding", "Accept-Language" },
});

// HTMX partial vs full-page responses
const vary = try server.middleware(Vary, .{
    .headers = &.{"HX-Request"},
});

// Wildcard (disables caching)
const vary = try server.middleware(Vary, .{
    .headers = &.{"*"},
});
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `headers` | `[]const []const u8` | *(required)* | Request header names to include in the Vary response header |

## Why this matters

Without a `Vary` header, a cache may serve the wrong response variant:

```
  ✗ Without Vary                        ✓ With Vary: Accept

  API client                             API client
    GET /data  ──► Cache MISS ──► Server   GET /data  ──► Cache MISS ──► Server
    Accept: application/json               Accept: application/json
               ◄── {"items": [...]}                   ◄── {"items": [...]}
                   cache stores                            cache stores under
                                                           /data + Accept=json

  Browser                                Browser
    GET /data  ──► Cache HIT               GET /data  ──► Cache MISS ──► Server
    Accept: text/html                      Accept: text/html
               ◄── {"items": [...]}                   ◄── <html>...</html>
                                                           cache stores under
    ✗ Browser renders raw JSON                             /data + Accept=html

                                           ✓ Correct variant every time
```

### Request flow

```
                  ┌────────────────────────────────────┐
                  │            httpz Server             │
                  │                                    │
  Request ────────┤► ┌──────────┐   ┌────────┐        │
  GET /data       │  │   Vary   │──►│Handler │        │
  Accept: json    │  │Middleware│   │  fn()  │        │
                  │  └──────────┘   └───┬────┘        │
                  │    Sets header:      Sets body:    │
                  │    Vary: Accept      {"items":[]}  │
                  │         │                │         │
  Response ◄──────┤─────────┴────────────────┘         │
  Vary: Accept    │                                    │
  {"items": []}   └────────────────────────────────────┘
```

## Design

See [DESIGN.md](DESIGN.md) for sequence diagrams of the caching bug and fix,
design decisions, and rejected alternatives.

## Structure

```
httpz-vary/
├── src/root.zig              # Middleware implementation + tests
├── examples/basic_server.zig # Content negotiation demo
├── build.zig                 # Build configuration
├── build.zig.zon             # Package manifest
├── DESIGN.md                 # Architecture and design decisions
├── LICENSE                   # MIT
└── README.md
```

## License

MIT
