// Declares clang::SyntaxOnlyAction.
//#include <clang/Frontend/FrontendActions.h>
#include <clang/Tooling/CommonOptionsParser.h>
#include <clang/Tooling/Tooling.h>
// Declares llvm::cl::extrahelp.
#include <llvm/Support/CommandLine.h>



#include <clang/Tooling/CompilationDatabase.h>


using namespace clang::tooling;
using namespace llvm;



// Apply a custom category to all command-line options so that they are the
// only ones displayed.
static cl::OptionCategory MyToolCategory("my-tool options");

// CommonOptionsParser declares HelpMessage with a description of the common
// command-line options related to the compilation database and input files.
// It's nice to have this help message in all tools.
//static cl::extrahelp CommonHelp(CommonOptionsParser::HelpMessage);

// A help message for this specific tool can be added afterwards.
//static cl::extrahelp MoreHelp("\nMore help text...\n");



static cl::opt<std::string> arg_Path("path", cl::desc("Specify path"), cl::value_desc("path"), cl::cat(MyToolCategory));
cl::opt<std::string> arg_None(cl::Positional, cl::desc("<regular expression>"), cl::cat(MyToolCategory)); 
static cl::opt<bool> arg_DumpAST("dump-ast", cl::desc("bool"), cl::cat(MyToolCategory));

int traverseAst(clang::tooling::ClangTool* tool, const std::string& db_name);
int dumpAst( clang::tooling::ClangTool* tool );

void AttachCrashHandler();


int main(int argc, const char **argv) {
	AttachCrashHandler();
	
	cl::HideUnrelatedOptions(MyToolCategory);
	cl::ParseCommandLineOptions(argc, argv);
	/*
	std::string ErrorMessage;
	std::unique_ptr<FixedCompilationDatabase> compDB = FixedCompilationDatabase::loadFromCommandLine(argc, argv, ErrorMessage);
	if (!ErrorMessage.empty()) {
		printf("failed to create db: '%s'\n", ErrorMessage.c_str() );
		return EXIT_FAILURE;
	}


	clang::tooling::ClangTool tool(
		*compDB,
		std::vector<std::string>(1, "main.cpp"));
	*/
	std::string loadError;
	std::unique_ptr<CompilationDatabase> db = CompilationDatabase::loadFromDirectory(arg_Path, loadError);
	if ( !db ) {
		fprintf(stderr, "failed to load db: %s\n", loadError.c_str());
		return EXIT_FAILURE;
	}



	ClangTool Tool(*db, db->getAllFiles());

	if ( arg_DumpAST )
	{
		return dumpAst( &Tool );
	}

	std::chrono::milliseconds ms = std::chrono::duration_cast< std::chrono::milliseconds >(
	std::chrono::system_clock::now().time_since_epoch() );

	char buf[1024];
	sprintf(buf, "%llu.db", ms.count());


	return traverseAst(&Tool, std::string(buf));
}
