const std = @import("std");


const Args = struct {

	name: []const u8,
	path: []const u8,


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
		.name = try allocator.dupe( u8, name ),
		.path = try allocator.dupe( u8, path ),
		};
}

pub fn main() !void
{
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("LEAK");
    }

	const args = try fetchArgs( allocator );
	defer args.deinit( allocator );


}