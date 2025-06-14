#include <clang/Frontend/ASTUnit.h>
#include <clang/Tooling/Tooling.h>
#include <clang/Tooling/ASTDiff/ASTDiff.h>

static void printNode(clang::raw_ostream &OS, clang::diff::SyntaxTree &Tree,
                      clang::diff::NodeId Id) {
  if (Id.isInvalid()) {
    OS << "None";
    return;
  }
  OS << Tree.getNode(Id).getTypeLabel();
  std::string Value = Tree.getNodeValue(Id);
  if (!Value.empty())
    OS << ": " << Value;
  OS << "(" << Id << ")";
}

static void printTree(clang::raw_ostream &OS, clang::diff::SyntaxTree &Tree) {
  for (clang::diff::NodeId Id : Tree) {
    for (int I = 0; I < Tree.getNode(Id).Depth; ++I)
      OS << " ";
    printNode(OS, Tree, Id);
    OS << "\n";
  }
}

int dumpAst( clang::tooling::ClangTool* tool )
{
	std::vector<std::unique_ptr<clang::ASTUnit>> ASTs;
  	tool->buildASTs(ASTs);

	for ( auto& ast : ASTs )
	{
		//clang::diff::SyntaxTree Tree(ast->getASTContext());
		//printTree(llvm::outs(), Tree);
	}

	return 0;
}
