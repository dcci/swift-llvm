//===- Local.cpp - Unit tests for Local -----------------------------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/Utils/Local.h"
#include "llvm/AsmParser/Parser.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/DIBuilder.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/Support/SourceMgr.h"
#include "gtest/gtest.h"

using namespace llvm;

TEST(Local, RecursivelyDeleteDeadPHINodes) {
  LLVMContext C;

  IRBuilder<> builder(C);

  // Make blocks
  BasicBlock *bb0 = BasicBlock::Create(C);
  BasicBlock *bb1 = BasicBlock::Create(C);

  builder.SetInsertPoint(bb0);
  PHINode    *phi = builder.CreatePHI(Type::getInt32Ty(C), 2);
  BranchInst *br0 = builder.CreateCondBr(builder.getTrue(), bb0, bb1);

  builder.SetInsertPoint(bb1);
  BranchInst *br1 = builder.CreateBr(bb0);

  phi->addIncoming(phi, bb0);
  phi->addIncoming(phi, bb1);

  // The PHI will be removed
  EXPECT_TRUE(RecursivelyDeleteDeadPHINode(phi));

  // Make sure the blocks only contain the branches
  EXPECT_EQ(&bb0->front(), br0);
  EXPECT_EQ(&bb1->front(), br1);

  builder.SetInsertPoint(bb0);
  phi = builder.CreatePHI(Type::getInt32Ty(C), 0);

  EXPECT_TRUE(RecursivelyDeleteDeadPHINode(phi));

  builder.SetInsertPoint(bb0);
  phi = builder.CreatePHI(Type::getInt32Ty(C), 0);
  builder.CreateAdd(phi, phi);

  EXPECT_TRUE(RecursivelyDeleteDeadPHINode(phi));

  bb0->dropAllReferences();
  bb1->dropAllReferences();
  delete bb0;
  delete bb1;
}

TEST(Local, RemoveDuplicatePHINodes) {
  LLVMContext C;
  IRBuilder<> B(C);

  std::unique_ptr<Function> F(
      Function::Create(FunctionType::get(B.getVoidTy(), false),
                       GlobalValue::ExternalLinkage, "F"));
  BasicBlock *Entry(BasicBlock::Create(C, "", F.get()));
  BasicBlock *BB(BasicBlock::Create(C, "", F.get()));
  BranchInst::Create(BB, Entry);

  B.SetInsertPoint(BB);

  AssertingVH<PHINode> P1 = B.CreatePHI(Type::getInt32Ty(C), 2);
  P1->addIncoming(B.getInt32(42), Entry);

  PHINode *P2 = B.CreatePHI(Type::getInt32Ty(C), 2);
  P2->addIncoming(B.getInt32(42), Entry);

  AssertingVH<PHINode> P3 = B.CreatePHI(Type::getInt32Ty(C), 2);
  P3->addIncoming(B.getInt32(42), Entry);
  P3->addIncoming(B.getInt32(23), BB);

  PHINode *P4 = B.CreatePHI(Type::getInt32Ty(C), 2);
  P4->addIncoming(B.getInt32(42), Entry);
  P4->addIncoming(B.getInt32(23), BB);

  P1->addIncoming(P3, BB);
  P2->addIncoming(P4, BB);
  BranchInst::Create(BB, BB);

  // Verify that we can eliminate PHIs that become duplicates after chaning PHIs
  // downstream.
  EXPECT_TRUE(EliminateDuplicatePHINodes(BB));
  EXPECT_EQ(3U, BB->size());
}

std::unique_ptr<Module> parseIR(LLVMContext &C, const char *IR) {
  SMDiagnostic Err;
  std::unique_ptr<Module> Mod = parseAssemblyString(IR, Err, C);
  if (!Mod)
    Err.print("UtilsTests", errs());
  return Mod;
}

TEST(Local, ReplaceDbgDeclare) {
  LLVMContext C;

  // Original C source to get debug info for a local variable:
  // void f() { int x; }
  std::unique_ptr<Module> M = parseIR(
      C,
      "define void @f() !dbg !8 {\n"
      "entry:\n"
      "  %x = alloca i32, align 4\n"
      "  call void @llvm.dbg.declare(metadata i32* %x, metadata !11, metadata "
      "!DIExpression()), !dbg !13\n"
      "  call void @llvm.dbg.declare(metadata i32* %x, metadata !11, metadata "
      "!DIExpression()), !dbg !13\n"
      "  ret void, !dbg !14\n"
      "}\n"
      "declare void @llvm.dbg.declare(metadata, metadata, metadata)\n"
      "!llvm.dbg.cu = !{!0}\n"
      "!llvm.module.flags = !{!3, !4}\n"
      "!0 = distinct !DICompileUnit(language: DW_LANG_C99, file: !1, producer: "
      "\"clang version 6.0.0 \", isOptimized: false, runtimeVersion: 0, "
      "emissionKind: FullDebug, enums: !2)\n"
      "!1 = !DIFile(filename: \"t2.c\", directory: \"foo\")\n"
      "!2 = !{}\n"
      "!3 = !{i32 2, !\"Dwarf Version\", i32 4}\n"
      "!4 = !{i32 2, !\"Debug Info Version\", i32 3}\n"
      "!8 = distinct !DISubprogram(name: \"f\", scope: !1, file: !1, line: 1, "
      "type: !9, isLocal: false, isDefinition: true, scopeLine: 1, "
      "isOptimized: false, unit: !0, variables: !2)\n"
      "!9 = !DISubroutineType(types: !10)\n"
      "!10 = !{null}\n"
      "!11 = !DILocalVariable(name: \"x\", scope: !8, file: !1, line: 2, type: "
      "!12)\n"
      "!12 = !DIBasicType(name: \"int\", size: 32, encoding: DW_ATE_signed)\n"
      "!13 = !DILocation(line: 2, column: 7, scope: !8)\n"
      "!14 = !DILocation(line: 3, column: 1, scope: !8)\n");
  auto *GV = M->getNamedValue("f");
  ASSERT_TRUE(GV);
  auto *F = dyn_cast<Function>(GV);
  ASSERT_TRUE(F);
  Instruction *Inst = &F->front().front();
  auto *AI = dyn_cast<AllocaInst>(Inst);
  ASSERT_TRUE(AI);
  Inst = Inst->getNextNode()->getNextNode();
  ASSERT_TRUE(Inst);
  auto *DII = dyn_cast<DbgDeclareInst>(Inst);
  ASSERT_TRUE(DII);
  Value *NewBase = Constant::getNullValue(Type::getInt32PtrTy(C));
  DIBuilder DIB(*M);
  replaceDbgDeclare(AI, NewBase, DII, DIB, DIExpression::NoDeref, 0,
                    DIExpression::NoDeref);

  // There should be exactly two dbg.declares.
  int Declares = 0;
  for (const Instruction &I : F->front())
    if (isa<DbgDeclareInst>(I))
      Declares++;
  EXPECT_EQ(2, Declares);
}
