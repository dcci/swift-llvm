; RUN: opt < %s -simplifycfg -S | FileCheck %s

define zeroext i1 @test1(i1 zeroext %flag, i32 %blksA, i32 %blksB, i32 %nblks) {
entry:
  br i1 %flag, label %if.then, label %if.else

; CHECK-LABEL: test1
; CHECK: add
; CHECK: select
; CHECK: icmp
; CHECK-NOT: br
if.then:
  %cmp = icmp uge i32 %blksA, %nblks
  %frombool1 = zext i1 %cmp to i8
  br label %if.end

if.else:
  %add = add i32 %nblks, %blksB
  %cmp2 = icmp ule i32 %add, %blksA
  %frombool3 = zext i1 %cmp2 to i8
  br label %if.end

if.end:
  %obeys.0 = phi i8 [ %frombool1, %if.then ], [ %frombool3, %if.else ]
  %tobool4 = icmp ne i8 %obeys.0, 0
  ret i1 %tobool4
}

define zeroext i1 @test2(i1 zeroext %flag, i32 %blksA, i32 %blksB, i32 %nblks) {
entry:
  br i1 %flag, label %if.then, label %if.else

; CHECK-LABEL: test2
; CHECK: add
; CHECK: select
; CHECK: icmp
; CHECK-NOT: br
if.then:
  %cmp = icmp uge i32 %blksA, %nblks
  %frombool1 = zext i1 %cmp to i8
  br label %if.end

if.else:
  %add = add i32 %nblks, %blksB
  %cmp2 = icmp uge i32 %blksA, %add
  %frombool3 = zext i1 %cmp2 to i8
  br label %if.end

if.end:
  %obeys.0 = phi i8 [ %frombool1, %if.then ], [ %frombool3, %if.else ]
  %tobool4 = icmp ne i8 %obeys.0, 0
  ret i1 %tobool4
}

declare i32 @foo(i32, i32) nounwind readnone

define i32 @test3(i1 zeroext %flag, i32 %x, i32 %y) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %x0 = call i32 @foo(i32 %x, i32 0) nounwind readnone
  %y0 = call i32 @foo(i32 %x, i32 1) nounwind readnone
  br label %if.end

if.else:
  %x1 = call i32 @foo(i32 %y, i32 0) nounwind readnone
  %y1 = call i32 @foo(i32 %y, i32 1) nounwind readnone
  br label %if.end

if.end:
  %xx = phi i32 [ %x0, %if.then ], [ %x1, %if.else ]
  %yy = phi i32 [ %y0, %if.then ], [ %y1, %if.else ]
  %ret = add i32 %xx, %yy
  ret i32 %ret
}

; CHECK-LABEL: test3
; CHECK: select
; CHECK: call
; CHECK: call
; CHECK: add
; CHECK-NOT: br

define i32 @test4(i1 zeroext %flag, i32 %x, i32* %y) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %a = add i32 %x, 5
  store i32 %a, i32* %y
  br label %if.end

if.else:
  %b = add i32 %x, 7
  store i32 %b, i32* %y
  br label %if.end

if.end:
  ret i32 1
}

; CHECK-LABEL: test4
; CHECK: select
; CHECK: store
; CHECK-NOT: store

define i32 @test5(i1 zeroext %flag, i32 %x, i32* %y) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %a = add i32 %x, 5
  store volatile i32 %a, i32* %y
  br label %if.end

if.else:
  %b = add i32 %x, 7
  store i32 %b, i32* %y
  br label %if.end

if.end:
  ret i32 1
}

; CHECK-LABEL: test5
; CHECK: store volatile
; CHECK: store

define i32 @test6(i1 zeroext %flag, i32 %x, i32* %y) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %a = add i32 %x, 5
  store volatile i32 %a, i32* %y
  br label %if.end

if.else:
  %b = add i32 %x, 7
  store volatile i32 %b, i32* %y
  br label %if.end

if.end:
  ret i32 1
}

; CHECK-LABEL: test6
; CHECK: select
; CHECK: store volatile
; CHECK-NOT: store

define i32 @test7(i1 zeroext %flag, i32 %x, i32* %y) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %z = load volatile i32, i32* %y
  %a = add i32 %z, 5
  store volatile i32 %a, i32* %y
  br label %if.end

if.else:
  %w = load volatile i32, i32* %y
  %b = add i32 %w, 7
  store volatile i32 %b, i32* %y
  br label %if.end

if.end:
  ret i32 1
}

; CHECK-LABEL: test7
; CHECK-DAG: select
; CHECK-DAG: load volatile
; CHECK: store volatile
; CHECK-NOT: load
; CHECK-NOT: store

; %z and %w are in different blocks. We shouldn't sink the add because
; there may be intervening memory instructions.
define i32 @test8(i1 zeroext %flag, i32 %x, i32* %y) {
entry:
  %z = load volatile i32, i32* %y
  br i1 %flag, label %if.then, label %if.else

if.then:
  %a = add i32 %z, 5
  store volatile i32 %a, i32* %y
  br label %if.end

if.else:
  %w = load volatile i32, i32* %y
  %b = add i32 %w, 7
  store volatile i32 %b, i32* %y
  br label %if.end

if.end:
  ret i32 1
}

; CHECK-LABEL: test8
; CHECK: add
; CHECK: add

; The extra store in %if.then means %z and %w are not equivalent.
define i32 @test9(i1 zeroext %flag, i32 %x, i32* %y, i32* %p) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  store i32 7, i32* %p
  %z = load volatile i32, i32* %y
  store i32 6, i32* %p
  %a = add i32 %z, 5
  store volatile i32 %a, i32* %y
  br label %if.end

if.else:
  %w = load volatile i32, i32* %y
  %b = add i32 %w, 7
  store volatile i32 %b, i32* %y
  br label %if.end

if.end:
  ret i32 1
}

; CHECK-LABEL: test9
; CHECK: add
; CHECK: add

%struct.anon = type { i32, i32 }

; The GEP indexes a struct type so cannot have a variable last index.
define i32 @test10(i1 zeroext %flag, i32 %x, i32* %y, %struct.anon* %s) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %dummy = add i32 %x, 5
  %gepa = getelementptr inbounds %struct.anon, %struct.anon* %s, i32 0, i32 0
  store volatile i32 %x, i32* %gepa
  br label %if.end

if.else:
  %dummy1 = add i32 %x, 6
  %gepb = getelementptr inbounds %struct.anon, %struct.anon* %s, i32 0, i32 1
  store volatile i32 %x, i32* %gepb
  br label %if.end

if.end:
  ret i32 1
}

; CHECK-LABEL: test10
; CHECK: getelementptr
; CHECK: getelementptr
; CHECK: phi
; CHECK: store volatile

; The shufflevector's mask operand cannot be merged in a PHI.
define i32 @test11(i1 zeroext %flag, i32 %w, <2 x i32> %x, <2 x i32> %y) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %dummy = add i32 %w, 5
  %sv1 = shufflevector <2 x i32> %x, <2 x i32> %y, <2 x i32> <i32 0, i32 1>
  br label %if.end

if.else:
  %dummy1 = add i32 %w, 6
  %sv2 = shufflevector <2 x i32> %x, <2 x i32> %y, <2 x i32> <i32 1, i32 0>
  br label %if.end

if.end:
  %p = phi <2 x i32> [ %sv1, %if.then ], [ %sv2, %if.else ]
  ret i32 1
}

; CHECK-LABEL: test11
; CHECK: shufflevector
; CHECK: shufflevector

; We can't common an intrinsic!
define i32 @test12(i1 zeroext %flag, i32 %w, i32 %x, i32 %y) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %dummy = add i32 %w, 5
  %sv1 = call i32 @llvm.ctlz.i32(i32 %x)
  br label %if.end

if.else:
  %dummy1 = add i32 %w, 6
  %sv2 = call i32 @llvm.cttz.i32(i32 %x)
  br label %if.end

if.end:
  %p = phi i32 [ %sv1, %if.then ], [ %sv2, %if.else ]
  ret i32 1
}

declare i32 @llvm.ctlz.i32(i32 %x) readnone
declare i32 @llvm.cttz.i32(i32 %x) readnone

; CHECK-LABEL: test12
; CHECK: call i32 @llvm.ctlz
; CHECK: call i32 @llvm.cttz

; The TBAA metadata should be properly combined.
define i32 @test13(i1 zeroext %flag, i32 %x, i32* %y) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %z = load volatile i32, i32* %y
  %a = add i32 %z, 5
  store volatile i32 %a, i32* %y, !tbaa !3
  br label %if.end

if.else:
  %w = load volatile i32, i32* %y
  %b = add i32 %w, 7
  store volatile i32 %b, i32* %y, !tbaa !4
  br label %if.end

if.end:
  ret i32 1
}

!0 = !{ !"an example type tree" }
!1 = !{ !"int", !0 }
!2 = !{ !"float", !0 }
!3 = !{ !"const float", !2, i64 0 }
!4 = !{ !"special float", !2, i64 1 }

; CHECK-LABEL: test13
; CHECK-DAG: select
; CHECK-DAG: load volatile
; CHECK: store volatile {{.*}}, !tbaa ![[TBAA:[0-9]]]
; CHECK-NOT: load
; CHECK-NOT: store

; The call should be commoned.
define i32 @test13a(i1 zeroext %flag, i32 %w, i32 %x, i32 %y) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %sv1 = call i32 @bar(i32 %x)
  br label %if.end

if.else:
  %sv2 = call i32 @bar(i32 %y)
  br label %if.end

if.end:
  %p = phi i32 [ %sv1, %if.then ], [ %sv2, %if.else ]
  ret i32 1
}
declare i32 @bar(i32)

; CHECK-LABEL: test13a
; CHECK: %[[x:.*]] = select i1 %flag
; CHECK: call i32 @bar(i32 %[[x]])

; The load should be commoned.
define i32 @test14(i1 zeroext %flag, i32 %w, i32 %x, i32 %y, %struct.anon* %s) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %dummy = add i32 %x, 1
  %gepa = getelementptr inbounds %struct.anon, %struct.anon* %s, i32 0, i32 1
  %sv1 = load i32, i32* %gepa
  %cmp1 = icmp eq i32 %sv1, 56
  br label %if.end

if.else:
  %dummy2 = add i32 %x, 4
  %gepb = getelementptr inbounds %struct.anon, %struct.anon* %s, i32 0, i32 1
  %sv2 = load i32, i32* %gepb
  %cmp2 = icmp eq i32 %sv2, 57
  call void @llvm.dbg.value(metadata i32 0, i64 0, metadata !9, metadata !DIExpression()), !dbg !11
  br label %if.end

if.end:
  %p = phi i1 [ %cmp1, %if.then ], [ %cmp2, %if.else ]
  ret i32 1
}

declare void @llvm.dbg.value(metadata, i64, metadata, metadata)
!llvm.module.flags = !{!5, !6}
!llvm.dbg.cu = !{!7}

!5 = !{i32 2, !"Dwarf Version", i32 4}
!6 = !{i32 2, !"Debug Info Version", i32 3}
!7 = distinct !DICompileUnit(language: DW_LANG_C99, file: !10)
!8 = distinct !DISubprogram(name: "foo", unit: !7)
!9 = !DILocalVariable(name: "b", line: 1, arg: 2, scope: !8)
!10 = !DIFile(filename: "a.c", directory: "a/b")
!11 = !DILocation(line: 1, column: 14, scope: !8)


declare void @g()

define void @test_pr30244(i1 %cond, i1 %cond2, i32 %a, i32 %b) {
entry:
  %add1 = add i32 %a, 1
  br label %succ

one:
  br i1 %cond, label %two, label %succ

two:
  call void @g()
  %add2 = add i32 %a, 1
  br label %succ

succ:
  %p = phi i32 [ 0, %entry ], [ %add1, %one ], [ %add2, %two ]
  br label %one
}


define i32 @test_pr30373a(i1 zeroext %flag, i32 %x, i32 %y) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %x0 = call i32 @foo(i32 %x, i32 0) nounwind readnone
  %y0 = call i32 @foo(i32 %x, i32 1) nounwind readnone
  %z0 = lshr i32 %y0, 8
  br label %if.end

if.else:
  %x1 = call i32 @foo(i32 %y, i32 0) nounwind readnone
  %y1 = call i32 @foo(i32 %y, i32 1) nounwind readnone
  %z1 = lshr exact i32 %y1, 8
  br label %if.end

if.end:
  %xx = phi i32 [ %x0, %if.then ], [ %x1, %if.else ]
  %yy = phi i32 [ %z0, %if.then ], [ %z1, %if.else ]
  %ret = add i32 %xx, %yy
  ret i32 %ret
}

; CHECK-LABEL: test_pr30373a
; CHECK: lshr
; CHECK-NOT: exact
; CHECK: }

define i32 @test_pr30373b(i1 zeroext %flag, i32 %x, i32 %y) {
entry:
  br i1 %flag, label %if.then, label %if.else

if.then:
  %x0 = call i32 @foo(i32 %x, i32 0) nounwind readnone
  %y0 = call i32 @foo(i32 %x, i32 1) nounwind readnone
  %z0 = lshr exact i32 %y0, 8
  br label %if.end

if.else:
  %x1 = call i32 @foo(i32 %y, i32 0) nounwind readnone
  %y1 = call i32 @foo(i32 %y, i32 1) nounwind readnone
  %z1 = lshr i32 %y1, 8
  br label %if.end

if.end:
  %xx = phi i32 [ %x0, %if.then ], [ %x1, %if.else ]
  %yy = phi i32 [ %z0, %if.then ], [ %z1, %if.else ]
  %ret = add i32 %xx, %yy
  ret i32 %ret
}

; CHECK-LABEL: test_pr30373b
; CHECK: lshr
; CHECK-NOT: exact
; CHECK: }

; Check that simplifycfg doesn't sink and merge inline-asm instructions.

define i32 @test_inline_asm1(i32 %c, i32 %r6) {
entry:
  %tobool = icmp eq i32 %c, 0
  br i1 %tobool, label %if.else, label %if.then

if.then:
  %0 = call i32 asm "rorl $2, $0", "=&r,0,n,~{dirflag},~{fpsr},~{flags}"(i32 %r6, i32 8)
  br label %if.end

if.else:
  %1 = call i32 asm "rorl $2, $0", "=&r,0,n,~{dirflag},~{fpsr},~{flags}"(i32 %r6, i32 6)
  br label %if.end

if.end:
  %r6.addr.0 = phi i32 [ %0, %if.then ], [ %1, %if.else ]
  ret i32 %r6.addr.0
}

; CHECK-LABEL: @test_inline_asm1(
; CHECK: call i32 asm "rorl $2, $0", "=&r,0,n,~{dirflag},~{fpsr},~{flags}"(i32 %r6, i32 8)
; CHECK: call i32 asm "rorl $2, $0", "=&r,0,n,~{dirflag},~{fpsr},~{flags}"(i32 %r6, i32 6)

declare i32 @call_target()

define void @test_operand_bundles(i1 %cond, i32* %ptr) {
entry:
  br i1 %cond, label %left, label %right

left:
  %val0 = call i32 @call_target() [ "deopt"(i32 10) ]
  store i32 %val0, i32* %ptr
  br label %merge

right:
  %val1 = call i32 @call_target() [ "deopt"(i32 20) ]
  store i32 %val1, i32* %ptr
  br label %merge

merge:
  ret void
}

; CHECK-LABEL: @test_operand_bundles(
; CHECK: left:
; CHECK-NEXT:   %val0 = call i32 @call_target() [ "deopt"(i32 10) ]
; CHECK: right:
; CHECK-NEXT:   %val1 = call i32 @call_target() [ "deopt"(i32 20) ]

; CHECK: ![[TBAA]] = !{![[TYPE:[0-9]]], ![[TYPE]], i64 0}
; CHECK: ![[TYPE]] = !{!"float", ![[TEXT:[0-9]]]}
; CHECK: ![[TEXT]] = !{!"an example type tree"}
