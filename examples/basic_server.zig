const std = @import("std");
const httpz = @import("httpz");
const Vary = @import("httpz_vary");

const PORT = 8080;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var server = try httpz.Server(void).init(io, allocator, .{ .address = .localhost(PORT) }, {});
    defer server.deinit();
    defer server.stop();

    // Every response gets `Vary: Accept` so caches store separate
    // entries for JSON and HTML clients requesting the same URL.
    const vary = try server.middleware(Vary, .{
        .headers = &.{"Accept"},
    });

    const router = try server.router(.{ .middlewares = &.{vary} });
    router.get("/greeting", getGreeting, .{});

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});
    try server.listen();
}

// ---------------------------------------------------------------------------
// Content negotiation — same URL returns JSON or HTML depending on Accept.
// Without Vary: Accept, a cache could serve the JSON body to a browser or
// the HTML body to an API client.
// ---------------------------------------------------------------------------

fn getGreeting(req: *httpz.Request, res: *httpz.Response) !void {
    if (req.header("accept")) |accept| {
        if (std.ascii.indexOfIgnoreCase(accept, "application/json") != null) {
            res.content_type = .JSON;
            res.body = "{\"message\":\"Hello\"}";
            return;
        }
    }

    res.content_type = .HTML;
    res.body =
        \\<!DOCTYPE html>
        \\<html><body><h1>Hello</h1></body></html>
    ;
}
