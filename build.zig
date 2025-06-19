const std = @import("std");

const winsdk = std.zig.WindowsSdk;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

   //const lib = b.addStaticLibrary(.{
   //    .name = "clang-tool",
   //    // In this case the main source file is merely a path, however, in more
   //    // complicated build scripts, this could be a generated file.
   //    .root_source_file = b.path("src/root.zig"),
   //    .target = target,
   //    .optimize = optimize,
   //});

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    //b.installArtifact(lib);

	
	
	var cmake_config = b.addSystemCommand( &.{ "cmake", ".." } );
	cmake_config.setCwd( b.path( "build" ) );

	var cmake_build = b.addSystemCommand( &.{ "cmake", "--build", "." } );
	cmake_build.setCwd( b.path( "build" ) );
	cmake_build.step.dependOn( &cmake_config.step );

	const dynlib = b.addInstallBinFile( b.path("build/libclang_tool_lib.dll"), "libclang_tool_lib.dll" );
	dynlib.step.dependOn( &cmake_build.step );
	b.getInstallStep().dependOn( &dynlib.step );
	const dynlib_sym = b.addInstallBinFile( b.path("build/libclang_tool_lib.pdb"), "libclang_tool_lib.pdb" );
	dynlib_sym.step.dependOn( &cmake_build.step );
	b.getInstallStep().dependOn( &dynlib_sym.step );

	const imgui_lib = b.addStaticLibrary(.{
		.name = "imgui",
		.target = target,
		.optimize = optimize
	} );

	
	imgui_lib.addIncludePath( b.path("src/") );
	imgui_lib.addIncludePath( .{ .cwd_relative = "/VulkanSDK/1.3.280.0/Include" } );
	imgui_lib.linkLibCpp();
	imgui_lib.linkSystemLibrary( "gdi32" );
	imgui_lib.linkSystemLibrary( "dwmapi" );
	imgui_lib.addCSourceFiles(.{
		.files = &.{ 
			"src/imgui_wrapper.cpp",
			"src/external/imgui/imgui_impl_vulkan.cpp",
			"src/external/imgui/imgui_impl_win32.cpp",
			"src/external/imgui/imgui.cpp",
			"src/external/imgui/imgui_widgets.cpp",
			"src/external/imgui/imgui_tables.cpp",
			"src/external/imgui/imgui_draw.cpp",
			"src/external/imgui/imgui_demo.cpp",
		}
	}
	);

	const sqlite_lib = b.addStaticLibrary(.{
		.name = "sqlite",
		.target = target,
		.optimize = optimize
	});
	sqlite_lib.linkLibC();
	sqlite_lib.addCSourceFiles(.{
		.files = &.{
			"src/external/sqlite/sqlite3.c"
		}
	});



    const exe = b.addExecutable(.{
        .name = "clang-tool",
        .root_source_file = b.path("src/zig/viewer.zig"),
        .target = target,
        .optimize = optimize,
    });

	exe.step.dependOn( &cmake_build.step );

	const driver = b.addExecutable(.{
			.name = "cet-driver",
			.root_source_file = b.path("src/parser/cet-driver.zig"),
			.target = target,
			.optimize = optimize,
	});
	driver.addIncludePath( b.path("src/") );
	driver.step.dependOn( &cmake_build.step );
	b.installArtifact( driver );

	const cl = b.addExecutable(.{
			.name = "cet-cl",
			.root_source_file = b.path("src/parser/cet-cl.zig"),
			.target = target,
			.optimize = optimize,
	});
	cl.addIncludePath( b.path("src/") );
	cl.step.dependOn( &cmake_build.step );
	b.installArtifact( cl );

	const ld = b.addExecutable(.{
			.name = "cet-ld",
			.root_source_file = b.path("src/parser/cet-ld.zig"),
			.target = target,
			.optimize = optimize,
	});
	ld.addIncludePath( b.path("src/") );
	ld.step.dependOn( &cmake_build.step );
	b.installArtifact( ld );

	//exe.addIncludePath( .{ .cwd_relative = "/Program Files (x86)/Windows Kits/10/include/10.0.22621.0/um/"});
	//exe.linkLibC();
	exe.addIncludePath( b.path("src/") );
	exe.addIncludePath( .{ .cwd_relative = "/VulkanSDK/1.3.280.0/Include" } );
	exe.addLibraryPath( .{ .cwd_relative = "/VulkanSDK/1.3.280.0/Lib" } );
	exe.linkSystemLibrary("vulkan-1");

	exe.linkLibrary( imgui_lib );
	exe.linkLibrary( sqlite_lib );

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
	b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    //const lib_unit_tests = b.addTest(.{
    //    .root_source_file = b.path("src/root.zig"),
    //    .target = target,
    //    .optimize = optimize,
    //});
//
    //const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/zig/viewer.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    //test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
