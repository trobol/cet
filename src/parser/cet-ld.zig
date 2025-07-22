const Clang = @import("clang.zig");
const std = @import("std");
const ObjFile = @import("objfile.zig");

const Options = @import("options.zig").makeOptions(.{

});


// want to be able to flush most memory to file


// operations needed
// whole db:
// identifier hash to index
// link identifier to node index
// obj file local:
// node id to node index
// 


pub fn main() !void
{
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();
	defer {
		const deinit_status = gpa.deinit();
		if (deinit_status == .leak) @panic("LEAK");
	}


	const options = try Options.parse( allocator );
	defer options.deinit();

	for ( options.args ) |file| {
		var reader = ObjFile.Reader.open( file ) catch |err|
		{
			return err;
		};

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

		

	}
}


pub fn PagedArray( T: type, size: usize ) type {
    const ArrayPage = struct {
        const Self = @This();
        data: [size]T,
        next: ?*Self
    };

    const Iterator = struct {
        const Self = @This();

        cur: *ArrayPage,
        idx: usize,
        curCount: usize,

        last: *ArrayPage, // to avoid touching next until we've iterated the page
        lastCount: usize,

        pub fn next( self: *Self ) ?T {
            if ( self.idx >= self.curCount )
            {
                const nextPage = self.cur.next orelse return null;
                if ( nextPage == self.last ) self.curCount = self.lastCount;
                self.cur = nextPage;
                self.idx = 0;
            }
            const index = self.idx;
            self.idx += 1;
            return self.cur.data[index];
        }
    };

    return struct {
        const Self = @This();

        first: ?*ArrayPage = null,
        last: ?*ArrayPage = null,
        count: usize = 0,


        pub fn append( self: *Self, allocator: std.mem.Allocator, val: T ) *T {
            const idx = self.count % size;
            if ( idx == 0 ) {
                const new = allocator.create( ArrayPage );
                new.next = null;
                if (self.last) |last| { last.next = new; }
                else { self.first = new; self.last = new; }
                self.last = new;
            }

            self.count += 1;
            const ptr = &self.last.?.data[idx];//if last is null something fucked up the count
            ptr.* = val; 
            return ptr;
        }

		pub fn front( self: Self ) ?*T
		{
			if ( self.first ) |first|
			{
				return &first.data[0];
			}

			return null;
		}

        pub fn back( self: *Self ) ?*T
        {
            if ( self.last ) |last|
            {
               return &last.data[(self.count-1) % size];
            }
            
            return null;
        }


        // TODO: make this work for empty arrays
        pub fn iterator( self: Self ) Iterator {
            var count: usize = size;
            if (self.first == self.last) count = self.count % size;

            return .{
                .cur = self.first.?,
                .idx = 0,
                .curCount = count,
                .last = self.last.?,
                .lastCount = self.count % size
            };

        }


    };
}


// chunks
// name

const DatabaseWriter = struct {
	
	fd: std.fs.File,

	const PAGE_SIZE: usize = 2048;

	const ChunkIden = packed struct {
		int: u32,
		str: [4]u8,
	};

	pub fn idenFromStr( str: []u8 ) ChunkIden
	{
		std.debug.assert( str.len <= 4 and str.len > 0 );
		const len = @min( str.len, 4 );
		var arr = std.mem.zeroes( [4]u8 );
		@memcpy( arr[0..len], str[0..len] );
		return .{ .str = arr };
	}



	const ChunkTable = extern struct {
		len: u32,
		pad: u32,
		data: [1023]Entry,
	
		const Entry = extern struct {
			iden: ChunkIden,
			offset: u32 // going to round this so the 4gb limit shouldn't be a problem
		};
	};

	
	pub fn writeString( self: *@This() ) usize
	{

	}

	pub fn writeNode( self: *@This(), node: ObjFile.Node ) usize
	{

	}

	pub fn writeConnection( self: *@This(), connection: ObjFile.Connection ) usize 
	{
		
	}

	pub fn writeChunk( self: *@This(), iden: ChunkIden, compressed_size: u32, uncompressed_size: u32 ) void
	{
		
	}
};