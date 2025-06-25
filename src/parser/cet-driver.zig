const std = @import("std");
const DynLib = std.DynLib;

const Clang = @import("clang.zig");

const Options = @import("options.zig");


const OptionsParser = Options.makeOptions(.{
	.{ "path", ?[:0]const u8, null, 'p', "path" },
	.{ "print-invocations", bool, false, 0, "print out all the invoked commands" },
	//.{ "dump", bool, false, 0, "dump tree in clang"},
});

pub fn main() !u8
{
	try Clang.initialize();

	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();
	defer {
		const deinit_status = gpa.deinit();
		if (deinit_status == .leak) @panic("LEAK");
	}

	const options = try OptionsParser.parse( allocator );
	defer options.deinit();

	const path: [:0]const u8 = options.get( .path ) orelse {
		_ = try std.io.getStdErr().write( "failed to get path\n" );
		return 1;
	};
	var err : [*c]const u8 = undefined;
	
	const db = Clang.parseDB( path.ptr, &err ) orelse {
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
		const child_output = try rewriteOutputPath( allocator, cmd.output[0..std.mem.len(cmd.output)]);
		defer allocator.free( child_output );

		const child_args = try rewriteOrAppendOutput( allocator, child_args_c, child_output );
		defer allocator.free( child_args );

		if (options.get( .@"print-invocations" ) ) try printInvocation( child_args );

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

fn printInvocation( args: [][]const u8 ) !void
{

	var bw = std.io.bufferedWriter( std.io.getStdOut().writer() );
	const writer = bw.writer();

	for( args ) |a|
	{
		try writer.print("{s} ", .{a});
	}

	try writer.writeByte( '\n' );
	try bw.flush();
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


fn rewriteOutputPath( allocator: std.mem.Allocator, c_output: []const u8 ) ![]const u8
{
	const ext = std.fs.path.extension( c_output );
	const new_ext = ".cetobj";
	const name_no_ext = c_output[0..c_output.len-ext.len];
	const out = try allocator.alloc( u8, name_no_ext.len + new_ext.len);
	@memcpy( out[0..name_no_ext.len], name_no_ext );
	@memcpy( out[name_no_ext.len..], new_ext);
	return out;
}

fn rewriteOrAppendOutput( allocator: std.mem.Allocator, c_args: [][*c]const u8, output: []const u8 ) ![][]const u8
{
	var idx : ?usize = null;
	var desired_size: usize = c_args.len + 2; 
	for (c_args, 0..) |a,i| {
		if (std.mem.orderZ(u8, "-o", a) != .eq) continue;
		if ( c_args.len <= i+1 ) unreachable; // TODO: handle this case

		// TODO: check that the arg after "-o" is valid
		idx = i+1;
		desired_size = c_args.len;
		break;	
	}

	const extra_args = [_][]const u8{"--driver-mode=g++"};

	const prepend_len = extra_args.len;
	const args = try allocator.alloc( []const u8, desired_size + prepend_len );

	// arg0
	args[0] = c_args[0][0..std.mem.len(c_args[0])];

	@memcpy( args[1..prepend_len+1], &extra_args );

	for (args[1+prepend_len..c_args.len+prepend_len],c_args[1..]) |*dst,src|
	{
		dst.* = src[0..std.mem.len(src)];
	}

	if (idx) |i| {
		args[i+prepend_len] = output;
	} else {
		args[c_args.len+prepend_len] = "-o";
		args[c_args.len+prepend_len+1] = output;
	}

	return args;
}
