# Design

## Problem

When a server returns different response bodies for the same URL based on
request headers (content negotiation, encoding, language), caches (CDN,
reverse proxy, browser back-forward cache) may serve the wrong variant.
The `Vary` HTTP response header (RFC 7231 §7.1.4) tells caches to store
separate entries per distinct value of the listed request headers.

### The bug without Vary

```
 ┌──────────┐         ┌───────┐         ┌──────────┐
 │API client │         │ Cache │         │  Server  │
 └─────┬────┘         └───┬───┘         └─────┬────┘
       │  GET /data        │                   │
       │  Accept: app/json │                   │
       │──────────────────►│  MISS             │
       │                   │──────────────────►│
       │                   │   200 OK          │
       │                   │◄──────────────────│
       │                   │   {"items":[...]} │
       │  {"items":[...]}  │                   │
       │◄──────────────────│   Cache stores    │
       │         ✓ OK      │   response for    │
       │                   │   GET /data       │
       │                   │                   │
 ┌──────────┐              │                   │
 │ Browser  │              │                   │
 └─────┬────┘              │                   │
       │  GET /data        │                   │
       │  Accept: text/html│                   │
       │──────────────────►│  HIT              │
       │                   │                   │
       │  {"items":[...]}  │  Serves cached    │
       │◄──────────────────│  JSON! ✗          │
       │                   │                   │
       │  ✗ Browser shows  │                   │
       │  raw JSON instead │                   │
       │  of HTML page     │                   │
       ▼                   ▼                   ▼
```

### The fix with Vary: Accept

```
 ┌──────────┐         ┌───────┐         ┌──────────┐
 │API client │         │ Cache │         │  Server  │
 └─────┬────┘         └───┬───┘         └─────┬────┘
       │  GET /data        │                   │
       │  Accept: app/json │                   │
       │──────────────────►│  MISS             │
       │                   │──────────────────►│
       │                   │  200 OK           │
       │                   │  Vary: Accept     │
       │                   │◄──────────────────│
       │  {"items":[...]}  │  {"items":[...]}  │
       │◄──────────────────│                   │
       │         ✓ OK      │  Cache stores     │
       │                   │  under key:       │
       │                   │  /data +          │
       │                   │  Accept=app/json  │
       │                   │                   │
 ┌──────────┐              │                   │
 │ Browser  │              │                   │
 └─────┬────┘              │                   │
       │  GET /data        │                   │
       │  Accept: text/html│                   │
       │──────────────────►│  MISS             │
       │                   │  (different key:  │
       │                   │  /data +          │
       │                   │  Accept=text/html)│
       │                   │──────────────────►│
       │                   │  200 OK           │
       │                   │  Vary: Accept     │
       │                   │◄──────────────────│
       │  <!DOCTYPE html>  │  <html>...</html> │
       │  <html>           │                   │
       │  full page...     │  Cache stores     │
       │◄──────────────────│  under key:       │
       │         ✓ OK      │  /data +          │
       │                   │  Accept=text/html │
       ▼                   ▼                   ▼
```

## Design decisions

### Why set Vary before the handler?

The middleware adds the `Vary` header before calling `executor.next()`.
This ensures the header is present even if the handler errors or returns
early. The Vary header is metadata about the request routing, not about
the response content — it's always correct to include it.

### Why not merge with existing Vary headers?

httpz's response headers are append-only (`StringKeyValue.add`). There is
no API to update or replace an existing header. Per RFC 7231 §7.1.4 and
RFC 7230 §3.2.2, multiple headers with the same field name can be combined
by the recipient. Adding a separate `Vary` entry is HTTP-compliant and
avoids the need for per-request allocation to merge strings.

### Why pre-compute the value?

The header names are static configuration — they don't change per request.
Computing the comma-joined string once in `init()` means `execute()` is
allocation-free and branch-free.

### Why require explicit headers (no default)?

Different applications vary on different headers. Providing a default would
embed a framework-specific assumption (e.g. HTMX's `HX-Request`) into a
general-purpose middleware. Requiring explicit configuration makes the
middleware composable across any use case: content negotiation (`Accept`),
compression (`Accept-Encoding`), i18n (`Accept-Language`), or custom headers.

### Wildcard handling

`Vary: *` indicates the response varies on factors beyond request headers
(RFC 7231 §7.1.4). It effectively disables caching. The middleware validates
that `*` is the sole entry if present — mixing `*` with other header names
is semantically meaningless and likely a configuration error.

```
  .headers = &.{"*"}                ✓  valid — Vary: *
  .headers = &.{"*", "Accept"}     ✗  error: WildcardMustBeAlone
  .headers = &.{}                  ✗  error: EmptyHeaders
  .headers = &.{"Accept", ""}      ✗  error: EmptyHeaderName
```

## Rejected alternatives

- **Per-request Vary computation**: unnecessary overhead for static config.
- **Merging with existing Vary headers at runtime**: would require per-request
  allocation and string manipulation for correctness. Multiple `Vary` headers
  are HTTP-compliant.
- **Default headers**: embeds an opinionated assumption. Explicit is better.
- **Conditional Vary (only when a header is present)**: this defeats the
  purpose. The cache needs to see `Vary` on *every* response for that URL,
  not just the ones where the header happened to be sent.
