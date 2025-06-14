#include <clang/AST/RecursiveASTVisitor.h>
#include <clang/Tooling/Tooling.h>
#include <clang/Frontend/CompilerInstance.h>
#include <clang/Index/USRGeneration.h>

#include <sqlite3.h>


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




class Recorder {
	
public:
	void record( int64_t id, int64_t parent_id, const char* text )
	{
		printf("%s\n", text);
		items.push_back({id, parent_id, strdup(text)});
	}

	struct Item 
	{
		int64_t id;
		int64_t parent_id;
		const char* text;
	};
	
	std::vector<Item> items;
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
};


int traverseAst( clang::tooling::ClangTool* tool, const std::string& db_name )
{

	Recorder recorder;
	std::vector<std::unique_ptr<clang::ASTUnit>> ASTs;
  	tool->buildASTs(ASTs);

	for ( auto& ast : ASTs )
	{
		clang::ASTContext* context = &ast->getASTContext();
		Visitor vistor( &recorder, context );
		vistor.TraverseDecl( context->getTranslationUnitDecl() );

	}

	return 0;
}
