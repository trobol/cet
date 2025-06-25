#include <clang/Frontend/ASTUnit.h>
#include <clang/Tooling/Tooling.h>
#include <clang/Tooling/ASTDiff/ASTDiff.h>

#include "clang.h"

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

int dumpAst( clang::ASTContext& ctx )
{

	clang::diff::SyntaxTree Tree(ctx);
	printTree(llvm::outs(), Tree);

	return 0;
}



