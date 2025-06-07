const std = @import("std");
const Allocator = std.mem.Allocator;

const pg = @import("pg");
const zap = @import("zap");

const Level = enum {
    genin,
    chuunin,
    jonin,
    sannin,
    anbu,
    kage,
    forbidden,

    pub fn to_string(self: *Level) []const 8 {
        switch (self) {
            .genin => "GENIN",
            .chuunin => "CHUUNIN",
            .jonin => "JONIN",
            .sannin => "SANNIN",
            .anbu => "ANBU",
            .kage => "KAGE",
            .forbidden => "FORBIDDEN",
        }
    }

    /// decided to not use std.meta.stringToEnum because it returns an optional
    /// and I didn't dig to get case sensitivity
    pub fn from_string(string: []const u8) Level {
        if (std.mem.eql(u8, "GENIN", string))
            return .genin;
        if (std.mem.eql(u8, "CHUUNIN", string))
            return .chuunin;
        if (std.mem.eql(u8, "JONIN", string))
            return .jonin;
        if (std.mem.eql(u8, "SANNIN", string))
            return .sannin;
        if (std.mem.eql(u8, "ANBU", string))
            return .anbu;
        if (std.mem.eql(u8, "KAGE", string))
            return .kage;
        if (std.mem.eql(u8, "FORBIDDEN", string))
            return .forbidden;

        @panic("unknown rank");
    }
};

const Scroll = struct {
    id: u32,
    rank: Level,
    jutsu: []const u8,
    usage: []const u8,
};

const ScrollRequest = struct {
    rank: []const u8,
    jutsu: []const u8,
    usage: []const u8,
};

// The global Application Context
const MyContext = struct {
    db_connection: *pg.Pool,

    pub fn init(connection_pool: *pg.Pool) MyContext {
        return .{
            .db_connection = connection_pool,
        };
    }
};

const ScrollEndpoint = struct {
    // the slug
    path: []const u8,
    error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

    fn get_bearer_token(r: zap.Request) []const u8 {
        const auth_header = zap.Auth.extractAuthHeader(.Bearer, &r) orelse "Bearer (no token)";
        return auth_header[zap.Auth.AuthScheme.Bearer.str().len..];
    }

    // we use the endpoint, the context, the arena, and try
    pub fn get(_: *ScrollEndpoint, arena: Allocator, context: *MyContext, r: zap.Request) !void {
        // const used_token = get_bearer_token(r);
        if (r.query) |query| {
            // query -> id=8
            // id at 3rd index
            const query_id = query[3];

            const id = try std.fmt.parseInt(i32, &.{query_id}, 10);

            const query_result = try context.db_connection.query("SELECT * FROM scroll WHERE id = $1", .{id});
            defer query_result.deinit();

            var scrolls = std.ArrayList(Scroll).init(arena);

            while (try query_result.next()) |row| {
                const scroll_id = row.get(i32, 0);

                const rank = Level.from_string(row.get([]u8, 1));

                const jutsu = row.get([]u8, 2);

                const usage = row.get([]u8, 3);

                const scroll = Scroll{
                    .id = @bitCast(scroll_id),
                    .rank = rank,
                    .jutsu = jutsu,
                    .usage = usage,
                };

                try scrolls.append(scroll);
            }

            var string = std.ArrayList(u8).init(arena);

            const scrolls_response = try scrolls.toOwnedSlice();

            try std.json.stringify(scrolls_response, .{}, string.writer());

            const s = try string.toOwnedSlice();

            r.setStatus(.ok);
            try r.sendJson(s);
        } else {
            const query_result = try context.db_connection.query("SELECT * FROM scroll", .{});
            defer query_result.deinit();

            var scrolls = std.ArrayList(Scroll).init(arena);

            while (try query_result.next()) |row| {
                const id = row.get(i32, 0);

                const rank = Level.from_string(row.get([]u8, 1));

                const jutsu = row.get([]u8, 2);

                const usage = row.get([]u8, 3);

                const scroll = Scroll{
                    .id = @bitCast(id),
                    .rank = rank,
                    .jutsu = jutsu,
                    .usage = usage,
                };

                try scrolls.append(scroll);
            }

            var string = std.ArrayList(u8).init(arena);

            const scrolls_response = try scrolls.toOwnedSlice();

            try std.json.stringify(scrolls_response, .{}, string.writer());

            const s = try string.toOwnedSlice();

            r.setStatus(.ok);
            try r.setContentType(.JSON);
            try r.sendBody(s);
        }
    }

    pub fn post(_: *ScrollEndpoint, arena: Allocator, context: *MyContext, r: zap.Request) !void {
        // parse body
        const body = r.body orelse return r.setStatus(.bad_request);

        const parsed = try std.json.parseFromSlice(ScrollRequest, arena, body, .{ .ignore_unknown_fields = true });
        const new_scroll = parsed.value;

        // repository
        const query_result = try context.db_connection.query("INSERT INTO scroll (rank, jutsu, usage) VALUES ($1::level, $2, $3)", .{ new_scroll.rank, new_scroll.jutsu, new_scroll.usage });
        defer query_result.deinit();

        r.setStatus(.created);
    }

    pub fn delete(_: *ScrollEndpoint, _: Allocator, context: *MyContext, r: zap.Request) !void {
        const query = r.query orelse return r.setStatus(.bad_request);
        // query -> id=8
        // id at 3rd index
        const query_id = query[3];

        const id = try std.fmt.parseInt(i32, &.{query_id}, 10);

        // repository
        const query_result = try context.db_connection.query("DELETE FROM scroll WHERE id = $1", .{id});
        defer query_result.deinit();

        r.setStatus(.accepted);
    }

    pub fn put(_: *ScrollEndpoint, _: Allocator, _: *MyContext, _: zap.Request) !void {}
    pub fn patch(_: *ScrollEndpoint, _: Allocator, _: *MyContext, _: zap.Request) !void {}
    pub fn options(_: *ScrollEndpoint, _: Allocator, _: *MyContext, _: zap.Request) !void {}
    pub fn head(_: *ScrollEndpoint, _: Allocator, _: *MyContext, _: zap.Request) !void {}
};

pub fn main() !void {
    var debugAllocator: std.heap.DebugAllocator(.{ .stack_trace_frames = 50, .thread_safe = true }) = .init;
    defer std.debug.print("\n\nLeaks detected: {}\n\n", .{debugAllocator.deinit() != .ok});

    const allocator = debugAllocator.allocator();

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const database_url = env_map.get("DATABASE_URL") orelse @panic("DATABASE_URL is not set in the environment");

    const database_uri = std.Uri.parse(database_url) catch @panic("DATABASE_URL is malformed and not a valid URI");

    const port = std.process.parseEnvVarInt("PORT", usize, 10) catch @panic("PORT is not set in the environment");

    var pool = try pg.Pool.initUri(allocator, database_uri, .{ .size = 5, .timeout = 10_000 });
    defer pool.deinit();

    var my_context = MyContext.init(pool);

    // our global app that holds the context
    // App is the type
    // app is the instance
    const App = zap.App.Create(MyContext);

    var app = try App.init(allocator, &my_context, .{});
    defer app.deinit();

    // create mini endpoint
    var ep: ScrollEndpoint = .{
        .path = "/scroll",
    };

    // make the authenticating endpoint known to the app
    try app.register(&ep);

    // listen
    try app.listen(.{
        .interface = "0.0.0.0",
        .port = port,
    });

    std.debug.print(
        \\ listening on port 7000
    , .{});

    // start worker threads
    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}
