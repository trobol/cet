const std = @import("std");
const Type = std.builtin.Type;


// name, type, default, short, description
//  

fn makeStorage( comptime spec: anytype ) type
{
	var fields: [spec.len]Type.StructField = undefined;
    for (spec,&fields) |t, *f| {
        f.* = .{
            .name = t[0],
            .type = t[1],
            .default_value_ptr = null, // not sure how to get optional types working here, just setting the defaults inside the default() function
            .is_comptime = false,
            .alignment = 0,
        };
    }
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = fields[0..],
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}


pub fn makeOptions( comptime spec: anytype ) type
{
    return struct {
        const NamedOptions = makeStorage( spec );


        named_opts: NamedOptions,
        args: [][:0]const u8,
        allocator: std.mem.Allocator,

        pub const Field = std.meta.FieldEnum(NamedOptions);

        fn FieldType(comptime field: Field) type
        {
            return @FieldType(NamedOptions, @tagName(field));
        }

        pub fn get( self: @This(), comptime field: Field ) FieldType(field)
        {
            return @field( self.named_opts, spec[@intFromEnum(field)][0] );
        }

        fn parseType( self: *@This(), comptime Root: type, comptime T: type, itr: anytype ) error{MissingValue, Overflow, InvalidCharacter,OutOfMemory}!Root
        {
            switch(@typeInfo(T)) 
            {
                .bool => return true,
                .int => {
                    const text = itr.next() orelse return error.MissingValue;
                    return try std.fmt.parseInt( T, text, 0 );
                },
                .optional => |info| return self.parseType( Root, info.child, itr ),
                .pointer => |info| {
                    if (info.size != .slice or info.child != u8) @compileError("cannot parse pointer");
                    // TODO: posix convention allows an arg to be declared right next to it eg "--foo=bar"
                    const text = itr.next() orelse return error.MissingValue;
					if (info.sentinel_ptr != null) {
						return try self.allocator.dupeZ( u8, text );
					} else {
						const dup = try self.allocator.dupe( u8, text );
						return dup;
					}
                },
                else => @compileError("unhandled type")
            } 
        }

        fn printError( field: []const u8, err: anytype ) !void // TODO: figure out how to specify the type properly
        {
            const stdErr = std.io.getStdErr().writer();
            switch( err )
            {
                error.MissingValue => {
                    try stdErr.print("missing arg for \"{s}\"\n", .{ field });
                    return error.OptionsParseFailed;
                },
                error.Overflow => {
                    try stdErr.print("invalid value for \"{s}\"\n", .{ field });
                },
                else => return err,
            }

             return error.OptionsParseFailed;
        }

        fn parseField( self: *@This(), comptime s: anytype, itr: anytype ) !void
        {
            @field( self.named_opts, s[0] ) = self.parseType( s[1], s[1], itr ) catch |err| return printError( s[0], err );
        }

        fn parseShort( self: *@This(), c: u8, itr: anytype ) !void
        {
            inline for( spec ) |s| {
                if (s[3] != 0 and s[3] == c) return self.parseField( s, itr );
            }
        }

        fn parseLong( self: *@This(), name: []const u8, itr: anytype ) !void
        {
            inline for( spec ) |s| {
                if ( std.mem.eql( u8, name, s[0] ) ) return self.parseField( s, itr );
            }
        }

        fn default( allocator: std.mem.Allocator ) @This()
        {
            var named_opts : NamedOptions = undefined;
            inline for(spec) |s|
            {
                @field(named_opts, s[0]) = s[2];
            }

            return .{ .named_opts = named_opts, .args = &[0][:0]u8{}, .allocator = allocator };
        }

        pub fn parse( allocator: std.mem.Allocator ) !@This()
        {
			var itr = try std.process.ArgIterator.initWithAllocator( allocator );
			defer itr.deinit();

			_ = itr.skip();
			return parseInternal( allocator, &itr );
		}

		pub fn parseFromSlice( allocator: std.mem.Allocator, args: [][:0]const u8 ) !@This()
		{
			const Itr = struct {
				slice: [][:0]const u8,
				idx: usize,

				pub fn next( itr: *@This() ) ?[]const u8
				{
					const i = itr.idx;
					itr.idx += 1;
					if ( i >= itr.slice.len ) return null;
					return itr.slice[i];
				}
			};

			var itr = Itr{ .slice = args, .idx = 0 };

			return parseInternal( allocator, &itr );
		}

		fn parseInternal( allocator: std.mem.Allocator, itr: anytype ) !@This()
		{
			var options: @This() = default( allocator );

            var args = std.ArrayList([:0]const u8).init( allocator );

            var parsing_named = true;
            while(itr.next()) |msg|
            {
                if (!parsing_named) {
                    try args.append( try allocator.dupeZ( u8, msg ) );
                    continue;
                }
                if (msg[0] != '-') {
                    try args.append( try allocator.dupeZ( u8, msg ) );
                    continue;
                }
                if ( msg.len == 1 )
                {
                    // TODO: what to do here?
                    continue;
                }
                if (msg[1] != '-') {
                    for (msg[1..]) |c| {
                        try options.parseShort( c, itr );
                    }
                    continue;
                }
                if ( std.mem.eql( u8, msg, "--" ) )
                {
                    parsing_named = false;
                    continue;
                }
                try options.parseLong( msg[2..], itr );
            }

            options.args = try args.toOwnedSlice();

            return options;
		}

        fn deinitField( self: @This(), v: anytype ) void
        {
            switch(@typeInfo(@TypeOf(v)))
            {
                .optional => if (v) |child_v| self.deinitField( child_v ),
                .pointer => |ptr| {
                    if (ptr.size == .slice) {
                        self.allocator.free( v );
                    }
                },
                else => {}
            }
        }

        pub fn deinit( self: @This() ) void
        {
            for(self.args) |arg|
            {
                self.allocator.free(arg);
            }
            self.allocator.free( self.args );

            inline for (spec) |s|
            {
                self.deinitField( @field( self.named_opts, s[0] ) );
            }
        }

        fn makeHelpLines( comptime remaining_text: []const u8 ) []const u8
        {
            const desired_len = 64;
            const prefix = "\n\t\t";
            if ( remaining_text.len < desired_len )
                return prefix ++ remaining_text;
            
            const line_end = blk: {
                for ( remaining_text[desired_len..], desired_len..) |c,i|
                {
                    if (c == ' ') break :blk i+1;
                }
                return prefix ++ remaining_text;
            };

            if ( line_end > remaining_text.len )
                return prefix ++ remaining_text;


            return prefix ++ remaining_text[0..line_end-1] ++ makeHelpLines( remaining_text[line_end..] );
        }

        pub fn printHelpText() !void
        {
            const lines = comptime blk: {
                var lines: [spec.len][]const u8 = undefined;
                for (spec,&lines) |s,*l|
                {
                    if (s[3] == 0) {
                        l.* = std.fmt.comptimePrint( "\n\t    --{s}{s}\n", .{ s[0], makeHelpLines(s[4]) });
                    } else {
                        l.* = std.fmt.comptimePrint( "\n\t-{c}, --{s}{s}\n", .{ s[3], s[0], makeHelpLines(s[4]) });
                    }
                }

                break :blk lines;
            };

            const stdout = std.io.getStdOut();
            for (lines) |line|
            {
                _ = try stdout.write( line );
            }
        }
    };
}

