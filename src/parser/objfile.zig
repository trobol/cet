


// signature        4 bytes cetdb
// spec ver         4 bytes
// file hash        8 bytes
// file write time  8 bytes
// item count      4 bytes
// text block count 4 bytes (block is 1024 bytes)
// file name
// build args       4 bytes offset to text block

// items


// id              8 bytes
// parent id       8 bytes
// text id         8 bytes



// text - big block of null terminated strings
// maybe 

const std = @import("std");


const version_major: u8 = 0;
const version_minor: u8 = 1;


const Sig = extern struct {
	sig: [6]u8, // "cetobj"
	ver_major: u8,
	ver_minor: u8,
};

pub const Header = extern struct {
	run_id: u64,
	nodes_count: u64,
	connections_count: u64,
	strings_len: u64,
	strings_count: u32,
};

pub const Node = extern struct {
	id: i64,
	string_hash: u64
};

pub const Connection = extern struct {
	from: i64,
	to: i64
};





pub const Writer = struct {
	const BufferedWriter = std.io.BufferedWriter( 2048, std.fs.File.Writer );
	const WriteError = std.fs.File.Writer.Error;
	const OpenError = std.fs.File.OpenError || WriteError;

	buffer: BufferedWriter,


	pub fn open( path: []const u8 ) OpenError!Writer
	{
		const file = try std.fs.cwd().createFile( path, .{ .truncate = true, .lock = .exclusive } );
		var buf = BufferedWriter{ .unbuffered_writer = file.writer() };
		const writer = buf.writer();
		const sig = Sig{ .sig = "cetobj".*, .ver_major = version_major, .ver_minor = version_minor };
		
		try writer.writeStruct( sig );
		return .{ .buffer = buf };
	}

	pub fn close( self: *Writer ) !void
	{
		try self.buffer.flush();
		self.buffer.unbuffered_writer.context.close();
	}


	pub fn writeHeader( self: *Writer, header: Header ) WriteError!void
	{
		const writer = self.buffer.writer();
		return writer.writeStruct( header );
	}

	pub fn writeNodes( self: *Writer, nodes: []Node ) WriteError!void
	{
		const writer = self.buffer.writer();
		return writer.writeAll( std.mem.sliceAsBytes( nodes ) );
	}

	pub fn writeConnections( self: *Writer, connections: []Connection ) WriteError!void
	{
		const writer = self.buffer.writer();
		return writer.writeAll( std.mem.sliceAsBytes( connections ) );
	}

	pub fn writeStrings( self: *Writer, strings: []const u8 ) WriteError!void
	{
		const writer = self.buffer.writer();
		return writer.writeAll( strings );
	}

};

pub const Reader = struct {
	const BufferedReader = std.io.BufferedReader( 2048, std.fs.File.Reader);
	const ReadError = error{EndOfStream,OutOfMemory} || std.fs.File.ReadError;
	const OpenError = error{IncorrectHeader,IncorrectVersion} || std.fs.File.OpenError || ReadError;

	buffer: BufferedReader,


	pub fn open( path: []const u8 ) OpenError!Reader
	{
		const file = try std.fs.cwd().openFile( path, .{ .mode = .read_only, .lock = .shared } );
		var buf = BufferedReader{ .unbuffered_reader = file.reader() };
		const reader = buf.reader();
		const sig = reader.readStruct( Sig ) catch |err| {
			switch( err ) {
				error.EndOfStream => return error.IncorrectHeader,
				else => return err,
			}
		};

		if ( !std.mem.eql( u8, &sig.sig, "cetobj" ) )
		{
			return error.IncorrectHeader;
		}

		if ( sig.ver_major == version_major and sig.ver_minor == sig.ver_major )
		{
			return error.IncorrectVersion;
		}

		return .{ .buffer = buf };
	}

	pub fn close( self: Reader ) void
	{
		self.unbuffered_reader.context.close();
	}

	pub fn readHeader( self: *Reader ) !Header
	{
		const reader = self.buffer.reader();
		return reader.readStruct( Header );
	}

	pub fn readNodes( self: *Reader, allocator: std.mem.Allocator, header: Header ) ReadError![]Node
	{
		const nodes = try allocator.alloc( Node, header.nodes_count );
		const reader = self.buffer.reader();
		try reader.readNoEof(std.mem.sliceAsBytes(nodes));
		return nodes;
	}

	pub fn readConnections( self: *Reader, allocator: std.mem.Allocator, header: Header ) ReadError![]Connection
	{
		const connections = try allocator.alloc( Connection, header.connections_count );
		const reader = self.buffer.reader();
		try reader.readNoEof(std.mem.sliceAsBytes(connections));
		return connections;
	}

	const HashContext = struct {
		pub fn hash( self: HashContext, a: u64 ) u64
		{
			_ = self;
			return a;
		}

		pub fn eql( self: HashContext, a: u64, b: u64 ) bool
		{
			_ = self;
			return a == b;
		}
	};

	pub const HashMap = std.HashMapUnmanaged( u64, []const u8, HashContext, 99);

	pub const StringTable = struct {

		hashmap: HashMap,
		strings: []const u8,

		pub fn deinit( self: *StringTable, allocator: std.mem.Allocator ) void
		{
			self.hashmap.deinit( allocator );
			allocator.free( self.strings );
		}
	};

	pub fn readStrings( self: *Reader, allocator: std.mem.Allocator, header: Header ) ReadError!StringTable
	{
		const strings = try allocator.alloc( u8, header.strings_len );
		try self.buffer.reader().readNoEof( strings );

		var hashmap = HashMap.empty;
		try hashmap.ensureTotalCapacity( allocator, header.strings_count );

		var str_start: usize = 0;
		for (strings, 0..) |c, i|
		{
			if (c != 0) continue;

			const str = strings[str_start..i];
			const hash = std.hash.Wyhash.hash( 0, str );
			hashmap.putAssumeCapacity( hash, str );
			str_start = i+1;
		}

		return .{ .hashmap = hashmap, .strings = strings };
	}

};

