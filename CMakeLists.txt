cmake_minimum_required(VERSION 3.27)

project(clang-tool-test VERSION 0.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Clang 18.1...<19.0 REQUIRED)
message(STATUS "Found LLVM ${LLVM_VERSION}")

add_library(External_lib_clang INTERFACE)
target_compile_definitions(External_lib_clang
	INTERFACE
		${LLVM_DEFINITIONS}
)
target_include_directories(External_lib_clang SYSTEM
	INTERFACE
		${LLVM_INCLUDE_DIRS}
		${CLANG_INCLUDE_DIRS}
)
llvm_map_components_to_libnames(REQ_LLVM_LIBS
	${LLVM_TARGETS_TO_BUILD} support core libdriver option
)
target_link_libraries(External_lib_clang
	INTERFACE
		clangASTMatchers
		clangFrontend
		clangSerialization
		clangDriver
		clangTooling
		clangToolingASTDiff
		clangParse
		clangSema
		clangStaticAnalyzerFrontend
		clangStaticAnalyzerCheckers
		clangStaticAnalyzerCore
		clangAnalysis
		clangRewriteFrontend
		clangEdit
		clangAST
		clangLex
		clangBasic

		${REQ_LLVM_LIBS}
)

add_library(External_lib_sqlite3
	src/external/sqlite/sqlite3.c
)
target_include_directories(External_lib_sqlite3 PUBLIC src/external/sqlite)

add_executable(sqlite_shell
	src/external/sqlite/shell.c
)
target_link_libraries(sqlite_shell
	PUBLIC
	External_lib_sqlite3
)

add_executable(viewer WIN32
	
	src/external/imgui/imgui_impl_vulkan.cpp
	src/external/imgui/imgui_impl_win32.cpp
	src/external/imgui/imgui.cpp
	src/external/imgui/imgui_widgets.cpp
	src/external/imgui/imgui_draw.cpp
	src/external/imgui/imgui_tables.cpp
	src/external/imgui/imgui_demo.cpp
	src/viewer/viewer.cpp
)

target_include_directories(viewer
	PRIVATE
	src/external/imgui
)

find_package(Vulkan REQUIRED)
target_link_libraries(viewer 
	PUBLIC
		External_lib_sqlite3
		Vulkan::Vulkan
		dwmapi
)



add_library( clang_tool_lib SHARED
	src/parser/ast_traversal.cpp
	src/parser/virtual_alloc.cpp
	src/parser/ast_dump.cpp
)

#set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDebug)


#set_property( TARGET clang_tool_lib PROPERTY MSVC_RUNTIME_LIBRARY MultiThreaded)

target_include_directories(clang_tool_lib PUBLIC
		${LLVM_INCLUDE_DIRS}
		${CLANG_INCLUDE_DIRS}	
)

target_link_libraries(clang_tool_lib
	PUBLIC
		External_lib_clang
		External_lib_sqlite3

)


#add_compile_options(/Bt+)
add_executable(clang-tool-test
	src/parser/parser.cpp
	src/parser/virtual_alloc.cpp
	src/parser/ast_traversal.cpp
	src/parser/ast_dump.cpp
	src/parser/crash_handler.cpp
)

target_include_directories(clang-tool-test SYSTEM
	INTERFACE
		${LLVM_INCLUDE_DIRS}
		${CLANG_INCLUDE_DIRS}	
)

target_link_libraries(clang-tool-test
	PUBLIC
		External_lib_clang
		External_lib_sqlite3
		user32
		kernel32 
)

#write_file( "libclang_path.txt" "${LLVM_INCLUDE_DIRS}" ";" "${CLANG_INCLUDE_DIRS}" )