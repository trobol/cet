#include <clang/AST/RecursiveASTVisitor.h>
#include <clang/Tooling/Tooling.h>
#include <clang/Frontend/CompilerInstance.h>
#include <clang/Index/USRGeneration.h>

#include <sqlite3.h>

int traverse_ast(clang::tooling::ClangTool* tool, const std::string& db_name);



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

class SingleFrontendActionFactory: public clang::tooling::FrontendActionFactory
{
public:
	SingleFrontendActionFactory(clang::FrontendAction* action) : m_action(action) {}
	std::unique_ptr<clang::FrontendAction> create() override { 
		printf("SingleFrontendActionFactory create\n");
		return std::unique_ptr<clang::FrontendAction>(m_action);
	}

private:
	clang::FrontendAction* m_action;
};



class Visitor : public clang::RecursiveASTVisitor<Visitor> {
public:

	int64_t get_parent()
	{
		if (parentStack.size() < 2) return 0;
		return parentStack[parentStack.size()-2];
	}

	bool TraverseDecl(clang::Decl *D) {

		bool recordParent = D->getKind() != clang::Decl::Kind::Var;
		
		if (recordParent) {
			int64_t id = D->getCanonicalDecl()->getID();
			parentStack.push_back(D->getID());
		}
        clang::RecursiveASTVisitor<Visitor>::TraverseDecl(D); // Forward to base class
		//printf("##TraverseDecl\n");
		//D->dump();
		if (recordParent) parentStack.pop_back();

		return true; // Return false to stop the AST analyzing
	}

	bool VisitNamedDecl(clang::NamedDecl *D)
	{	
		if (!D->isCanonicalDecl()) return true;

		D->getDeclName().dump();
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
		sql_run_stmt(pStmt,
			D->getID(),
			get_parent(),
			name,
			usr_buf.c_str(),
			params
		);
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
		return true;
	}

	bool VisitDeclRefExpr(clang::DeclRefExpr* expr)
	{
		//if (pStmt == NULL) fprintf( stderr, "null statement\n");
		//printf("%s %lli %s\n", indent + parentStack.size(), expr->getID(*Context), expr->getDecl()->getName().data());
		sql_add_node(pStmt, expr->getID(*Context), parentStack.back(), expr->getDecl()->getName().data()); 
		
		return false;
	}


	bool TraverseType(clang::QualType x) {
		clang::RecursiveASTVisitor<Visitor>::TraverseType(x);
		return true;
	}
	Visitor(sqlite3_stmt *stmt) : pStmt{stmt} {};
	sqlite3_stmt *pStmt;
	clang::ASTContext* Context;
	std::vector<int64_t> parentStack;
};


class FindNamedClassConsumer : public clang::ASTConsumer {
public:
	explicit FindNamedClassConsumer(clang::ASTContext *Context, sqlite3_stmt *stmt) : Visitor(stmt) {}

	virtual void HandleTranslationUnit(clang::ASTContext &Context) {
	//printf("HandleTranslationUnit\n");
		Visitor.Context = &Context;
		Visitor.TraverseDecl(Context.getTranslationUnitDecl());
	}
private:
	Visitor Visitor;
};

class FindNamedClassAction : public clang::ASTFrontendAction {
public:
	virtual std::unique_ptr<clang::ASTConsumer> CreateASTConsumer( clang::CompilerInstance &Compiler, llvm::StringRef InFile ) {
		printf("make FindNamedClassConsumer\n");
		return std::make_unique<FindNamedClassConsumer>(&Compiler.getASTContext(), pStmt);
	}

	FindNamedClassAction(sqlite3_stmt *stmt) : pStmt{stmt} {}
	sqlite3_stmt *pStmt;
};




int traverseAst(clang::tooling::ClangTool* tool, const std::string& db_name)
{
	sqlite3 *db;
	int rc = sqlite3_open(db_name.c_str(), &db);
	if( rc ){
		fprintf(stderr, "Can't open database: %s\n", sqlite3_errmsg(db));
		sqlite3_close(db);
		return(1);
	}

	sql_run_raw(db, "CREATE TABLE compile_db (id BIGINT, parent_id BIGINT, identifier text, usr text, params text);");

	sqlite3_stmt *pStmt;
	rc = sqlite3_prepare_v2(db, "INSERT INTO compile_db (id, parent_id, identifier, usr, params) VALUES (?, ?, ?, ?, ?)", -1, &pStmt, NULL);
	if (rc != SQLITE_OK)
	{
		fprintf(stderr, "SQL prepare error: %i %s\n", rc, sqlite3_errmsg(db));
		return EXIT_FAILURE;
	}

	clang::ASTFrontendAction* action = new FindNamedClassAction(pStmt);
	int toolstate = tool->run(new SingleFrontendActionFactory(action));

	fprintf( stderr, "\n\nfinished!\n" );
	sqlite3_finalize(pStmt);
	sqlite3_close(db);
	return toolstate;
}