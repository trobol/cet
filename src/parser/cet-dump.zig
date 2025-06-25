const std = @import( "std" );
const Options = @import( "options.zig" );
const ObjFile = @import( "objfile.zig" );


const OptionsParser = Options.makeOptions(.{

});

pub fn main() !u8
{
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();
	defer {
		const deinit_status = gpa.deinit();
		if (deinit_status == .leak) @panic("LEAK");
	}

	const options = try OptionsParser.parse( allocator );
	defer options.deinit();

	if (options.args.len < 1) {
		_ = try std.io.getStdErr().write("missing path arg\n");
		return 1;
	}

	const path = options.args[0];
	var reader = try ObjFile.Reader.open( path );

	const header = try reader.readHeader();
	const nodes = try reader.readNodes( allocator, header );
	defer allocator.free( nodes );

	const connections = try reader.readConnections( allocator, header );
	defer allocator.free( connections );

	var strings = try reader.readStrings( allocator, header );
	defer strings.deinit( allocator );


	for (nodes) |node|
	{
		const id = node.id;
		const str = strings.hashmap.get( node.string_hash ).?;
		std.debug.print("{} {s}\n", .{ id, str });
	}

	return 0;
}