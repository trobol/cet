const std = @import("std");
const DynLib = std.DynLib;

const Clang = @import("clang.zig");

const Args = struct {

	name: [:0]const u8,
	path: [:0]const u8,


	fn deinit( self: Args, allocator: std.mem.Allocator ) void
	{
		allocator.free( self.name );
		allocator.free( self.path );
	}
};

fn fetchArgs( allocator: std.mem.Allocator ) !Args
{
	var args = try std.process.argsWithAllocator( allocator );
	defer args.deinit();

	const name = args.next() orelse "";
	const path = args.next() orelse "";

	return .{ 
		.name = try allocator.dupeZ( u8, name ),
		.path = try allocator.dupeZ( u8, path ),
		};
}


fn appendToEnvPath( allocator: std.mem.Allocator, path: []const u8 ) !void
{
	const win = std.os.windows;

	const PATH = @constCast( std.unicode.wtf8ToWtf16LeStringLiteral( "PATH" ).*[0..].ptr );

	const pathu16 = try std.unicode.wtf8ToWtf16LeAllocZ( allocator, path );
	defer allocator.free( pathu16 );

	const null_buf: [0]u16 = undefined;
	const cur_len = try win.GetEnvironmentVariableW( PATH, &null_buf, 0 );
	
	const new_len = cur_len + path.len + 1; // cur_len includes the null term + 1 for a semicolon

	const buf = try allocator.allocSentinel( u16, new_len, 0 );
	defer allocator.free( buf );

	_ = try win.GetEnvironmentVariableW( PATH, buf.ptr, cur_len + 1 );
	


	if ( std.mem.indexOf( u16, buf, pathu16 ) ) |_|
	{
		return;
	}

	buf[cur_len] = ';';
	std.mem.copyForwards( u16, buf[cur_len+1..], pathu16 );

	const formatted = try std.unicode.wtf16LeToWtf8Alloc( allocator, buf );
	defer allocator.free(formatted);
	_ = try std.io.getStdErr().writer().write( formatted );

	_ = win.kernel32.SetEnvironmentVariableW( PATH, buf.ptr );
}


fn getChildExePath( allocator: std.mem.Allocator, name: []const u8 ) ![]const u8
{
	var buf: [std.fs.max_path_bytes]u8 = undefined;
	const self_dir = try std.fs.selfExeDirPath(&buf);

	const paths = [_][]const u8{ self_dir, name }; 
	return std.fs.path.resolve( allocator, &paths );
}

pub fn main() !u8
{
	try Clang.initialize();

	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();
	defer {
		const deinit_status = gpa.deinit();
		if (deinit_status == .leak) @panic("LEAK");
	}

	const args = try std.process.argsAlloc( allocator );
	defer std.process.argsFree( allocator, args );


	const path = args[1];

	if ( args.len < 1 )
	{
		return error.MissingArg;
	}
	var err : [*c]const u8 = undefined;

	
	const db = Clang.parseDB( path, &err ) orelse {
		// FIXME: error message gets duplicated here
		try std.io.getStdErr().writer().print( "failed to parse db: {s}", .{ err } );
		return 1;
	};
	defer db.deinit();

	const s = db.getAllCommands();

	const selfpath = try std.fs.selfExeDirPathAlloc( allocator );
	defer allocator.free( selfpath );

	const cl_path = try getChildExePath( allocator, "cet-cl.exe" );
	defer allocator.free( cl_path );

	for ( s ) |cmd|
	{
		const child_args_c = cmd.argv[0..cmd.argc];
		const child_args = try allocator.alloc( []const u8, child_args_c.len );
		defer allocator.free( child_args );
		
		for (child_args,child_args_c) |*dst,src|
		{
			dst.* = src[0..std.mem.len(src)];
		}
		
		// TODO: should I look at the first arg before rewriting it?
		child_args[0] = cl_path;
		
		const cwd = cmd.directory[ 0..std.mem.len( cmd.directory ) ];

		const dir = try std.fs.openDirAbsolute( cwd, .{} );

		var child = std.process.Child.init( child_args, allocator );
		child.cwd_dir = dir;
		_ = try child.spawn();
		_ = try child.wait();
	}


	return 0;
}

