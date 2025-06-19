const Clang = @import("clang.zig");
const std = @import( "std" );

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

	const args_c: [][*c]const u8 = try allocator.alloc( [*c]const u8, args.len );
	defer allocator.free( args_c );
	for ( args, args_c ) |src,*dst|
	{
		dst.* = src.ptr;
	}

	for ( args[1..] ) |a|
	{
		std.debug.print("{s} ", .{a});
	}
	std.debug.print("\n", .{});


	const results = Clang.parseFromArgs( args_c ) orelse {
		return 1;
	};
	_ = results;

	return 0;
}