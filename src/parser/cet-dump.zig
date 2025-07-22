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

	const nodes = try reader.readNodes( allocator );
	defer allocator.free( nodes );

	const connections = try reader.readConnections( allocator );
	defer allocator.free( connections );

	var strings = try reader.readStrings( allocator );
	defer strings.deinit( allocator );

	const linklinks = try reader.readLinkLinks( allocator );
	defer allocator.free( linklinks );

	var linknames = try reader.readLinkNames( allocator );
	defer linknames.deinit( allocator );


	std.debug.print( "{}\n", .{ reader.hdr } );

	for (nodes) |node|
	{
		const id = node.id;
		const str = strings.hashmap.get( node.string_hash ).?;
		std.debug.print("{} {s}\n", .{ id, str });
	}

	for (linklinks) |link|
	{
		var node: ?*ObjFile.Node = null;
		for (nodes) |*n|
		{
			if ( link.node_id == n.id ) {
				node = n;
			}
		}

		const str = if (node) |n| strings.hashmap.get( n.string_hash ).? else "????";
		const linkname = linknames.hashmap.get( link.string_hash ).?;
		std.debug.print("{s} {s}\n", .{ str, linkname });
	}

	return 0;
}