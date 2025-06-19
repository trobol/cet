#include <clang/AST/RecursiveASTVisitor.h>
#include <clang/Tooling/Tooling.h>
#include <clang/Tooling/CompilationDatabase.h>
#include <clang/Frontend/CompilerInstance.h>
#include <clang/Index/USRGeneration.h>

#include <clang/Tooling/CommonOptionsParser.h>
#include <clang/Tooling/Tooling.h>
// Declares llvm::cl::extrahelp.
#include <llvm/Support/CommandLine.h>



#include <clang/Tooling/CompilationDatabase.h>

#include <sqlite3.h>

#include "clang.h"

#include <clang/Frontend/Utils.h>



static int sql_callback(void *NotUsed, int argc, char **argv, char **azColName){
	int i;
	for(i=0; i<argc; i++){
		printf("%s = %s\n", azColName[i], argv[i] ? argv[i] : "NULL");
	}
	printf("\n");
	return 0;
}

void sql_run_raw(sqlite3 *db, const char* cmd)
{
	char *zErrMsg = 0;
	int rc = sqlite3_exec(db, cmd, sql_callback, 0, &zErrMsg);
	if (rc != SQLITE_OK) 
	{
		fprintf(stderr, "SQL error: %s\n", zErrMsg);
		sqlite3_free(zErrMsg);
		exit(EXIT_FAILURE);
	}
}

template <typename T>
int sql_bind( sqlite3_stmt *stmt, int idx, T value);

template <>
int sql_bind<const char*>( sqlite3_stmt *stmt, int idx, const char* value)
{
	return sqlite3_bind_text(stmt, idx, value, -1, NULL);
}

template <>
int sql_bind<char*>( sqlite3_stmt *stmt, int idx, char* value)
{
	return sqlite3_bind_text(stmt, idx, value, -1, NULL);
}

template <>
int sql_bind<int64_t>( sqlite3_stmt *stmt, int idx, int64_t value)
{
	return sqlite3_bind_int64(stmt, idx, value);
}

template <typename...Args>
int sql_stmt_bind(sqlite3_stmt *stmt, Args... args)
{
	return sql_stmt_bind_impl( stmt, 1, args...);
}


template <typename T>
int sql_stmt_bind_impl(sqlite3_stmt *stmt, int idx, T arg0)
{
	int rc = sql_bind(stmt, idx, arg0);
	if (rc != SQLITE_OK) {
		fprintf(stderr, "SQL bind %i failed %i\n", idx, rc);
	}
	return rc;
}


template <typename T, typename...Args>
int sql_stmt_bind_impl(sqlite3_stmt *stmt, int idx, T arg0, Args... args)
{
	int rc = sql_stmt_bind_impl( stmt, idx, arg0 );
	if (rc != SQLITE_OK) {
		return rc;
	}
	return sql_stmt_bind_impl( stmt, idx + 1, args...);
}

template <typename...Args>
void sql_run_stmt(sqlite3_stmt *stmt, Args... args)
{
	int rc;
	rc = sql_stmt_bind(stmt, args...);
	
	while( 1 ) {
		rc = sqlite3_step(stmt);
		if (rc == SQLITE_DONE) break;
		if (rc == SQLITE_BUSY) continue;
		if (rc == SQLITE_ERROR) 
		{
			fprintf(stderr, "SQL error while running query");
			return;
		}
	}

	sqlite3_reset(stmt);
}


void sql_add_node(sqlite3_stmt *stmt, int64_t id, int64_t parent_id, const char* text)
{
	fprintf( stderr, "%lli %lli %s\n", id, parent_id, text);
	int rc;
	rc = sql_bind(stmt, 1, id);
	if (rc != SQLITE_OK) {
		fprintf(stderr, "SQL bind 1 failed %i\n", rc);
	}

	rc = sql_bind(stmt, 2, parent_id);
	if (rc != SQLITE_OK)
	{
		fprintf(stderr, "SQL bind 2 failed %i\n", rc);
	}

	rc = sql_bind(stmt, 3, text);
	if (rc != SQLITE_OK)
	{
		fprintf(stderr, "SQL bind 3 failed %i\n", rc);
	}

	while( 1 ) {
		rc = sqlite3_step(stmt);
		if (rc == SQLITE_DONE) break;
		if (rc == SQLITE_BUSY) continue;
		if (rc == SQLITE_ERROR) 
		{
			fprintf(stderr, "SQL error while running query");
			return;
		}
	}

	sqlite3_reset(stmt);
}


void* OS_MemReserve( size_t size );
void OS_MemFree( void* ptr );
void* OS_MemCommit( void* ptr, size_t size );

template <typename T>
class InfiniteArray
{
public:
	static InfiniteArray Init()
	{
		ptrdiff_t reserve_size = RESERVE_GRANULARITY * 256;
		char* begin = (char*)OS_MemReserve(reserve_size);
		
		return InfiniteArray( begin );
	}


	T* create( size_t count )
	{
		ptrdiff_t padding = (-(uintptr_t)m_head) & ( alignof(T) - 1 );
		ptrdiff_t available = m_tail - m_head - padding;
		if (available < 0 || count > available/sizeof(T)) {
			expand( count*sizeof(T));
		}

		void *p = m_head + padding;
		m_head += padding + count*sizeof(T);
		return (T*)memset(p, 0, count*sizeof(T));
	}

	void push_back( T val )
	{
		T* ptr = create( 1 );
		*ptr = val;
	}

	void deinit()
	{
		OS_MemFree( m_head );
	}

	size_t size() { return (reinterpret_cast<size_t>( m_head ) - reinterpret_cast<size_t>( m_start )) / sizeof(T); };
	T* data() { return reinterpret_cast<T*>( m_start ); };

private:
	static const size_t COMMIT_GRANULARITY = 1024 * 4;
	static const size_t RESERVE_GRANULARITY = 1024 * 64;
	
	InfiniteArray( char* begin) : m_start{begin}, m_head{begin}, m_tail{begin} {}

	char* m_start; // start of the whole reserved area
	char* m_head; // start of the current free but commited area
	char* m_tail; // end of current committed area

	
	void expand( ptrdiff_t amount )
	{
		// round to nearest COMMIT_GRANULARITY
		ptrdiff_t commit_size = amount % COMMIT_GRANULARITY;
		if (commit_size != 0) commit_size = COMMIT_GRANULARITY - commit_size;
		commit_size += amount;
		
		// attemt to commit enough size starting at end
		// this might commit the same page again, but that won't cause an error, and for now I'm not gonna worry about it
		void* result = OS_MemCommit( m_tail, commit_size );
		if (result == NULL) {
			// TODO: if the error is ERROR_INVALID_ADDRESS, we have probably run out of reserved memory and should give a different message
			// DWORD err = GetLastError();
			abort();
		}
		m_tail += commit_size;

	}
};


class InfiniteTextBuffer : public InfiniteArray<char>
{
public:
	const char* dupe( const char* start, size_t len )
	{
		char* copy = create( len + 1 );
		memcpy(copy, start, len);
		copy[len] = '\0';
		return copy;
	}

};

struct ParsedModuleInfo
{
	InfiniteArray<ParsedItemInfo> infos;
	InfiniteTextBuffer text_buf;
};


Slice_ParsedItemInfo ParsedModuleInfo_getItems( ParsedModuleInfo* minfo )
{
	return { minfo->infos.data(), minfo->infos.size() };
}

Slice_Byte ParsedModuleInfo_getTextCache( ParsedModuleInfo* minfo )
{
	return { minfo->text_buf.data(), minfo->text_buf.size() };
}

void ParsedModuleInfo_deinit( ParsedModuleInfo* minfo )
{
	minfo->infos.deinit();
	minfo->text_buf.deinit();
}

class Recorder {
	
	Recorder() : output{InfiniteArray<ParsedItemInfo>::Init(), InfiniteArray<char>::Init()} {}

public:
	void record( int64_t id, int64_t parent_id, std::string_view name )
	{
		const char* copy = output.text_buf.dupe( name.data(), name.size() );
		output.infos.push_back(ParsedItemInfo{id, parent_id, copy});
	}

	struct Item 
	{
		int64_t id;
		int64_t parent_id;
		const char* text;
	};
	
	ParsedModuleInfo output;

	static Recorder Init( )
	{
		return Recorder();
	}
};



class Visitor : public clang::RecursiveASTVisitor<Visitor> {
public:


	using ParentStack = std::vector<int64_t>;

	struct ParentPopper {
		ParentStack* parentStack;
		int64_t id;

		ParentPopper() : parentStack{nullptr}, id{0} {};
		ParentPopper(ParentStack* p, int64_t i) : parentStack{p}, id{i} {};
		ParentPopper (const ParentPopper&) = delete;
		ParentPopper& operator= (const ParentPopper&) = delete;

		ParentPopper(ParentPopper&& other) { parentStack = other.parentStack; id = other.id; other.parentStack = nullptr; };
		ParentPopper& operator=(ParentPopper&& other) { parentStack = other.parentStack; id = other.id; other.parentStack = nullptr; return *this; };
		~ParentPopper() {
			if (parentStack != nullptr)
			{
				assert( parentStack->back() == id );
				parentStack->pop_back();
			}
		}
	};

	ParentPopper pushParent( int64_t id )
	{
		parentStack.push_back( id );
		return std::move(ParentPopper( &parentStack, id  ));
	}

	int64_t get_parent()
	{
		if (parentStack.size() < 2) return 0;
		return parentStack[parentStack.size()-2];
	}

	bool TraverseDecl(clang::Decl *D) {

		bool recordParent = D->getKind() != clang::Decl::Kind::Var;

		ParentPopper pp = {};
		
		if (recordParent) {
			int64_t id = D->getCanonicalDecl()->getID();
			pp = pushParent(D->getID());
		}
        clang::RecursiveASTVisitor<Visitor>::TraverseDecl(D); // Forward to base class
		return true; // Return false to stop the AST analyzing
	}

	bool VisitNamedDecl(clang::NamedDecl *D)
	{	
		if (!D->isCanonicalDecl()) return true;

		//D->getDeclName().dump();
		const char* name = "";
		clang::IdentifierInfo* info = D->getIdentifier();
		if (info)
		{
			name = info->getNameStart();
		}

		char params[256] = {};
		clang::Decl::Kind kind = D->getKind();
		if ( kind == clang::Decl::Kind::Function )
		{

		}
		
		
		llvm::SmallString<1024> usr_buf;
		clang::index::generateUSRForDecl(D, usr_buf);
		recorder->record( D->getID(), get_parent(), name );
		return true;
	}

	bool TraverseStmt(clang::Stmt *x) {

		//parentStack.push_back(x->getID(*Context));
		clang::RecursiveASTVisitor<Visitor>::TraverseStmt(x);
		//parentStack.pop_back();

		return true;
	}

	bool VisitStmt(clang::Stmt* smt)
	{
		//sql_add_node(pStmt, smt->getID(*Context), get_parent(), ""); 
		//recorder->record( smt->getID(*Context), parentStack.back(), smt->getName().data() );
		return true;
	}

	bool VisitDeclRefExpr(clang::DeclRefExpr* expr)
	{
		//if (pStmt == NULL) fprintf( stderr, "null statement\n");
		//printf("%s %lli %s\n", indent + parentStack.size(), expr->getID(*Context), expr->getDecl()->getName().data());
		recorder->record(expr->getID(*Context), parentStack.back(), expr->getDecl()->getName().data()); 
		
		return false;
	}


	bool TraverseType(clang::QualType x) {
		clang::RecursiveASTVisitor<Visitor>::TraverseType(x);
		return true;
	}
	Visitor(Recorder *r, clang::ASTContext* c) : recorder{r}, Context{c} {};
	clang::ASTContext* Context;
	std::vector<int64_t> parentStack;
	Recorder* recorder;


	static void RecordAst( Recorder* recorder, clang::ASTContext* context )
	{
		Visitor visitor( recorder, context );
		visitor.TraverseDecl( context->getTranslationUnitDecl() );
	}
};


class AstQueuer : public clang::tooling::ToolAction {

	using Queue = std::vector<std::unique_ptr<clang::ASTUnit>>;

	std::vector<std::unique_ptr<clang::ASTUnit>> *m_queue;

public:

	AstQueuer( Queue* queue ) : m_queue{queue} {}

	
	bool runInvocation(std::shared_ptr<clang::CompilerInvocation> Invocation,
                     clang::FileManager *Files,
                     std::shared_ptr<clang::PCHContainerOperations> PCHContainerOps,
                     clang::DiagnosticConsumer *DiagConsumer) override {
    std::unique_ptr<clang::ASTUnit> AST = clang::ASTUnit::LoadFromCompilerInvocation(
        Invocation, std::move(PCHContainerOps),
        clang::CompilerInstance::createDiagnostics(&Invocation->getDiagnosticOpts(),
                                            DiagConsumer,
                                            /*ShouldOwnClient=*/false),
        Files);
    if (!AST)
      return false;

    m_queue->emplace_back(std::move(AST));
    return true;
  }

};

int traverseAst( clang::tooling::ClangTool* tool, const std::string& db_name )
{

	Recorder recorder = Recorder::Init();
	std::vector<std::unique_ptr<clang::ASTUnit>> ASTs;
	tool->buildASTs(ASTs);

	for ( auto& ast : ASTs )
	{
		clang::ASTContext* context = &ast->getASTContext();
		Visitor::RecordAst( &recorder, context );
	}

	return 0;
}

int traverseAstNullTest( clang::tooling::ClangTool* tool, const std::string& db_name )
{

	Recorder recorder = Recorder::Init();
	std::vector<std::unique_ptr<clang::ASTUnit>> ASTs;
	tool->buildASTs(ASTs);
	return 0;
}

struct CompileDatabase
{
	InfiniteTextBuffer text;
	InfiniteArray<const char*> argv;
	InfiniteArray<CompileCommand> commands; 
};

EXPORTED Slice_CompileCommand CompileDatabase_getAllCommands( CompileDatabase* db )
{
	return { db->commands.data(), db->commands.size() };
}

EXPORTED void CompileDatabase_deinit( CompileDatabase* db )
{
	db->text.deinit();
	db->argv.deinit();
	db->commands.deinit();
}

EXPORTED CompileDatabase* parseDB( const char* directory, const char** err )
{

	std::string load_err;
	std::unique_ptr<clang::tooling::CompilationDatabase> db = 
		clang::tooling::CompilationDatabase::loadFromDirectory(directory, load_err);
	if ( !db ) {
		*err = strdup( load_err.c_str() );
		return nullptr;
	}

	fflush( stdout );
	CompileDatabase* out = new CompileDatabase{
		InfiniteArray<char>::Init(), 
		InfiniteArray<const char*>::Init(),
		InfiniteArray<CompileCommand>::Init() };

	std::vector<clang::tooling::CompileCommand> cmds = db->getAllCompileCommands();

	for ( clang::tooling::CompileCommand& cmd : cmds )
	{
		CompileCommand* ptr = out->commands.create(1);

		ptr->directory = out->text.dupe( cmd.Directory.c_str(), cmd.Directory.size() );
		ptr->filename = out->text.dupe( cmd.Filename.c_str(), cmd.Filename.size() );
		ptr->output = out->text.dupe( cmd.Output.c_str(), cmd.Output.size() );

		ptr->heuristic = nullptr;
		if (cmd.Heuristic.size() > 0)
		{
			ptr->heuristic = out->text.dupe( cmd.Heuristic.c_str(), cmd.Heuristic.size() );
		}

		size_t argc = cmd.CommandLine.size();
		ptr->argc = argc;
	
		const char** argv = out->argv.create( argc );
		for (int i = 0; i < argc; i++)
		{
			argv[i] = out->text.dupe( cmd.CommandLine[i].c_str(), cmd.CommandLine[i].size() );
		}
		ptr->argv = argv;
	}

	return out;
}

// TODO: look at  ASTUnit::LoadFromCommandLine and see if there is anything missing
EXPORTED ParsedModuleInfo* parseFromArgs( size_t argc, const char* argv[] )
{

		// fixme: do I need to use injectResourceDir here?

#if 0 
	clang::ArrayRef<const char*> args( argv, argc );
	std::unique_ptr<clang::CompilerInvocation> invocation( clang::createInvocation( args ) );

	std::unique_ptr<clang::ASTUnit> AST = clang::ASTUnit::LoadFromCompilerInvocation(
        std::move( invocation ), {},
        clang::CompilerInstance::createDiagnostics(&invocation->getDiagnosticOpts(),
                                            /*DiagConsumer=*/nullptr,
                                            /*ShouldOwnClient=*/false), nullptr );
#endif


	std::unique_ptr<clang::ASTUnit> ast = clang::ASTUnit::LoadFromCommandLine( 
		argv, argv + argc,
		std::make_shared<clang::PCHContainerOperations>(),
		clang::CompilerInstance::createDiagnostics(new clang::DiagnosticOptions),
		""
		);

	Recorder recorder = Recorder::Init();
	Visitor::RecordAst( &recorder, &ast->getASTContext() );

	return new ParsedModuleInfo( recorder.output );
}

EXPORTED ParsedModuleInfo* parseFromDB( const char* path )
{
	return nullptr;
}


// signature        4 bytes cetdb
// spec ver         4 bytes
// file hash        8 bytes
// file write time  8 bytes
// item count	    4 bytes
// text block count 4 bytes (block is 1024 bytes)

// items


// id              8 bytes
// parent id       8 bytes
// text id         8 bytes

// text