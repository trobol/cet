//#include <stdint.h>


#if __cplusplus
#if HAVE_VISIBILITY
#define EXPORTED __attribute__((__visibility__("default"))) extern "C"
#elif (defined _WIN32 && !defined __CYGWIN__) 
#define EXPORTED __declspec(dllexport) extern "C"
#else
#error ""
#endif
#else
#define EXPORTED
#endif

typedef unsigned long long u64;
typedef long long i64;

typedef struct CompileCommand 
{
	const char* directory;
	const char* filename;
	const char* heuristic;
	const char* output;
	u64 argc;
	const char** argv;
} CompileCommand;



typedef struct Slice_CompileCommand
{
	CompileCommand* ptr;
	u64 len;
} Slice_CompileCommand;

typedef struct CompileDatabase CompileDatabase;
EXPORTED Slice_CompileCommand CompileDatabase_getAllCommands( CompileDatabase* db );
EXPORTED void CompileDatabase_deinit( CompileDatabase* db );

// pointer is owned by caller, call CompileDatabase_deinit to free it
EXPORTED CompileDatabase* parseDB( const char* directory , const char** err );

EXPORTED void printFree( );

typedef struct ParsedItemInfo
{
	i64 id;
	i64 parent_id;
	const char* text;
	// todo: source location
} ParsedItemInfo;



typedef struct ParsedModuleInfo ParsedModuleInfo;

struct Slice_ParsedItemInfo { ParsedItemInfo* ptr; u64 len; };
EXPORTED struct Slice_ParsedItemInfo ParsedModuleInfo_getItems( ParsedModuleInfo* minfo );

struct Slice_Byte { const char* ptr; u64 len; };
EXPORTED struct Slice_Byte ParsedModuleInfo_getTextCache( ParsedModuleInfo* minfo );

EXPORTED void ParsedModuleInfo_deinit( ParsedModuleInfo* minfo );



EXPORTED ParsedModuleInfo* parseFromArgs( u64 argc, const char* argv[] );
EXPORTED ParsedModuleInfo* parseFromDB( const char* path );

