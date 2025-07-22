const Clang = @import("clang.zig");
const std = @import("std");
const Options = @import("options.zig");

const ObjFile = @import("objfile.zig");

const OptionsParser = Options.makeOptions(.{
    .{ "dump", bool, false, 0, "dump tree in clang" },
});

pub fn main() !u8 {
    try Clang.initialize();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("LEAK");
    }

    const base_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, base_args);

	// weird bit to force slice value type to const, is this even legal? why can't it just them be const?
	const const_base_args = @as( [*][:0]const u8, @ptrCast( base_args.ptr ) )[0..base_args.len];
    const parsed_options = shouldParseOptions( const_base_args );
    const options = if (parsed_options) try OptionsParser.parseFromSlice(allocator, const_base_args ) else null;
    defer if (options) |o| o.deinit();

    const args = if (options) |o| o.args else const_base_args;

    const outputPath = getOutputPath(args) orelse {
        _ = try std.io.getStdOut().write("no output file specified\n");
        return 1;
    };

    const args_c: [][*c]const u8 = try cifyArgs(allocator, args);
    defer allocator.free(args_c);

    if (options) |o| {
        if (o.get(.dump)) {
            Clang.dumpFromArgs(args_c);
            return 0;
        }
    }

    var recorder: Recorder = .{ .allocator = allocator, .stringarena = StringArena.init(), .linknames = StringArena.init() };
    defer recorder.deinit();

    Clang.parseFromArgs(&recorder, args_c);

    var writer = try ObjFile.Writer.open(outputPath);
    const header = ObjFile.Header{
        .run_id = 0, // TODO: generate this
        .connections_count = recorder.connections.items.len,
        .nodes_count = recorder.nodes.items.len,
        .strings_len = recorder.stringarena.len(),
        .strings_count = recorder.hashtable.size,
		.linklinks_count = @intCast( recorder.linklinks.items.len ),
		.linknames_len = recorder.linknames.len(),
		.linknames_count = recorder.linknamesmap.size
    };
    try writer.writeHeader(header);
    try writer.writeNodes(recorder.nodes.items);
    try writer.writeConnections(recorder.connections.items);
    try writer.writeStrings(recorder.stringarena.data());
	try writer.writeLinkLinks( recorder.linklinks.items );
	try writer.writeLinkNames( recorder.linknames.data() );

    try writer.close();

    return 0;
}

const StringArena = struct {
    start: [*]u8, // start of the whole reserved area
    head: [*]u8, // start of the current free but committed area
    tail: [*]u8, // end of current committed area

    const COMMIT_GRANULARITY: usize = 1024 * 4;
    const RESERVE_GRANULARITY: usize = 1024 * 64;

    pub fn init() StringArena {
        const win = std.os.windows;
        const reserve_size = RESERVE_GRANULARITY * 256;
        const ptr: [*]u8 = @ptrCast(win.VirtualAlloc(null, reserve_size, win.MEM_RESERVE, win.PAGE_NOACCESS) catch @panic("page reserve failed"));
        return .{
            .start = ptr,
            .head = ptr,
            .tail = ptr,
        };
    }

    pub fn add(self: *StringArena, str: []const u8) void {
        const write_len = str.len + 1; // +1 for null terminator
        const ilen: isize = @intCast(write_len);
        const ispace: isize = @intCast(self.tail - self.head);
        const delta: isize = ispace - ilen;

        if (delta < 0) {
            self.expand(@intCast(-delta));
        }

        @memcpy(self.head[0..str.len], str);
        self.head[str.len] = 0;

        self.head += write_len;
    }

    pub fn deinit(self: *StringArena) void {
        const win = std.os.windows;
        win.VirtualFree(self.start, 0, win.MEM_RELEASE);
    }

    pub fn data(self: StringArena) []const u8 {
        return self.start[0..self.len()];
    }

    pub fn len(self: StringArena) usize {
        return self.head - self.start;
    }

    fn expand(self: *StringArena, amount: usize) void {
        const win = std.os.windows;
        const commit_size = std.mem.alignForward(usize, amount, COMMIT_GRANULARITY);

        _ = win.VirtualAlloc(self.tail, commit_size, win.MEM_COMMIT, win.PAGE_READWRITE) catch @panic("allocation failed");
        self.tail += commit_size;
    }
};

const Recorder = struct {
    const HashContext = struct {
        pub fn hash(self: HashContext, a: u64) u64 {
            _ = self;
            return a;
        }

        pub fn eql(self: HashContext, a: u64, b: u64) bool {
            _ = self;
            return a == b;
        }
    };

	const StringHashSet = std.HashMapUnmanaged(u64, void, HashContext, 88);

    allocator: std.mem.Allocator,
    hashtable: StringHashSet = .empty,
    nodes: std.ArrayListUnmanaged(ObjFile.Node) = .empty,
    connections: std.ArrayListUnmanaged(ObjFile.Connection) = .empty,
    stringarena: StringArena,
	linklinks: std.ArrayListUnmanaged( ObjFile.LinkLink ) = .empty,
	linknames: StringArena,
	linknamesmap: StringHashSet = .empty,

    pub fn addNode(self: *Recorder, id: i64, identifier: []const u8) void {
        const hash = std.hash.Wyhash.hash(0, identifier);
        self.nodes.append(self.allocator, .{ .id = id, .string_hash = hash }) catch unreachable;

        const result = self.hashtable.getOrPut(self.allocator, hash) catch unreachable;
        if (!result.found_existing) {
            self.stringarena.add(identifier);
        }
    }

    pub fn addConnection(self: *Recorder, from: i64, to: i64) void {
        self.connections.append(self.allocator, .{ .from = from, .to = to }) catch unreachable;
    }

	pub fn addLinkIdentifier(self: *Recorder, id:i64, identifier: []const u8) void {
		const hash = std.hash.Wyhash.hash(0, identifier);
		self.linklinks.append( self.allocator, .{ .node_id = id, .string_hash = hash }) catch unreachable;

		const result = self.linknamesmap.getOrPut(self.allocator, hash) catch unreachable;
		if (!result.found_existing) {
			self.linknames.add(identifier);
		}
	}

    pub fn deinit(self: *Recorder) void {
        self.hashtable.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
        self.connections.deinit(self.allocator);
        self.stringarena.deinit();
		self.linklinks.deinit( self.allocator );
		self.linknames.deinit();
		self.linknamesmap.deinit( self.allocator );
    }
};

fn getOutputPath(args: [][:0]const u8) ?[]const u8 {
    for (args, 0..) |a, i| {
        if (!std.mem.eql(u8, "-o", a)) continue;
        if (args.len <= i + 1) return null;
        return args[i + 1];
    }
    return null;
}

fn shouldParseOptions(args: [][:0]const u8) bool {
    for (args) |a| {
        if (std.mem.eql(u8, a, "--")) {
            return true;
        }
    }
    return false;
}

fn cifyArgs(allocator: std.mem.Allocator, args: [][:0]const u8) ![][*c]const u8 {
    const args_c = try allocator.alloc([*c]const u8, args.len);
    for (args, args_c) |src, *dst| {
        dst.* = src.ptr;
    }

    return args_c;
}
