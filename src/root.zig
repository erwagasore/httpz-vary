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
pub fn init(config: Config, mc: httpz.MiddlewareConfig) !@This() {
    if (config.headers.len == 0) return error.EmptyHeaders;

    for (config.headers) |h| {
        if (std.mem.eql(u8, h, "*")) {
            if (config.headers.len != 1) return error.WildcardMustBeAlone;
            return .{ .vary_value = "*" };
        }
        if (h.len == 0) return error.EmptyHeaderName;
    }

    return .{ .vary_value = try std.mem.join(mc.arena, ", ", config.headers) };
}

/// Required by httpz middleware interface. Nothing to clean up —
/// the pre-computed value lives in the server arena.
pub fn deinit(_: *@This()) void {}

/// Middleware execution — called by httpz for each request.
///
/// Sets the `Vary` response header with the configured header names.
/// Per RFC 7230 §3.2.2, multiple headers with the same field name are
/// valid and recipients combine them, so this simply adds its own `Vary`
/// entry without inspecting or merging with existing values.
pub fn execute(self: *const @This(), _: *httpz.Request, res: *httpz.Response, executor: anytype) !void {
    res.header("Vary", self.vary_value);
    return executor.next();
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
