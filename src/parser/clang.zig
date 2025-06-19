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
	ParsedModuleInfo_getItems: @TypeOf( &c.ParsedModuleInfo_getItems ), 
	parseFromArgs: @TypeOf( &c.parseFromArgs ),
} = undefined;


pub fn parseDB( directory: [*c]const u8, err: [*c][*c]const u8 ) ?CompileDatabase
{
	const db = g_lib.parseDB( directory, err );
	if ( db ) |ptr| return .{ .ptr = ptr };
	return null;
}

pub fn parseFromArgs( args: [][*c]const u8 ) ?ParsedModuleInfo
{
	const module = g_lib.parseFromArgs( args.len, args.ptr );
	if ( module ) |ptr| return .{ .ptr = ptr };
	return null;
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

	pub fn deinit( self: CompileDatabase ) void
	{
		g_lib.ParsedModuleInfo_deinit( self.ptr );
	}

	pub fn getItems( self: CompileDatabase )  []ParsedItemInfo
	{
		const s = g_lib.ParsedModuleInfo_getItems( self.ptr );
		return s.ptr[ 0..s.len ];
	}
};