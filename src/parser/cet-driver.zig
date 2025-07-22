const std = @import("std");
const DynLib = std.DynLib;

const Child = @import("Child.zig");
const Clang = @import("clang.zig");
const Options = @import("options.zig");


const OptionsParser = Options.makeOptions(.{
	.{ "path", ?[:0]const u8, null, 'p', "path" },
	.{ "print-invocations", bool, false, 0, "print out all the invoked commands" },
	.{ "clean", bool, false, 0, "delete all cetobj files that will be written if they exist" },
});

pub fn main() !u8
{
	var global_timer = try std.time.Timer.start();
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

	const instances: usize = 8;
	var pool = try ProcessPool.init( allocator, instances );
	defer pool.deinit( allocator );

	var completed: usize = 0;
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
		
		try pool.add( allocator, child_args, cwd );
		if ( try pool.run() )
		{
			completed += 1;
		}
	}

	while( try pool.finish() ) {}

	const end = global_timer.read();
	_ = end;
	//try std.io.getStdErr().writer().print( "parsing completed in {}s\n", .{ end / std.time.ns_per_s } );

	return 0;
}



const DWORD = std.os.windows.DWORD;
const HANDLE = std.os.windows.HANDLE;
const BOOL = std.os.windows.BOOL;

extern "kernel32" fn PeekNamedPipe( 
  hNamedPipe: HANDLE,
  lpBuffer: ?*anyopaque,
  nBufferSize: DWORD,
  lpBytesRead: ?*DWORD,
  lpTotalBytesAvail: *DWORD,
  lpBytesLeftThisMessage: ?*DWORD
) BOOL;



const ProcessPool = struct {

	const HandlePair = struct {
		id: Child.Id,
		idx: u32
	};

	const HandleList = std.MultiArrayList( HandlePair );

	const Item = struct {
		process: Child,
		id: ?Child.Id,
		next_free: ?u32,

		overlapped: std.os.windows.OVERLAPPED,
		buffer: []u8,

		pipe_read: ?std.fs.File,
		pipe_write: std.fs.File,
	};

	const ItemList = std.MultiArrayList( Item );

	items: ItemList,
	handles: HandleList,
	first_free: ?u32,
	free_count: u32,
	nul_handle: std.fs.File,


	pub fn init( allocator: std.mem.Allocator, len: usize ) !ProcessPool
	{
		const windows = std.os.windows;
		var items = ItemList{};
		try items.resize( allocator, len );

		const s = items.items( .next_free );
		for ( s[0..s.len-1], 0.. ) |*idx, i| {
			idx.* = @as( u32, @intCast(i) ) + 1;
		}
		s[s.len-1] = null;

		for ( items.items( .id ) ) |*id|
		{
			id.* = null; // FIXME: does this work for posix?
		}

		const buffer_size: usize = 4096;
		const buffers = try allocator.alloc( u8, len * buffer_size );

		for ( items.items( .buffer ), 0.. ) |*buffer, i|
		{
			const start = i * buffer_size;
			const end = start + buffer_size;
			buffer.* = buffers[start..end];
		}

		const nul_handle = try Child.nullHandle();

		var saAttr = windows.SECURITY_ATTRIBUTES{
			.nLength = @sizeOf(windows.SECURITY_ATTRIBUTES),
			.bInheritHandle = windows.TRUE,
			.lpSecurityDescriptor = null,
		};
		for ( items.items( .pipe_write ), items.items( .pipe_read ) ) |*wr,*rd|
		{
			var rd_handle: ?windows.HANDLE = undefined;
			var wr_handle: ?windows.HANDLE = undefined;
			try Child.windowsMakeAsyncPipe(&rd_handle, &wr_handle, &saAttr );
			wr.* = .{ .handle = wr_handle.? };
			rd.* = .{ .handle = rd_handle.? };
		}

		for ( items.items( .overlapped ),  items.items( .pipe_read ), items.items( .buffer ) ) |*overlap, rd, buffer|
		{
			overlap.* = std.mem.zeroes( windows.OVERLAPPED );
			if (windows.kernel32.ReadFile(rd.?.handle, buffer.ptr, @intCast( buffer.len ), null, overlap) == 0) {
			switch (windows.GetLastError()) {
					.IO_PENDING => {},
					.OPERATION_ABORTED => continue,
					.BROKEN_PIPE => return error.BrokenPipe,
					.HANDLE_EOF => return error.HandleEof,
					.NETNAME_DELETED => return error.ConnectionResetByPeer,
					.LOCK_VIOLATION => return error.LockViolation,
					else => |err| return windows.unexpectedError(err),
				}
			}

		}

		var handles = HandleList{};
		try handles.resize( allocator, len );

		return .{ 
			.items = items,
			.first_free = 0,
			.free_count = @intCast( len ),
			.nul_handle = nul_handle ,
			.handles = handles
			};
	}

	pub fn deinit( self: *ProcessPool, allocator: std.mem.Allocator ) void
	{
		self.handles.deinit( allocator );

		const buffer_size: usize = 4096;
		const buffer = self.items.items( .buffer )[0];
		const len = self.items.len * buffer_size;
		allocator.free( buffer.ptr[0..len]);
		self.items.deinit( allocator );
	}

	// returns true if a process finished
	fn run( self: *ProcessPool ) !bool
	{
		if (self.first_free != null) return false;

		while ( try self.wait() ) {
			try self.processPipes( false );
		}

		return true;
	}

	fn finish( self: *ProcessPool ) !bool
	{
		while ( try self.wait() ) {
			try self.processPipes( false );
		}

		if ( self.free_count < self.items.len )
		{
			return true;
		}

		try self.processPipes( true );

		return false;
	}


	// make sure there is a free index before calling
	fn add( self: *ProcessPool, allocator: std.mem.Allocator, args: [][]const u8, cwd: []const u8 ) !void
	{
		const free = self.first_free.?;
		self.first_free = self.items.items( .next_free )[free];

		//const dir = try std.fs.openDirAbsolute( cwd, .{} );
		const pipe_write = self.items.items( .pipe_write )[free];
		const pipe_in = self.nul_handle;

		var child = Child.init( args, allocator );
		child.cwd = cwd;
		_ = try child.spawn( pipe_write, pipe_in );


		self.items.items( .next_free )[free] = null;
		self.items.items( .process )[free] 	 = child;
		self.items.items( .id )[free] 		 = child.id;


		self.free_count -= 1;
	}




	fn wait( self: *ProcessPool ) !bool {
		const handles = &self.handles;
		handles.shrinkRetainingCapacity( 0 );

		for ( self.items.items( .id ), 0.. ) |id, idx|
		{
			if (id == null) continue;
			handles.appendAssumeCapacity( .{ .id = id.?, .idx = @intCast( idx ) });
		}

		const slice = handles.items( .id );
		const offset = std.os.windows.WaitForMultipleObjectsEx( slice, false, 10, false ) catch |err| {
			if ( err == error.WaitTimeOut ) return true;
			return err;
		};

		const idx = handles.items( .idx )[offset];

		var item = self.items.get( idx );

		item.next_free = self.first_free;
		item.id = null;
		_ = try item.process.wait();

		self.items.set( idx, item );

		self.first_free = idx;
		self.free_count += 1;

		return false;
	}

	fn processPipes( self: *ProcessPool, final: bool ) !void {
		const overlapped = self.items.items( .overlapped );
		const children = self.items.items( .id );
		const buffers = self.items.items( .buffer );
		const reads = self.items.items( .pipe_read );
		for ( overlapped, children, buffers, reads ) |*overlap, id, buffer, *rd_op|
		{
			_ = id;
			const rd = if (rd_op.*) |r| r else continue;
			const bytes = std.os.windows.GetOverlappedResult( rd.handle, overlap, false ) catch |err|
			{
				if ( err == error.WouldBlock ) continue;
				return err;
			};

			const stdout = std.io.getStdOut();
			_ = try stdout.write( buffer[0..bytes] );
			
			if (!final) {
				try beginRead( overlap, rd.handle, buffer );
			} else {
				const windows =std.os.windows;

				// empty the pipe
				var bytes_available: DWORD = 0;
				var bytes_read: DWORD = 0;
				if ( PeekNamedPipe( rd.handle, null, 0, null, &bytes_available, null) == 1 ) {
					while ( bytes_available > bytes_read ) {
						bytes_available -= bytes_read;
						if (windows.kernel32.ReadFile(rd.handle, buffer.ptr, @intCast( buffer.len ), &bytes_read, null) == 0) {
							switch (windows.GetLastError()) {
								.IO_PENDING => {},
								.OPERATION_ABORTED => return,
								.BROKEN_PIPE => return error.BrokenPipe,
								.HANDLE_EOF => return error.HandleEof,
								.NETNAME_DELETED => return error.ConnectionResetByPeer,
								.LOCK_VIOLATION => return error.LockViolation,
								else => |err| return windows.unexpectedError(err),
							}
						}

						if (bytes_read == 0) break;
						_ = try stdout.write( buffer[0..bytes_read] );
					}
				}
				// TODO check errors
			}
		}
	}


	fn beginRead( overlap: *std.os.windows.OVERLAPPED, handle: std.os.windows.HANDLE, buffer: []u8 ) !void
	{
		const windows =std.os.windows;
		overlap.* = std.mem.zeroes( windows.OVERLAPPED  );
		if (windows.kernel32.ReadFile(handle, buffer.ptr, @intCast( buffer.len ), null, overlap) == 0) {
		switch (windows.GetLastError()) {
				.IO_PENDING => {},
				.OPERATION_ABORTED => return,
				.BROKEN_PIPE => return error.BrokenPipe,
				.HANDLE_EOF => return error.HandleEof,
				.NETNAME_DELETED => return error.ConnectionResetByPeer,
				.LOCK_VIOLATION => return error.LockViolation,
				else => |err| return windows.unexpectedError(err),
			}
		}
	}
};

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

	const arg0 = c_args[0][0..std.mem.len(c_args[0])];
	const com_name = std.fs.path.stem( arg0 );

	const driver_mode = x: {
		if ( std.mem.endsWith( u8, "c++", com_name ) ) {
			break :x "--driver-mode=g++";
		}
		if ( std.mem.endsWith( u8, "cc", com_name ) ) {
			break :x "--driver-mode=gcc";
		}

		// TODO: other driver modes
		break :x "--driver-mode=g++";
	};

	const extra_args = [_][]const u8{ driver_mode };
	const prepend_len = extra_args.len;
	const args = try allocator.alloc( []const u8, desired_size + prepend_len );

	// arg0
	args[0] = arg0;

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
