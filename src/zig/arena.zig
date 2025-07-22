const Allocator: type = std.mem.Allocator;
const std: type = @import("std");
const win: type = std.os.windows;


const COMMIT_GRANULARITY: usize = 1024 * 4;
const RESERVE_GRANULARITY: usize =  1024 * 64;



fn internal_alloc(arena: *Arena, size: usize, alignment: usize, n: usize) [*]u8 {
    const ptr = std.mem.alignForward( usize, @intFromPtr(arena.start), alignment );
    const end = ptr + ( size * n );

    if ( end > @intFromPtr( arena.end ) )
    {
        const deficient: usize = end - @intFromPtr( arena.end );
        const commit: usize = std.mem.alignForward( usize, deficient, COMMIT_GRANULARITY );
        _ = win.VirtualAlloc( arena.end, commit, win.MEM_COMMIT, win.PAGE_READWRITE) catch unreachable;
        arena.end += commit;
    }

    const bytes: [*]u8 = @ptrFromInt( ptr );
    @memset( bytes[0..(size*n)], 0 );

    arena.start = @ptrFromInt( end );
    return bytes;
}

fn is_at_end( self: *Arena, start: [*]u8, len: usize, size: usize ) bool
{
    const memEnd = start + (len * size);
    return self.start == memEnd;
}


pub const ScratchArena = struct {
	parent: *const Arena,

	pub fn arena( self: ScratchArena ) Arena
	{
		return self.parent.*;
	}

	
};


pub const Arena: type = struct {
    start: [*]u8,
    end: [*]u8,
    

    pub fn init() Arena {	
        const reserve_size = RESERVE_GRANULARITY * RESERVE_GRANULARITY;
        const ptr = win.VirtualAlloc( null, reserve_size, win.MEM_RESERVE, win.PAGE_NOACCESS) catch unreachable;
        return .{
            .start = @ptrCast(ptr),
            .end = @ptrCast(ptr)
        };
    }

    pub fn create(self: *Arena, comptime T: type ) *T {
        return @ptrCast( @alignCast( internal_alloc(self, @sizeOf(T), @alignOf(T), 1) ) );
    }

    pub fn alloc(self: *Arena, comptime T: type, n: usize) []align(@alignOf(T)) T {
        const ptr: [*]align(@alignOf(T)) T = @ptrCast( @alignCast( internal_alloc(self, @sizeOf(T), @alignOf(T), n) ) );
        return ptr[0..n];
    }

	// alloc space and copy contents into there
	pub fn copy( self: *Arena, comptime T: type, ptr: *T ) *T 
	{
		const new = self.create(T);
		new.* = ptr.*;
		return new;
	}

    // TODO: don't like this, should do less and catch problems in ship builds
    pub fn expandInPlace( self: *Arena, old_mem: anytype, expand_n: usize ) @TypeOf(old_mem)
    {
        const Slice = @typeInfo(@TypeOf(old_mem)).pointer;
        const T: type = Slice.child;

        const mem_end = @intFromPtr( old_mem.ptr + old_mem.len ); 

        if ( is_at_end( self, @ptrCast( old_mem.ptr ), old_mem.len, @sizeOf(T) ) == false ) unreachable;

        const new_mem = internal_alloc( self, @sizeOf(T), @alignOf(T), expand_n );

        if ( mem_end != @intFromPtr( new_mem ) ) unreachable;
        
        return old_mem.ptr[0..expand_n+old_mem.len];
    }

    pub fn shrink( self: *Arena, mem: anytype, new_n: usize ) @TypeOf(mem)
    {
        const Slice = @typeInfo(@TypeOf(mem)).pointer;
        const T: type = Slice.child;
        if ( false == is_at_end( self, @ptrCast( mem.ptr ), mem.len, @sizeOf(T) ) ) unreachable;
        if (new_n > mem.len) unreachable;
        self.start = @ptrCast( mem.ptr + new_n );
        return mem[0..new_n];
    }

	fn v_alloc( ctx: *anyopaque, n: usize, log2_ptr_align: u8, return_address: usize) ?[*]u8
	{
		_ = return_address;
		const self: *Arena = @ptrCast(@alignCast(ctx));

		const ptr_align = @as(usize, 1) << @as(Allocator.Log2Align, @intCast(log2_ptr_align));

		return internal_alloc(self, n, ptr_align, n);
	}

	fn v_resize( ctx: *anyopaque,
            buf: []u8,
            log2_buf_align: u8,
            new_size: usize,
            return_address: usize) bool
	{
		_ = ctx;
		_ = buf;
		_ = log2_buf_align;
		_ = new_size;
		_ = return_address;
		return false; // TODO: try to resize in place
	}

	fn v_free( ctx: *anyopaque,
            buf: []u8,
            log2_buf_align: u8,
            return_address: usize ) void
	{
		_ = ctx;
		_ = buf;
		_ = log2_buf_align;
		_ = return_address;
	}

	pub fn allocator( self: *Arena ) Allocator
	{
		return .{
			.ptr = self,
			.vtable = &.{
				.alloc = v_alloc,
				.resize = v_resize,
				.free = v_free
			},
		};
	}
};



const testing: type = std.testing;
fn scratch_test(scratch_arena: Arena) void {
    var arena = scratch_arena;
    const a = arena.create(usize);
    a.* = 50;
}

test "scratch" {
    var arena = Arena.init();
    const start_start = arena.start;
    const start_end = arena.end;

    scratch_test(arena);

    try testing.expectEqual(start_start, arena.start);
    try testing.expectEqual(start_end, arena.end);

    var arr = arena.alloc(u32, 30 );
    arr = arena.expandInPlace( arr, 40 );
    arr = arena.shrink( arr, 20 );
}



// unfinished
pub fn HashMap( keytype: type, valtype: type ) type {
    return struct {
        child: [4]*HashMap( keytype, valtype ),
        key: keytype,
        val: valtype,


    };
}


const MurmurHash = std.hash.Murmur2_64;

pub const StrSet = struct {
    child: [4]?*StrSet,
    hash: u64,
    str: []const u8,

    pub fn init( setArena: *Arena ) *StrSet
    {
        return setArena.create(StrSet);
    }


    pub fn upsert( set: *StrSet, str: []const u8, setArena: *Arena, stringArena: *Arena ) []const u8 
    {
        const hash: u64 = MurmurHash.hash( str );
        var h = hash;
        var set_var: ?*StrSet = set;
        var optional_m: *?*StrSet = &set_var;
        while( optional_m.* ) |m|
        {
            if ( m.*.hash == hash ) {
                return m.*.str;
            }
            optional_m = &m.*.child[h>>62]; 
            h = h << 2;
            
        }

        const newNode = StrSet.init( setArena );
        optional_m.* = newNode;

        const strCopy = stringArena.alloc(u8, str.len);
        std.mem.copyForwards(u8, strCopy, str);
        newNode.str = strCopy;
        newNode.hash = hash;

        return strCopy;
    }
};


test "str_set" {

    //var set: StrSet = .{ .child = .{ undefined, undefined, undefined, undefined }, .hash = 0, .str = "" };

    const str1 = "abcd";
    const str2 = "abcd";
    const str3 = "other";

    var arena = Arena.init();

    var set = StrSet.init( &arena );

    const copy1 = set.upsert(str1, &arena, &arena);
    const copy2 = set.upsert(str3, &arena, &arena);

    try testing.expectEqual(copy1, set.upsert(str1, &arena, &arena));
    try testing.expectEqual(copy1, set.upsert( str2, &arena, &arena));
    try testing.expectEqual(copy2, set.upsert(str3, &arena, &arena));
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


        pub fn append( self: *Self, val: T, arena: *Arena ) *T {
            const idx = self.count % size;
            if ( idx == 0 ) {
                const new = arena.create( ArrayPage );
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




// stack that will grow in fixed size pages
// be careful as the stack will never release any allocations
pub fn PagedStack( T: type, countPerPage: usize ) type {
    const StackPage = struct {
        const Self = @This();
        data: [countPerPage]T,
        prev: ?*Self,
        next: ?*Self,
    };
    return struct {
        const Self = @This();

        first: *StackPage,
        last: *StackPage,
        lastCount: usize,

        pub fn init( arena: *Arena ) Self
        {
            const first = arena.create(StackPage);
            return .{
                .first = first,
                .last = first,
                .lastCount = 0
            };
        }

        pub fn top( self: Self ) ?*T
        {
            if ( self.lastCount == 0 ) {
                return null;
            }
            return &self.last.data[self.lastCount-1];
        }

        pub fn push( self: *Self, arena: *Arena, val: T ) *T
        {
            if ( self.lastCount >= countPerPage ) {
                self.lastCount = 0;
                if ( self.last.next ) |next| {
                    self.last = next;
                } else {
                    const new = arena.create( StackPage );
                    new.prev = self.last;
                    self.last.next = new;
                    self.last = new;
                }
            }
            
            const index = self.lastCount;
            self.lastCount += 1;

            self.last.data[index] = val;
            return &self.last.data[index];
        }

        pub fn pop( self: *Self ) void
        {
            self.lastCount = self.lastCount - 1; // popping from an empty stack is an error
              
            if ( self.lastCount == 0 )
            {
                if ( self.last.prev ) |prev|
                {
                    self.last = prev;
                    self.lastCount = countPerPage;
                }
            }
        }
    };
}


test "paged stack" {

    var arena = Arena.init();
    var stack = PagedStack(usize, 32).init( &arena );

    try testing.expectEqual( stack.top(), null );
    
    const count = 32;
    for (0..count+1) |i|
    {
        _ = stack.push( &arena, i );
    }

    for (0..count) |i|
    {
        try testing.expectEqual(count - i, stack.top().?.*);
        stack.pop(); 
    }
}

const Writer = struct {
    pub const Error = error{};

    pub const Context = struct {
        arena: *Arena,
        buf: []u8,
        idx: usize,
    };

    ctx: *Context,

    fn makeSpace( self: Writer, len: usize ) []u8
    {
        const ctx = self.ctx;
        const idx = ctx.idx;
        const spaceNeed = idx + len;
        if ( spaceNeed > ctx.buf.len ) {
            const spaceMake = std.mem.alignForward(usize, spaceNeed, 32 );
            ctx.buf = ctx.arena.expandInPlace( ctx.buf, spaceMake );
        }
        const ret = ctx.buf[idx..idx+len];
        ctx.idx += len;

        return ret;
    }


    pub fn writeAll( self: Writer, str: []const u8 ) Error!void
    {
        const space = self.makeSpace( str.len );
        @memcpy( space, str );
    }

    pub fn writeBytesNTimes( self: Writer, bytes: []const u8, n: usize ) Error!void
    {
        const space = self.makeSpace( n*bytes.len );
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const start = bytes.len * i;
            @memcpy( space[start..start+bytes.len], bytes );
        }
    }

    pub fn writeByteNTimes( self: Writer, byte: u8, n: usize ) Error!void
    {
        const space = self.makeSpace( n );
        @memset( space, byte );
    }
};

const WriterWrapper = struct {
    pub const Error = Writer.Error;

    writer: *Writer,

    pub fn writeAll( self: WriterWrapper, str: []const u8 ) Error!void {
        try self.writer.writeAll(str);
    }
};

pub fn sprintf( arena: *Arena, comptime format: []const u8, args: anytype ) anyerror![]const u8 {
    // have to do this because writer is constant
    var ctx: Writer.Context = .{
            .arena = arena,
            .buf = arena.alloc( u8, 32 ),
            .idx = 0
        };
    const writer: Writer = .{
        .ctx = &ctx
    };
  


    try std.fmt.format(writer, format, args);

    return arena.shrink( ctx.buf, ctx.idx );
}


test "sprintf" {

    var arena = Arena.init();
    
    try std.testing.expectEqualStrings("2.1", try sprintf( &arena, "{d}", .{ 2.1 }));
}


const GENERIC_READ                    :win.DWORD = 0x80000000;
const GENERIC_WRITE                   :win.DWORD = 0x40000000;
const GENERIC_EXECUTE                 :win.DWORD = 0x20000000;
const GENERIC_ALL                     :win.DWORD = 0x10000000;

const FILE_SHARE_READ                :win.DWORD = 0x00000001;  
const FILE_SHARE_WRITE               :win.DWORD = 0x00000002;  
const FILE_SHARE_DELETE              :win.DWORD = 0x00000004; 

const CREATE_NEW          : win.DWORD = 1;
const CREATE_ALWAYS       : win.DWORD = 2;
const OPEN_EXISTING       : win.DWORD = 3;
const OPEN_ALWAYS         : win.DWORD = 4;
const TRUNCATE_EXISTING   : win.DWORD = 5;

const FILE_ATTRIBUTE_NORMAL   : win.DWORD =   0x00000080;

const INVALID_FILE_SIZE: win.DWORD = 0xFFFFFFFF;

extern "kernel32" fn CreateFileA( lpFileName: win.LPCSTR, dwDesiredAccess: win.DWORD, dwSharedMode: win.DWORD, lpSecurityAttributes: ?*opaque{}, dwCreationDisposition: win.DWORD, dwFlagsAndAttributes: win.DWORD, hTemplateFile: ?win.HANDLE ) callconv(win.WINAPI) win.HANDLE;
extern "kernel32" fn GetFileSize( hFile: win.HANDLE, lpFileSizeHigh: ?*win.DWORD ) callconv(win.WINAPI) win.DWORD;
extern "kernel32" fn ReadFile( hFile: win.HANDLE, lpBuffer: [*]u8, nNumberOfBytesToRead: win.DWORD, lpNumberOfBytesRead: ?*win.DWORD, lpOverlapped: ?*opaque{}) callconv(win.WINAPI) win.BOOL;
extern "kernel32" fn CloseHandle( hObject: win.HANDLE ) callconv(win.WINAPI) win.BOOL;


// TODO: convert all this junk to calls from zig std, see Dir.createFile
pub fn ReadWholeFile(path: []const u8, arena: *Arena) error{Unexpected}![]u8
{
	var arenaCopy = arena.*;
	var pathTerminated: [:0] u8 = @ptrCast( arenaCopy.alloc( u8, path.len + 1 ) );
	@memcpy( pathTerminated[0..path.len], path );
	pathTerminated[pathTerminated.len] = 0;

	const handle = CreateFileA( pathTerminated, GENERIC_READ, FILE_SHARE_READ, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null );
	if (handle == win.INVALID_HANDLE_VALUE) return win.unexpectedError(win.GetLastError());

	
	const size = GetFileSize(handle, null);
	if (size == INVALID_FILE_SIZE) return win.unexpectedError(win.GetLastError());

	const buffer = arena.alloc( u8, size );

	if ( ReadFile( handle, buffer.ptr, @truncate( buffer.len ), null, null ) == 0 ) return win.unexpectedError(win.GetLastError());
	
	if ( CloseHandle( handle ) == 0 ) return win.unexpectedError(win.GetLastError());

	return buffer;
}