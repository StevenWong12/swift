//===--- AfterPoundExprCompletion.cpp -------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#include "swift/IDE/AfterPoundExprCompletion.h"
#include "swift/IDE/CodeCompletion.h"
#include "swift/IDE/CompletionLookup.h"
#include "swift/Sema/CompletionContextFinder.h"
#include "swift/Sema/ConstraintSystem.h"
#include "swift/Sema/IDETypeChecking.h"

using namespace swift;
using namespace swift::constraints;
using namespace swift::ide;

void AfterPoundExprCompletion::sawSolutionImpl(const constraints::Solution &S) {
  auto &CS = S.getConstraintSystem();
  Type ExpectedTy = getTypeForCompletion(S, CompletionExpr);

  bool IsAsync = isContextAsync(S, DC);

  // If ExpectedTy is a duplicate of any other result, ignore this solution.
  auto IsEqual = [&](const Result &R) {
    return R.ExpectedTy->isEqual(ExpectedTy);
  };
  if (!llvm::any_of(Results, IsEqual)) {
    bool SingleExprBody = isImplicitSingleExpressionReturn(CS, CompletionExpr);
    Results.push_back({ExpectedTy, SingleExprBody, IsAsync});
  }
}

void AfterPoundExprCompletion::deliverResults(
    ide::CodeCompletionContext &CompletionCtx,
    CodeCompletionConsumer &Consumer) {
  ASTContext &Ctx = DC->getASTContext();
  CompletionLookup Lookup(CompletionCtx.getResultSink(), Ctx, DC,
                          &CompletionCtx);

  Lookup.shouldCheckForDuplicates(Results.size() > 1);

  for (auto &Result : Results) {
    Lookup.setExpectedTypes({Result.ExpectedTy},
                            Result.IsImplicitSingleExpressionReturn,
                            /*expectsNonVoid=*/true);
    Lookup.addPoundAvailable(ParentStmtKind);
    Lookup.addPoundLiteralCompletions(/*needPound=*/false);
    Lookup.addObjCPoundKeywordCompletions(/*needPound=*/false);
    Lookup.getMacroCompletions(/*needPound=*/false);
  }

  deliverCompletionResults(CompletionCtx, Lookup, DC, Consumer);
}
