//! Vary header middleware for httpz.
//!
//! Automatically sets the `Vary` response header so caches can distinguish
//! responses that differ by request headers (e.g. content negotiation,
//! encoding, language, or framework-specific headers like `HX-Request`).
//!
//! ## Usage
//!
//! ```zig
//! const Vary = @import("httpz_vary");
//!
//! const vary = try server.middleware(Vary, .{
//!     .headers = &.{"Accept"},
//! });
//! ```

const std = @import("std");
const httpz = @import("httpz");

const Vary = @This();
const vary_header = "Vary";
const separator = ", ";
const wildcard = "*";

/// Configuration errors detected before any middleware state is allocated.
pub const ConfigError = error{
    EmptyHeaders,
    EmptyHeaderName,
    InvalidHeaderName,
    DuplicateHeaderName,
    WildcardMustBeAlone,
};

/// Errors returned by init. Configuration errors are deterministic; OutOfMemory
/// can occur while copying the final header value into httpz's server arena.
pub const InitError = ConfigError || std.mem.Allocator.Error;

/// Configuration for the Vary middleware.
pub const Config = struct {
    /// Request header names to include in the Vary response header.
    /// Must contain at least one entry.
    ///
    /// Set to `&.{"*"}` to indicate the response varies on everything
    /// (effectively disabling caching — use sparingly).
    headers: []const []const u8,
};

/// Pre-computed Vary header value, built at init time.
vary_value: []const u8,

/// Initialise the middleware. Validates configuration and pre-computes the
/// Vary header value so execute() has zero allocation overhead.
pub fn init(config: Config, mc: httpz.MiddlewareConfig) InitError!Vary {
    try validateHeaders(config.headers);

    if (std.mem.eql(u8, config.headers[0], wildcard)) {
        return .{ .vary_value = wildcard };
    }

    // Copy into httpz's server arena so the middleware owns the bytes for the
    // server lifetime, even if config.headers came from temporary storage.
    return .{ .vary_value = try std.mem.join(mc.arena, separator, config.headers) };
}

/// Required by httpz middleware interface. Nothing to clean up —
/// the pre-computed value lives in the server arena.
pub fn deinit(_: *Vary) void {}

/// Middleware execution — called by httpz for each request.
///
/// Sets the `Vary` response header with the configured header names.
/// Per RFC 7230 §3.2.2, multiple headers with the same field name are
/// valid and recipients combine them, so this simply adds its own `Vary`
/// entry without inspecting or merging with existing values.
pub fn execute(self: *const Vary, _: *httpz.Request, res: *httpz.Response, executor: anytype) !void {
    res.header(vary_header, self.vary_value);
    return executor.next();
}

fn validateHeaders(headers: []const []const u8) ConfigError!void {
    if (headers.len == 0) return error.EmptyHeaders;

    for (headers, 0..) |header, i| {
        if (std.mem.eql(u8, header, wildcard)) {
            if (headers.len != 1) return error.WildcardMustBeAlone;
            return;
        }

        try validateHeaderName(header);

        for (headers[0..i]) |previous| {
            if (std.ascii.eqlIgnoreCase(header, previous)) {
                return error.DuplicateHeaderName;
            }
        }
    }
}

fn validateHeaderName(header: []const u8) ConfigError!void {
    if (header.len == 0) return error.EmptyHeaderName;

    for (header) |c| {
        if (!isTokenChar(c)) return error.InvalidHeaderName;
    }
}

fn isTokenChar(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9' => true,
        '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => true,
        else => false,
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

/// MiddlewareConfig with undefined arena — used for code paths that must
/// never allocate (error cases, wildcard). Any accidental arena access
/// will crash immediately, acting as an assertion.
const no_alloc_mc: httpz.MiddlewareConfig = .{ .arena = undefined, .allocator = undefined };

/// Test helper: creates a MiddlewareConfig backed by a test arena.
const TestMc = struct {
    arena: std.heap.ArenaAllocator,

    fn init() TestMc {
        return .{ .arena = std.heap.ArenaAllocator.init(testing.allocator) };
    }
    fn mc(self: *TestMc) httpz.MiddlewareConfig {
        return .{ .arena = self.arena.allocator(), .allocator = testing.allocator };
    }
    fn deinit(self: *TestMc) void {
        self.arena.deinit();
    }
};

fn initHt() httpz.testing.Testing {
    return httpz.testing.init(.{});
}

const NoopExecutor = struct {
    called: bool = false,
    pub fn next(self: *NoopExecutor) !void {
        self.called = true;
    }
};

const FailingExecutor = struct {
    pub fn next(_: *FailingExecutor) !void {
        return error.HandlerFailed;
    }
};

// -- init validation ---------------------------------------------------------

test "init: single header" {
    var tmc = TestMc.init();
    defer tmc.deinit();

    const headers = [_][]const u8{"Accept"};
    const mw = try @This().init(.{ .headers = &headers }, tmc.mc());
    try testing.expectEqualStrings("Accept", mw.vary_value);
}

test "init: multiple headers joined with comma-space" {
    var tmc = TestMc.init();
    defer tmc.deinit();

    const headers = [_][]const u8{ "Accept", "Accept-Encoding", "Accept-Language" };
    const mw = try @This().init(.{ .headers = &headers }, tmc.mc());
    try testing.expectEqualStrings("Accept, Accept-Encoding, Accept-Language", mw.vary_value);
}

test "init: wildcard alone is valid" {
    const headers = [_][]const u8{"*"};
    const mw = try @This().init(.{ .headers = &headers }, no_alloc_mc);
    try testing.expectEqualStrings("*", mw.vary_value);
}

test "init: wildcard with other headers is rejected (wildcard first)" {
    const headers = [_][]const u8{ "*", "Accept" };
    try testing.expectError(error.WildcardMustBeAlone, @This().init(.{ .headers = &headers }, no_alloc_mc));
}

test "init: wildcard with other headers is rejected (wildcard last)" {
    const headers = [_][]const u8{ "Accept", "*" };
    try testing.expectError(error.WildcardMustBeAlone, @This().init(.{ .headers = &headers }, no_alloc_mc));
}

test "init: empty headers slice is rejected" {
    const headers = [_][]const u8{};
    try testing.expectError(error.EmptyHeaders, @This().init(.{ .headers = &headers }, no_alloc_mc));
}

test "init: single empty header name is rejected" {
    const headers = [_][]const u8{""};
    try testing.expectError(error.EmptyHeaderName, @This().init(.{ .headers = &headers }, no_alloc_mc));
}

test "init: empty header name among others is rejected" {
    const headers = [_][]const u8{ "Accept", "" };
    try testing.expectError(error.EmptyHeaderName, @This().init(.{ .headers = &headers }, no_alloc_mc));
}

test "init: duplicate header names are rejected" {
    const headers = [_][]const u8{ "Accept", "Accept" };
    try testing.expectError(error.DuplicateHeaderName, @This().init(.{ .headers = &headers }, no_alloc_mc));
}

test "init: duplicate header names are rejected case-insensitively" {
    const headers = [_][]const u8{ "Accept", "accept" };
    try testing.expectError(error.DuplicateHeaderName, @This().init(.{ .headers = &headers }, no_alloc_mc));
}

test "init: invalid header name is rejected" {
    const headers = [_][]const u8{"Accept Language"};
    try testing.expectError(error.InvalidHeaderName, @This().init(.{ .headers = &headers }, no_alloc_mc));
}

test "init: valid HTTP token characters are accepted" {
    var tmc = TestMc.init();
    defer tmc.deinit();

    const headers = [_][]const u8{"X-Token_123~"};
    const mw = try @This().init(.{ .headers = &headers }, tmc.mc());
    try testing.expectEqualStrings("X-Token_123~", mw.vary_value);
}

test "init: configured header casing is preserved" {
    var tmc = TestMc.init();
    defer tmc.deinit();

    const headers = [_][]const u8{"HX-Request"};
    const mw = try @This().init(.{ .headers = &headers }, tmc.mc());
    try testing.expectEqualStrings("HX-Request", mw.vary_value);
}

test "init: header values are copied into the middleware arena" {
    var tmc = TestMc.init();
    defer tmc.deinit();

    var header = [_]u8{ 'A', 'c', 'c', 'e', 'p', 't' };
    const headers = [_][]const u8{header[0..]};
    const mw = try @This().init(.{ .headers = &headers }, tmc.mc());

    @memcpy(header[0..], "Cookie");
    try testing.expectEqualStrings("Accept", mw.vary_value);
}

// -- Middleware integration --------------------------------------------------

test "middleware: sets Vary header" {
    var ht = initHt();
    defer ht.deinit();
    ht.url("/");

    var tmc = TestMc.init();
    defer tmc.deinit();

    const headers = [_][]const u8{"Accept-Encoding"};
    const mw = try @This().init(.{ .headers = &headers }, tmc.mc());
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    try testing.expect(exec.called);
    try testing.expectEqualStrings("Accept-Encoding", ht.res.headers.get("Vary").?);
}

test "middleware: sets Vary with multiple headers" {
    var ht = initHt();
    defer ht.deinit();
    ht.url("/");

    var tmc = TestMc.init();
    defer tmc.deinit();

    const headers = [_][]const u8{ "Accept", "Accept-Language" };
    const mw = try @This().init(.{ .headers = &headers }, tmc.mc());
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    try testing.expect(exec.called);
    try testing.expectEqualStrings("Accept, Accept-Language", ht.res.headers.get("Vary").?);
}

test "middleware: wildcard sets Vary to *" {
    var ht = initHt();
    defer ht.deinit();
    ht.url("/");

    const wildcard_headers = [_][]const u8{"*"};
    const mw = try @This().init(.{ .headers = &wildcard_headers }, no_alloc_mc);
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    try testing.expect(exec.called);
    try testing.expectEqualStrings("*", ht.res.headers.get("Vary").?);
}

test "middleware: calls executor.next()" {
    var ht = initHt();
    defer ht.deinit();
    ht.url("/");

    var tmc = TestMc.init();
    defer tmc.deinit();

    const headers = [_][]const u8{"Accept"};
    const mw = try @This().init(.{ .headers = &headers }, tmc.mc());
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    try testing.expect(exec.called);
}

test "middleware: handler error propagates and Vary is still set" {
    var ht = initHt();
    defer ht.deinit();
    ht.url("/");

    var tmc = TestMc.init();
    defer tmc.deinit();

    const headers = [_][]const u8{"Accept"};
    const mw = try @This().init(.{ .headers = &headers }, tmc.mc());
    var exec = FailingExecutor{};
    const result = mw.execute(ht.req, ht.res, &exec);

    try testing.expectError(error.HandlerFailed, result);
    try testing.expectEqualStrings("Accept", ht.res.headers.get("Vary").?);
}

test "middleware: works with all HTTP methods" {
    var tmc = TestMc.init();
    defer tmc.deinit();
    const headers = [_][]const u8{"Accept"};
    const mw = try @This().init(.{ .headers = &headers }, tmc.mc());

    const methods = [_]httpz.Method{ .GET, .POST, .PUT, .DELETE, .PATCH, .HEAD, .OPTIONS };
    for (methods) |method| {
        var ht = initHt();
        defer ht.deinit();
        ht.url("/");
        ht.req.method = method;

        var exec = NoopExecutor{};
        try mw.execute(ht.req, ht.res, &exec);

        try testing.expect(exec.called);
        try testing.expectEqualStrings("Accept", ht.res.headers.get("Vary").?);
    }
}

test "middleware: Vary header coexists with other response headers" {
    var ht = initHt();
    defer ht.deinit();
    ht.url("/");
    ht.res.header("X-Custom", "value");

    var tmc = TestMc.init();
    defer tmc.deinit();

    const headers = [_][]const u8{"Accept"};
    const mw = try @This().init(.{ .headers = &headers }, tmc.mc());
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    try testing.expect(exec.called);
    try testing.expectEqualStrings("Accept", ht.res.headers.get("Vary").?);
    try testing.expectEqualStrings("value", ht.res.headers.get("X-Custom").?);
}

test "middleware: response status is untouched" {
    var ht = initHt();
    defer ht.deinit();
    ht.url("/");
    ht.res.status = 404;

    var tmc = TestMc.init();
    defer tmc.deinit();

    const headers = [_][]const u8{"Accept"};
    const mw = try @This().init(.{ .headers = &headers }, tmc.mc());
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    try testing.expect(exec.called);
    try testing.expectEqual(@as(u16, 404), ht.res.status);
    try testing.expectEqualStrings("Accept", ht.res.headers.get("Vary").?);
}
