
pub const r = @cImport({
	@cInclude("external/sqlite/sqlite3.h");
});


pub const Result = enum(c_int) {
	OK = r.SQLITE_OK,
	ERROR = r.SQLITE_ERROR,
	INTERNAL = r.SQLITE_INTERNAL,
	PERM = r.SQLITE_PERM,
	ABORT = r.SQLITE_ABORT,
	BUSY = r.SQLITE_BUSY,
	LOCKED = r.SQLITE_LOCKED,
	NOMEM = r.SQLITE_NOMEM,
	READONLY = r.SQLITE_READONLY,
	INTERRUPT = r.SQLITE_INTERRUPT,
	IOERR = r.SQLITE_IOERR,
	CORRUPT = r.SQLITE_CORRUPT,
	NOTFOUND = r.SQLITE_NOTFOUND,
	FULL = r.SQLITE_FULL,
	CANTOPEN = r.SQLITE_CANTOPEN,
	PROTOCOL = r.SQLITE_PROTOCOL,
	EMPTY = r.SQLITE_EMPTY,
	SCHEMA = r.SQLITE_SCHEMA,
	TOOBIG = r.SQLITE_TOOBIG,
	CONSTRAINT = r.SQLITE_CONSTRAINT,
	MISMATCH = r.SQLITE_MISMATCH,
	MISUSE = r.SQLITE_MISUSE,
	NOLFS = r.SQLITE_NOLFS,
	AUTH = r.SQLITE_AUTH,
	FORMAT = r.SQLITE_FORMAT,
	RANGE = r.SQLITE_RANGE,
	NOTADB = r.SQLITE_NOTADB,
	NOTICE = r.SQLITE_NOTICE,
	WARNING = r.SQLITE_WARNING,
	ROW = r.SQLITE_ROW,
	DONE = r.SQLITE_DONE,
};


fn makeCmdStmt() type
{
	const s = struct {
		stmt: Stmt,
		pub fn exec() void {

		}
	};

	_ = s;
}

pub const Stmt = struct {
	stmt: *r.sqlite3_stmt,



	pub fn destroy( self: @This() ) error{Unexpected}
	{
		const ret = r.sqlite3_finalize( self.stmt );
		if ( ret != r.SQLITE_OK )
		{
			return error.Unexpected;
		}
	} 

	pub fn step( self: @This() ) !Result
	{
		const rc: Result = @enumFromInt( r.sqlite3_run( self.stmt ) );
		if ( rc != .ERROR )
		{
			return error.Error;
		}

		return rc;
	}

	pub fn bind( self: @This(), values: anytype ) !void 
	{
		_ = self;
		_ = values;
	}

	pub fn bindField( self: @This(), comptime T: type, value: anytype, bind_index: c_int ) !void
	{
		var rc: c_int = 0;

		switch ( @typeInfo(T) )
		{
			.null => rc = r.sqlite3_bind_null( self.stmt, bind_index ),
			.int, .comptime_int => rc = r.sqlite3_bind_int64( self.stmt, bind_index, @intCast(value) ),
			.float, .comptime_float => rc = r.sqlite3_bind_double( self.stmt, bind_index, value ),
			.pointer => |ptr| {
				_ = ptr;
			},
		}
	}
};





pub const DB = struct {
	db: *r.sqlite3,

	pub fn prepare( self: @This(), zSql:[]const u8 ) !Stmt
	{
		var stmt: *r.sqlite3_stmt = undefined;
		const ret = r.sqlite3_prepare_v2( self.db, zSql.ptr, zSql.len, &stmt, null );
		if ( ret != r.SQLITE_OK )
		{
			return error.Unexpected;
		}

		return .{ .stmt = stmt };
	}

	pub fn close( self: @This() ) error{Unexpected}
	{
		const ret = r.sqlite3_close( self.db );
		if ( ret != r.SQLITE_OK )
		{
			return error.Unexpected;
		}
	}

	pub fn enter( self: @This() ) void
	{
		r.sqlite3_mutex_enter( r.sqlite3_db_mutex( self.db ) );
	}

	pub fn exit( self: @This() ) void
	{
		r.sqlite3_mutex_exit( r.sqlite3_db_mutex( self.db ) );
	}

	pub fn exec( self: @This(), zSql:[]const u8 ) !Result
	{
		self.enter();
		defer self.exit();

		const stmt = try self.prepare( zSql );
		const rc = try stmt.step();
		stmt.destroy();

		return rc;
	}

};



pub fn open( name:[*:0]const u8 ) error{Unexpected}!DB
{
	var db: *r.sqlite3 = undefined;
	const ret = r.sqlite3_open_v2( name, @ptrCast(&db), r.SQLITE_OPEN_READONLY, null );
	if ( ret != r.SQLITE_OK ) 
	{
		return error.Unexpected;
	}

	return .{ .db = db };
}



test "database" {
	const db = open( ":memory:" );
	defer db.close();

	_ = db.exec( "CREATE TABLE compile_db (id BIGINT, parent_id BIGINT, identifier text, usr text, params text);" );

	
}