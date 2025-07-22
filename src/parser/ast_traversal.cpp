#include <clang/AST/RecursiveASTVisitor.h>
#include <clang/AST/Mangle.h>
#include <clang/Tooling/Tooling.h>
#include <clang/Tooling/CompilationDatabase.h>
#include <clang/Frontend/CompilerInstance.h>
#include <clang/Index/USRGeneration.h>

#include <clang/Tooling/CommonOptionsParser.h>
#include <clang/Tooling/Tooling.h>
// Declares llvm::cl::extrahelp.
#include <llvm/Support/CommandLine.h>



#include <clang/Tooling/CompilationDatabase.h>

#include "clang.h"

#include <clang/Frontend/Utils.h>

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
	InfiniteArray<Node> nodes;
	InfiniteArray<Connection> connections;
	InfiniteTextBuffer text_buf; // TODO: make this a hashmap + allocator
};

EXPORTED struct Slice_Node ParsedModuleInfo_getNodes( ParsedModuleInfo* minfo )
{
	return { minfo->nodes.data(), minfo->nodes.size() };
}

EXPORTED struct Slice_Connection ParsedModuleInfo_getConnections( ParsedModuleInfo* minfo )
{
	return { minfo->connections.data(), minfo->connections.size() };
}


Slice_Byte ParsedModuleInfo_getTextCache( ParsedModuleInfo* minfo )
{
	return { minfo->text_buf.data(), minfo->text_buf.size() };
}

void ParsedModuleInfo_deinit( ParsedModuleInfo* minfo )
{
	minfo->nodes.deinit();
	minfo->connections.deinit();
	delete minfo;
}

class Recorder {
public:
	RecorderInterface interface;
	void addNode( int64_t id, std::string_view identifier )
	{
		interface.addNode( interface.ud, id, identifier.data(), identifier.size() );
	}

	void addConnection( int64_t from, int64_t to )
	{
		interface.addConnection( interface.ud, from, to );
	}

	void addLinkIdentifier( int64_t id, std::string_view identifier )
	{
		interface.addLinkIdentifier( interface.ud, id, identifier.data(), identifier.size() );
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
		if (!D) return true;
		bool recordParent = D->getKind() != clang::Decl::Kind::Var;

		ParentPopper pp = {};
		
		if (recordParent) {
			int64_t id = D->getCanonicalDecl()->getID();
			pp = pushParent(D->getID());
		}


		return clang::RecursiveASTVisitor<Visitor>::TraverseDecl(D);; // Return false to stop the AST analyzing
	}


	// TODO: is there any reason to visit non-named decls, 
	// seems like most things count as "named" to clang, is there a definition of this in some standard?
	bool VisitNamedDecl(clang::NamedDecl *D)
	{	
		// TODO: evaluate and write down what will be effected by this call
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
		
		
		//llvm::SmallString<1024> usr_buf;
		//clang::index::generateUSRForDecl(D, usr_buf);
		int64_t id = D->getID();

		recorder->addNode( id, name );
		recorder->addConnection(id, get_parent());


		// TAKEN FROM llvm JSONNodeDumper
		// FIXME: There are likely other contexts in which it makes no sense to ask
		// for a mangled name.
		if (llvm::isa<clang::RequiresExprBodyDecl>(D->getDeclContext()))
			return true;

		// If the declaration is dependent or is in a dependent context, then the
		// mangling is unlikely to be meaningful (and in some cases may cause
		// "don't know how to mangle this" assertion failures.
		if (D->isTemplated())
			return true;

		// Mangled names are not meaningful for locals, and may not be well-defined
		// in the case of VLAs.
		auto *VD = llvm::dyn_cast<clang::VarDecl>(D);
		if (VD && VD->hasLocalStorage())
			return true;

		// Do not mangle template deduction guides.
		if (llvm::isa<clang::CXXDeductionGuideDecl>(D))
			return true;

		
		llvm::SmallString<1024> name_buf;
		llvm::raw_svector_ostream stream(name_buf);
		if ( astNameGenerator.writeName(D, stream) == false )
		{
			recorder->addLinkIdentifier( id, { name_buf.c_str(), name_buf.size() });
		}

		//std::vector<std::string> identifiers = astNameGenerator.getAllManglings( D );
		//for ( std::string& str : identifiers ) {
		//	recorder->addLinkIdentifier( id, str );
		//}
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
		int64_t id = expr->getID(*Context);
		recorder->addNode( id, expr->getDecl()->getNameAsString().data()); 
		recorder->addConnection( id, parentStack.back());
		return false;
	}

	bool VisitExpr(clang::Expr *expr)
	{
		
		return true;
	}


	bool TraverseType(clang::QualType x) {
		clang::RecursiveASTVisitor<Visitor>::TraverseType(x);
		return true;
	}


	Visitor(Recorder *r, clang::ASTContext* c) : recorder{r}, Context{c}, astNameGenerator{*c} {};
	clang::ASTContext* Context;
	std::vector<int64_t> parentStack;
	Recorder* recorder;
	clang::ASTNameGenerator astNameGenerator;


	static void RecordAst( Recorder* recorder, clang::ASTContext* context )
	{
		Visitor visitor( recorder, context );
		visitor.TraverseDecl( context->getTranslationUnitDecl() );
	}
};


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
	delete db;
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
EXPORTED void parseFromArgs( RecorderInterface interface, u64 argc, const char* argv[] )
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


	Recorder recorder = Recorder{interface};
	Visitor::RecordAst( &recorder, &ast->getASTContext() );
}

int dumpAst( clang::ASTContext& ctx );
EXPORTED void dumpFromArgs( u64 argc, const char* argv[] )
{
	std::unique_ptr<clang::ASTUnit> ast = clang::ASTUnit::LoadFromCommandLine( 
	argv, argv + argc,
	std::make_shared<clang::PCHContainerOperations>(),
	clang::CompilerInstance::createDiagnostics(new clang::DiagnosticOptions),
	""
	);

	dumpAst( ast->getASTContext() );
	
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