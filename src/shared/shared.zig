const sqlite = @import("../zig/sqlite.zig");


const Ctx = struct {
	db: sqlite.DB,
	edge_stmt: sqlite.r.sqlite3_stmt,
	node_stmt: sqlite.r.sqlite3_stmt,
};

export fn createDB( raw_db: sqlite.r.sqlite3 ) void
{
	const db: sqlite.DB = .{ .db = raw_db };

	const stmt = db.prepare( );


}