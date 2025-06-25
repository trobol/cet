const std = @import( "std" );
const c = @cImport({
	@cInclude("parser/clang.h");
});

const DynLib = std.DynLib;

fn makeDynLibType( comptime input: type ) type
{
	const decls = @typeInfo( input ).@"struct".decls;

	var fields: [decls.len+1]std.builtin.Type.StructField = undefined;
	fields[0] = .{
		.name = "lib",
		.type = @TypeOf( DynLib ),
		.is_comptime = false,
		.alignment = @alignOf( @TypeOf( DynLib ) ),
		.default_value_ptr = null,
	};

	var idx: u32 = 1;
	blk: for(decls) |d|
	{
		const decl = @field(input, d.name );
		const declInfo = @typeInfo( @TypeOf( decl ) );
		switch(declInfo)
		{
			else => { continue :blk; },
			.@"fn" => {
				fields[idx] =
				.{
					.name = d.name,
					.type = @TypeOf( &decl ),
					.is_comptime = false,
					.alignment = @alignOf( @TypeOf( decl ) ),
					.default_value_ptr = null,
				};
				idx += 1;
			},
		}
	}

	return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = fields[0..],
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

fn loadLib( Lib: type, name: []const u8) !Lib
{
	var dynlib = try DynLib.open( name );

	var lib: Lib = undefined;
	lib.lib = dynlib;

	var loadfailed = false;
	inline for (std.meta.fields(Lib)[1..]) |f|
	{
		const lookup = dynlib.lookup( f.type, f.name );
		if (lookup) |l|
		{
			@field( lib, f.name ) = l;
		} else {
			try std.io.getStdErr().writer().print( "library {s} is missing field {s}\n", .{ name, f.name });
			loadfailed = true;
		}
		
	}
	if (loadfailed)
	{
		std.process.abort();
	}

	return lib;
}



var g_lib: struct {
	lib: DynLib,
	parseDB: @TypeOf( &c.parseDB ),
	CompileDatabase_getAllCommands: @TypeOf( &c.CompileDatabase_getAllCommands ),
	CompileDatabase_deinit: @TypeOf( &c.CompileDatabase_deinit ),
	ParsedModuleInfo_deinit: @TypeOf( &c.ParsedModuleInfo_deinit ),
	parseFromArgs: @TypeOf( &c.parseFromArgs ),
	dumpFromArgs: @TypeOf( &c.dumpFromArgs ),
} = undefined;


fn makeRecorderType( T: type ) type
{
	const pointer = @typeInfo(T).pointer;
    std.debug.assert(pointer.size == .one);
	return struct {
		pub fn addNode( ud: ?*anyopaque, id: c_longlong, str: [*c]const u8, len: c_ulonglong ) callconv(.C) void {
			const recorder: T =  @ptrCast( @alignCast( ud.? ) );
			recorder.addNode( id, str[0..len] );
		}

		pub fn addConnection( ud: ?*anyopaque, from: c_longlong, to: c_longlong ) callconv(.C) void {
			const recorder: T =  @ptrCast( @alignCast( ud.? ) );
			recorder.addConnection( from,  to );
		}
	};
}

pub fn parseDB( directory: [*c]const u8, err: [*c][*c]const u8 ) ?CompileDatabase
{
	const db = g_lib.parseDB( directory, err );
	if ( db ) |ptr| return .{ .ptr = ptr };
	return null;
}

pub fn parseFromArgs( recorder: anytype, args: [][*c]const u8 ) void
{
	const interface = makeRecorderType( @TypeOf( recorder) );
	g_lib.parseFromArgs( .{ .ud = recorder, .addNode = &interface.addNode, .addConnection = &interface.addConnection }, args.len, args.ptr );
	//if ( module ) |ptr| return .{ .ptr = ptr };
	//return null;
}

pub fn dumpFromArgs( args: [][*c]const u8 ) void
{
	g_lib.dumpFromArgs( args.len, args.ptr );
}

pub fn initialize() !void
{
	g_lib = try loadLib( @TypeOf( g_lib ), "libclang_tool_lib" );
}


pub const CompileCommand = c.CompileCommand;

pub const CompileDatabase = struct {
	ptr: *c.CompileDatabase,

	
	pub fn deinit( self: CompileDatabase ) void
	{
		g_lib.CompileDatabase_deinit( self.ptr );
	}

	// all data is owned by db so it will get free'd when the db is
	pub fn getAllCommands( self: CompileDatabase ) []CompileCommand
	{
		const s = g_lib.CompileDatabase_getAllCommands( self.ptr );
		return s.ptr[ 0..s.len ];
	}
};

pub const ParsedItemInfo = c.ParsedItemInfo;

pub const ParsedModuleInfo = struct {
	ptr: *c.ParsedModuleInfo,

	pub fn deinit( self: ParsedModuleInfo ) void
	{
		g_lib.ParsedModuleInfo_deinit( self.ptr );
	}

	pub fn getItems( self: ParsedModuleInfo )  []ParsedItemInfo
	{
		const s = g_lib.ParsedModuleInfo_getItems( self.ptr );
		return s.ptr[ 0..s.len ];
	}
};
