const std = @import("std");

test "cl_0" {
	const allocator = std.testing.allocator;
	const dir = try std.fs.cwd().openDir( "cl_0", .{ .access_sub_paths = false } );



	const result = try std.process.Child.run( .{
		.allocator = allocator,
		.argv = &.{ "cet-driver", "--path", "." },
		.cwd_dir = dir
	} );
	defer {
		allocator.free( result.stderr );
		allocator.free( result.stdout );
	}
}