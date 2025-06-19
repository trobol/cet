const Clang = @import("clang.zig");


pub fn main() !void
{
	try Clang.initialize();

}