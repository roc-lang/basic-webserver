; ModuleID = 'app'
source_filename = "builtins-host"
target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128"
target triple = "aarch64-unknown-macosx11.7.1-unknown"

%str.RocStr = type { ptr, i64, i64 }
%macho.mach_header_64 = type { i32, i32, i32, i32, i32, i32, i32, i32 }
%fmt.FormatOptions = type { { i64, i8, [7 x i8] }, { i64, i8, [7 x i8] }, i2, i8, [6 x i8] }
%list.RocList = type { ptr, i64, i64 }
%"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write'))" = type { ptr }
%"io.fixed_buffer_stream.FixedBufferStream([]u8)" = type { { ptr, i64 }, i64 }

@0 = private unnamed_addr constant { i16, i3, [1 x i8] } { i16 0, i3 -4, [1 x i8] undef }, align 4
@1 = private unnamed_addr constant { i64, i16, [6 x i8] } { i64 undef, i16 21, [6 x i8] undef }, align 8
@2 = private unnamed_addr constant { i16, i3, [1 x i8] } { i16 0, i3 1, [1 x i8] undef }, align 4
@3 = private unnamed_addr constant { i16, i3, [1 x i8] } { i16 0, i3 2, [1 x i8] undef }, align 4
@4 = private unnamed_addr constant { i16, i3, [1 x i8] } { i16 0, i3 3, [1 x i8] undef }, align 4
@fmt.digits2__anon_14344 = internal unnamed_addr constant [201 x i8] c"00010203040506070809101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899\00", align 1
@5 = private unnamed_addr constant %str.RocStr { ptr null, i64 0, i64 -9223372036854775808 }, align 8
@_mh_execute_header = weak_odr dso_local local_unnamed_addr global %macho.mach_header_64 undef, align 4
@6 = private unnamed_addr constant %fmt.FormatOptions { { i64, i8, [7 x i8] } { i64 undef, i8 0, [7 x i8] undef }, { i64, i8, [7 x i8] } { i64 undef, i8 0, [7 x i8] undef }, i2 -2, i8 32, [6 x i8] undef }, align 8
@_str_literal_821981871794291864 = private unnamed_addr constant [37 x i8] c"\00\00\00\00\00\00\00\00unrecognized method from host", align 8
@_str_literal_13609154173082167094 = private unnamed_addr constant [36 x i8] c"\00\00\00\00\00\00\00\00Integer addition overflowed!", align 8
@_str_literal_10601663616719294079 = private unnamed_addr constant [60 x i8] c"\00\00\00\00\00\00\00\00SERVER INFO: Doing stuff before the server starts...", align 8

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly, ptr noalias nocapture readonly, i64, i1 immarg) #0

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare { i128, i1 } @llvm.sadd.with.overflow.i128(i128, i128) #1

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: write)
declare void @llvm.memset.p0.i64(ptr nocapture writeonly, i8, i64, i1 immarg) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare { i128, i1 } @llvm.smul.with.overflow.i128(i128, i128) #1

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare { i128, i1 } @llvm.ssub.with.overflow.i128(i128, i128) #1

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.umin.i64(i64, i64) #1

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.usub.sat.i64(i64, i64) #1

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.ctlz.i64(i64, i1 immarg) #1

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare { i64, i1 } @llvm.uadd.with.overflow.i64(i64, i64) #1

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(argmem: readwrite) uwtable
define internal i64 @roc_builtins.str.count_utf8_bytes(ptr nocapture noundef readonly %0) local_unnamed_addr #3 {
str.RocStr.len.exit:
  %.sroa.1.0..sroa_idx = getelementptr inbounds i8, ptr %0, i64 8
  %.sroa.1.0.copyload = load i64, ptr %.sroa.1.0..sroa_idx, align 8
  %.sroa.2.0..sroa_idx = getelementptr inbounds i8, ptr %0, i64 16
  %.sroa.2.0.copyload = load i64, ptr %.sroa.2.0..sroa_idx, align 8
  %1 = icmp slt i64 %.sroa.2.0.copyload, 0
  %2 = lshr i64 %.sroa.2.0.copyload, 56
  %3 = xor i64 %2, 128
  %4 = and i64 %.sroa.1.0.copyload, 9223372036854775807
  %common.ret.op.i = select i1 %1, i64 %3, i64 %4
  ret i64 %common.ret.op.i
}

; Function Attrs: nounwind uwtable
define internal void @roc_builtins.str.concat(ptr noalias nocapture nonnull writeonly sret(%str.RocStr) %0, ptr nocapture noundef readonly %1, ptr nocapture noundef readonly %2) local_unnamed_addr #4 {
  %4 = alloca %str.RocStr, align 8
  %5 = alloca %str.RocStr, align 8
  %6 = alloca %str.RocStr, align 8
  %7 = alloca %str.RocStr, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %7, ptr noundef nonnull align 8 dereferenceable(24) %1, i64 24, i1 false)
  %.sroa.2.sroa.2.0..sroa_idx = getelementptr inbounds i8, ptr %2, i64 8
  %.sroa.2.sroa.2.0.copyload = load i64, ptr %.sroa.2.sroa.2.0..sroa_idx, align 8
  %.sroa.2.sroa.3.0..sroa_idx = getelementptr inbounds i8, ptr %2, i64 16
  %.sroa.2.sroa.3.0.copyload = load i64, ptr %.sroa.2.sroa.3.0..sroa_idx, align 8
  %8 = icmp slt i64 %.sroa.2.sroa.3.0.copyload, 0
  %9 = lshr i64 %.sroa.2.sroa.3.0.copyload, 56
  %10 = xor i64 %9, 128
  %11 = and i64 %.sroa.2.sroa.2.0.copyload, 9223372036854775807
  %common.ret.op.i.i = select i1 %8, i64 %10, i64 %11
  %12 = icmp eq i64 %common.ret.op.i.i, 0
  br i1 %12, label %13, label %str.RocStr.len.exit

13:                                               ; preds = %str.RocStr.len.exit, %3
  %14 = phi ptr [ %6, %str.RocStr.len.exit ], [ %7, %3 ]
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %14, i64 24, i1 false)
  ret void

str.RocStr.len.exit:                              ; preds = %3
  %15 = icmp slt i64 %.sroa.2.sroa.3.0.copyload, 0
  %.sroa.2.sroa.0.0.copyload = load ptr, ptr %2, align 8
  %.sroa.136.0..sroa_idx = getelementptr inbounds i8, ptr %7, i64 8
  %.sroa.136.0.copyload = load i64, ptr %.sroa.136.0..sroa_idx, align 8
  %.sroa.2.0..sroa_idx = getelementptr inbounds i8, ptr %7, i64 16
  %.sroa.2.0.copyload = load i64, ptr %.sroa.2.0..sroa_idx, align 8
  %16 = icmp slt i64 %.sroa.2.0.copyload, 0
  %17 = lshr i64 %.sroa.2.0.copyload, 56
  %18 = xor i64 %17, 128
  %19 = and i64 %.sroa.136.0.copyload, 9223372036854775807
  %common.ret.op.i = select i1 %16, i64 %18, i64 %19
  %20 = add nuw i64 %common.ret.op.i, %common.ret.op.i.i
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %5, ptr noundef nonnull align 8 dereferenceable(24) %1, i64 24, i1 false)
  call fastcc void @str.RocStr.reallocate(ptr noalias %6, ptr nonnull readonly align 8 %5, i64 %20)
  %21 = getelementptr inbounds i8, ptr %6, i64 16
  %.val.i = load i64, ptr %21, align 8
  %22 = icmp slt i64 %.val.i, 0
  %23 = load ptr, ptr %6, align 8
  %common.ret.op.i8 = select i1 %22, ptr %6, ptr %23
  %24 = getelementptr inbounds i8, ptr %common.ret.op.i8, i64 %common.ret.op.i
  store ptr %.sroa.2.sroa.0.0.copyload, ptr %4, align 8
  %.sroa.5.0..sroa_idx25 = getelementptr inbounds i8, ptr %4, i64 8
  store i64 %.sroa.2.sroa.2.0.copyload, ptr %.sroa.5.0..sroa_idx25, align 8
  %.sroa.6.0..sroa_idx30 = getelementptr inbounds i8, ptr %4, i64 16
  store i64 %.sroa.2.sroa.3.0.copyload, ptr %.sroa.6.0..sroa_idx30, align 8
  %common.ret.op.i1446 = select i1 %15, ptr %4, ptr %.sroa.2.sroa.0.0.copyload
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %24, ptr align 1 %common.ret.op.i1446, i64 %common.ret.op.i.i, i1 false)
  br label %13
}

; Function Attrs: nounwind uwtable
define private fastcc void @str.RocStr.reallocate(ptr noalias nocapture nonnull writeonly %0, ptr nocapture nonnull readonly align 8 %1, i64 %2) unnamed_addr #4 {
  %4 = alloca %str.RocStr, align 8
  %5 = alloca %str.RocStr, align 8
  %6 = alloca %str.RocStr, align 8
  %7 = alloca %str.RocStr, align 8
  %.sroa.1.0..sroa_idx = getelementptr inbounds i8, ptr %1, i64 8
  %.sroa.1.0.copyload = load i64, ptr %.sroa.1.0..sroa_idx, align 8
  %.sroa.2.0..sroa_idx = getelementptr inbounds i8, ptr %1, i64 16
  %.sroa.2.0.copyload = load i64, ptr %.sroa.2.0..sroa_idx, align 8
  %8 = icmp slt i64 %.sroa.2.0.copyload, 0
  br i1 %8, label %.critedge, label %str.RocStr.isSeamlessSlice.exit

str.RocStr.isSeamlessSlice.exit:                  ; preds = %3
  %9 = icmp slt i64 %.sroa.1.0.copyload, 0
  %10 = and i64 %.sroa.1.0.copyload, 9223372036854775807
  %spec.select.i = select i1 %9, i64 %10, i64 %.sroa.2.0.copyload
  br i1 %9, label %.critedge, label %str.RocStr.getCapacity.exit.i.i

str.RocStr.getCapacity.exit.i.i:                  ; preds = %str.RocStr.isSeamlessSlice.exit
  %.sroa.017.0.copyload = load ptr, ptr %1, align 8
  %.not29 = icmp eq i64 %.sroa.2.0.copyload, 0
  br i1 %.not29, label %14, label %str.RocStr.isUnique.exit

str.RocStr.isUnique.exit:                         ; preds = %str.RocStr.getCapacity.exit.i.i
  %11 = getelementptr inbounds i64, ptr %.sroa.017.0.copyload, i64 -1
  %12 = load i64, ptr %11, align 8
  %13 = icmp eq i64 %12, -9223372036854775808
  br i1 %13, label %.thread, label %.critedge

common.ret:                                       ; preds = %utils.unsafeReallocate.exit, %str.RocStr.setLen.exit, %16, %.critedge
  ret void

.critedge:                                        ; preds = %str.RocStr.isUnique.exit, %str.RocStr.isSeamlessSlice.exit, %3
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %7, ptr noundef nonnull align 8 dereferenceable(24) %1, i64 24, i1 false)
  call fastcc void @str.RocStr.reallocateFresh(ptr noalias %6, ptr nonnull readonly align 8 %7, i64 %2)
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %6, i64 24, i1 false)
  br label %common.ret

14:                                               ; preds = %str.RocStr.getCapacity.exit.i.i
  %.not = icmp eq ptr %.sroa.017.0.copyload, null
  br i1 %.not, label %16, label %.thread

.thread:                                          ; preds = %14, %str.RocStr.isUnique.exit
  %15 = icmp ugt i64 %spec.select.i, %2
  br i1 %15, label %str.RocStr.setLen.exit, label %19

16:                                               ; preds = %14
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %5, ptr noundef nonnull align 8 dereferenceable(24) %1, i64 24, i1 false)
  call fastcc void @str.RocStr.reallocateFresh(ptr noalias %4, ptr nonnull readonly align 8 %5, i64 %2)
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %4, i64 24, i1 false)
  br label %common.ret

str.RocStr.setLen.exit:                           ; preds = %.thread
  %17 = and i64 %.sroa.1.0.copyload, -9223372036854775808
  %18 = or i64 %17, %2
  store ptr %.sroa.017.0.copyload, ptr %0, align 8
  %.sroa.221.0..sroa_idx22 = getelementptr inbounds i8, ptr %0, i64 8
  store i64 %18, ptr %.sroa.221.0..sroa_idx22, align 8
  %.sroa.4.0..sroa_idx24 = getelementptr inbounds i8, ptr %0, i64 16
  store i64 %.sroa.2.0.copyload, ptr %.sroa.4.0..sroa_idx24, align 8
  br label %common.ret

19:                                               ; preds = %.thread
  %20 = icmp eq i64 %spec.select.i, 0
  br i1 %20, label %21, label %31

21:                                               ; preds = %39, %37, %33, %19
  %.0 = phi i64 [ %34, %33 ], [ %38, %37 ], [ %42, %39 ], [ 64, %19 ]
  %22 = tail call i64 @llvm.umax.i64(i64 %.0, i64 %2)
  %.not.i = icmp ult i64 %spec.select.i, %22
  br i1 %.not.i, label %23, label %utils.unsafeReallocate.exit

23:                                               ; preds = %21
  %24 = add nuw i64 %22, 8
  %25 = add nuw i64 %spec.select.i, 8
  %26 = getelementptr inbounds i8, ptr %.sroa.017.0.copyload, i64 -8
  %27 = tail call ptr @roc_realloc(ptr nonnull align 1 %26, i64 %24, i64 %25, i32 8)
  %28 = getelementptr inbounds i8, ptr %27, i64 8
  br label %utils.unsafeReallocate.exit

utils.unsafeReallocate.exit:                      ; preds = %23, %21
  %common.ret.op.i11 = phi ptr [ %28, %23 ], [ %.sroa.017.0.copyload, %21 ]
  store ptr %common.ret.op.i11, ptr %0, align 8
  %29 = getelementptr inbounds %str.RocStr, ptr %0, i64 0, i32 1
  store i64 %2, ptr %29, align 8
  %30 = getelementptr inbounds %str.RocStr, ptr %0, i64 0, i32 2
  store i64 %22, ptr %30, align 8
  br label %common.ret

31:                                               ; preds = %19
  %32 = icmp ult i64 %spec.select.i, 4096
  br i1 %32, label %33, label %35

33:                                               ; preds = %31
  %34 = shl nuw nsw i64 %spec.select.i, 1
  br label %21

35:                                               ; preds = %31
  %36 = icmp ugt i64 %spec.select.i, 131072
  br i1 %36, label %37, label %39

37:                                               ; preds = %35
  %38 = shl nuw i64 %spec.select.i, 1
  br label %21

39:                                               ; preds = %35
  %40 = mul nuw nsw i64 %spec.select.i, 3
  %41 = add nuw nsw i64 %40, 1
  %42 = lshr i64 %41, 1
  br label %21
}

; Function Attrs: nofree nosync nounwind memory(read, argmem: readwrite, inaccessiblemem: none) uwtable
define internal zeroext i1 @roc_builtins.str.equal(ptr nocapture noundef readonly %0, ptr nocapture noundef readonly %1) local_unnamed_addr #5 {
  %3 = alloca %str.RocStr, align 8
  %4 = alloca %str.RocStr, align 8
  %.sroa.0.0.copyload = load ptr, ptr %0, align 8
  %.sroa.3.0..sroa_idx = getelementptr inbounds i8, ptr %0, i64 8
  %.sroa.3.0.copyload = load i64, ptr %.sroa.3.0..sroa_idx, align 8
  %.sroa.5.0..sroa_idx = getelementptr inbounds i8, ptr %0, i64 16
  %.sroa.5.0.copyload = load i64, ptr %.sroa.5.0..sroa_idx, align 8
  call void @llvm.lifetime.start.p0(i64 24, ptr nonnull %3)
  call void @llvm.lifetime.start.p0(i64 24, ptr nonnull %4)
  %5 = load ptr, ptr %1, align 8
  %6 = icmp eq ptr %.sroa.0.0.copyload, %5
  br i1 %6, label %7, label %..critedge_crit_edge.i

..critedge_crit_edge.i:                           ; preds = %2
  %.sroa.117.0..sroa_idx.phi.trans.insert.i = getelementptr inbounds i8, ptr %1, i64 8
  %.sroa.117.0.copyload.pre.i = load i64, ptr %.sroa.117.0..sroa_idx.phi.trans.insert.i, align 8
  br label %.critedge.i

7:                                                ; preds = %2
  %8 = getelementptr inbounds %str.RocStr, ptr %1, i64 0, i32 1
  %9 = load i64, ptr %8, align 8
  %10 = icmp eq i64 %.sroa.3.0.copyload, %9
  br i1 %10, label %11, label %.critedge.i

11:                                               ; preds = %7
  %12 = getelementptr inbounds %str.RocStr, ptr %1, i64 0, i32 2
  %13 = load i64, ptr %12, align 8
  %14 = icmp eq i64 %.sroa.5.0.copyload, %13
  br i1 %14, label %str.RocStr.eq.exit, label %.critedge.i

.critedge.i:                                      ; preds = %11, %7, %..critedge_crit_edge.i
  %.sroa.117.0.copyload.i = phi i64 [ %.sroa.117.0.copyload.pre.i, %..critedge_crit_edge.i ], [ %9, %7 ], [ %.sroa.3.0.copyload, %11 ]
  %15 = icmp slt i64 %.sroa.5.0.copyload, 0
  %16 = lshr i64 %.sroa.5.0.copyload, 56
  %17 = xor i64 %16, 128
  %18 = and i64 %.sroa.3.0.copyload, 9223372036854775807
  %common.ret.op.i.i = select i1 %15, i64 %17, i64 %18
  %.sroa.218.0..sroa_idx.i = getelementptr inbounds i8, ptr %1, i64 16
  %.sroa.218.0.copyload.i = load i64, ptr %.sroa.218.0..sroa_idx.i, align 8
  %19 = icmp slt i64 %.sroa.218.0.copyload.i, 0
  %20 = lshr i64 %.sroa.218.0.copyload.i, 56
  %21 = xor i64 %20, 128
  %22 = and i64 %.sroa.117.0.copyload.i, 9223372036854775807
  %common.ret.op.i10.i = select i1 %19, i64 %21, i64 %22
  %.not.i = icmp eq i64 %common.ret.op.i.i, %common.ret.op.i10.i
  br i1 %.not.i, label %str.RocStr.asU8ptr.exit.i, label %str.RocStr.eq.exit

str.RocStr.asU8ptr.exit.i:                        ; preds = %.critedge.i
  %23 = icmp slt i64 %.sroa.5.0.copyload, 0
  store ptr %.sroa.0.0.copyload, ptr %4, align 8
  %.sroa.3.0..sroa_idx2 = getelementptr inbounds i8, ptr %4, i64 8
  store i64 %.sroa.3.0.copyload, ptr %.sroa.3.0..sroa_idx2, align 8
  %.sroa.5.0..sroa_idx4 = getelementptr inbounds i8, ptr %4, i64 16
  store i64 %.sroa.5.0.copyload, ptr %.sroa.5.0..sroa_idx4, align 8
  %spec.select.i = select i1 %23, ptr %4, ptr %.sroa.0.0.copyload
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %3, ptr noundef nonnull align 8 dereferenceable(24) %1, i64 24, i1 false)
  %24 = getelementptr inbounds i8, ptr %3, i64 16
  %.val.i13.i = load i64, ptr %24, align 8
  %25 = icmp slt i64 %.val.i13.i, 0
  %26 = load ptr, ptr %3, align 8
  %common.ret.op.i14.i = select i1 %25, ptr %3, ptr %26
  %.not22.i = icmp eq i64 %common.ret.op.i.i, 0
  br i1 %.not22.i, label %str.RocStr.eq.exit, label %.lr.ph.i.preheader

.lr.ph.i.preheader:                               ; preds = %str.RocStr.asU8ptr.exit.i
  %27 = add nsw i64 %common.ret.op.i.i, -1
  br label %.lr.ph.i

.lr.ph.i:                                         ; preds = %.lr.ph.i, %.lr.ph.i.preheader
  %lsr.iv8 = phi ptr [ %spec.select.i, %.lr.ph.i.preheader ], [ %uglygep9, %.lr.ph.i ]
  %lsr.iv7 = phi ptr [ %common.ret.op.i14.i, %.lr.ph.i.preheader ], [ %uglygep, %.lr.ph.i ]
  %lsr.iv = phi i64 [ %27, %.lr.ph.i.preheader ], [ %math, %.lr.ph.i ]
  %28 = load i8, ptr %lsr.iv8, align 1
  %29 = load i8, ptr %lsr.iv7, align 1
  %.not7.i = icmp eq i8 %28, %29
  %30 = call { i64, i1 } @llvm.uadd.with.overflow.i64(i64 %lsr.iv, i64 -1)
  %math = extractvalue { i64, i1 } %30, 0
  %ov = extractvalue { i64, i1 } %30, 1
  %or.cond.not = select i1 %.not7.i, i1 %ov, i1 false
  %uglygep = getelementptr i8, ptr %lsr.iv7, i64 1
  %uglygep9 = getelementptr i8, ptr %lsr.iv8, i64 1
  br i1 %or.cond.not, label %.lr.ph.i, label %str.RocStr.eq.exit

str.RocStr.eq.exit:                               ; preds = %.lr.ph.i, %str.RocStr.asU8ptr.exit.i, %.critedge.i, %11
  %common.ret.op.i = phi i1 [ true, %11 ], [ false, %.critedge.i ], [ true, %str.RocStr.asU8ptr.exit.i ], [ %.not7.i, %.lr.ph.i ]
  call void @llvm.lifetime.end.p0(i64 24, ptr nonnull %3)
  call void @llvm.lifetime.end.p0(i64 24, ptr nonnull %4)
  ret i1 %common.ret.op.i
}

; Function Attrs: nounwind uwtable
define internal void @roc_builtins.str.to_utf8(ptr noalias nocapture nonnull writeonly sret(%list.RocList) %0, ptr nocapture noundef readonly %1) local_unnamed_addr #4 {
  %3 = alloca %list.RocList, align 8
  %4 = alloca %list.RocList, align 8
  %5 = alloca %str.RocStr, align 8
  %6 = alloca %list.RocList, align 8
  %.sroa.2.0..sroa_idx = getelementptr inbounds i8, ptr %1, i64 16
  %.sroa.2.0.copyload = load i64, ptr %.sroa.2.0..sroa_idx, align 8
  %7 = icmp slt i64 %.sroa.2.0.copyload, 0
  br i1 %7, label %str.RocStr.len.exit, label %str.RocStr.len.exit.thread

str.RocStr.len.exit:                              ; preds = %2
  %8 = lshr i64 %.sroa.2.0.copyload, 56
  %9 = xor i64 %8, 128
  %10 = icmp eq i64 %9, 0
  br i1 %10, label %15, label %str.RocStr.asU8ptr.exit

str.RocStr.len.exit.thread:                       ; preds = %2
  %.sroa.1.0..sroa_idx = getelementptr inbounds i8, ptr %1, i64 8
  %.sroa.1.0.copyload = load i64, ptr %.sroa.1.0..sroa_idx, align 8
  %11 = and i64 %.sroa.1.0.copyload, 9223372036854775807
  %12 = icmp eq i64 %11, 0
  br i1 %12, label %15, label %24

13:                                               ; preds = %24, %str.RocStr.asU8ptr.exit, %15
  %14 = phi ptr [ %6, %15 ], [ %4, %str.RocStr.asU8ptr.exit ], [ %3, %24 ]
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %14, i64 24, i1 false)
  ret void

15:                                               ; preds = %str.RocStr.len.exit.thread, %str.RocStr.len.exit
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %6, i8 0, i64 24, i1 false), !alias.scope !5
  br label %13

str.RocStr.asU8ptr.exit:                          ; preds = %str.RocStr.len.exit
  %16 = add nuw nsw i64 %9, 8
  %17 = tail call ptr @roc_alloc(i64 %16, i32 8)
  %18 = getelementptr inbounds i8, ptr %17, i64 8
  store i64 -9223372036854775808, ptr %17, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %5, ptr noundef nonnull align 8 dereferenceable(24) %1, i64 24, i1 false)
  %19 = getelementptr inbounds i8, ptr %5, i64 16
  %.val.i = load i64, ptr %19, align 8
  %20 = icmp slt i64 %.val.i, 0
  %21 = load ptr, ptr %5, align 8
  %spec.select = select i1 %20, ptr %5, ptr %21
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %18, ptr align 1 %spec.select, i64 %9, i1 false)
  %22 = getelementptr inbounds %list.RocList, ptr %4, i64 0, i32 1
  store i64 %9, ptr %22, align 8
  store ptr %18, ptr %4, align 8
  %23 = getelementptr inbounds %list.RocList, ptr %4, i64 0, i32 2
  store i64 %9, ptr %23, align 8
  br label %13

24:                                               ; preds = %str.RocStr.len.exit.thread
  %25 = and i64 %.sroa.1.0.copyload, -9223372036854775808
  %26 = getelementptr inbounds %list.RocList, ptr %3, i64 0, i32 1
  store i64 %11, ptr %26, align 8
  %27 = load ptr, ptr %1, align 8
  store ptr %27, ptr %3, align 8
  %28 = getelementptr inbounds %list.RocList, ptr %3, i64 0, i32 2
  %29 = or i64 %.sroa.2.0.copyload, %25
  store i64 %29, ptr %28, align 8
  br label %13
}

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(argmem: readwrite) uwtable
define internal ptr @roc_builtins.str.allocation_ptr(ptr nocapture noundef readonly %0) local_unnamed_addr #3 {
  %.sroa.0.0.copyload = load ptr, ptr %0, align 8
  %.sroa.2.0..sroa_idx = getelementptr inbounds i8, ptr %0, i64 8
  %.sroa.2.0.copyload = load i64, ptr %.sroa.2.0..sroa_idx, align 8
  %.sroa.3.0..sroa_idx = getelementptr inbounds i8, ptr %0, i64 16
  %.sroa.3.0.copyload = load i64, ptr %.sroa.3.0..sroa_idx, align 8
  %2 = ptrtoint ptr %.sroa.0.0.copyload to i64
  %3 = shl i64 %.sroa.3.0.copyload, 1
  %isneg.i = icmp slt i64 %.sroa.2.0.copyload, 0
  %4 = select i1 %isneg.i, i64 %3, i64 %2
  %5 = inttoptr i64 %4 to ptr
  ret ptr %5
}

; Function Attrs: nounwind uwtable
define internal void @roc_builtins.str.from_int.i128(ptr noalias nocapture nonnull writeonly sret(%str.RocStr) %0, i128 %1) local_unnamed_addr #4 {
  %3 = alloca [129 x i8], align 1
  %4 = alloca %str.RocStr, align 8
  %5 = alloca %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write'))", align 8
  %6 = alloca %"io.fixed_buffer_stream.FixedBufferStream([]u8)", align 8
  %7 = alloca [40 x i8], align 1
  call void @llvm.lifetime.start.p0(i64 8, ptr nonnull %5)
  call void @llvm.lifetime.start.p0(i64 24, ptr nonnull %6)
  store ptr %7, ptr %6, align 8, !noalias !8
  %.sroa.2.0..sroa_idx.i = getelementptr inbounds i8, ptr %6, i64 8
  store <2 x i64> <i64 40, i64 0>, ptr %.sroa.2.0..sroa_idx.i, align 8, !noalias !8
  store ptr %6, ptr %5, align 8, !alias.scope !11, !noalias !8
  call void @llvm.lifetime.start.p0(i64 129, ptr nonnull %3), !noalias !8
  %common.ret.op.i.i.i.i.i.i.i = call i128 @llvm.abs.i128(i128 %1, i1 false)
  %8 = icmp ugt i128 %common.ret.op.i.i.i.i.i.i.i, 99
  br i1 %8, label %.lr.ph.i.i.i.i.i.i.preheader, label %._crit_edge.i.i.i.i.i.i

.lr.ph.i.i.i.i.i.i.preheader:                     ; preds = %2
  br label %.lr.ph.i.i.i.i.i.i

9:                                                ; preds = %25, %20
  %.024.i.i.i.i.i.i = phi i64 [ %21, %20 ], [ %26, %25 ]
  %10 = icmp slt i128 %1, 0
  br i1 %10, label %.critedge.sink.split.i.i.i.i.i.i, label %fmt.format__anon_13451.exit.i

.lr.ph.i.i.i.i.i.i:                               ; preds = %.lr.ph.i.i.i.i.i.i, %.lr.ph.i.i.i.i.i.i.preheader
  %lsr.iv = phi i64 [ 127, %.lr.ph.i.i.i.i.i.i.preheader ], [ %lsr.iv.next, %.lr.ph.i.i.i.i.i.i ]
  %.028.i.i.i.i.i.i = phi i128 [ %11, %.lr.ph.i.i.i.i.i.i ], [ %common.ret.op.i.i.i.i.i.i.i, %.lr.ph.i.i.i.i.i.i.preheader ]
  %uglygep = getelementptr i8, ptr %3, i64 %lsr.iv
  %.028.i.i.i.i.i.i.frozen = freeze i128 %.028.i.i.i.i.i.i
  %11 = udiv i128 %.028.i.i.i.i.i.i.frozen, 100
  %12 = mul i128 %11, 100
  %.decomposed = sub i128 %.028.i.i.i.i.i.i.frozen, %12
  %13 = trunc i128 %.decomposed to i64
  %14 = shl nuw nsw i64 %13, 1
  %15 = getelementptr inbounds i8, ptr @fmt.digits2__anon_14344, i64 %14
  %16 = load i16, ptr %15, align 1, !noalias !14
  store i16 %16, ptr %uglygep, align 1, !noalias !8
  %17 = icmp ugt i128 %.028.i.i.i.i.i.i, 9999
  %lsr.iv.next = add i64 %lsr.iv, -2
  br i1 %17, label %.lr.ph.i.i.i.i.i.i, label %._crit_edge.i.i.i.i.i.i.loopexit

._crit_edge.i.i.i.i.i.i.loopexit:                 ; preds = %.lr.ph.i.i.i.i.i.i
  %18 = add i64 %lsr.iv.next, 2
  br label %._crit_edge.i.i.i.i.i.i

._crit_edge.i.i.i.i.i.i:                          ; preds = %._crit_edge.i.i.i.i.i.i.loopexit, %2
  %.125.lcssa.i.i.i.i.i.i = phi i64 [ 129, %2 ], [ %18, %._crit_edge.i.i.i.i.i.i.loopexit ]
  %.0.lcssa.i.i.i.i.i.i = phi i128 [ %common.ret.op.i.i.i.i.i.i.i, %2 ], [ %11, %._crit_edge.i.i.i.i.i.i.loopexit ]
  %19 = icmp ult i128 %.0.lcssa.i.i.i.i.i.i, 10
  br i1 %19, label %20, label %25

20:                                               ; preds = %._crit_edge.i.i.i.i.i.i
  %21 = add i64 %.125.lcssa.i.i.i.i.i.i, -1
  %22 = getelementptr inbounds [129 x i8], ptr %3, i64 0, i64 %21
  %23 = trunc i128 %.0.lcssa.i.i.i.i.i.i to i8
  %24 = add nuw nsw i8 %23, 48
  store i8 %24, ptr %22, align 1, !noalias !8
  br label %9

25:                                               ; preds = %._crit_edge.i.i.i.i.i.i
  %26 = add i64 %.125.lcssa.i.i.i.i.i.i, -2
  %27 = getelementptr inbounds i8, ptr %3, i64 %26
  %28 = trunc i128 %.0.lcssa.i.i.i.i.i.i to i64
  %29 = shl nuw nsw i64 %28, 1
  %30 = getelementptr inbounds i8, ptr @fmt.digits2__anon_14344, i64 %29
  %31 = load i16, ptr %30, align 1, !noalias !17
  store i16 %31, ptr %27, align 1, !noalias !8
  br label %9

.critedge.sink.split.i.i.i.i.i.i:                 ; preds = %9
  %32 = add i64 %.024.i.i.i.i.i.i, -1
  %33 = getelementptr inbounds [129 x i8], ptr %3, i64 0, i64 %32
  store i8 45, ptr %33, align 1, !noalias !8
  br label %fmt.format__anon_13451.exit.i

fmt.format__anon_13451.exit.i:                    ; preds = %.critedge.sink.split.i.i.i.i.i.i, %9
  %.3.i.i.i.i.i.i = phi i64 [ %32, %.critedge.sink.split.i.i.i.i.i.i ], [ %.024.i.i.i.i.i.i, %9 ]
  %34 = getelementptr inbounds i8, ptr %3, i64 %.3.i.i.i.i.i.i
  %35 = sub nuw i64 129, %.3.i.i.i.i.i.i
  %36 = call fastcc i16 @fmt.formatBuf__anon_13240(ptr nonnull readonly align 1 %34, i64 %35, ptr nonnull readonly align 8 @6, ptr nonnull readonly align 8 %5), !noalias !8
  call void @llvm.lifetime.end.p0(i64 129, ptr nonnull %3), !noalias !8
  %sunkaddr = getelementptr inbounds i8, ptr %6, i64 16
  %.val3.i = load i64, ptr %sunkaddr, align 8, !noalias !8
  call void @llvm.lifetime.end.p0(i64 8, ptr nonnull %5)
  call void @llvm.lifetime.end.p0(i64 24, ptr nonnull %6)
  call void @llvm.lifetime.start.p0(i64 24, ptr nonnull %3)
  %37 = icmp ugt i64 %.val3.i, 23
  br i1 %37, label %str.RocStr.allocate.exit.i, label %str.RocStr.allocate.exit.thread.i

str.RocStr.allocate.exit.thread.i:                ; preds = %fmt.format__anon_13451.exit.i
  %38 = shl nuw nsw i64 %.val3.i, 56
  %.sroa.3.23.insert.shift.i = or i64 %38, -9223372036854775808
  br label %str.RocStr.init.exit

str.RocStr.allocate.exit.i:                       ; preds = %fmt.format__anon_13451.exit.i
  %39 = call i64 @llvm.umax.i64(i64 %.val3.i, i64 64)
  %40 = add nuw i64 %39, 8
  %41 = call ptr @roc_alloc(i64 %40, i32 8), !noalias !20
  %42 = getelementptr inbounds i8, ptr %41, i64 8
  store i64 -9223372036854775808, ptr %41, align 8, !noalias !20
  %43 = icmp slt i64 %39, 0
  %spec.select.i = select i1 %43, ptr %3, ptr %42
  br label %str.RocStr.init.exit

str.RocStr.init.exit:                             ; preds = %str.RocStr.allocate.exit.i, %str.RocStr.allocate.exit.thread.i
  %.sink7.i = phi ptr [ %42, %str.RocStr.allocate.exit.i ], [ null, %str.RocStr.allocate.exit.thread.i ]
  %.sink.i = phi i64 [ %.val3.i, %str.RocStr.allocate.exit.i ], [ 0, %str.RocStr.allocate.exit.thread.i ]
  %.sroa.3.23.insert.shift.sink.i = phi i64 [ %39, %str.RocStr.allocate.exit.i ], [ %.sroa.3.23.insert.shift.i, %str.RocStr.allocate.exit.thread.i ]
  %common.ret.op.i.i = phi ptr [ %spec.select.i, %str.RocStr.allocate.exit.i ], [ %3, %str.RocStr.allocate.exit.thread.i ]
  store ptr %.sink7.i, ptr %3, align 8, !noalias !27
  %44 = getelementptr inbounds i8, ptr %3, i64 8
  store i64 %.sink.i, ptr %44, align 8, !noalias !27
  %45 = getelementptr inbounds i8, ptr %3, i64 16
  store i64 %.sroa.3.23.insert.shift.sink.i, ptr %45, align 8, !noalias !27
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %common.ret.op.i.i, ptr nonnull align 1 %7, i64 %.val3.i, i1 false), !noalias !27
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %3, i64 24, i1 false)
  call void @llvm.lifetime.end.p0(i64 24, ptr nonnull %3)
  ret void
}

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.umax.i32(i32, i32) #1

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.umax.i64(i64, i64) #1

; Function Attrs: nounwind uwtable
define internal ptr @roc_builtins.utils.allocate_with_refcount(i64 %0, i32 %1, i1 zeroext %2) local_unnamed_addr #4 {
  %4 = tail call i32 @llvm.umax.i32(i32 %1, i32 8)
  %..i = select i1 %2, i64 16, i64 8
  %5 = zext i32 %1 to i64
  %6 = tail call i64 @llvm.umax.i64(i64 %..i, i64 %5)
  %7 = add nuw i64 %6, %0
  %8 = tail call ptr @roc_alloc(i64 %7, i32 %4)
  %9 = getelementptr inbounds i8, ptr %8, i64 %6
  %10 = getelementptr inbounds i8, ptr %9, i64 -8
  store i64 -9223372036854775808, ptr %10, align 8
  ret ptr %9
}

; Function Attrs: noreturn nounwind uwtable
declare void @roc_panic(ptr nonnull readonly align 8, i32) local_unnamed_addr #6

; Function Attrs: nounwind uwtable
define weak_odr dso_local i32 @__roc_force_setjmp(ptr align 4 %0) local_unnamed_addr #4 {
  %2 = tail call i32 @setjmp(ptr align 4 %0)
  ret i32 %2
}

; Function Attrs: nounwind uwtable
declare i32 @setjmp(ptr align 4) local_unnamed_addr #4

; Function Attrs: noreturn nounwind uwtable
define weak_odr dso_local void @__roc_force_longjmp(ptr align 4 %0, i32 %1) local_unnamed_addr #6 {
  tail call void @longjmp(ptr align 4 %0, i32 %1)
  unreachable
}

; Function Attrs: noreturn nounwind uwtable
declare void @longjmp(ptr align 4, i32) local_unnamed_addr #6

; Function Attrs: nounwind uwtable
define weak_odr dso_local i128 @__divti3(i128 %0, i128 %1) local_unnamed_addr #4 {
  %3 = ashr i128 %0, 127
  %4 = ashr i128 %1, 127
  %5 = xor i128 %3, %0
  %6 = sub i128 %5, %3
  %7 = xor i128 %4, %1
  %8 = sub i128 %7, %4
  %9 = tail call fastcc i128 @compiler_rt.udivmod.udivmod__anon_12849(i128 %6, i128 %8, ptr align 16 null)
  %10 = xor i128 %4, %3
  %11 = xor i128 %9, %10
  %12 = sub i128 %11, %10
  ret i128 %12
}

; Function Attrs: nofree nosync nounwind memory(argmem: write) uwtable
define private fastcc i128 @compiler_rt.udivmod.udivmod__anon_12849(i128 %0, i128 %1, ptr writeonly align 16 %2) unnamed_addr #7 {
  %4 = icmp ugt i128 %1, %0
  br i1 %4, label %5, label %6

5:                                                ; preds = %3
  %.not47 = icmp eq ptr %2, null
  br i1 %.not47, label %common.ret, label %8

6:                                                ; preds = %3
  %.sroa.07.0.extract.trunc = trunc i128 %0 to i64
  %.sroa.2.0.extract.shift = lshr i128 %0, 64
  %.sroa.2.0.extract.trunc = trunc i128 %.sroa.2.0.extract.shift to i64
  %.sroa.015.0.extract.trunc = trunc i128 %1 to i64
  %.sroa.216.0.extract.shift = lshr i128 %1, 64
  %.sroa.216.0.extract.trunc = trunc i128 %.sroa.216.0.extract.shift to i64
  %7 = icmp eq i64 %.sroa.216.0.extract.trunc, 0
  br i1 %7, label %9, label %11

common.ret:                                       ; preds = %142, %129, %8, %5
  %common.ret.op = phi i128 [ %.sroa.017.0.insert.insert, %129 ], [ %.sroa.017.0.insert.ext21, %142 ], [ 0, %8 ], [ 0, %5 ]
  ret i128 %common.ret.op

8:                                                ; preds = %5
  store i128 %0, ptr %2, align 16
  br label %common.ret

9:                                                ; preds = %6
  %10 = icmp ult i64 %.sroa.2.0.extract.trunc, %.sroa.015.0.extract.trunc
  br i1 %10, label %24, label %75

11:                                               ; preds = %6
  %12 = tail call i64 @llvm.ctlz.i64(i64 %.sroa.216.0.extract.trunc, i1 true), !range !28
  %13 = trunc i64 %12 to i7
  %14 = tail call i64 @llvm.ctlz.i64(i64 %.sroa.2.0.extract.trunc, i1 false), !range !28
  %15 = trunc i64 %14 to i7
  %16 = sub nuw i7 %13, %15
  %17 = zext i7 %16 to i128
  %18 = shl i128 %1, %17
  %19 = add nuw i7 %16, 1
  %20 = zext i7 %19 to i64
  br label %131

21:                                               ; preds = %compiler_rt.udivmod.divwide__anon_14189.exit60, %compiler_rt.udivmod.divwide__anon_14189.exit
  %.037.i.i52.sink = phi i64 [ %.037.i.i52, %compiler_rt.udivmod.divwide__anon_14189.exit60 ], [ %.037.i.i, %compiler_rt.udivmod.divwide__anon_14189.exit ]
  %.040.i.i59.sink = phi i64 [ %.040.i.i59, %compiler_rt.udivmod.divwide__anon_14189.exit60 ], [ %.040.i.i, %compiler_rt.udivmod.divwide__anon_14189.exit ]
  %.sroa.0.0 = phi i64 [ %128, %compiler_rt.udivmod.divwide__anon_14189.exit60 ], [ %74, %compiler_rt.udivmod.divwide__anon_14189.exit ]
  %.sroa.10.0 = phi i64 [ %76, %compiler_rt.udivmod.divwide__anon_14189.exit60 ], [ 0, %compiler_rt.udivmod.divwide__anon_14189.exit ]
  %22 = shl i64 %.037.i.i52.sink, 32
  %23 = add i64 %.040.i.i59.sink, %22
  %.not46 = icmp eq ptr %2, null
  br i1 %.not46, label %129, label %130

24:                                               ; preds = %9
  %25 = tail call i64 @llvm.ctlz.i64(i64 %.sroa.015.0.extract.trunc, i1 true), !range !28
  %.not.i.i = icmp eq i64 %25, 0
  br i1 %.not.i.i, label %26, label %34

26:                                               ; preds = %34, %24
  %.036.i.i = phi i64 [ %41, %34 ], [ %.sroa.07.0.extract.trunc, %24 ]
  %.035.i.i = phi i64 [ %40, %34 ], [ %.sroa.2.0.extract.trunc, %24 ]
  %.0.i.i = phi i64 [ %35, %34 ], [ %.sroa.015.0.extract.trunc, %24 ]
  %27 = lshr i64 %.0.i.i, 32
  %28 = and i64 %.0.i.i, 4294967295
  %29 = lshr i64 %.036.i.i, 32
  %30 = and i64 %.036.i.i, 4294967295
  %31 = udiv i64 %.035.i.i, %27
  %32 = mul i64 %31, %27
  %33 = sub i64 %.035.i.i, %32
  br label %50

34:                                               ; preds = %24
  %35 = shl i64 %.sroa.015.0.extract.trunc, %25
  %36 = shl i64 %.sroa.2.0.extract.trunc, %25
  %37 = sub nsw i64 0, %25
  %38 = and i64 %37, 63
  %39 = lshr i64 %.sroa.07.0.extract.trunc, %38
  %40 = or i64 %39, %36
  %41 = shl i64 %.sroa.07.0.extract.trunc, %25
  br label %26

42:                                               ; preds = %.critedge.i.i, %52
  %.037.i.i = phi i64 [ %57, %.critedge.i.i ], [ %.1.i.i, %52 ]
  %43 = shl i64 %.035.i.i, 32
  %44 = or i64 %43, %29
  %45 = mul i64 %.037.i.i, %.0.i.i
  %46 = sub i64 %44, %45
  %47 = udiv i64 %46, %27
  %48 = mul i64 %47, %27
  %49 = sub i64 %46, %48
  br label %60

50:                                               ; preds = %.critedge.i.i, %26
  %.038.i.i = phi i64 [ %33, %26 ], [ %58, %.critedge.i.i ]
  %.1.i.i = phi i64 [ %31, %26 ], [ %57, %.critedge.i.i ]
  %51 = icmp ugt i64 %.1.i.i, 4294967295
  br i1 %51, label %.critedge.i.i, label %52

52:                                               ; preds = %50
  %53 = mul nuw i64 %.1.i.i, %28
  %54 = shl nuw i64 %.038.i.i, 32
  %55 = or i64 %54, %29
  %56 = icmp ugt i64 %53, %55
  br i1 %56, label %.critedge.i.i, label %42

.critedge.i.i:                                    ; preds = %52, %50
  %57 = add i64 %.1.i.i, -1
  %58 = add nuw i64 %.038.i.i, %27
  %59 = icmp ugt i64 %58, 4294967295
  br i1 %59, label %42, label %50

60:                                               ; preds = %.critedge2.i.i, %42
  %.141.i.i = phi i64 [ %47, %42 ], [ %67, %.critedge2.i.i ]
  %.139.i.i = phi i64 [ %49, %42 ], [ %68, %.critedge2.i.i ]
  %61 = icmp ugt i64 %.141.i.i, 4294967295
  br i1 %61, label %.critedge2.i.i, label %62

62:                                               ; preds = %60
  %63 = mul nuw i64 %.141.i.i, %28
  %64 = shl nuw i64 %.139.i.i, 32
  %65 = or i64 %64, %30
  %66 = icmp ugt i64 %63, %65
  br i1 %66, label %.critedge2.i.i, label %compiler_rt.udivmod.divwide__anon_14189.exit

.critedge2.i.i:                                   ; preds = %62, %60
  %67 = add i64 %.141.i.i, -1
  %68 = add nuw i64 %.139.i.i, %27
  %69 = icmp ugt i64 %68, 4294967295
  br i1 %69, label %compiler_rt.udivmod.divwide__anon_14189.exit, label %60

compiler_rt.udivmod.divwide__anon_14189.exit:     ; preds = %.critedge2.i.i, %62
  %.040.i.i = phi i64 [ %67, %.critedge2.i.i ], [ %.141.i.i, %62 ]
  %70 = shl i64 %46, 32
  %71 = or i64 %70, %30
  %72 = mul i64 %.040.i.i, %.0.i.i
  %73 = sub i64 %71, %72
  %74 = lshr i64 %73, %25
  br label %21

75:                                               ; preds = %9
  %.sroa.2.0.extract.trunc.frozen = freeze i64 %.sroa.2.0.extract.trunc
  %.sroa.015.0.extract.trunc.frozen = freeze i64 %.sroa.015.0.extract.trunc
  %76 = udiv i64 %.sroa.2.0.extract.trunc.frozen, %.sroa.015.0.extract.trunc.frozen
  %77 = mul i64 %76, %.sroa.015.0.extract.trunc.frozen
  %.decomposed = sub i64 %.sroa.2.0.extract.trunc.frozen, %77
  %78 = tail call i64 @llvm.ctlz.i64(i64 %.sroa.015.0.extract.trunc, i1 false), !range !28
  %79 = and i64 %78, 63
  %.not.i.i48 = icmp eq i64 %79, 0
  br i1 %.not.i.i48, label %80, label %88

80:                                               ; preds = %88, %75
  %.036.i.i49 = phi i64 [ %95, %88 ], [ %.sroa.07.0.extract.trunc, %75 ]
  %.035.i.i50 = phi i64 [ %94, %88 ], [ %.decomposed, %75 ]
  %.0.i.i51 = phi i64 [ %89, %88 ], [ %.sroa.015.0.extract.trunc, %75 ]
  %81 = lshr i64 %.0.i.i51, 32
  %82 = and i64 %.0.i.i51, 4294967295
  %83 = lshr i64 %.036.i.i49, 32
  %84 = and i64 %.036.i.i49, 4294967295
  %85 = udiv i64 %.035.i.i50, %81
  %86 = mul i64 %85, %81
  %87 = sub i64 %.035.i.i50, %86
  br label %104

88:                                               ; preds = %75
  %89 = shl i64 %.sroa.015.0.extract.trunc, %79
  %90 = shl i64 %.decomposed, %79
  %91 = sub nsw i64 0, %78
  %92 = and i64 %91, 63
  %93 = lshr i64 %.sroa.07.0.extract.trunc, %92
  %94 = or i64 %90, %93
  %95 = shl i64 %.sroa.07.0.extract.trunc, %79
  br label %80

96:                                               ; preds = %.critedge.i.i55, %106
  %.037.i.i52 = phi i64 [ %111, %.critedge.i.i55 ], [ %.1.i.i54, %106 ]
  %97 = shl i64 %.035.i.i50, 32
  %98 = or i64 %97, %83
  %99 = mul i64 %.037.i.i52, %.0.i.i51
  %100 = sub i64 %98, %99
  %101 = udiv i64 %100, %81
  %102 = mul i64 %101, %81
  %103 = sub i64 %100, %102
  br label %114

104:                                              ; preds = %.critedge.i.i55, %80
  %.038.i.i53 = phi i64 [ %87, %80 ], [ %112, %.critedge.i.i55 ]
  %.1.i.i54 = phi i64 [ %85, %80 ], [ %111, %.critedge.i.i55 ]
  %105 = icmp ugt i64 %.1.i.i54, 4294967295
  br i1 %105, label %.critedge.i.i55, label %106

106:                                              ; preds = %104
  %107 = mul nuw i64 %.1.i.i54, %82
  %108 = shl nuw i64 %.038.i.i53, 32
  %109 = or i64 %108, %83
  %110 = icmp ugt i64 %107, %109
  br i1 %110, label %.critedge.i.i55, label %96

.critedge.i.i55:                                  ; preds = %106, %104
  %111 = add i64 %.1.i.i54, -1
  %112 = add nuw i64 %.038.i.i53, %81
  %113 = icmp ugt i64 %112, 4294967295
  br i1 %113, label %96, label %104

114:                                              ; preds = %.critedge2.i.i58, %96
  %.141.i.i56 = phi i64 [ %101, %96 ], [ %121, %.critedge2.i.i58 ]
  %.139.i.i57 = phi i64 [ %103, %96 ], [ %122, %.critedge2.i.i58 ]
  %115 = icmp ugt i64 %.141.i.i56, 4294967295
  br i1 %115, label %.critedge2.i.i58, label %116

116:                                              ; preds = %114
  %117 = mul nuw i64 %.141.i.i56, %82
  %118 = shl nuw i64 %.139.i.i57, 32
  %119 = or i64 %118, %84
  %120 = icmp ugt i64 %117, %119
  br i1 %120, label %.critedge2.i.i58, label %compiler_rt.udivmod.divwide__anon_14189.exit60

.critedge2.i.i58:                                 ; preds = %116, %114
  %121 = add i64 %.141.i.i56, -1
  %122 = add nuw i64 %.139.i.i57, %81
  %123 = icmp ugt i64 %122, 4294967295
  br i1 %123, label %compiler_rt.udivmod.divwide__anon_14189.exit60, label %114

compiler_rt.udivmod.divwide__anon_14189.exit60:   ; preds = %.critedge2.i.i58, %116
  %.040.i.i59 = phi i64 [ %121, %.critedge2.i.i58 ], [ %.141.i.i56, %116 ]
  %124 = shl i64 %100, 32
  %125 = or i64 %124, %84
  %126 = mul i64 %.040.i.i59, %.0.i.i51
  %127 = sub i64 %125, %126
  %128 = lshr i64 %127, %79
  br label %21

129:                                              ; preds = %130, %21
  %.sroa.10.0.insert.ext = zext i64 %.sroa.10.0 to i128
  %.sroa.10.0.insert.shift = shl nuw i128 %.sroa.10.0.insert.ext, 64
  %.sroa.017.0.insert.ext = zext i64 %23 to i128
  %.sroa.017.0.insert.insert = or i128 %.sroa.10.0.insert.shift, %.sroa.017.0.insert.ext
  br label %common.ret

130:                                              ; preds = %21
  %.sroa.0.0.insert.ext = zext i64 %.sroa.0.0 to i128
  store i128 %.sroa.0.0.insert.ext, ptr %2, align 16
  br label %129

131:                                              ; preds = %131, %11
  %lsr.iv = phi i64 [ %20, %11 ], [ %lsr.iv.next, %131 ]
  %.04066 = phi i128 [ %18, %11 ], [ %140, %131 ]
  %.04165 = phi i128 [ %0, %11 ], [ %139, %131 ]
  %.sroa.017.164 = phi i64 [ 0, %11 ], [ %137, %131 ]
  %132 = shl i64 %.sroa.017.164, 1
  %133 = xor i128 %.04165, -1
  %134 = add i128 %.04066, %133
  %135 = lshr i128 %134, 127
  %136 = trunc i128 %135 to i64
  %137 = or i64 %132, %136
  %isneg = icmp slt i128 %134, 0
  %138 = select i1 %isneg, i128 %.04066, i128 0
  %139 = sub nuw i128 %.04165, %138
  %140 = lshr i128 %.04066, 1
  %lsr.iv.next = add i64 %lsr.iv, -1
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %141, label %131

141:                                              ; preds = %131
  %.not = icmp eq ptr %2, null
  br i1 %.not, label %142, label %143

142:                                              ; preds = %143, %141
  %.sroa.017.0.insert.ext21 = zext i64 %137 to i128
  br label %common.ret

143:                                              ; preds = %141
  store i128 %139, ptr %2, align 16
  br label %142
}

; Function Attrs: nounwind uwtable
define weak_odr dso_local i128 @__udivti3(i128 %0, i128 %1) local_unnamed_addr #4 {
  %3 = tail call fastcc i128 @compiler_rt.udivmod.udivmod__anon_12849(i128 %0, i128 %1, ptr align 16 null)
  ret i128 %3
}

; Function Attrs: nounwind uwtable
define weak_odr dso_local i128 @__modti3(i128 %0, i128 %1) local_unnamed_addr #4 {
  %3 = alloca i128, align 16
  %4 = ashr i128 %0, 127
  %5 = xor i128 %4, %0
  %6 = sub i128 %5, %4
  %7 = tail call i128 @llvm.abs.i128(i128 %1, i1 false)
  %8 = call fastcc i128 @compiler_rt.udivmod.udivmod__anon_12849(i128 %6, i128 %7, ptr nonnull align 16 %3)
  %9 = load i128, ptr %3, align 16
  %10 = xor i128 %9, %4
  %11 = sub i128 %10, %4
  ret i128 %11
}

; Function Attrs: nounwind uwtable
define weak_odr dso_local i128 @__muloti4(i128 %0, i128 %1, ptr nonnull align 4 %2) local_unnamed_addr #4 {
  %.fr = freeze i128 %1
  store i32 0, ptr %2, align 4
  %mul = tail call { i128, i1 } @llvm.smul.with.overflow.i128(i128 %0, i128 %.fr)
  %4 = icmp slt i128 %0, 0
  %5 = icmp eq i128 %.fr, -170141183460469231731687303715884105728
  %6 = and i1 %4, %5
  br i1 %6, label %.critedge, label %7

.critedge2:                                       ; preds = %.critedge, %7
  %mul.val = extractvalue { i128, i1 } %mul, 0
  ret i128 %mul.val

7:                                                ; preds = %3
  %mul.ov = extractvalue { i128, i1 } %mul, 1
  br i1 %mul.ov, label %.critedge, label %.critedge2

.critedge:                                        ; preds = %7, %3
  store i32 1, ptr %2, align 4
  br label %.critedge2
}

; Function Attrs: nounwind uwtable
define weak_odr dso_local float @floorf(float %0) local_unnamed_addr #4 {
  %2 = bitcast float %0 to i32
  %3 = lshr i32 %2, 23
  %4 = and i32 %3, 255
  %5 = add nuw nsw i32 %3, 1
  %6 = fcmp oeq float %0, 0.000000e+00
  %7 = icmp ugt i32 %4, 149
  %or.cond = select i1 %6, i1 true, i1 %7
  br i1 %or.cond, label %common.ret, label %8

common.ret:                                       ; preds = %18, %15, %10, %1
  %common.ret.op = phi float [ %23, %18 ], [ %0, %1 ], [ %., %15 ], [ %0, %10 ]
  ret float %common.ret.op

8:                                                ; preds = %1
  %9 = icmp ugt i32 %4, 126
  br i1 %9, label %10, label %15

10:                                               ; preds = %8
  %11 = and i32 %5, 31
  %12 = lshr i32 8388607, %11
  %13 = and i32 %12, %2
  %14 = icmp eq i32 %13, 0
  br i1 %14, label %common.ret, label %18

15:                                               ; preds = %8
  %16 = fadd float %0, 0x4770000000000000
  tail call void asm sideeffect "", "rm"(float %16) #14
  %17 = icmp sgt i32 %2, -1
  %. = select i1 %17, float 0.000000e+00, float -1.000000e+00
  br label %common.ret

18:                                               ; preds = %10
  %19 = fadd float %0, 0x4770000000000000
  tail call void asm sideeffect "", "rm"(float %19) #14
  %.not11 = icmp slt i32 %2, 0
  %20 = select i1 %.not11, i32 %12, i32 0
  %spec.select = add nuw i32 %20, %2
  %21 = ashr i32 -8388608, %11
  %22 = and i32 %spec.select, %21
  %23 = bitcast i32 %22 to float
  br label %common.ret
}

; Function Attrs: nounwind uwtable
define weak_odr dso_local ptr @memcpy(ptr noalias align 1 %0, ptr noalias readonly align 1 %1, i64 %2) local_unnamed_addr #4 {
  %.not = icmp eq i64 %2, 0
  br i1 %.not, label %.loopexit, label %.preheader

.preheader:                                       ; preds = %3
  %4 = load i8, ptr %1, align 1
  store i8 %4, ptr %0, align 1
  %5 = add i64 %2, -1
  %6 = icmp eq i64 %5, 0
  br i1 %6, label %.loopexit, label %iter.check

iter.check:                                       ; preds = %.preheader
  %min.iters.check = icmp ult i64 %2, 9
  br i1 %min.iters.check, label %.lr.ph.preheader, label %vector.main.loop.iter.check

vector.main.loop.iter.check:                      ; preds = %iter.check
  %min.iters.check11 = icmp ult i64 %2, 33
  br i1 %min.iters.check11, label %vec.epilog.ph, label %vector.ph

vector.ph:                                        ; preds = %vector.main.loop.iter.check
  %n.vec = and i64 %5, -32
  %uglygep50 = getelementptr i8, ptr %1, i64 17
  %uglygep54 = getelementptr i8, ptr %0, i64 17
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv58 = phi i64 [ %lsr.iv.next59, %vector.body ], [ %n.vec, %vector.ph ]
  %lsr.iv55 = phi ptr [ %uglygep56, %vector.body ], [ %uglygep54, %vector.ph ]
  %lsr.iv51 = phi ptr [ %uglygep52, %vector.body ], [ %uglygep50, %vector.ph ]
  %uglygep57 = getelementptr i8, ptr %lsr.iv55, i64 -16
  %uglygep53 = getelementptr i8, ptr %lsr.iv51, i64 -16
  %wide.load = load <16 x i8>, ptr %uglygep53, align 1
  %wide.load15 = load <16 x i8>, ptr %lsr.iv51, align 1
  store <16 x i8> %wide.load, ptr %uglygep57, align 1
  store <16 x i8> %wide.load15, ptr %lsr.iv55, align 1
  %uglygep52 = getelementptr i8, ptr %lsr.iv51, i64 32
  %uglygep56 = getelementptr i8, ptr %lsr.iv55, i64 32
  %lsr.iv.next59 = add i64 %lsr.iv58, -32
  %7 = icmp eq i64 %lsr.iv.next59, 0
  br i1 %7, label %middle.block, label %vector.body, !llvm.loop !29

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %5, %n.vec
  br i1 %cmp.n, label %.loopexit, label %vec.epilog.iter.check

vec.epilog.iter.check:                            ; preds = %middle.block
  %ind.end27 = getelementptr i8, ptr %1, i64 %n.vec
  %ind.end24 = getelementptr i8, ptr %0, i64 %n.vec
  %ind.end21 = and i64 %5, 31
  %n.vec.remaining = and i64 %5, 24
  %min.epilog.iters.check = icmp eq i64 %n.vec.remaining, 0
  br i1 %min.epilog.iters.check, label %.lr.ph.preheader, label %vec.epilog.ph

vec.epilog.ph:                                    ; preds = %vec.epilog.iter.check, %vector.main.loop.iter.check
  %vec.epilog.resume.val = phi i64 [ %n.vec, %vec.epilog.iter.check ], [ 0, %vector.main.loop.iter.check ]
  %n.vec19 = and i64 %5, -8
  %ind.end20 = and i64 %5, 7
  %ind.end23 = getelementptr i8, ptr %0, i64 %n.vec19
  %ind.end26 = getelementptr i8, ptr %1, i64 %n.vec19
  %8 = add nuw nsw i64 %vec.epilog.resume.val, 1
  %uglygep43 = getelementptr i8, ptr %1, i64 %8
  %uglygep46 = getelementptr i8, ptr %0, i64 %8
  %9 = sub i64 %vec.epilog.resume.val, %n.vec19
  br label %vec.epilog.vector.body

vec.epilog.vector.body:                           ; preds = %vec.epilog.vector.body, %vec.epilog.ph
  %lsr.iv49 = phi i64 [ %lsr.iv.next, %vec.epilog.vector.body ], [ %9, %vec.epilog.ph ]
  %lsr.iv47 = phi ptr [ %uglygep48, %vec.epilog.vector.body ], [ %uglygep46, %vec.epilog.ph ]
  %lsr.iv44 = phi ptr [ %uglygep45, %vec.epilog.vector.body ], [ %uglygep43, %vec.epilog.ph ]
  %wide.load33 = load <8 x i8>, ptr %lsr.iv44, align 1
  store <8 x i8> %wide.load33, ptr %lsr.iv47, align 1
  %uglygep45 = getelementptr i8, ptr %lsr.iv44, i64 8
  %uglygep48 = getelementptr i8, ptr %lsr.iv47, i64 8
  %lsr.iv.next = add i64 %lsr.iv49, 8
  %10 = icmp eq i64 %lsr.iv.next, 0
  br i1 %10, label %vec.epilog.middle.block, label %vec.epilog.vector.body, !llvm.loop !32

vec.epilog.middle.block:                          ; preds = %vec.epilog.vector.body
  %cmp.n29 = icmp eq i64 %5, %n.vec19
  br i1 %cmp.n29, label %.loopexit, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %vec.epilog.middle.block, %vec.epilog.iter.check, %iter.check
  %.ph = phi i64 [ %ind.end20, %vec.epilog.middle.block ], [ %ind.end21, %vec.epilog.iter.check ], [ %5, %iter.check ]
  %.010.ph = phi ptr [ %ind.end23, %vec.epilog.middle.block ], [ %ind.end24, %vec.epilog.iter.check ], [ %0, %iter.check ]
  %.059.ph = phi ptr [ %ind.end26, %vec.epilog.middle.block ], [ %ind.end27, %vec.epilog.iter.check ], [ %1, %iter.check ]
  %uglygep = getelementptr i8, ptr %.010.ph, i64 1
  %uglygep40 = getelementptr i8, ptr %.059.ph, i64 1
  br label %.lr.ph

.loopexit:                                        ; preds = %.lr.ph, %vec.epilog.middle.block, %middle.block, %.preheader, %3
  ret ptr %0

.lr.ph:                                           ; preds = %.lr.ph, %.lr.ph.preheader
  %lsr.iv41 = phi ptr [ %uglygep40, %.lr.ph.preheader ], [ %uglygep42, %.lr.ph ]
  %lsr.iv = phi ptr [ %uglygep, %.lr.ph.preheader ], [ %uglygep39, %.lr.ph ]
  %11 = phi i64 [ %13, %.lr.ph ], [ %.ph, %.lr.ph.preheader ]
  %12 = load i8, ptr %lsr.iv41, align 1
  store i8 %12, ptr %lsr.iv, align 1
  %13 = add i64 %11, -1
  %uglygep39 = getelementptr i8, ptr %lsr.iv, i64 1
  %uglygep42 = getelementptr i8, ptr %lsr.iv41, i64 1
  %14 = icmp eq i64 %13, 0
  br i1 %14, label %.loopexit, label %.lr.ph, !llvm.loop !33
}

; Function Attrs: nounwind uwtable
define weak_odr dso_local ptr @memset(ptr align 1 %0, i8 zeroext %1, i64 %2) local_unnamed_addr #4 {
  %.not = icmp eq i64 %2, 0
  br i1 %.not, label %.loopexit, label %iter.check

iter.check:                                       ; preds = %3
  %min.iters.check = icmp ult i64 %2, 8
  br i1 %min.iters.check, label %.preheader.preheader, label %vector.main.loop.iter.check

vector.main.loop.iter.check:                      ; preds = %iter.check
  %min.iters.check6 = icmp ult i64 %2, 32
  br i1 %min.iters.check6, label %vec.epilog.ph, label %vector.ph

vector.ph:                                        ; preds = %vector.main.loop.iter.check
  %n.vec = and i64 %2, -32
  %broadcast.splatinsert = insertelement <16 x i8> poison, i8 %1, i64 0
  %broadcast.splat = shufflevector <16 x i8> %broadcast.splatinsert, <16 x i8> poison, <16 x i32> zeroinitializer
  %broadcast.splatinsert8 = insertelement <16 x i8> poison, i8 %1, i64 0
  %broadcast.splat9 = shufflevector <16 x i8> %broadcast.splatinsert8, <16 x i8> poison, <16 x i32> zeroinitializer
  %uglygep26 = getelementptr i8, ptr %0, i64 16
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv30 = phi i64 [ %lsr.iv.next31, %vector.body ], [ %n.vec, %vector.ph ]
  %lsr.iv27 = phi ptr [ %uglygep28, %vector.body ], [ %uglygep26, %vector.ph ]
  %uglygep29 = getelementptr i8, ptr %lsr.iv27, i64 -16
  store <16 x i8> %broadcast.splat, ptr %uglygep29, align 1
  store <16 x i8> %broadcast.splat9, ptr %lsr.iv27, align 1
  %uglygep28 = getelementptr i8, ptr %lsr.iv27, i64 32
  %lsr.iv.next31 = add i64 %lsr.iv30, -32
  %4 = icmp eq i64 %lsr.iv.next31, 0
  br i1 %4, label %middle.block, label %vector.body, !llvm.loop !34

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %n.vec, %2
  br i1 %cmp.n, label %.loopexit, label %vec.epilog.iter.check

vec.epilog.iter.check:                            ; preds = %middle.block
  %ind.end16 = getelementptr i8, ptr %0, i64 %n.vec
  %ind.end13 = and i64 %2, 31
  %n.vec.remaining = and i64 %2, 24
  %min.epilog.iters.check = icmp eq i64 %n.vec.remaining, 0
  br i1 %min.epilog.iters.check, label %.preheader.preheader, label %vec.epilog.ph

vec.epilog.ph:                                    ; preds = %vec.epilog.iter.check, %vector.main.loop.iter.check
  %vec.epilog.resume.val = phi i64 [ %n.vec, %vec.epilog.iter.check ], [ 0, %vector.main.loop.iter.check ]
  %n.vec11 = and i64 %2, -8
  %ind.end12 = and i64 %2, 7
  %ind.end15 = getelementptr i8, ptr %0, i64 %n.vec11
  %broadcast.splatinsert21 = insertelement <8 x i8> poison, i8 %1, i64 0
  %broadcast.splat22 = shufflevector <8 x i8> %broadcast.splatinsert21, <8 x i8> poison, <8 x i32> zeroinitializer
  %uglygep = getelementptr i8, ptr %0, i64 %vec.epilog.resume.val
  %5 = sub i64 %vec.epilog.resume.val, %n.vec11
  br label %vec.epilog.vector.body

vec.epilog.vector.body:                           ; preds = %vec.epilog.vector.body, %vec.epilog.ph
  %lsr.iv25 = phi i64 [ %lsr.iv.next, %vec.epilog.vector.body ], [ %5, %vec.epilog.ph ]
  %lsr.iv = phi ptr [ %uglygep24, %vec.epilog.vector.body ], [ %uglygep, %vec.epilog.ph ]
  store <8 x i8> %broadcast.splat22, ptr %lsr.iv, align 1
  %uglygep24 = getelementptr i8, ptr %lsr.iv, i64 8
  %lsr.iv.next = add i64 %lsr.iv25, 8
  %6 = icmp eq i64 %lsr.iv.next, 0
  br i1 %6, label %vec.epilog.middle.block, label %vec.epilog.vector.body, !llvm.loop !35

vec.epilog.middle.block:                          ; preds = %vec.epilog.vector.body
  %cmp.n18 = icmp eq i64 %n.vec11, %2
  br i1 %cmp.n18, label %.loopexit, label %.preheader.preheader

.preheader.preheader:                             ; preds = %vec.epilog.middle.block, %vec.epilog.iter.check, %iter.check
  %.03.ph = phi i64 [ %ind.end12, %vec.epilog.middle.block ], [ %ind.end13, %vec.epilog.iter.check ], [ %2, %iter.check ]
  %.0.ph = phi ptr [ %ind.end15, %vec.epilog.middle.block ], [ %ind.end16, %vec.epilog.iter.check ], [ %0, %iter.check ]
  br label %.preheader

.loopexit:                                        ; preds = %.preheader, %vec.epilog.middle.block, %middle.block, %3
  ret ptr %0

.preheader:                                       ; preds = %.preheader, %.preheader.preheader
  %.03 = phi i64 [ %7, %.preheader ], [ %.03.ph, %.preheader.preheader ]
  %.0 = phi ptr [ %8, %.preheader ], [ %.0.ph, %.preheader.preheader ]
  store i8 %1, ptr %.0, align 1
  %7 = add i64 %.03, -1
  %8 = getelementptr inbounds i8, ptr %.0, i64 1
  %9 = icmp eq i64 %7, 0
  br i1 %9, label %.loopexit, label %.preheader, !llvm.loop !36
}

; Function Attrs: nofree nosync nounwind memory(argmem: readwrite, inaccessiblemem: readwrite) uwtable
define private fastcc void @unicode.utf8CountCodepoints(ptr noalias nocapture nonnull writeonly %0, ptr nocapture nonnull readonly align 1 %1, i64 %2) unnamed_addr #8 {
  %4 = alloca { i21, i16, [2 x i8] }, align 4
  %.not56 = icmp eq i64 %2, 0
  br i1 %.not56, label %._crit_edge54, label %.preheader.lr.ph

.preheader.lr.ph:                                 ; preds = %3
  %5 = load i32, ptr @0, align 4
  %6 = load i32, ptr @4, align 4
  %7 = load i32, ptr @3, align 4
  %8 = load i32, ptr @2, align 4
  br label %.preheader

common.ret:                                       ; preds = %45, %33, %._crit_edge54
  ret void

.preheader:                                       ; preds = %15, %.preheader.lr.ph
  %.053 = phi i64 [ 0, %.preheader.lr.ph ], [ %.2, %15 ]
  %.02952 = phi i64 [ 0, %.preheader.lr.ph ], [ %.231, %15 ]
  %9 = add nuw i64 %.02952, 8
  %.not45 = icmp ugt i64 %9, %2
  br i1 %.not45, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %.preheader
  br label %.lr.ph

._crit_edge54:                                    ; preds = %15, %3
  %.0.lcssa = phi i64 [ 0, %3 ], [ %.2, %15 ]
  store i64 %.0.lcssa, ptr %0, align 8
  %.sroa.228.0..sroa_idx = getelementptr inbounds i8, ptr %0, i64 8
  store i16 0, ptr %.sroa.228.0..sroa_idx, align 8
  br label %common.ret

._crit_edge:                                      ; preds = %12, %.lr.ph, %.preheader
  %.130.lcssa = phi i64 [ %.02952, %.preheader ], [ %lsr.iv, %.lr.ph ], [ %lsr.iv.next, %12 ]
  %.1.lcssa = phi i64 [ %.053, %.preheader ], [ %.147, %.lr.ph ], [ %13, %12 ]
  %10 = icmp ult i64 %.130.lcssa, %2
  br i1 %10, label %17, label %15

.lr.ph:                                           ; preds = %12, %.lr.ph.preheader
  %lsr.iv = phi i64 [ %.02952, %.lr.ph.preheader ], [ %lsr.iv.next, %12 ]
  %.147 = phi i64 [ %13, %12 ], [ %.053, %.lr.ph.preheader ]
  %uglygep = getelementptr i8, ptr %1, i64 %lsr.iv
  %.val = load i64, ptr %uglygep, align 1
  %11 = and i64 %.val, -9187201950435737472
  %.not39 = icmp eq i64 %11, 0
  br i1 %.not39, label %12, label %._crit_edge

12:                                               ; preds = %.lr.ph
  %13 = add i64 %.147, 8
  %lsr.iv.next = add i64 %lsr.iv, 8
  %14 = add i64 %lsr.iv.next, 8
  %.not = icmp ugt i64 %14, %2
  br i1 %.not, label %._crit_edge, label %.lr.ph

15:                                               ; preds = %41, %._crit_edge
  %.231 = phi i64 [ %36, %41 ], [ %.130.lcssa, %._crit_edge ]
  %.2 = phi i64 [ %42, %41 ], [ %.1.lcssa, %._crit_edge ]
  %16 = icmp ult i64 %.231, %2
  br i1 %16, label %.preheader, label %._crit_edge54

17:                                               ; preds = %._crit_edge
  %18 = getelementptr inbounds i8, ptr %1, i64 %.130.lcssa
  %19 = load i8, ptr %18, align 1
  %20 = zext i8 %19 to i32
  %21 = trunc i32 %20 to i8
  %22 = icmp sgt i8 %21, -1
  br i1 %22, label %unicode.utf8ByteSequenceLength.exit, label %23

23:                                               ; preds = %17
  %24 = and i32 %20, 224
  %25 = icmp eq i32 %24, 192
  br i1 %25, label %unicode.utf8ByteSequenceLength.exit, label %26

26:                                               ; preds = %23
  %27 = and i32 %20, 240
  %28 = icmp eq i32 %27, 224
  br i1 %28, label %unicode.utf8ByteSequenceLength.exit, label %29

29:                                               ; preds = %26
  %30 = and i32 %20, 248
  %31 = icmp eq i32 %30, 240
  %spec.select.i = select i1 %31, i32 %5, i32 20
  br label %unicode.utf8ByteSequenceLength.exit

unicode.utf8ByteSequenceLength.exit:              ; preds = %29, %26, %23, %17
  %.sink.i = phi i32 [ %spec.select.i, %29 ], [ %8, %17 ], [ %7, %23 ], [ %6, %26 ]
  %32 = and i32 %.sink.i, 65535
  %.not37 = icmp eq i32 %32, 0
  br i1 %.not37, label %34, label %33

33:                                               ; preds = %unicode.utf8ByteSequenceLength.exit
  %.sroa.0.0.extract.trunc.le = trunc i32 %.sink.i to i16
  %.sroa.1.0..sroa_idx = getelementptr inbounds i8, ptr %0, i64 8
  store i16 %.sroa.0.0.extract.trunc.le, ptr %.sroa.1.0..sroa_idx, align 8
  br label %common.ret

34:                                               ; preds = %unicode.utf8ByteSequenceLength.exit
  %.sroa.2.0.extract.shift = lshr i32 %.sink.i, 16
  %.mask = and i32 %.sroa.2.0.extract.shift, 7
  %35 = zext i32 %.mask to i64
  %36 = add nuw i64 %.130.lcssa, %35
  %37 = icmp ugt i64 %36, %2
  br i1 %37, label %38, label %39

38:                                               ; preds = %34
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) @1, i64 16, i1 false)
  ret void

39:                                               ; preds = %34
  %40 = and i32 %.sink.i, 458752
  %cond = icmp eq i32 %40, 65536
  br i1 %cond, label %41, label %43

41:                                               ; preds = %43, %39
  %42 = add nuw i64 %.1.lcssa, 1
  br label %15

43:                                               ; preds = %39
  call fastcc void @unicode.utf8Decode(ptr noalias %4, ptr nonnull readonly align 1 %18, i64 %35)
  %sunkaddr = getelementptr inbounds i8, ptr %4, i64 4
  %44 = load i16, ptr %sunkaddr, align 4
  %.not38 = icmp eq i16 %44, 0
  br i1 %.not38, label %41, label %45

45:                                               ; preds = %43
  %.sroa.125.0..sroa_idx = getelementptr inbounds i8, ptr %0, i64 8
  store i16 %44, ptr %.sroa.125.0..sroa_idx, align 8
  br label %common.ret
}

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(argmem: readwrite, inaccessiblemem: readwrite) uwtable
define private fastcc void @unicode.utf8Decode(ptr noalias nocapture nonnull writeonly %0, ptr nocapture nonnull readonly align 1 %1, i64 %2) unnamed_addr #9 {
  %.sroa.09.i.sroa.0 = alloca i24, align 4
  %.sroa.08.i.sroa.0 = alloca i24, align 4
  %.sroa.04.i.sroa.0 = alloca i24, align 4
  %.sroa.0 = alloca [3 x i8], align 4
  switch i64 %2, label %5 [
    i64 1, label %6
    i64 2, label %9
    i64 3, label %26
    i64 4, label %58
  ]

4:                                                ; preds = %unicode.utf8Decode4.exit, %unicode.utf8Decode3.exit, %unicode.utf8Decode2.exit, %6
  ret void

5:                                                ; preds = %3
  unreachable

6:                                                ; preds = %3
  %7 = load i8, ptr %1, align 1
  %8 = zext i8 %7 to i21
  store i21 %8, ptr %.sroa.0, align 4
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 4 dereferenceable(3) %0, ptr noundef nonnull align 4 dereferenceable(3) %.sroa.0, i64 3, i1 false)
  %.sroa.21.0..sroa_idx = getelementptr inbounds i8, ptr %0, i64 4
  store i16 0, ptr %.sroa.21.0..sroa_idx, align 4
  br label %4

9:                                                ; preds = %3
  %.val = load i8, ptr %1, align 1
  %10 = zext i8 %.val to i32
  %11 = getelementptr i8, ptr %1, i64 1
  %.val2 = load i8, ptr %11, align 1
  %12 = zext i8 %.val2 to i32
  call void @llvm.lifetime.start.p0(i64 3, ptr nonnull %.sroa.04.i.sroa.0)
  %13 = and i32 %12, 192
  %.not.i = icmp eq i32 %13, 128
  br i1 %.not.i, label %14, label %unicode.utf8Decode2.exit

14:                                               ; preds = %9
  %15 = and i32 %10, 31
  %16 = trunc i32 %15 to i8
  %17 = zext i8 %16 to i21
  %18 = shl nuw nsw i21 %17, 6
  %19 = and i32 %12, 63
  %20 = trunc i32 %19 to i8
  %21 = zext i8 %20 to i21
  %22 = or i21 %18, %21
  %23 = icmp ult i21 %22, 128
  br i1 %23, label %unicode.utf8Decode2.exit, label %24

24:                                               ; preds = %14
  store i21 %22, ptr %.sroa.04.i.sroa.0, align 4, !noalias !37
  %.sroa.04.i.sroa.0.0..sroa.04.i.sroa.0.0..sroa.04.i.sroa.0.0..sroa.04.i.sroa.0.0..sroa.05.sroa.0.0.copyload = load i24, ptr %.sroa.04.i.sroa.0, align 4
  %25 = zext i24 %.sroa.04.i.sroa.0.0..sroa.04.i.sroa.0.0..sroa.04.i.sroa.0.0..sroa.04.i.sroa.0.0..sroa.05.sroa.0.0.copyload to i64
  br label %unicode.utf8Decode2.exit

unicode.utf8Decode2.exit:                         ; preds = %24, %14, %9
  %.sroa.05.sroa.0.0 = phi i64 [ %25, %24 ], [ 0, %9 ], [ 0, %14 ]
  %.sroa.4.0 = phi i64 [ 0, %24 ], [ 94489280512, %9 ], [ 98784247808, %14 ]
  call void @llvm.lifetime.end.p0(i64 3, ptr nonnull %.sroa.04.i.sroa.0)
  %.sroa.05.0.insert.insert = or i64 %.sroa.4.0, %.sroa.05.sroa.0.0
  store i64 %.sroa.05.0.insert.insert, ptr %0, align 4
  br label %4

26:                                               ; preds = %3
  call void @llvm.lifetime.start.p0(i64 3, ptr nonnull %.sroa.08.i.sroa.0)
  %27 = load i8, ptr %1, align 1, !noalias !40
  %28 = zext i8 %27 to i32
  %29 = getelementptr inbounds i8, ptr %1, i64 1
  %30 = load i8, ptr %29, align 1, !noalias !40
  %31 = zext i8 %30 to i32
  %32 = and i32 %31, 192
  %.not.i3 = icmp eq i32 %32, 128
  br i1 %.not.i3, label %33, label %unicode.utf8Decode3.exit

33:                                               ; preds = %26
  %34 = getelementptr inbounds i8, ptr %1, i64 2
  %35 = load i8, ptr %34, align 1, !noalias !40
  %36 = zext i8 %35 to i32
  %37 = and i32 %36, 192
  %.not10.i = icmp eq i32 %37, 128
  br i1 %.not10.i, label %38, label %unicode.utf8Decode3.exit

38:                                               ; preds = %33
  %39 = and i32 %28, 15
  %40 = trunc i32 %39 to i8
  %41 = zext i8 %40 to i21
  %42 = and i32 %31, 63
  %43 = trunc i32 %42 to i8
  %44 = zext i8 %43 to i21
  %45 = shl nuw nsw i21 %41, 12
  %46 = shl nuw nsw i21 %44, 6
  %47 = or i21 %46, %45
  %48 = and i32 %36, 63
  %49 = trunc i32 %48 to i8
  %50 = zext i8 %49 to i21
  %51 = or i21 %47, %50
  %52 = icmp ult i21 %51, 2048
  br i1 %52, label %unicode.utf8Decode3.exit, label %53

53:                                               ; preds = %38
  %54 = and i21 %47, 63488
  %55 = icmp eq i21 %54, 55296
  br i1 %55, label %unicode.utf8Decode3.exit, label %56

56:                                               ; preds = %53
  store i21 %51, ptr %.sroa.08.i.sroa.0, align 4, !noalias !40
  %.sroa.08.i.sroa.0.0..sroa.08.i.sroa.0.0..sroa.08.i.sroa.0.0..sroa.08.i.sroa.0.0..sroa.06.sroa.0.0.copyload = load i24, ptr %.sroa.08.i.sroa.0, align 4
  %57 = zext i24 %.sroa.08.i.sroa.0.0..sroa.08.i.sroa.0.0..sroa.08.i.sroa.0.0..sroa.08.i.sroa.0.0..sroa.06.sroa.0.0.copyload to i64
  br label %unicode.utf8Decode3.exit

unicode.utf8Decode3.exit:                         ; preds = %56, %53, %38, %33, %26
  %.sroa.06.sroa.0.0 = phi i64 [ %57, %56 ], [ 0, %26 ], [ 0, %33 ], [ 0, %38 ], [ 0, %53 ]
  %.sroa.6.0 = phi i64 [ 0, %56 ], [ 94489280512, %26 ], [ 94489280512, %33 ], [ 98784247808, %38 ], [ 103079215104, %53 ]
  call void @llvm.lifetime.end.p0(i64 3, ptr nonnull %.sroa.08.i.sroa.0)
  %.sroa.06.0.insert.insert = or i64 %.sroa.6.0, %.sroa.06.sroa.0.0
  store i64 %.sroa.06.0.insert.insert, ptr %0, align 4
  br label %4

58:                                               ; preds = %3
  call void @llvm.lifetime.start.p0(i64 3, ptr nonnull %.sroa.09.i.sroa.0)
  %59 = load i8, ptr %1, align 1, !noalias !43
  %60 = zext i8 %59 to i32
  %61 = getelementptr inbounds i8, ptr %1, i64 1
  %62 = load i8, ptr %61, align 1, !noalias !43
  %63 = zext i8 %62 to i32
  %64 = and i32 %63, 192
  %.not.i4 = icmp eq i32 %64, 128
  br i1 %.not.i4, label %65, label %unicode.utf8Decode4.exit

65:                                               ; preds = %58
  %66 = getelementptr inbounds i8, ptr %1, i64 2
  %67 = load i8, ptr %66, align 1, !noalias !43
  %68 = zext i8 %67 to i32
  %69 = and i32 %68, 192
  %.not11.i = icmp eq i32 %69, 128
  br i1 %.not11.i, label %70, label %unicode.utf8Decode4.exit

70:                                               ; preds = %65
  %71 = getelementptr inbounds i8, ptr %1, i64 3
  %72 = load i8, ptr %71, align 1, !noalias !43
  %73 = zext i8 %72 to i32
  %74 = and i32 %73, 192
  %.not12.i = icmp eq i32 %74, 128
  br i1 %.not12.i, label %75, label %unicode.utf8Decode4.exit

75:                                               ; preds = %70
  %76 = trunc i32 %60 to i8
  %77 = zext i8 %76 to i21
  %78 = shl nuw nsw i21 %77, 12
  %79 = and i32 %63, 63
  %80 = trunc i32 %79 to i8
  %81 = zext i8 %80 to i21
  %82 = shl nuw nsw i21 %81, 6
  %83 = or i21 %82, %78
  %84 = and i32 %68, 63
  %85 = trunc i32 %84 to i8
  %86 = zext i8 %85 to i21
  %87 = or i21 %83, %86
  %88 = shl i21 %87, 6
  %89 = and i32 %73, 63
  %90 = trunc i32 %89 to i8
  %91 = zext i8 %90 to i21
  %92 = or i21 %88, %91
  %93 = icmp ult i21 %92, 65536
  br i1 %93, label %unicode.utf8Decode4.exit, label %94

94:                                               ; preds = %75
  %95 = icmp ugt i21 %92, -983041
  br i1 %95, label %unicode.utf8Decode4.exit, label %96

96:                                               ; preds = %94
  store i21 %92, ptr %.sroa.09.i.sroa.0, align 4, !noalias !43
  %.sroa.09.i.sroa.0.0..sroa.09.i.sroa.0.0..sroa.09.i.sroa.0.0..sroa.09.i.sroa.0.0..sroa.07.sroa.0.0.copyload = load i24, ptr %.sroa.09.i.sroa.0, align 4
  %97 = zext i24 %.sroa.09.i.sroa.0.0..sroa.09.i.sroa.0.0..sroa.09.i.sroa.0.0..sroa.09.i.sroa.0.0..sroa.07.sroa.0.0.copyload to i64
  br label %unicode.utf8Decode4.exit

unicode.utf8Decode4.exit:                         ; preds = %96, %94, %75, %70, %65, %58
  %.sroa.07.sroa.0.0 = phi i64 [ %97, %96 ], [ 0, %58 ], [ 0, %65 ], [ 0, %70 ], [ 0, %75 ], [ 0, %94 ]
  %.sroa.7.0 = phi i64 [ 0, %96 ], [ 94489280512, %58 ], [ 94489280512, %65 ], [ 94489280512, %70 ], [ 98784247808, %75 ], [ 107374182400, %94 ]
  call void @llvm.lifetime.end.p0(i64 3, ptr nonnull %.sroa.09.i.sroa.0)
  %.sroa.07.0.insert.insert = or i64 %.sroa.7.0, %.sroa.07.sroa.0.0
  store i64 %.sroa.07.0.insert.insert, ptr %0, align 4
  br label %4
}

; Function Attrs: nofree nosync nounwind uwtable
define private fastcc i16 @fmt.formatBuf__anon_13240(ptr nocapture nonnull readonly align 1 %0, i64 %1, ptr nocapture nonnull readonly align 8 %2, ptr nocapture nonnull readonly align 8 %3) unnamed_addr #10 {
  %5 = alloca [256 x i8], align 1
  %6 = alloca [256 x i8], align 1
  %7 = alloca [256 x i8], align 1
  %8 = alloca %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write'))", align 8
  %9 = alloca { i64, i16, [6 x i8] }, align 8
  %.sroa.2.0..sroa_idx = getelementptr inbounds %fmt.FormatOptions, ptr %2, i64 0, i32 1, i32 1
  %.sroa.2.0.copyload = load i8, ptr %.sroa.2.0..sroa_idx, align 8
  %.not = icmp eq i8 %.sroa.2.0.copyload, 0
  br i1 %.not, label %18, label %10

common.ret:                                       ; preds = %172, %.lr.ph.i90, %169, %.loopexit116, %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit81", %.loopexit112, %131, %.lr.ph.i63, %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit54", %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit", %66, %.lr.ph.i33, %43, %.lr.ph.i21, %40, %36, %25, %.lr.ph.i, %22, %18
  %common.ret.op = phi i16 [ %common.ret.op.i37, %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit" ], [ 5, %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit54" ], [ %144, %.loopexit112 ], [ 5, %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit81" ], [ 0, %18 ], [ 0, %36 ], [ 0, %.loopexit116 ], [ 5, %.lr.ph.i ], [ 5, %25 ], [ 0, %22 ], [ 5, %.lr.ph.i33 ], [ 5, %66 ], [ 5, %.lr.ph.i63 ], [ 5, %131 ], [ 5, %.lr.ph.i90 ], [ 5, %172 ], [ 0, %169 ], [ 5, %.lr.ph.i21 ], [ 5, %43 ], [ 0, %40 ]
  ret i16 %common.ret.op

10:                                               ; preds = %4
  %11 = getelementptr inbounds %fmt.FormatOptions, ptr %2, i64 0, i32 1
  %.sroa.0.0.copyload = load i64, ptr %11, align 8
  call fastcc void @unicode.utf8CountCodepoints(ptr noalias %9, ptr nonnull readonly align 1 %0, i64 %1)
  %12 = getelementptr inbounds { i64, i16, [6 x i8] }, ptr %9, i64 0, i32 1
  %13 = load i16, ptr %12, align 8
  %14 = icmp eq i16 %13, 0
  %15 = load i64, ptr %9, align 8
  %16 = select i1 %14, i64 %15, i64 %1
  %17 = tail call i64 @llvm.usub.sat.i64(i64 %.sroa.0.0.copyload, i64 %16)
  %.not8 = icmp ugt i64 %.sroa.0.0.copyload, %16
  br i1 %.not8, label %54, label %36

18:                                               ; preds = %4
  %19 = load i64, ptr %3, align 8
  %.not15.i = icmp eq i64 %1, 0
  br i1 %.not15.i, label %common.ret, label %.lr.ph.i.preheader

.lr.ph.i.preheader:                               ; preds = %18
  %20 = inttoptr i64 %19 to ptr
  %21 = getelementptr inbounds %"io.fixed_buffer_stream.FixedBufferStream([]u8)", ptr %20, i64 0, i32 1
  %.pre136 = load i64, ptr %21, align 8, !noalias !46
  br label %.lr.ph.i

22:                                               ; preds = %25
  %23 = add nuw i64 %31, %.016.i
  %.not.i = icmp eq i64 %23, %1
  br i1 %.not.i, label %common.ret, label %.lr.ph.i

.lr.ph.i:                                         ; preds = %22, %.lr.ph.i.preheader
  %24 = phi i64 [ %34, %22 ], [ %.pre136, %.lr.ph.i.preheader ]
  %.016.i = phi i64 [ %23, %22 ], [ 0, %.lr.ph.i.preheader ]
  %sunkaddr = inttoptr i64 %19 to ptr
  %sunkaddr173 = getelementptr inbounds i8, ptr %sunkaddr, i64 8
  %.unpack10.i.i.i = load i64, ptr %sunkaddr173, align 8, !noalias !46
  %.not.i.i.i = icmp ugt i64 %.unpack10.i.i.i, %24
  br i1 %.not.i.i.i, label %25, label %common.ret

25:                                               ; preds = %.lr.ph.i
  %26 = inttoptr i64 %19 to ptr
  %27 = sub nuw i64 %1, %.016.i
  %28 = getelementptr inbounds i8, ptr %0, i64 %.016.i
  %29 = add nuw i64 %24, %27
  %.not11.i.i.i = icmp ugt i64 %29, %.unpack10.i.i.i
  %30 = sub nuw i64 %.unpack10.i.i.i, %24
  %31 = select i1 %.not11.i.i.i, i64 %30, i64 %27
  %.unpack.i.i.i = load ptr, ptr %26, align 8, !noalias !46
  %32 = getelementptr inbounds i8, ptr %.unpack.i.i.i, i64 %24
  tail call void @llvm.memcpy.p0.p0.i64(ptr align 1 %32, ptr nonnull align 1 %28, i64 %31, i1 false), !noalias !46
  %sunkaddr174 = inttoptr i64 %19 to ptr
  %sunkaddr175 = getelementptr inbounds i8, ptr %sunkaddr174, i64 16
  %33 = load i64, ptr %sunkaddr175, align 8, !noalias !46
  %34 = add nuw i64 %33, %31
  store i64 %34, ptr %sunkaddr175, align 8, !noalias !46
  %35 = icmp eq i64 %31, 0
  br i1 %35, label %common.ret, label %22

36:                                               ; preds = %10
  %37 = load i64, ptr %3, align 8
  %.not15.i13 = icmp eq i64 %1, 0
  br i1 %.not15.i13, label %common.ret, label %.lr.ph.i21.preheader

.lr.ph.i21.preheader:                             ; preds = %36
  %38 = inttoptr i64 %37 to ptr
  %39 = getelementptr inbounds %"io.fixed_buffer_stream.FixedBufferStream([]u8)", ptr %38, i64 0, i32 1
  %.pre = load i64, ptr %39, align 8, !noalias !51
  br label %.lr.ph.i21

40:                                               ; preds = %43
  %41 = add nuw i64 %49, %.016.i16
  %.not.i15 = icmp eq i64 %41, %1
  br i1 %.not.i15, label %common.ret, label %.lr.ph.i21

.lr.ph.i21:                                       ; preds = %40, %.lr.ph.i21.preheader
  %42 = phi i64 [ %52, %40 ], [ %.pre, %.lr.ph.i21.preheader ]
  %.016.i16 = phi i64 [ %41, %40 ], [ 0, %.lr.ph.i21.preheader ]
  %sunkaddr176 = inttoptr i64 %37 to ptr
  %sunkaddr177 = getelementptr inbounds i8, ptr %sunkaddr176, i64 8
  %.unpack10.i.i.i19 = load i64, ptr %sunkaddr177, align 8, !noalias !51
  %.not.i.i.i20 = icmp ugt i64 %.unpack10.i.i.i19, %42
  br i1 %.not.i.i.i20, label %43, label %common.ret

43:                                               ; preds = %.lr.ph.i21
  %44 = inttoptr i64 %37 to ptr
  %45 = sub nuw i64 %1, %.016.i16
  %46 = getelementptr inbounds i8, ptr %0, i64 %.016.i16
  %47 = add nuw i64 %42, %45
  %.not11.i.i.i22 = icmp ugt i64 %47, %.unpack10.i.i.i19
  %48 = sub nuw i64 %.unpack10.i.i.i19, %42
  %49 = select i1 %.not11.i.i.i22, i64 %48, i64 %45
  %.unpack.i.i.i23 = load ptr, ptr %44, align 8, !noalias !51
  %50 = getelementptr inbounds i8, ptr %.unpack.i.i.i23, i64 %42
  tail call void @llvm.memcpy.p0.p0.i64(ptr align 1 %50, ptr nonnull align 1 %46, i64 %49, i1 false), !noalias !51
  %sunkaddr178 = inttoptr i64 %37 to ptr
  %sunkaddr179 = getelementptr inbounds i8, ptr %sunkaddr178, i64 16
  %51 = load i64, ptr %sunkaddr179, align 8, !noalias !51
  %52 = add nuw i64 %51, %49
  store i64 %52, ptr %sunkaddr179, align 8, !noalias !51
  %53 = icmp eq i64 %49, 0
  br i1 %53, label %common.ret, label %40

54:                                               ; preds = %10
  %55 = getelementptr inbounds %fmt.FormatOptions, ptr %2, i64 0, i32 2
  %56 = load i2, ptr %55, align 8
  %57 = zext i2 %56 to i32
  switch i32 %57, label %58 [
    i32 0, label %59
    i32 1, label %99
    i32 2, label %.lr.ph.i72.preheader
  ]

58:                                               ; preds = %54
  unreachable

59:                                               ; preds = %54
  %60 = load i64, ptr %3, align 8
  %.not15.i25 = icmp eq i64 %1, 0
  br i1 %.not15.i25, label %.lr.ph.i38.preheader, label %.lr.ph.i33.preheader

.lr.ph.i33.preheader:                             ; preds = %59
  %61 = inttoptr i64 %60 to ptr
  %62 = getelementptr inbounds %"io.fixed_buffer_stream.FixedBufferStream([]u8)", ptr %61, i64 0, i32 1
  %.pre133 = load i64, ptr %62, align 8, !noalias !56
  br label %.lr.ph.i33

63:                                               ; preds = %66
  %64 = add nuw i64 %72, %.016.i28
  %.not.i27 = icmp eq i64 %64, %1
  br i1 %.not.i27, label %.loopexit.loopexit, label %.lr.ph.i33

.lr.ph.i33:                                       ; preds = %63, %.lr.ph.i33.preheader
  %65 = phi i64 [ %75, %63 ], [ %.pre133, %.lr.ph.i33.preheader ]
  %.016.i28 = phi i64 [ %64, %63 ], [ 0, %.lr.ph.i33.preheader ]
  %sunkaddr180 = inttoptr i64 %60 to ptr
  %sunkaddr181 = getelementptr inbounds i8, ptr %sunkaddr180, i64 8
  %.unpack10.i.i.i31 = load i64, ptr %sunkaddr181, align 8, !noalias !56
  %.not.i.i.i32 = icmp ugt i64 %.unpack10.i.i.i31, %65
  br i1 %.not.i.i.i32, label %66, label %common.ret

66:                                               ; preds = %.lr.ph.i33
  %67 = inttoptr i64 %60 to ptr
  %68 = sub nuw i64 %1, %.016.i28
  %69 = getelementptr inbounds i8, ptr %0, i64 %.016.i28
  %70 = add nuw i64 %65, %68
  %.not11.i.i.i34 = icmp ugt i64 %70, %.unpack10.i.i.i31
  %71 = sub nuw i64 %.unpack10.i.i.i31, %65
  %72 = select i1 %.not11.i.i.i34, i64 %71, i64 %68
  %.unpack.i.i.i35 = load ptr, ptr %67, align 8, !noalias !56
  %73 = getelementptr inbounds i8, ptr %.unpack.i.i.i35, i64 %65
  tail call void @llvm.memcpy.p0.p0.i64(ptr align 1 %73, ptr nonnull align 1 %69, i64 %72, i1 false), !noalias !56
  %sunkaddr182 = inttoptr i64 %60 to ptr
  %sunkaddr183 = getelementptr inbounds i8, ptr %sunkaddr182, i64 16
  %74 = load i64, ptr %sunkaddr183, align 8, !noalias !56
  %75 = add nuw i64 %74, %72
  store i64 %75, ptr %sunkaddr183, align 8, !noalias !56
  %76 = icmp eq i64 %72, 0
  br i1 %76, label %common.ret, label %63

.loopexit.loopexit:                               ; preds = %63
  %.pre134 = load i64, ptr %3, align 8
  br label %.lr.ph.i38.preheader

.lr.ph.i38.preheader:                             ; preds = %.loopexit.loopexit, %59
  %77 = phi i64 [ %.pre134, %.loopexit.loopexit ], [ %60, %59 ]
  %78 = getelementptr inbounds %fmt.FormatOptions, ptr %2, i64 0, i32 3
  %79 = load i8, ptr %78, align 1
  call void @llvm.lifetime.start.p0(i64 256, ptr nonnull %5)
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(256) %5, i8 %79, i64 256, i1 false)
  %80 = inttoptr i64 %77 to ptr
  %81 = getelementptr inbounds %"io.fixed_buffer_stream.FixedBufferStream([]u8)", ptr %80, i64 0, i32 1
  %.pre.i.pre = load i64, ptr %81, align 8, !noalias !61
  br label %.lr.ph.i38

.lr.ph.i38:                                       ; preds = %97, %.lr.ph.i38.preheader
  %.pre.i = phi i64 [ %95, %97 ], [ %.pre.i.pre, %.lr.ph.i38.preheader ]
  %.011.i = phi i64 [ %98, %97 ], [ %17, %.lr.ph.i38.preheader ]
  %82 = tail call i64 @llvm.umin.i64(i64 %.011.i, i64 256)
  br label %.lr.ph.i.i

83:                                               ; preds = %86
  %84 = add nuw i64 %92, %.016.i.i
  %.not.i.i = icmp eq i64 %84, %82
  br i1 %.not.i.i, label %97, label %.lr.ph.i.i

.lr.ph.i.i:                                       ; preds = %83, %.lr.ph.i38
  %85 = phi i64 [ %95, %83 ], [ %.pre.i, %.lr.ph.i38 ]
  %.016.i.i = phi i64 [ %84, %83 ], [ 0, %.lr.ph.i38 ]
  %sunkaddr184 = inttoptr i64 %77 to ptr
  %sunkaddr185 = getelementptr inbounds i8, ptr %sunkaddr184, i64 8
  %.unpack10.i.i.i.i = load i64, ptr %sunkaddr185, align 8, !noalias !61
  %.not.i.i.i.i = icmp ugt i64 %.unpack10.i.i.i.i, %85
  br i1 %.not.i.i.i.i, label %86, label %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit"

86:                                               ; preds = %.lr.ph.i.i
  %87 = inttoptr i64 %77 to ptr
  %88 = sub nuw i64 %82, %.016.i.i
  %89 = getelementptr inbounds i8, ptr %5, i64 %.016.i.i
  %90 = add nuw i64 %88, %85
  %.not11.i.i.i.i = icmp ugt i64 %90, %.unpack10.i.i.i.i
  %91 = sub nuw i64 %.unpack10.i.i.i.i, %85
  %92 = select i1 %.not11.i.i.i.i, i64 %91, i64 %88
  %.unpack.i.i.i.i = load ptr, ptr %87, align 8, !noalias !61
  %93 = getelementptr inbounds i8, ptr %.unpack.i.i.i.i, i64 %85
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %93, ptr nonnull align 1 %89, i64 %92, i1 false), !noalias !61
  %sunkaddr186 = inttoptr i64 %77 to ptr
  %sunkaddr187 = getelementptr inbounds i8, ptr %sunkaddr186, i64 16
  %94 = load i64, ptr %sunkaddr187, align 8, !noalias !61
  %95 = add nuw i64 %94, %92
  store i64 %95, ptr %sunkaddr187, align 8, !noalias !61
  %96 = icmp eq i64 %92, 0
  br i1 %96, label %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit", label %83

97:                                               ; preds = %83
  %98 = sub nuw i64 %.011.i, %82
  %.not.i39 = icmp eq i64 %98, 0
  br i1 %.not.i39, label %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit", label %.lr.ph.i38

"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit": ; preds = %97, %86, %.lr.ph.i.i
  %common.ret.op.i37 = phi i16 [ 5, %86 ], [ 5, %.lr.ph.i.i ], [ 0, %97 ]
  call void @llvm.lifetime.end.p0(i64 256, ptr nonnull %5)
  br label %common.ret

99:                                               ; preds = %54
  %100 = add nuw i64 %17, 1
  %101 = lshr i64 %100, 1
  %102 = load i64, ptr %3, align 8
  %103 = getelementptr inbounds %fmt.FormatOptions, ptr %2, i64 0, i32 3
  %104 = load i8, ptr %103, align 1
  call void @llvm.lifetime.start.p0(i64 256, ptr nonnull %5)
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(256) %5, i8 %104, i64 256, i1 false)
  %.not10.i40 = icmp ult i64 %17, 2
  br i1 %.not10.i40, label %.loopexit113, label %.lr.ph.i45.preheader

.lr.ph.i45.preheader:                             ; preds = %99
  %105 = lshr i64 %17, 1
  %106 = inttoptr i64 %102 to ptr
  %107 = getelementptr inbounds %"io.fixed_buffer_stream.FixedBufferStream([]u8)", ptr %106, i64 0, i32 1
  %.pre.i44.pre = load i64, ptr %107, align 8, !noalias !66
  br label %.lr.ph.i45

.lr.ph.i45:                                       ; preds = %123, %.lr.ph.i45.preheader
  %.pre.i44 = phi i64 [ %121, %123 ], [ %.pre.i44.pre, %.lr.ph.i45.preheader ]
  %.011.i42 = phi i64 [ %124, %123 ], [ %105, %.lr.ph.i45.preheader ]
  %108 = tail call i64 @llvm.umin.i64(i64 %.011.i42, i64 256)
  br label %.lr.ph.i.i50

109:                                              ; preds = %112
  %110 = add nuw i64 %118, %.016.i.i47
  %.not.i.i46 = icmp eq i64 %110, %108
  br i1 %.not.i.i46, label %123, label %.lr.ph.i.i50

.lr.ph.i.i50:                                     ; preds = %109, %.lr.ph.i45
  %111 = phi i64 [ %121, %109 ], [ %.pre.i44, %.lr.ph.i45 ]
  %.016.i.i47 = phi i64 [ %110, %109 ], [ 0, %.lr.ph.i45 ]
  %sunkaddr188 = inttoptr i64 %102 to ptr
  %sunkaddr189 = getelementptr inbounds i8, ptr %sunkaddr188, i64 8
  %.unpack10.i.i.i.i48 = load i64, ptr %sunkaddr189, align 8, !noalias !66
  %.not.i.i.i.i49 = icmp ugt i64 %.unpack10.i.i.i.i48, %111
  br i1 %.not.i.i.i.i49, label %112, label %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit54"

112:                                              ; preds = %.lr.ph.i.i50
  %113 = inttoptr i64 %102 to ptr
  %114 = sub nuw i64 %108, %.016.i.i47
  %115 = getelementptr inbounds i8, ptr %5, i64 %.016.i.i47
  %116 = add nuw i64 %114, %111
  %.not11.i.i.i.i51 = icmp ugt i64 %116, %.unpack10.i.i.i.i48
  %117 = sub nuw i64 %.unpack10.i.i.i.i48, %111
  %118 = select i1 %.not11.i.i.i.i51, i64 %117, i64 %114
  %.unpack.i.i.i.i52 = load ptr, ptr %113, align 8, !noalias !66
  %119 = getelementptr inbounds i8, ptr %.unpack.i.i.i.i52, i64 %111
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %119, ptr nonnull align 1 %115, i64 %118, i1 false), !noalias !66
  %sunkaddr190 = inttoptr i64 %102 to ptr
  %sunkaddr191 = getelementptr inbounds i8, ptr %sunkaddr190, i64 16
  %120 = load i64, ptr %sunkaddr191, align 8, !noalias !66
  %121 = add nuw i64 %120, %118
  store i64 %121, ptr %sunkaddr191, align 8, !noalias !66
  %122 = icmp eq i64 %118, 0
  br i1 %122, label %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit54", label %109

123:                                              ; preds = %109
  %124 = sub nuw i64 %.011.i42, %108
  %.not.i53 = icmp eq i64 %124, 0
  br i1 %.not.i53, label %.loopexit113.loopexit, label %.lr.ph.i45

"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit54": ; preds = %112, %.lr.ph.i.i50
  call void @llvm.lifetime.end.p0(i64 256, ptr nonnull %5)
  br label %common.ret

.loopexit113.loopexit:                            ; preds = %123
  %.pre130 = load i64, ptr %3, align 8
  br label %.loopexit113

.loopexit113:                                     ; preds = %.loopexit113.loopexit, %99
  %125 = phi i64 [ %.pre130, %.loopexit113.loopexit ], [ %102, %99 ]
  call void @llvm.lifetime.end.p0(i64 256, ptr nonnull %5)
  %.not15.i55 = icmp eq i64 %1, 0
  br i1 %.not15.i55, label %.loopexit112, label %.lr.ph.i63.preheader

.lr.ph.i63.preheader:                             ; preds = %.loopexit113
  %126 = inttoptr i64 %125 to ptr
  %127 = getelementptr inbounds %"io.fixed_buffer_stream.FixedBufferStream([]u8)", ptr %126, i64 0, i32 1
  %.pre131 = load i64, ptr %127, align 8, !noalias !71
  br label %.lr.ph.i63

128:                                              ; preds = %131
  %129 = add nuw i64 %137, %.016.i58
  %.not.i57 = icmp eq i64 %129, %1
  br i1 %.not.i57, label %.loopexit112.loopexit, label %.lr.ph.i63

.lr.ph.i63:                                       ; preds = %128, %.lr.ph.i63.preheader
  %130 = phi i64 [ %140, %128 ], [ %.pre131, %.lr.ph.i63.preheader ]
  %.016.i58 = phi i64 [ %129, %128 ], [ 0, %.lr.ph.i63.preheader ]
  %sunkaddr192 = inttoptr i64 %125 to ptr
  %sunkaddr193 = getelementptr inbounds i8, ptr %sunkaddr192, i64 8
  %.unpack10.i.i.i61 = load i64, ptr %sunkaddr193, align 8, !noalias !71
  %.not.i.i.i62 = icmp ugt i64 %.unpack10.i.i.i61, %130
  br i1 %.not.i.i.i62, label %131, label %common.ret

131:                                              ; preds = %.lr.ph.i63
  %132 = inttoptr i64 %125 to ptr
  %133 = sub nuw i64 %1, %.016.i58
  %134 = getelementptr inbounds i8, ptr %0, i64 %.016.i58
  %135 = add nuw i64 %130, %133
  %.not11.i.i.i64 = icmp ugt i64 %135, %.unpack10.i.i.i61
  %136 = sub nuw i64 %.unpack10.i.i.i61, %130
  %137 = select i1 %.not11.i.i.i64, i64 %136, i64 %133
  %.unpack.i.i.i65 = load ptr, ptr %132, align 8, !noalias !71
  %138 = getelementptr inbounds i8, ptr %.unpack.i.i.i65, i64 %130
  tail call void @llvm.memcpy.p0.p0.i64(ptr align 1 %138, ptr nonnull align 1 %134, i64 %137, i1 false), !noalias !71
  %sunkaddr194 = inttoptr i64 %125 to ptr
  %sunkaddr195 = getelementptr inbounds i8, ptr %sunkaddr194, i64 16
  %139 = load i64, ptr %sunkaddr195, align 8, !noalias !71
  %140 = add nuw i64 %139, %137
  store i64 %140, ptr %sunkaddr195, align 8, !noalias !71
  %141 = icmp eq i64 %137, 0
  br i1 %141, label %common.ret, label %128

.loopexit112.loopexit:                            ; preds = %128
  %.pre132 = load i64, ptr %3, align 8
  br label %.loopexit112

.loopexit112:                                     ; preds = %.loopexit112.loopexit, %.loopexit113
  %142 = phi i64 [ %.pre132, %.loopexit112.loopexit ], [ %125, %.loopexit113 ]
  store i64 %142, ptr %8, align 8
  %sunkaddr196 = getelementptr inbounds i8, ptr %2, i64 33
  %143 = load i8, ptr %sunkaddr196, align 1
  %144 = call fastcc i16 @"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes"(ptr nonnull readonly align 8 %8, i8 %143, i64 %101)
  br label %common.ret

.lr.ph.i72.preheader:                             ; preds = %54
  %145 = load i64, ptr %3, align 8
  %146 = getelementptr inbounds %fmt.FormatOptions, ptr %2, i64 0, i32 3
  %147 = load i8, ptr %146, align 1
  call void @llvm.lifetime.start.p0(i64 256, ptr nonnull %5)
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(256) %5, i8 %147, i64 256, i1 false)
  %148 = inttoptr i64 %145 to ptr
  %149 = getelementptr inbounds %"io.fixed_buffer_stream.FixedBufferStream([]u8)", ptr %148, i64 0, i32 1
  %.pre.i71.pre = load i64, ptr %149, align 8, !noalias !76
  br label %.lr.ph.i72

.lr.ph.i72:                                       ; preds = %165, %.lr.ph.i72.preheader
  %.pre.i71 = phi i64 [ %163, %165 ], [ %.pre.i71.pre, %.lr.ph.i72.preheader ]
  %.011.i69 = phi i64 [ %166, %165 ], [ %17, %.lr.ph.i72.preheader ]
  %150 = tail call i64 @llvm.umin.i64(i64 %.011.i69, i64 256)
  br label %.lr.ph.i.i77

151:                                              ; preds = %154
  %152 = add nuw i64 %160, %.016.i.i74
  %.not.i.i73 = icmp eq i64 %152, %150
  br i1 %.not.i.i73, label %165, label %.lr.ph.i.i77

.lr.ph.i.i77:                                     ; preds = %151, %.lr.ph.i72
  %153 = phi i64 [ %163, %151 ], [ %.pre.i71, %.lr.ph.i72 ]
  %.016.i.i74 = phi i64 [ %152, %151 ], [ 0, %.lr.ph.i72 ]
  %sunkaddr197 = inttoptr i64 %145 to ptr
  %sunkaddr198 = getelementptr inbounds i8, ptr %sunkaddr197, i64 8
  %.unpack10.i.i.i.i75 = load i64, ptr %sunkaddr198, align 8, !noalias !76
  %.not.i.i.i.i76 = icmp ugt i64 %.unpack10.i.i.i.i75, %153
  br i1 %.not.i.i.i.i76, label %154, label %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit81"

154:                                              ; preds = %.lr.ph.i.i77
  %155 = inttoptr i64 %145 to ptr
  %156 = sub nuw i64 %150, %.016.i.i74
  %157 = getelementptr inbounds i8, ptr %5, i64 %.016.i.i74
  %158 = add nuw i64 %156, %153
  %.not11.i.i.i.i78 = icmp ugt i64 %158, %.unpack10.i.i.i.i75
  %159 = sub nuw i64 %.unpack10.i.i.i.i75, %153
  %160 = select i1 %.not11.i.i.i.i78, i64 %159, i64 %156
  %.unpack.i.i.i.i79 = load ptr, ptr %155, align 8, !noalias !76
  %161 = getelementptr inbounds i8, ptr %.unpack.i.i.i.i79, i64 %153
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %161, ptr nonnull align 1 %157, i64 %160, i1 false), !noalias !76
  %sunkaddr199 = inttoptr i64 %145 to ptr
  %sunkaddr200 = getelementptr inbounds i8, ptr %sunkaddr199, i64 16
  %162 = load i64, ptr %sunkaddr200, align 8, !noalias !76
  %163 = add nuw i64 %162, %160
  store i64 %163, ptr %sunkaddr200, align 8, !noalias !76
  %164 = icmp eq i64 %160, 0
  br i1 %164, label %"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit81", label %151

165:                                              ; preds = %151
  %166 = sub nuw i64 %.011.i69, %150
  %.not.i80 = icmp eq i64 %166, 0
  br i1 %.not.i80, label %.loopexit116, label %.lr.ph.i72

"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes.exit81": ; preds = %154, %.lr.ph.i.i77
  call void @llvm.lifetime.end.p0(i64 256, ptr nonnull %5)
  br label %common.ret

.loopexit116:                                     ; preds = %165
  %.pre127 = load i64, ptr %3, align 8
  call void @llvm.lifetime.end.p0(i64 256, ptr nonnull %5)
  %.not15.i82 = icmp eq i64 %1, 0
  br i1 %.not15.i82, label %common.ret, label %.lr.ph.i90.preheader

.lr.ph.i90.preheader:                             ; preds = %.loopexit116
  %167 = inttoptr i64 %.pre127 to ptr
  %168 = getelementptr inbounds %"io.fixed_buffer_stream.FixedBufferStream([]u8)", ptr %167, i64 0, i32 1
  %.pre128 = load i64, ptr %168, align 8, !noalias !81
  br label %.lr.ph.i90

169:                                              ; preds = %172
  %170 = add nuw i64 %178, %.016.i85
  %.not.i84 = icmp eq i64 %170, %1
  br i1 %.not.i84, label %common.ret, label %.lr.ph.i90

.lr.ph.i90:                                       ; preds = %169, %.lr.ph.i90.preheader
  %171 = phi i64 [ %181, %169 ], [ %.pre128, %.lr.ph.i90.preheader ]
  %.016.i85 = phi i64 [ %170, %169 ], [ 0, %.lr.ph.i90.preheader ]
  %sunkaddr201 = inttoptr i64 %.pre127 to ptr
  %sunkaddr202 = getelementptr inbounds i8, ptr %sunkaddr201, i64 8
  %.unpack10.i.i.i88 = load i64, ptr %sunkaddr202, align 8, !noalias !81
  %.not.i.i.i89 = icmp ugt i64 %.unpack10.i.i.i88, %171
  br i1 %.not.i.i.i89, label %172, label %common.ret

172:                                              ; preds = %.lr.ph.i90
  %173 = inttoptr i64 %.pre127 to ptr
  %174 = sub nuw i64 %1, %.016.i85
  %175 = getelementptr inbounds i8, ptr %0, i64 %.016.i85
  %176 = add nuw i64 %171, %174
  %.not11.i.i.i91 = icmp ugt i64 %176, %.unpack10.i.i.i88
  %177 = sub nuw i64 %.unpack10.i.i.i88, %171
  %178 = select i1 %.not11.i.i.i91, i64 %177, i64 %174
  %.unpack.i.i.i92 = load ptr, ptr %173, align 8, !noalias !81
  %179 = getelementptr inbounds i8, ptr %.unpack.i.i.i92, i64 %171
  tail call void @llvm.memcpy.p0.p0.i64(ptr align 1 %179, ptr nonnull align 1 %175, i64 %178, i1 false), !noalias !81
  %sunkaddr203 = inttoptr i64 %.pre127 to ptr
  %sunkaddr204 = getelementptr inbounds i8, ptr %sunkaddr203, i64 16
  %180 = load i64, ptr %sunkaddr204, align 8, !noalias !81
  %181 = add nuw i64 %180, %178
  store i64 %181, ptr %sunkaddr204, align 8, !noalias !81
  %182 = icmp eq i64 %178, 0
  br i1 %182, label %common.ret, label %169
}

; Function Attrs: nofree nosync nounwind memory(readwrite, inaccessiblemem: none) uwtable
define private fastcc i16 @"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).writeByteNTimes"(ptr nocapture nonnull readonly align 8 %0, i8 %1, i64 %2) unnamed_addr #11 {
  %4 = alloca [256 x i8], align 1
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(256) %4, i8 %1, i64 256, i1 false)
  %.not10 = icmp eq i64 %2, 0
  br i1 %.not10, label %common.ret, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %3
  br label %.lr.ph

common.ret:                                       ; preds = %23, %12, %.lr.ph.i, %3
  %common.ret.op = phi i16 [ 0, %3 ], [ 5, %.lr.ph.i ], [ 5, %12 ], [ 0, %23 ]
  ret i16 %common.ret.op

.lr.ph:                                           ; preds = %23, %.lr.ph.preheader
  %.011 = phi i64 [ %24, %23 ], [ %2, %.lr.ph.preheader ]
  %5 = tail call i64 @llvm.umin.i64(i64 %.011, i64 256)
  %6 = load i64, ptr %0, align 8
  %7 = inttoptr i64 %6 to ptr
  %8 = getelementptr inbounds %"io.fixed_buffer_stream.FixedBufferStream([]u8)", ptr %7, i64 0, i32 1
  %.pre = load i64, ptr %8, align 8, !noalias !86
  br label %.lr.ph.i

9:                                                ; preds = %12
  %10 = add nuw i64 %18, %.016.i
  %.not.i = icmp eq i64 %10, %5
  br i1 %.not.i, label %23, label %.lr.ph.i

.lr.ph.i:                                         ; preds = %9, %.lr.ph
  %11 = phi i64 [ %21, %9 ], [ %.pre, %.lr.ph ]
  %.016.i = phi i64 [ %10, %9 ], [ 0, %.lr.ph ]
  %sunkaddr = inttoptr i64 %6 to ptr
  %sunkaddr17 = getelementptr inbounds i8, ptr %sunkaddr, i64 8
  %.unpack10.i.i.i = load i64, ptr %sunkaddr17, align 8, !noalias !86
  %.not.i.i.i = icmp ugt i64 %.unpack10.i.i.i, %11
  br i1 %.not.i.i.i, label %12, label %common.ret

12:                                               ; preds = %.lr.ph.i
  %13 = inttoptr i64 %6 to ptr
  %14 = sub nuw i64 %5, %.016.i
  %15 = getelementptr inbounds i8, ptr %4, i64 %.016.i
  %16 = add nuw i64 %11, %14
  %.not11.i.i.i = icmp ugt i64 %16, %.unpack10.i.i.i
  %17 = sub nuw i64 %.unpack10.i.i.i, %11
  %18 = select i1 %.not11.i.i.i, i64 %17, i64 %14
  %.unpack.i.i.i = load ptr, ptr %13, align 8, !noalias !86
  %19 = getelementptr inbounds i8, ptr %.unpack.i.i.i, i64 %11
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %19, ptr nonnull align 1 %15, i64 %18, i1 false), !noalias !86
  %sunkaddr18 = inttoptr i64 %6 to ptr
  %sunkaddr19 = getelementptr inbounds i8, ptr %sunkaddr18, i64 16
  %20 = load i64, ptr %sunkaddr19, align 8, !noalias !86
  %21 = add nuw i64 %20, %18
  store i64 %21, ptr %sunkaddr19, align 8, !noalias !86
  %22 = icmp eq i64 %18, 0
  br i1 %22, label %common.ret, label %9

23:                                               ; preds = %9
  %24 = sub nuw i64 %.011, %5
  %.not = icmp eq i64 %24, 0
  br i1 %.not, label %common.ret, label %.lr.ph
}

; Function Attrs: nounwind uwtable
define private fastcc void @str.RocStr.reallocateFresh(ptr noalias nocapture nonnull writeonly %0, ptr nocapture nonnull readonly align 8 %1, i64 %2) unnamed_addr #4 {
str.RocStr.len.exit:
  %3 = alloca %str.RocStr, align 8
  %4 = alloca %str.RocStr, align 8
  %5 = alloca %str.RocStr, align 8
  %6 = alloca %str.RocStr, align 8
  %.sroa.1.0..sroa_idx = getelementptr inbounds i8, ptr %1, i64 8
  %.sroa.1.0.copyload = load i64, ptr %.sroa.1.0..sroa_idx, align 8
  %.sroa.2.0..sroa_idx = getelementptr inbounds i8, ptr %1, i64 16
  %.sroa.2.0.copyload = load i64, ptr %.sroa.2.0..sroa_idx, align 8
  %7 = icmp slt i64 %.sroa.2.0.copyload, 0
  %8 = lshr i64 %.sroa.2.0.copyload, 56
  %9 = xor i64 %8, 128
  %10 = and i64 %.sroa.1.0.copyload, 9223372036854775807
  %common.ret.op.i = select i1 %7, i64 %9, i64 %10
  %11 = icmp ugt i64 %2, 23
  br i1 %11, label %str.RocStr.asU8ptr.exit, label %str.RocStr.asU8ptr.exit14

common.ret.sink.split:                            ; preds = %61, %39
  %.sink38 = phi ptr [ %37, %39 ], [ %59, %61 ]
  %.sink.ph = phi ptr [ %6, %39 ], [ %4, %61 ]
  tail call void @roc_dealloc(ptr nonnull align 1 %.sink38, i32 8)
  br label %common.ret

common.ret:                                       ; preds = %61, %57, %51, %mem.copyForwards__anon_9882.exit19, %39, %35, %29, %mem.copyForwards__anon_9882.exit, %common.ret.sink.split
  %.sink = phi ptr [ %6, %mem.copyForwards__anon_9882.exit ], [ %6, %29 ], [ %6, %35 ], [ %6, %39 ], [ %4, %mem.copyForwards__anon_9882.exit19 ], [ %4, %51 ], [ %4, %57 ], [ %4, %61 ], [ %.sink.ph, %common.ret.sink.split ]
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %.sink, i64 24, i1 false)
  ret void

str.RocStr.asU8ptr.exit:                          ; preds = %str.RocStr.len.exit
  %12 = tail call i64 @llvm.umax.i64(i64 %2, i64 64)
  %13 = add nuw i64 %12, 8
  %14 = tail call ptr @roc_alloc(i64 %13, i32 8), !noalias !91
  %15 = getelementptr inbounds i8, ptr %14, i64 8
  store i64 -9223372036854775808, ptr %14, align 8, !noalias !91
  store ptr %15, ptr %6, align 8
  %.sroa.230.0..sroa_idx = getelementptr inbounds i8, ptr %6, i64 8
  store i64 %2, ptr %.sroa.230.0..sroa_idx, align 8
  %.sroa.3.0..sroa_idx = getelementptr inbounds i8, ptr %6, i64 16
  store i64 %12, ptr %.sroa.3.0..sroa_idx, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %5, ptr noundef nonnull align 8 dereferenceable(24) %1, i64 24, i1 false)
  %16 = getelementptr inbounds i8, ptr %5, i64 16
  %.val.i = load i64, ptr %16, align 8
  %17 = icmp slt i64 %.val.i, 0
  %18 = load ptr, ptr %5, align 8
  %spec.select = select i1 %17, ptr %5, ptr %18
  %19 = icmp slt i64 %12, 0
  %common.ret.op.i9 = select i1 %19, ptr %6, ptr %15
  %.not.i = icmp eq i64 %common.ret.op.i, 0
  br i1 %.not.i, label %mem.copyForwards__anon_9882.exit, label %iter.check

iter.check:                                       ; preds = %str.RocStr.asU8ptr.exit
  %common.ret.op.i939 = ptrtoint ptr %common.ret.op.i9 to i64
  %spec.select40 = ptrtoint ptr %spec.select to i64
  %min.iters.check = icmp ult i64 %common.ret.op.i, 8
  %20 = sub i64 %common.ret.op.i939, %spec.select40
  %diff.check = icmp ult i64 %20, 32
  %or.cond = select i1 %min.iters.check, i1 true, i1 %diff.check
  br i1 %or.cond, label %.lr.ph.i.preheader, label %vector.main.loop.iter.check

vector.main.loop.iter.check:                      ; preds = %iter.check
  %min.iters.check41 = icmp ult i64 %common.ret.op.i, 32
  br i1 %min.iters.check41, label %vec.epilog.ph, label %vector.ph

vector.ph:                                        ; preds = %vector.main.loop.iter.check
  %n.vec = and i64 %common.ret.op.i, 9223372036854775776
  %uglygep62 = getelementptr i8, ptr %common.ret.op.i9, i64 16
  %uglygep66 = getelementptr i8, ptr %spec.select, i64 16
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv70 = phi i64 [ %lsr.iv.next71, %vector.body ], [ %n.vec, %vector.ph ]
  %lsr.iv67 = phi ptr [ %uglygep68, %vector.body ], [ %uglygep66, %vector.ph ]
  %lsr.iv63 = phi ptr [ %uglygep64, %vector.body ], [ %uglygep62, %vector.ph ]
  %uglygep65 = getelementptr i8, ptr %lsr.iv63, i64 -16
  %uglygep69 = getelementptr i8, ptr %lsr.iv67, i64 -16
  %wide.load = load <16 x i8>, ptr %uglygep69, align 1
  %wide.load42 = load <16 x i8>, ptr %lsr.iv67, align 1
  store <16 x i8> %wide.load, ptr %uglygep65, align 1
  store <16 x i8> %wide.load42, ptr %lsr.iv63, align 1
  %uglygep64 = getelementptr i8, ptr %lsr.iv63, i64 32
  %uglygep68 = getelementptr i8, ptr %lsr.iv67, i64 32
  %lsr.iv.next71 = add nsw i64 %lsr.iv70, -32
  %21 = icmp eq i64 %lsr.iv.next71, 0
  br i1 %21, label %middle.block, label %vector.body, !llvm.loop !94

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %common.ret.op.i, %n.vec
  br i1 %cmp.n, label %mem.copyForwards__anon_9882.exit, label %vec.epilog.iter.check

vec.epilog.iter.check:                            ; preds = %middle.block
  %n.vec.remaining = and i64 %common.ret.op.i, 24
  %min.epilog.iters.check = icmp eq i64 %n.vec.remaining, 0
  br i1 %min.epilog.iters.check, label %.lr.ph.i.preheader, label %vec.epilog.ph

vec.epilog.ph:                                    ; preds = %vec.epilog.iter.check, %vector.main.loop.iter.check
  %vec.epilog.resume.val = phi i64 [ %n.vec, %vec.epilog.iter.check ], [ 0, %vector.main.loop.iter.check ]
  %n.vec44 = and i64 %common.ret.op.i, 9223372036854775800
  %uglygep54 = getelementptr i8, ptr %common.ret.op.i9, i64 %vec.epilog.resume.val
  %uglygep57 = getelementptr i8, ptr %spec.select, i64 %vec.epilog.resume.val
  %22 = sub i64 %vec.epilog.resume.val, %n.vec44
  br label %vec.epilog.vector.body

vec.epilog.vector.body:                           ; preds = %vec.epilog.vector.body, %vec.epilog.ph
  %lsr.iv60 = phi i64 [ %lsr.iv.next61, %vec.epilog.vector.body ], [ %22, %vec.epilog.ph ]
  %lsr.iv58 = phi ptr [ %uglygep59, %vec.epilog.vector.body ], [ %uglygep57, %vec.epilog.ph ]
  %lsr.iv55 = phi ptr [ %uglygep56, %vec.epilog.vector.body ], [ %uglygep54, %vec.epilog.ph ]
  %wide.load47 = load <8 x i8>, ptr %lsr.iv58, align 1
  store <8 x i8> %wide.load47, ptr %lsr.iv55, align 1
  %uglygep56 = getelementptr i8, ptr %lsr.iv55, i64 8
  %uglygep59 = getelementptr i8, ptr %lsr.iv58, i64 8
  %lsr.iv.next61 = add i64 %lsr.iv60, 8
  %23 = icmp eq i64 %lsr.iv.next61, 0
  br i1 %23, label %vec.epilog.middle.block, label %vec.epilog.vector.body, !llvm.loop !95

vec.epilog.middle.block:                          ; preds = %vec.epilog.vector.body
  %cmp.n45 = icmp eq i64 %common.ret.op.i, %n.vec44
  br i1 %cmp.n45, label %mem.copyForwards__anon_9882.exit, label %.lr.ph.i.preheader

.lr.ph.i.preheader:                               ; preds = %vec.epilog.middle.block, %vec.epilog.iter.check, %iter.check
  %.03.i.ph = phi i64 [ %n.vec44, %vec.epilog.middle.block ], [ %n.vec, %vec.epilog.iter.check ], [ 0, %iter.check ]
  %24 = sub i64 %common.ret.op.i, %.03.i.ph
  %uglygep = getelementptr i8, ptr %spec.select, i64 %.03.i.ph
  %uglygep51 = getelementptr i8, ptr %common.ret.op.i9, i64 %.03.i.ph
  br label %.lr.ph.i

.lr.ph.i:                                         ; preds = %.lr.ph.i, %.lr.ph.i.preheader
  %lsr.iv52 = phi ptr [ %uglygep51, %.lr.ph.i.preheader ], [ %uglygep53, %.lr.ph.i ]
  %lsr.iv49 = phi ptr [ %uglygep, %.lr.ph.i.preheader ], [ %uglygep50, %.lr.ph.i ]
  %lsr.iv = phi i64 [ %24, %.lr.ph.i.preheader ], [ %lsr.iv.next, %.lr.ph.i ]
  %25 = load i8, ptr %lsr.iv49, align 1
  store i8 %25, ptr %lsr.iv52, align 1
  %lsr.iv.next = add i64 %lsr.iv, -1
  %uglygep50 = getelementptr i8, ptr %lsr.iv49, i64 1
  %uglygep53 = getelementptr i8, ptr %lsr.iv52, i64 1
  %exitcond.not.i = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not.i, label %mem.copyForwards__anon_9882.exit, label %.lr.ph.i, !llvm.loop !96

mem.copyForwards__anon_9882.exit:                 ; preds = %.lr.ph.i, %vec.epilog.middle.block, %middle.block, %str.RocStr.asU8ptr.exit
  %26 = getelementptr inbounds i8, ptr %common.ret.op.i9, i64 %common.ret.op.i
  %27 = sub nuw i64 %2, %common.ret.op.i
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %26, i8 0, i64 %27, i1 false)
  %sunkaddr = getelementptr inbounds i8, ptr %1, i64 16
  %.sroa.333.0.copyload = load i64, ptr %sunkaddr, align 8
  %28 = icmp slt i64 %.sroa.333.0.copyload, 0
  br i1 %28, label %common.ret, label %29

29:                                               ; preds = %mem.copyForwards__anon_9882.exit
  %sunkaddr72 = getelementptr inbounds i8, ptr %1, i64 8
  %.sroa.232.0.copyload = load i64, ptr %sunkaddr72, align 8
  %.sroa.031.0.copyload = load ptr, ptr %1, align 8
  %30 = ptrtoint ptr %.sroa.031.0.copyload to i64
  %31 = shl nuw i64 %.sroa.333.0.copyload, 1
  %isneg.i.i = icmp slt i64 %.sroa.232.0.copyload, 0
  %32 = select i1 %isneg.i.i, i64 %31, i64 %30
  %33 = icmp ne i64 %.sroa.333.0.copyload, 0
  %34 = icmp ne i64 %32, 0
  %or.cond.i.i = select i1 %33, i1 %34, i1 false
  br i1 %or.cond.i.i, label %35, label %common.ret

35:                                               ; preds = %29
  %36 = inttoptr i64 %32 to ptr
  %37 = getelementptr inbounds i64, ptr %36, i64 -1
  %38 = load i64, ptr %37, align 8
  %.not.i.i = icmp eq i64 %38, 0
  br i1 %.not.i.i, label %common.ret, label %39

39:                                               ; preds = %35
  %40 = add i64 %38, -1
  store i64 %40, ptr %37, align 8
  %41 = icmp eq i64 %38, -9223372036854775808
  br i1 %41, label %common.ret.sink.split, label %common.ret

str.RocStr.asU8ptr.exit14:                        ; preds = %str.RocStr.len.exit
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %4, ptr noundef nonnull align 8 dereferenceable(24) @5, i64 24, i1 false)
  %42 = getelementptr inbounds i8, ptr %4, i64 23
  %43 = trunc i64 %2 to i8
  %44 = or i8 %43, -128
  store i8 %44, ptr %42, align 1
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %3, ptr noundef nonnull align 8 dereferenceable(24) %1, i64 24, i1 false)
  %.not.i15 = icmp eq i64 %common.ret.op.i, 0
  br i1 %.not.i15, label %mem.copyForwards__anon_9882.exit19, label %.lr.ph.i18.preheader

.lr.ph.i18.preheader:                             ; preds = %str.RocStr.asU8ptr.exit14
  %45 = getelementptr inbounds i8, ptr %3, i64 16
  %.val.i12 = load i64, ptr %45, align 8
  %46 = icmp slt i64 %.val.i12, 0
  %47 = load ptr, ptr %3, align 8
  %spec.select37 = select i1 %46, ptr %3, ptr %47
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 8 %4, ptr align 1 %spec.select37, i64 %common.ret.op.i, i1 false)
  br label %mem.copyForwards__anon_9882.exit19

mem.copyForwards__anon_9882.exit19:               ; preds = %.lr.ph.i18.preheader, %str.RocStr.asU8ptr.exit14
  %48 = icmp slt i64 %.sroa.2.0.copyload, 0
  %49 = getelementptr inbounds i8, ptr %4, i64 %common.ret.op.i
  %50 = sub nuw nsw i64 %2, %common.ret.op.i
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %49, i8 0, i64 %50, i1 false)
  br i1 %48, label %common.ret, label %51

51:                                               ; preds = %mem.copyForwards__anon_9882.exit19
  %.sroa.034.0.copyload = load ptr, ptr %1, align 8
  %52 = ptrtoint ptr %.sroa.034.0.copyload to i64
  %53 = shl nuw i64 %.sroa.2.0.copyload, 1
  %isneg.i.i25 = icmp slt i64 %.sroa.1.0.copyload, 0
  %54 = select i1 %isneg.i.i25, i64 %53, i64 %52
  %55 = icmp ne i64 %.sroa.2.0.copyload, 0
  %56 = icmp ne i64 %54, 0
  %or.cond.i.i26 = select i1 %55, i1 %56, i1 false
  br i1 %or.cond.i.i26, label %57, label %common.ret

57:                                               ; preds = %51
  %58 = inttoptr i64 %54 to ptr
  %59 = getelementptr inbounds i64, ptr %58, i64 -1
  %60 = load i64, ptr %59, align 8
  %.not.i.i27 = icmp eq i64 %60, 0
  br i1 %.not.i.i27, label %common.ret, label %61

61:                                               ; preds = %57
  %62 = add i64 %60, -1
  store i64 %62, ptr %59, align 8
  %63 = icmp eq i64 %60, -9223372036854775808
  br i1 %63, label %common.ret.sink.split, label %common.ret
}

; Function Attrs: nounwind uwtable
declare void @roc_dealloc(ptr nonnull align 1, i32) local_unnamed_addr #4

; Function Attrs: nounwind uwtable
declare ptr @roc_alloc(i64, i32) local_unnamed_addr #4

; Function Attrs: nounwind uwtable
declare ptr @roc_realloc(ptr nonnull align 1, i64, i64, i32) local_unnamed_addr #4

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i128 @llvm.abs.i128(i128, i1 immarg) #1

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #12

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #12

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.smax.i64(i64, i64) #1

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(argmem: readwrite) uwtable
define internal i64 @roc_builtins.str.number_of_bytes(ptr nocapture noundef readonly %0) local_unnamed_addr #3 {
  %2 = tail call i64 @roc_builtins.str.count_utf8_bytes(ptr nocapture noundef readonly %0) #3
  ret i64 %2
}

define internal fastcc { %str.RocStr, {} } @Stdout_line_1e4d2f1e6b4984301a1489b71481ade3a818d1fae80b8f87ea525c7bff923(ptr %str) !dbg !97 {
entry:
  %result_value = alloca %str.RocStr, align 8
  call fastcc void @Effect_stdoutLine_b57223634213b1c687e1cf06fef47be7eed4c64d12c154ffb6abc557b2b473(ptr %str, ptr nonnull %result_value), !dbg !102
  %call = call fastcc { %str.RocStr, {} } @Effect_map_78e95374ca5c3ffeb4c3c6d1fee15f4627b4cb8e78c83389fa66fa17b11860(ptr nonnull %result_value, {} zeroinitializer), !dbg !102
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value), !dbg !102
  %call1 = call fastcc { %str.RocStr, {} } @InternalTask_fromEffect_7f755070a828d5b0991fd43175b6036d1cb7ecf871d1b823a8797b553d92bc({ %str.RocStr, {} } %call), !dbg !102
  ret { %str.RocStr, {} } %call1, !dbg !102
}

define internal fastcc void @InternalTask_ok_789661f33c6ea1791479ecf1f52dd93e21b779364a5197d9de3459113903b9c(ptr %a, ptr %0) !dbg !104 {
entry:
  %result_value = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !105
  %tag_alloca = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !105
  %data_buffer = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !105
  store ptr %a, ptr %data_buffer, align 8, !dbg !105
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !105
  store i8 1, ptr %tag_id_ptr, align 8, !dbg !105
  call fastcc void @Effect_always_e7d224cfcafcc878740e4416f7931bf725f9fd3378f8c73d6a4dc1d8c8883f(ptr nonnull %tag_alloca, ptr nonnull %result_value), !dbg !105
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %result_value, i64 48, i1 false), !dbg !105
  ret void, !dbg !105
}

define internal fastcc void @Task_await_13f5c26ce0b5e6eebef533619a72113f96d1ebc7728f2a7c4631d56ba55ad7c({ %str.RocStr, {} } %task, i1 %transform, ptr %0) !dbg !107 {
entry:
  %result_value1 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !108
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !108
  %call = tail call fastcc { %str.RocStr, {} } @InternalTask_toEffect_1b6b9e2f2c8025d6941d1d79426973c1ba899598ef8eecc9bea3f5f3657b4477({ %str.RocStr, {} } %task), !dbg !108
  call fastcc void @Effect_after_ac6315adde982c4b62c768a77be738d224267f4f9e6f1a02f3bc60549578c({ %str.RocStr, {} } %call, i1 %transform, ptr nonnull %result_value), !dbg !108
  call fastcc void @InternalTask_fromEffect_dc6b1b42abfea2844b7c4985e150c54b77c535b47ead6acd59d6a08b80d2(ptr nonnull %result_value, ptr nonnull %result_value1), !dbg !108
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value1, i64 64, i1 false), !dbg !108
  ret void, !dbg !108
}

define internal fastcc void @Http_methodToStr_172247c57cf29182b738e1647bff697cbe655ff06cf0aee2ca31b6b397327385(i8 %method, ptr %0) !dbg !110 {
entry:
  %const_str_store8 = alloca %str.RocStr, align 8, !dbg !111
  %const_str_store7 = alloca %str.RocStr, align 8, !dbg !111
  %const_str_store6 = alloca %str.RocStr, align 8, !dbg !111
  %const_str_store5 = alloca %str.RocStr, align 8, !dbg !111
  %const_str_store4 = alloca %str.RocStr, align 8, !dbg !111
  %const_str_store3 = alloca %str.RocStr, align 8, !dbg !111
  %const_str_store2 = alloca %str.RocStr, align 8, !dbg !111
  %const_str_store1 = alloca %str.RocStr, align 8, !dbg !111
  %const_str_store = alloca %str.RocStr, align 8, !dbg !111
  switch i8 %method, label %default [
    i8 4, label %branch4
    i8 2, label %branch2
    i8 6, label %branch6
    i8 7, label %branch7
    i8 1, label %branch1
    i8 3, label %branch3
    i8 8, label %branch8
    i8 0, label %branch0
  ], !dbg !111

default:                                          ; preds = %entry
  store ptr inttoptr (i64 448345170256 to ptr), ptr %const_str_store8, align 8, !dbg !111
  %const_str_store8.repack25 = getelementptr inbounds %str.RocStr, ptr %const_str_store8, i64 0, i32 1, !dbg !111
  store i64 0, ptr %const_str_store8.repack25, align 8, !dbg !111
  %const_str_store8.repack26 = getelementptr inbounds %str.RocStr, ptr %const_str_store8, i64 0, i32 2, !dbg !111
  store i64 -8863084066665136128, ptr %const_str_store8.repack26, align 8, !dbg !111
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %const_str_store8, i64 24, i1 false), !dbg !111
  ret void, !dbg !111

branch4:                                          ; preds = %entry
  store ptr inttoptr (i64 32491047111389263 to ptr), ptr %const_str_store, align 8, !dbg !111
  %const_str_store.repack23 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 1, !dbg !111
  store i64 0, ptr %const_str_store.repack23, align 8, !dbg !111
  %const_str_store.repack24 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 2, !dbg !111
  store i64 -8718968878589280256, ptr %const_str_store.repack24, align 8, !dbg !111
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %const_str_store, i64 24, i1 false), !dbg !111
  ret void, !dbg !111

branch2:                                          ; preds = %entry
  store ptr inttoptr (i64 7628103 to ptr), ptr %const_str_store1, align 8, !dbg !111
  %const_str_store1.repack21 = getelementptr inbounds %str.RocStr, ptr %const_str_store1, i64 0, i32 1, !dbg !111
  store i64 0, ptr %const_str_store1.repack21, align 8, !dbg !111
  %const_str_store1.repack22 = getelementptr inbounds %str.RocStr, ptr %const_str_store1, i64 0, i32 2, !dbg !111
  store i64 -9007199254740992000, ptr %const_str_store1.repack22, align 8, !dbg !111
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %const_str_store1, i64 24, i1 false), !dbg !111
  ret void, !dbg !111

branch6:                                          ; preds = %entry
  store ptr inttoptr (i64 1953722192 to ptr), ptr %const_str_store2, align 8, !dbg !111
  %const_str_store2.repack19 = getelementptr inbounds %str.RocStr, ptr %const_str_store2, i64 0, i32 1, !dbg !111
  store i64 0, ptr %const_str_store2.repack19, align 8, !dbg !111
  %const_str_store2.repack20 = getelementptr inbounds %str.RocStr, ptr %const_str_store2, i64 0, i32 2, !dbg !111
  store i64 -8935141660703064064, ptr %const_str_store2.repack20, align 8, !dbg !111
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %const_str_store2, i64 24, i1 false), !dbg !111
  ret void, !dbg !111

branch7:                                          ; preds = %entry
  store ptr inttoptr (i64 7632208 to ptr), ptr %const_str_store3, align 8, !dbg !111
  %const_str_store3.repack17 = getelementptr inbounds %str.RocStr, ptr %const_str_store3, i64 0, i32 1, !dbg !111
  store i64 0, ptr %const_str_store3.repack17, align 8, !dbg !111
  %const_str_store3.repack18 = getelementptr inbounds %str.RocStr, ptr %const_str_store3, i64 0, i32 2, !dbg !111
  store i64 -9007199254740992000, ptr %const_str_store3.repack18, align 8, !dbg !111
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %const_str_store3, i64 24, i1 false), !dbg !111
  ret void, !dbg !111

branch1:                                          ; preds = %entry
  store ptr inttoptr (i64 111550592214340 to ptr), ptr %const_str_store4, align 8, !dbg !111
  %const_str_store4.repack15 = getelementptr inbounds %str.RocStr, ptr %const_str_store4, i64 0, i32 1, !dbg !111
  store i64 0, ptr %const_str_store4.repack15, align 8, !dbg !111
  %const_str_store4.repack16 = getelementptr inbounds %str.RocStr, ptr %const_str_store4, i64 0, i32 2, !dbg !111
  store i64 -8791026472627208192, ptr %const_str_store4.repack16, align 8, !dbg !111
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %const_str_store4, i64 24, i1 false), !dbg !111
  ret void, !dbg !111

branch3:                                          ; preds = %entry
  store ptr inttoptr (i64 1684104520 to ptr), ptr %const_str_store5, align 8, !dbg !111
  %const_str_store5.repack13 = getelementptr inbounds %str.RocStr, ptr %const_str_store5, i64 0, i32 1, !dbg !111
  store i64 0, ptr %const_str_store5.repack13, align 8, !dbg !111
  %const_str_store5.repack14 = getelementptr inbounds %str.RocStr, ptr %const_str_store5, i64 0, i32 2, !dbg !111
  store i64 -8935141660703064064, ptr %const_str_store5.repack14, align 8, !dbg !111
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %const_str_store5, i64 24, i1 false), !dbg !111
  ret void, !dbg !111

branch8:                                          ; preds = %entry
  store ptr inttoptr (i64 435459027540 to ptr), ptr %const_str_store6, align 8, !dbg !111
  %const_str_store6.repack11 = getelementptr inbounds %str.RocStr, ptr %const_str_store6, i64 0, i32 1, !dbg !111
  store i64 0, ptr %const_str_store6.repack11, align 8, !dbg !111
  %const_str_store6.repack12 = getelementptr inbounds %str.RocStr, ptr %const_str_store6, i64 0, i32 2, !dbg !111
  store i64 -8863084066665136128, ptr %const_str_store6.repack12, align 8, !dbg !111
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %const_str_store6, i64 24, i1 false), !dbg !111
  ret void, !dbg !111

branch0:                                          ; preds = %entry
  store ptr inttoptr (i64 32760384594014019 to ptr), ptr %const_str_store7, align 8, !dbg !111
  %const_str_store7.repack9 = getelementptr inbounds %str.RocStr, ptr %const_str_store7, i64 0, i32 1, !dbg !111
  store i64 0, ptr %const_str_store7.repack9, align 8, !dbg !111
  %const_str_store7.repack10 = getelementptr inbounds %str.RocStr, ptr %const_str_store7, i64 0, i32 2, !dbg !111
  store i64 -8718968878589280256, ptr %const_str_store7.repack10, align 8, !dbg !111
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %const_str_store7, i64 24, i1 false), !dbg !111
  ret void, !dbg !111
}

define internal fastcc void @Effect_after_3c58d86b4437e7512e2b91aaabac14e86a30d0bfd8a27923c73b19fd673fff({ { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %"115", ptr %effect_after_toEffect, ptr %0) !dbg !113 {
entry:
  %tag_alloca = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8
  %struct_alloca = alloca { { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } }, { [0 x i32], [4 x i8], i8, [3 x i8] } }, align 8
  %"115.elt" = extractvalue { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %"115", 0, !dbg !114
  %"115.elt.elt" = extractvalue { %str.RocStr, {} } %"115.elt", 0, !dbg !114
  %"115.elt.elt.elt" = extractvalue %str.RocStr %"115.elt.elt", 0, !dbg !114
  store ptr %"115.elt.elt.elt", ptr %struct_alloca, align 8, !dbg !114
  %struct_alloca.repack6 = getelementptr inbounds %str.RocStr, ptr %struct_alloca, i64 0, i32 1, !dbg !114
  %"115.elt.elt.elt7" = extractvalue %str.RocStr %"115.elt.elt", 1, !dbg !114
  store i64 %"115.elt.elt.elt7", ptr %struct_alloca.repack6, align 8, !dbg !114
  %struct_alloca.repack8 = getelementptr inbounds %str.RocStr, ptr %struct_alloca, i64 0, i32 2, !dbg !114
  %"115.elt.elt.elt9" = extractvalue %str.RocStr %"115.elt.elt", 2, !dbg !114
  store i64 %"115.elt.elt.elt9", ptr %struct_alloca.repack8, align 8, !dbg !114
  %"115.elt3" = extractvalue { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %"115", 1, !dbg !114
  %struct_alloca.repack2.repack10 = getelementptr inbounds { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } }, ptr %struct_alloca, i64 0, i32 1, !dbg !114
  %"115.elt3.elt11" = extractvalue { [0 x i32], [4 x i8], i8, [3 x i8] } %"115.elt3", 1, !dbg !114
  %"115.elt3.elt11.elt" = extractvalue [4 x i8] %"115.elt3.elt11", 0, !dbg !114
  store i8 %"115.elt3.elt11.elt", ptr %struct_alloca.repack2.repack10, align 8, !dbg !114
  %struct_alloca.repack2.repack10.repack16 = getelementptr inbounds { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } }, ptr %struct_alloca, i64 0, i32 1, i32 1, i64 1, !dbg !114
  %"115.elt3.elt11.elt17" = extractvalue [4 x i8] %"115.elt3.elt11", 1, !dbg !114
  store i8 %"115.elt3.elt11.elt17", ptr %struct_alloca.repack2.repack10.repack16, align 1, !dbg !114
  %struct_alloca.repack2.repack10.repack18 = getelementptr inbounds { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } }, ptr %struct_alloca, i64 0, i32 1, i32 1, i64 2, !dbg !114
  %"115.elt3.elt11.elt19" = extractvalue [4 x i8] %"115.elt3.elt11", 2, !dbg !114
  store i8 %"115.elt3.elt11.elt19", ptr %struct_alloca.repack2.repack10.repack18, align 2, !dbg !114
  %struct_alloca.repack2.repack10.repack20 = getelementptr inbounds { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } }, ptr %struct_alloca, i64 0, i32 1, i32 1, i64 3, !dbg !114
  %"115.elt3.elt11.elt21" = extractvalue [4 x i8] %"115.elt3.elt11", 3, !dbg !114
  store i8 %"115.elt3.elt11.elt21", ptr %struct_alloca.repack2.repack10.repack20, align 1, !dbg !114
  %struct_alloca.repack2.repack12 = getelementptr inbounds { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } }, ptr %struct_alloca, i64 0, i32 1, i32 2, !dbg !114
  %"115.elt3.elt13" = extractvalue { [0 x i32], [4 x i8], i8, [3 x i8] } %"115.elt3", 2, !dbg !114
  store i8 %"115.elt3.elt13", ptr %struct_alloca.repack2.repack12, align 4, !dbg !114
  %struct_alloca.repack2.repack14 = getelementptr inbounds { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } }, ptr %struct_alloca, i64 0, i32 1, i32 3, !dbg !114
  %"115.elt3.elt15" = extractvalue { [0 x i32], [4 x i8], i8, [3 x i8] } %"115.elt3", 3, !dbg !114
  %"115.elt3.elt15.elt" = extractvalue [3 x i8] %"115.elt3.elt15", 0, !dbg !114
  store i8 %"115.elt3.elt15.elt", ptr %struct_alloca.repack2.repack14, align 1, !dbg !114
  %struct_alloca.repack2.repack14.repack22 = getelementptr inbounds { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } }, ptr %struct_alloca, i64 0, i32 1, i32 3, i64 1, !dbg !114
  %"115.elt3.elt15.elt23" = extractvalue [3 x i8] %"115.elt3.elt15", 1, !dbg !114
  store i8 %"115.elt3.elt15.elt23", ptr %struct_alloca.repack2.repack14.repack22, align 2, !dbg !114
  %struct_alloca.repack2.repack14.repack24 = getelementptr inbounds { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } }, ptr %struct_alloca, i64 0, i32 1, i32 3, i64 2, !dbg !114
  %"115.elt3.elt15.elt25" = extractvalue [3 x i8] %"115.elt3.elt15", 2, !dbg !114
  store i8 %"115.elt3.elt15.elt25", ptr %struct_alloca.repack2.repack14.repack24, align 1, !dbg !114
  %struct_field_gep1 = getelementptr inbounds { { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } }, { [0 x i32], [4 x i8], i8, [3 x i8] } }, ptr %struct_alloca, i64 0, i32 1, !dbg !114
  %1 = load i64, ptr %effect_after_toEffect, align 4, !dbg !114
  store i64 %1, ptr %struct_field_gep1, align 8, !dbg !114
  %data_buffer = getelementptr inbounds { [0 x i64], [5 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !114
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %data_buffer, ptr noundef nonnull align 8 dereferenceable(40) %struct_alloca, i64 40, i1 false), !dbg !114
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [5 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !114
  store i8 0, ptr %tag_id_ptr, align 8, !dbg !114
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %tag_alloca, i64 48, i1 false), !dbg !114
  ret void, !dbg !114
}

define internal fastcc void @Effect_effect_after_inner_544c19588062ed4289757939f8edf854589b8a37c6e1b564139c3298a34d6({} %"179", { { { %str.RocStr, {} }, {} }, {} } %"#arg_closure", ptr %0) !dbg !116 {
entry:
  %result_value3 = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !117
  %result_value2 = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !117
  %result_value1 = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !117
  %result_value = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !117
  %struct_field_access_record_1 = extractvalue { { { %str.RocStr, {} }, {} }, {} } %"#arg_closure", 1, !dbg !117
  %struct_field_access_record_0 = extractvalue { { { %str.RocStr, {} }, {} }, {} } %"#arg_closure", 0, !dbg !117
  call fastcc void @Effect_effect_after_inner_3994ebd10847f51a1ba443e4f3b9fb75da3f81a354da59de9bd34aaa2e927d({} zeroinitializer, { { %str.RocStr, {} }, {} } %struct_field_access_record_0, ptr nonnull %result_value), !dbg !117
  call fastcc void @Task_44_12a8ad799c7b34402483623f9b421f07775e1054bb6bfcf2ae122184609a(ptr nonnull %result_value, {} %struct_field_access_record_1, ptr nonnull %result_value1), !dbg !117
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [5 x i64], i8, [7 x i8] }, ptr %result_value1, i64 0, i32 2, !dbg !117
  %load_tag_id = load i8, ptr %tag_id_ptr, align 8, !dbg !117
  switch i8 %load_tag_id, label %default [
    i8 0, label %branch0
  ], !dbg !117

default:                                          ; preds = %entry
  call fastcc void @Effect_effect_always_inner_6e2f5c347617f02c84c4ee1199b6f064c2d91a5297c3fa525844f328c49949({} zeroinitializer, ptr nonnull %result_value1, ptr nonnull %result_value3), !dbg !117
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %result_value3, i64 16, i1 false), !dbg !117
  ret void, !dbg !117

branch0:                                          ; preds = %entry
  call fastcc void @Effect_effect_after_inner_1414869acb920f6db8ce61389f4b2ab8ee18505e1ddd7ea302888aec917e({} zeroinitializer, ptr nonnull %result_value1, ptr nonnull %result_value2), !dbg !117
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %result_value2, i64 16, i1 false), !dbg !117
  ret void, !dbg !117
}

define internal fastcc ptr @Box_box_d1a1e4356bd9fe6c31754def4c60a14042ade1c6c101618179cfd5d1c73189({} %"#arg1") !dbg !119 {
entry:
  %call_builtin = tail call ptr @roc_builtins.utils.allocate_with_refcount(i64 0, i32 1, i1 false), !dbg !120
  ret ptr %call_builtin, !dbg !120
}

define internal fastcc {} @InternalDateTime_dayWithPaddedZeros_7761c8128128ceb6e9a61eef6135bff7bcac2ab2ea5a7e1ad63b023aa1a8f68() !dbg !122 {
entry:
  ret {} zeroinitializer, !dbg !123
}

define internal fastcc i128 @Num_rem_cabb163ea8b383114bab450f2ea4bdf6f97d5dc22e57b593db81e3bce47(i128 %a, i128 %b) !dbg !125 {
entry:
  %const_str_store = alloca %str.RocStr, align 8, !dbg !126
  %call = tail call fastcc i1 @Num_isZero_f57b151e8a6dfbc520c29ccc134c8fb5357cdd96058ecd185f0787f48b7a6(i128 %b), !dbg !126
  br i1 %call, label %then_block, label %else_block, !dbg !126

then_block:                                       ; preds = %entry
  store ptr inttoptr (i64 2338042651316874825 to ptr), ptr %const_str_store, align 8, !dbg !126
  %const_str_store.repack2 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 1, !dbg !126
  store i64 7957695010998479204, ptr %const_str_store.repack2, align 8, !dbg !126
  %const_str_store.repack3 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 2, !dbg !126
  store i64 -7638068477433388512, ptr %const_str_store.repack3, align 8, !dbg !126
  call void @roc_panic(ptr %const_str_store, i32 1), !dbg !126
  unreachable, !dbg !126

else_block:                                       ; preds = %entry
  %call1 = tail call fastcc i128 @Num_remUnchecked_dc3f621de1221c7c53a19e877c377561ede91cdd88b1a687d310a39785a(i128 %a, i128 %b), !dbg !126
  ret i128 %call1, !dbg !126
}

define internal fastcc void @Task_err_b29e3b7af499d7231de5e31772f94a674636903232cb1b301cf274977992d8b({ %str.RocStr, i32 } %a, ptr %0) !dbg !128 {
entry:
  %result_value = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8
  call fastcc void @InternalTask_err_5cbbff1635f59ae21a02af6cfe0157283a05fb77d9b6ef4377a9133a78ffbe5({ %str.RocStr, i32 } %a, ptr nonnull %result_value), !dbg !129
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %result_value, i64 40, i1 false), !dbg !129
  ret void, !dbg !129
}

define internal fastcc void @InternalTask_toEffect_10259c295470b0dd303c429b36412fb6f21861ad97f73a2722c7516d147991f(ptr %"13", ptr %0) !dbg !131 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %"13", i64 40, i1 false), !dbg !132
  ret void, !dbg !132
}

define internal fastcc void @InternalTask_toEffect_935229af12e1c6ee752a73f7b73add5a7c7a22cfba9e577e778e240ed627a(ptr %"13", ptr %0) !dbg !134 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %"13", i64 48, i1 false), !dbg !135
  ret void, !dbg !135
}

define internal fastcc void @_33_aad9a2f5f9418b386cce489a0bac8cb5bba34171864909e4dfec1ea4e26bfb7({} %"51", ptr %0) !dbg !137 {
entry:
  %result_value = alloca { %list.RocList, %list.RocList, i16 }, align 8
  %struct_alloca = alloca { %list.RocList, %list.RocList, i16 }, align 8
  store ptr null, ptr %struct_alloca, align 8, !dbg !138
  %struct_alloca.repack3 = getelementptr inbounds %list.RocList, ptr %struct_alloca, i64 0, i32 1, !dbg !138
  store i64 0, ptr %struct_alloca.repack3, align 8, !dbg !138
  %struct_alloca.repack4 = getelementptr inbounds %list.RocList, ptr %struct_alloca, i64 0, i32 2, !dbg !138
  store i64 0, ptr %struct_alloca.repack4, align 8, !dbg !138
  %struct_field_gep1 = getelementptr inbounds { %list.RocList, %list.RocList, i16 }, ptr %struct_alloca, i64 0, i32 1, !dbg !138
  store ptr null, ptr %struct_field_gep1, align 8, !dbg !138
  %struct_field_gep1.repack5 = getelementptr inbounds { %list.RocList, %list.RocList, i16 }, ptr %struct_alloca, i64 0, i32 1, i32 1, !dbg !138
  store i64 0, ptr %struct_field_gep1.repack5, align 8, !dbg !138
  %struct_field_gep1.repack6 = getelementptr inbounds { %list.RocList, %list.RocList, i16 }, ptr %struct_alloca, i64 0, i32 1, i32 2, !dbg !138
  store i64 0, ptr %struct_field_gep1.repack6, align 8, !dbg !138
  %struct_field_gep2 = getelementptr inbounds { %list.RocList, %list.RocList, i16 }, ptr %struct_alloca, i64 0, i32 2, !dbg !138
  store i16 500, ptr %struct_field_gep2, align 8, !dbg !138
  call fastcc void @InternalTask_ok_a1fdfd7ca485c5e9436ed61186fef7b9b914edaf84deff48d9823fcadcd6ac(ptr nonnull %struct_alloca, ptr nonnull %result_value), !dbg !138
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %0, ptr noundef nonnull align 8 dereferenceable(56) %result_value, i64 56, i1 false), !dbg !138
  ret void, !dbg !138
}

define internal fastcc { { %str.RocStr, {} }, {} } @InternalTask_fromEffect_af58df284beb8fc541e167d520a5c53bd3e05fcd2fb56799b9aee4cfc3ed3f({ { %str.RocStr, {} }, {} } %effect) !dbg !140 {
entry:
  ret { { %str.RocStr, {} }, {} } %effect, !dbg !141
}

define internal fastcc void @InternalTask_ok_1cd410b47325ca54fd4d13db9f372fff17944e80d3dc60ceb6fa212947a({} %a, ptr %0) !dbg !143 {
entry:
  %result_value = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !144
  %tag_alloca = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !144
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !144
  store i8 1, ptr %tag_id_ptr, align 8, !dbg !144
  call fastcc void @Effect_always_aacdfa21c937a3152a4c9abafa557bcab3033c1362c20c33c558b64d99d3e5(ptr nonnull %tag_alloca, ptr nonnull %result_value), !dbg !144
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %result_value, i64 40, i1 false), !dbg !144
  ret void, !dbg !144
}

define internal fastcc void @Effect_effect_after_inner_3c34ade886ecb9c29fd02363474d39cd94178ea81fd90fb2871dcdcb2a3aad({} %"179", ptr %"#arg_closure", ptr %0) !dbg !146 {
entry:
  %result_value5 = alloca { %list.RocList, %list.RocList, i16 }, align 8, !dbg !147
  %result_value = alloca { %list.RocList, %list.RocList, i16 }, align 8, !dbg !147
  %get_opaque_data_ptr1 = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, i64 3, !dbg !147
  %load_element = load i1, ptr %get_opaque_data_ptr1, align 1, !dbg !147
  %get_opaque_data_ptr2 = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, !dbg !147
  %load_element4.unpack.unpack = load ptr, ptr %get_opaque_data_ptr2, align 8, !dbg !147
  %1 = insertvalue %str.RocStr poison, ptr %load_element4.unpack.unpack, 0, !dbg !147
  %load_element4.unpack.elt9 = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, i64 1, !dbg !147
  %load_element4.unpack.unpack10 = load i64, ptr %load_element4.unpack.elt9, align 8, !dbg !147
  %2 = insertvalue %str.RocStr %1, i64 %load_element4.unpack.unpack10, 1, !dbg !147
  %load_element4.unpack.elt11 = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, i64 2, !dbg !147
  %load_element4.unpack.unpack12 = load i64, ptr %load_element4.unpack.elt11, align 8, !dbg !147
  %load_element4.unpack13 = insertvalue %str.RocStr %2, i64 %load_element4.unpack.unpack12, 2, !dbg !147
  %3 = insertvalue { %str.RocStr, {} } poison, %str.RocStr %load_element4.unpack13, 0, !dbg !147
  %load_element48 = insertvalue { %str.RocStr, {} } %3, {} poison, 1, !dbg !147
  %call = tail call fastcc {} @Effect_effect_map_inner_c2d7201047722d5a148179c401bb3be69049c213c67ac89fa2daff2ad24745({} zeroinitializer, { %str.RocStr, {} } %load_element48), !dbg !147
  call fastcc void @Task_53_f752fd971dee73f4bef39e126f15a0a84437112755ca589db8702463ce739a({} %call, i1 %load_element, ptr nonnull %result_value), !dbg !147
  call fastcc void @Effect_effect_always_inner_6510a4d2b643dbf56ded4867b8cf49fe92c910e8961840e3a156bc971ee31a({} zeroinitializer, ptr nonnull %result_value, ptr nonnull %result_value5), !dbg !147
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %0, ptr noundef nonnull align 8 dereferenceable(56) %result_value5, i64 56, i1 false), !dbg !147
  ret void, !dbg !147
}

define internal fastcc {} @Effect_posixTime_229c75d6969a8a8a593eb2c44e915f34577963371a1cc7e544a8418a694a1e2() !dbg !149 {
entry:
  ret {} zeroinitializer, !dbg !150
}

define internal fastcc void @Utc_12_131fc9d292b7c25af42a6c6deb3979c2144f1a7423d39eb46aef237b8f774b(i128 %"47", ptr %0) !dbg !152 {
entry:
  %tag_alloca = alloca { [0 x i128], [4 x i64], i8, [15 x i8] }, align 16, !dbg !153
  %data_buffer = getelementptr inbounds { [0 x i128], [4 x i64], i8, [15 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !153
  store i128 %"47", ptr %data_buffer, align 16, !dbg !153
  %tag_id_ptr = getelementptr inbounds { [0 x i128], [4 x i64], i8, [15 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !153
  store i8 1, ptr %tag_id_ptr, align 16, !dbg !153
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(48) %0, ptr noundef nonnull align 16 dereferenceable(48) %tag_alloca, i64 48, i1 false), !dbg !153
  ret void, !dbg !153
}

define internal fastcc { %str.RocStr, {} } @Effect_map_78e95374ca5c3ffeb4c3c6d1fee15f4627b4cb8e78c83389fa66fa17b11860(ptr %"116", {} %effect_map_mapper) !dbg !155 {
entry:
  tail call fastcc void @"#Attr_#inc_2"(ptr %"116", i64 1), !dbg !156
  %load_tag_to_put_in_struct.unpack = load ptr, ptr %"116", align 8, !dbg !156
  %0 = insertvalue %str.RocStr poison, ptr %load_tag_to_put_in_struct.unpack, 0, !dbg !156
  %load_tag_to_put_in_struct.elt2 = getelementptr inbounds %str.RocStr, ptr %"116", i64 0, i32 1, !dbg !156
  %load_tag_to_put_in_struct.unpack3 = load i64, ptr %load_tag_to_put_in_struct.elt2, align 8, !dbg !156
  %1 = insertvalue %str.RocStr %0, i64 %load_tag_to_put_in_struct.unpack3, 1, !dbg !156
  %load_tag_to_put_in_struct.elt4 = getelementptr inbounds %str.RocStr, ptr %"116", i64 0, i32 2, !dbg !156
  %load_tag_to_put_in_struct.unpack5 = load i64, ptr %load_tag_to_put_in_struct.elt4, align 8, !dbg !156
  %load_tag_to_put_in_struct6 = insertvalue %str.RocStr %1, i64 %load_tag_to_put_in_struct.unpack5, 2, !dbg !156
  %insert_record_field = insertvalue { %str.RocStr, {} } zeroinitializer, %str.RocStr %load_tag_to_put_in_struct6, 0, !dbg !156
  %insert_record_field1 = insertvalue { %str.RocStr, {} } %insert_record_field, {} %effect_map_mapper, 1, !dbg !156
  ret { %str.RocStr, {} } %insert_record_field1, !dbg !156
}

define internal fastcc { { %str.RocStr, {} }, {} } @Task_await_7988d89080438f51df37e0664fee86ae858164dcb95eaeb555d2849513259182({ %str.RocStr, {} } %task, {} %transform) !dbg !158 {
entry:
  %call = tail call fastcc { %str.RocStr, {} } @InternalTask_toEffect_260dec8de9897e99a5126b882cbb9d2ee2f32cd2b94c727fdd1aa87e467d({ %str.RocStr, {} } %task), !dbg !159
  %call1 = tail call fastcc { { %str.RocStr, {} }, {} } @Effect_after_c5b690bc22238d3ac9e996befafbf2c431a107de306ea8b8318875c9fcba16({ %str.RocStr, {} } %call, {} %transform), !dbg !159
  %call2 = tail call fastcc { { %str.RocStr, {} }, {} } @InternalTask_fromEffect_af58df284beb8fc541e167d520a5c53bd3e05fcd2fb56799b9aee4cfc3ed3f({ { %str.RocStr, {} }, {} } %call1), !dbg !159
  ret { { %str.RocStr, {} }, {} } %call2, !dbg !159
}

define internal fastcc { %str.RocStr, {} } @InternalTask_fromEffect_edd459f1588e2edc4160caf3fec49aefc7d7fec1545146fd82c6ba52b293834({ %str.RocStr, {} } %effect) !dbg !161 {
entry:
  ret { %str.RocStr, {} } %effect, !dbg !162
}

define internal fastcc void @Effect_effect_after_inner_4ef81b983bd7cde6bbc497dcbaeffcb1ff38a9d8bb9b208abb417910dc73a6d1({} %"179", { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %"#arg_closure", ptr %0) !dbg !164 {
entry:
  %result_value1 = alloca { [0 x i32], [4 x i8], i8, [3 x i8] }, align 8, !dbg !165
  %result_value = alloca { [0 x i32], [4 x i8], i8, [3 x i8] }, align 8, !dbg !165
  %struct_field = alloca { [0 x i32], [4 x i8], i8, [3 x i8] }, align 8, !dbg !165
  %struct_field_access_record_1 = extractvalue { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %"#arg_closure", 1, !dbg !165
  %struct_field.repack2 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %struct_field, i64 0, i32 1, !dbg !165
  %struct_field_access_record_1.elt3 = extractvalue { [0 x i32], [4 x i8], i8, [3 x i8] } %struct_field_access_record_1, 1, !dbg !165
  %struct_field_access_record_1.elt3.elt = extractvalue [4 x i8] %struct_field_access_record_1.elt3, 0, !dbg !165
  store i8 %struct_field_access_record_1.elt3.elt, ptr %struct_field.repack2, align 8, !dbg !165
  %struct_field.repack2.repack8 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %struct_field, i64 0, i32 1, i64 1, !dbg !165
  %struct_field_access_record_1.elt3.elt9 = extractvalue [4 x i8] %struct_field_access_record_1.elt3, 1, !dbg !165
  store i8 %struct_field_access_record_1.elt3.elt9, ptr %struct_field.repack2.repack8, align 1, !dbg !165
  %struct_field.repack2.repack10 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %struct_field, i64 0, i32 1, i64 2, !dbg !165
  %struct_field_access_record_1.elt3.elt11 = extractvalue [4 x i8] %struct_field_access_record_1.elt3, 2, !dbg !165
  store i8 %struct_field_access_record_1.elt3.elt11, ptr %struct_field.repack2.repack10, align 2, !dbg !165
  %struct_field.repack2.repack12 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %struct_field, i64 0, i32 1, i64 3, !dbg !165
  %struct_field_access_record_1.elt3.elt13 = extractvalue [4 x i8] %struct_field_access_record_1.elt3, 3, !dbg !165
  store i8 %struct_field_access_record_1.elt3.elt13, ptr %struct_field.repack2.repack12, align 1, !dbg !165
  %struct_field.repack4 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %struct_field, i64 0, i32 2, !dbg !165
  %struct_field_access_record_1.elt5 = extractvalue { [0 x i32], [4 x i8], i8, [3 x i8] } %struct_field_access_record_1, 2, !dbg !165
  store i8 %struct_field_access_record_1.elt5, ptr %struct_field.repack4, align 4, !dbg !165
  %struct_field.repack6 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %struct_field, i64 0, i32 3, !dbg !165
  %struct_field_access_record_1.elt7 = extractvalue { [0 x i32], [4 x i8], i8, [3 x i8] } %struct_field_access_record_1, 3, !dbg !165
  %struct_field_access_record_1.elt7.elt = extractvalue [3 x i8] %struct_field_access_record_1.elt7, 0, !dbg !165
  store i8 %struct_field_access_record_1.elt7.elt, ptr %struct_field.repack6, align 1, !dbg !165
  %struct_field.repack6.repack14 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %struct_field, i64 0, i32 3, i64 1, !dbg !165
  %struct_field_access_record_1.elt7.elt15 = extractvalue [3 x i8] %struct_field_access_record_1.elt7, 1, !dbg !165
  store i8 %struct_field_access_record_1.elt7.elt15, ptr %struct_field.repack6.repack14, align 2, !dbg !165
  %struct_field.repack6.repack16 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %struct_field, i64 0, i32 3, i64 2, !dbg !165
  %struct_field_access_record_1.elt7.elt17 = extractvalue [3 x i8] %struct_field_access_record_1.elt7, 2, !dbg !165
  store i8 %struct_field_access_record_1.elt7.elt17, ptr %struct_field.repack6.repack16, align 1, !dbg !165
  %struct_field_access_record_0 = extractvalue { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %"#arg_closure", 0, !dbg !165
  %call = tail call fastcc {} @Effect_effect_map_inner_c2d7201047722d5a148179c401bb3be69049c213c67ac89fa2daff2ad24745({} zeroinitializer, { %str.RocStr, {} } %struct_field_access_record_0), !dbg !165
  call fastcc void @Task_60_e19be4977dae6e316e964ccb3f3519dc19317486f4e86b58a231a1854931186({} %call, ptr nonnull %struct_field, ptr nonnull %result_value), !dbg !165
  call fastcc void @Effect_effect_always_inner_dbbb614026929029a924a622e5a645206e5e1277bd8c25cb7b78527df1a8c({} zeroinitializer, ptr nonnull %result_value, ptr nonnull %result_value1), !dbg !165
  %1 = load i64, ptr %result_value1, align 8, !dbg !165
  store i64 %1, ptr %0, align 4, !dbg !165
  ret void, !dbg !165
}

define internal fastcc void @"#UserApp_7_13b85edde3cd334a6265af1614664111ffe13ba3b2be97d0f8e38d9c799cb7"(i128 %"#!1_arg", ptr %req, ptr %0) !dbg !167 {
entry:
  %result_value11 = alloca { [0 x i64], [8 x i64], i8, [7 x i8] }, align 8
  %result_value10 = alloca %str.RocStr, align 8
  %result_value9 = alloca %str.RocStr, align 8
  %result_value8 = alloca %str.RocStr, align 8
  %result_value7 = alloca %str.RocStr, align 8
  %struct_field6 = alloca %str.RocStr, align 8
  %struct_field3 = alloca %str.RocStr, align 8
  %const_str_store2 = alloca %str.RocStr, align 8
  %result_value1 = alloca %str.RocStr, align 8
  %const_str_store = alloca %str.RocStr, align 8
  %result_value = alloca %str.RocStr, align 8
  call fastcc void @Utc_toIso8601Str_46849c3b86f45f4f9e25198bc9b2ae6bcae76ebfbd692c6f18d9d9111cb9233c(i128 %"#!1_arg", ptr nonnull %result_value), !dbg !168
  store ptr inttoptr (i64 32 to ptr), ptr %const_str_store, align 8, !dbg !168
  %const_str_store.repack12 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 1, !dbg !168
  store i64 0, ptr %const_str_store.repack12, align 8, !dbg !168
  %const_str_store.repack13 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 2, !dbg !168
  store i64 -9151314442816847872, ptr %const_str_store.repack13, align 8, !dbg !168
  %struct_field_access_record_5 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %req, i64 0, i32 5, !dbg !168
  %struct_field = load i8, ptr %struct_field_access_record_5, align 1, !dbg !168
  call fastcc void @Http_methodToStr_172247c57cf29182b738e1647bff697cbe655ff06cf0aee2ca31b6b397327385(i8 %struct_field, ptr nonnull %result_value1), !dbg !168
  store ptr inttoptr (i64 32 to ptr), ptr %const_str_store2, align 8, !dbg !168
  %const_str_store2.repack14 = getelementptr inbounds %str.RocStr, ptr %const_str_store2, i64 0, i32 1, !dbg !168
  store i64 0, ptr %const_str_store2.repack14, align 8, !dbg !168
  %const_str_store2.repack15 = getelementptr inbounds %str.RocStr, ptr %const_str_store2, i64 0, i32 2, !dbg !168
  store i64 -9151314442816847872, ptr %const_str_store2.repack15, align 8, !dbg !168
  %struct_field_access_record_4 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %req, i64 0, i32 4, !dbg !168
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %struct_field3, ptr noundef nonnull align 8 dereferenceable(24) %struct_field_access_record_4, i64 24, i1 false), !dbg !168
  %struct_field4.unpack = load ptr, ptr %req, align 8, !dbg !168
  %1 = insertvalue %list.RocList poison, ptr %struct_field4.unpack, 0, !dbg !168
  %struct_field4.elt16 = getelementptr inbounds %list.RocList, ptr %req, i64 0, i32 1, !dbg !168
  %struct_field4.unpack17 = load i64, ptr %struct_field4.elt16, align 8, !dbg !168
  %2 = insertvalue %list.RocList %1, i64 %struct_field4.unpack17, 1, !dbg !168
  %struct_field4.elt18 = getelementptr inbounds %list.RocList, ptr %req, i64 0, i32 2, !dbg !168
  %struct_field4.unpack19 = load i64, ptr %struct_field4.elt18, align 8, !dbg !168
  %struct_field420 = insertvalue %list.RocList %2, i64 %struct_field4.unpack19, 2, !dbg !168
  call fastcc void @"#Attr_#dec_3"(%list.RocList %struct_field420), !dbg !168
  %struct_field_access_record_1 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %req, i64 0, i32 1, !dbg !168
  %struct_field5.unpack = load ptr, ptr %struct_field_access_record_1, align 8, !dbg !168
  %3 = insertvalue %list.RocList poison, ptr %struct_field5.unpack, 0, !dbg !168
  %struct_field5.elt21 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %req, i64 0, i32 1, i32 1, !dbg !168
  %struct_field5.unpack22 = load i64, ptr %struct_field5.elt21, align 8, !dbg !168
  %4 = insertvalue %list.RocList %3, i64 %struct_field5.unpack22, 1, !dbg !168
  %struct_field5.elt23 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %req, i64 0, i32 1, i32 2, !dbg !168
  %struct_field5.unpack24 = load i64, ptr %struct_field5.elt23, align 8, !dbg !168
  %struct_field525 = insertvalue %list.RocList %4, i64 %struct_field5.unpack24, 2, !dbg !168
  call fastcc void @"#Attr_#dec_4"(%list.RocList %struct_field525), !dbg !168
  %struct_field_access_record_2 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %req, i64 0, i32 2, !dbg !168
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %struct_field6, ptr noundef nonnull align 8 dereferenceable(24) %struct_field_access_record_2, i64 24, i1 false), !dbg !168
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %struct_field6), !dbg !168
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %const_str_store2, ptr nonnull %struct_field3, ptr nonnull %result_value7), !dbg !168
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %struct_field3), !dbg !168
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %result_value1, ptr nonnull %result_value7, ptr nonnull %result_value8), !dbg !168
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value7), !dbg !168
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %const_str_store, ptr nonnull %result_value8, ptr nonnull %result_value9), !dbg !168
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value8), !dbg !168
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %result_value, ptr nonnull %result_value9, ptr nonnull %result_value10), !dbg !168
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value9), !dbg !168
  %call = call fastcc { %str.RocStr, {} } @Stdout_line_99c9f773566b1d5d689233ef7949cf16c8797c970a4668678361d8c89d24f20(ptr nonnull %result_value10), !dbg !168
  call fastcc void @Task_await_ca98df76e744faeef21fb76918295997c9c1b552a2e623d6fc162a11de8fae({ %str.RocStr, {} } %call, {} zeroinitializer, ptr nonnull %result_value11), !dbg !168
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(72) %0, ptr noundef nonnull align 8 dereferenceable(72) %result_value11, i64 72, i1 false), !dbg !168
  ret void, !dbg !168
}

define internal fastcc void @Task_92_42f43e247a90ff93dac3c860bb219ee18693539a6e942bad35bcb7297d6e16(ptr %res, ptr %0) !dbg !170 {
entry:
  %result_value1 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  call fastcc void @Task_ok_47379a71f6fa75b326383965b5622141f57df12cc22d7140acdf38f0ac8dbc6d(ptr %res, ptr nonnull %result_value), !dbg !171
  call fastcc void @InternalTask_toEffect_8719a5fa4a4d2d7fe17773695c6c6d3ecd8b7cfffd135c8d4ca89f29f876d1f(ptr nonnull %result_value, ptr nonnull %result_value1), !dbg !171
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value1, i64 64, i1 false), !dbg !171
  ret void, !dbg !171
}

define internal fastcc void @Effect_effect_always_inner_cd87b8ad69bc5b0a62f3f19932d2d2ba97fc6f54781f6533ef735e0b0235064({} %"266", ptr %"#arg_closure", ptr %0) !dbg !173 {
entry:
  %load_element = alloca { %list.RocList, %list.RocList, i16 }, align 8, !dbg !174
  %get_opaque_data_ptr = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, !dbg !174
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %load_element, ptr noundef nonnull align 8 dereferenceable(56) %get_opaque_data_ptr, i64 56, i1 false), !dbg !174
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %0, ptr noundef nonnull align 8 dereferenceable(56) %load_element, i64 56, i1 false), !dbg !174
  ret void, !dbg !174
}

define internal fastcc void @InternalTask_ok_21b5c7d5305aa5ff4df495f05c9e59c37d76367eacec9dd321a0e78143dfc4a3({} %a, ptr %0) !dbg !176 {
entry:
  %result_value = alloca { [0 x i32], [4 x i8], i8, [3 x i8] }, align 8, !dbg !177
  %tag_alloca = alloca { [0 x i32], [4 x i8], i8, [3 x i8] }, align 8, !dbg !177
  %tag_id_ptr = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !177
  store i8 1, ptr %tag_id_ptr, align 4, !dbg !177
  call fastcc void @Effect_always_a472f7aba8f6717343f24da54150b124829637a3f252c7e04811e4754b343d0(ptr nonnull %tag_alloca, ptr nonnull %result_value), !dbg !177
  %1 = load i64, ptr %result_value, align 8, !dbg !177
  store i64 %1, ptr %0, align 4, !dbg !177
  ret void, !dbg !177
}

define internal fastcc void @InternalTask_fromEffect_dc6b1b42abfea2844b7c4985e150c54b77c535b47ead6acd59d6a08b80d2(ptr %effect, ptr %0) !dbg !179 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %effect, i64 64, i1 false), !dbg !180
  ret void, !dbg !180
}

define internal fastcc i1 @Bool_or_52459ae5e05017996bb4298dd9ac3944ffe997fa2e2ad98ba6fd7348395f63(i1 %"#arg1", i1 %"#arg2") !dbg !182 {
entry:
  %bool_or = or i1 %"#arg1", %"#arg2", !dbg !183
  ret i1 %bool_or, !dbg !183
}

define internal fastcc i1 @Bool_isNotEq_91183c4be76c8c6e9a1aca423ca6b7bdfddc155d7aac337b8db73395e0e64d(i128 %a, i128 %b) !dbg !185 {
entry:
  %call = tail call fastcc i1 @Bool_structuralNotEq_53eef38977ca9e3af29e8b6fc9f50f557be9bbd173abd2118eb5488f19fb2(i128 %a, i128 %b), !dbg !186
  ret i1 %call, !dbg !186
}

define internal fastcc void @Task_53_d0954aeb42c3a999750fa5b4068c6679ed2537c3257fc7e6c4e91bdc4133ae0(ptr %res, {} %transform, ptr %0) !dbg !188 {
entry:
  %result_value1 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  call fastcc void @_25_1c44a9ca60e694ea5bce656141adb8728c249dc46543e7c34883c1136ab140(ptr %res, ptr nonnull %result_value), !dbg !189
  call fastcc void @InternalTask_toEffect_99494e9e9babe4dcb72b4144dc54d31ba956a4ee34496553143a5e7cb7dc78c4(ptr nonnull %result_value, ptr nonnull %result_value1), !dbg !189
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value1, i64 64, i1 false), !dbg !189
  ret void, !dbg !189
}

define internal fastcc void @Effect_stdoutLine_b57223634213b1c687e1cf06fef47be7eed4c64d12c154ffb6abc557b2b473(ptr %closure_arg_stdoutLine_0, ptr %0) !dbg !191 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %closure_arg_stdoutLine_0, i64 24, i1 false), !dbg !192
  ret void, !dbg !192
}

define internal fastcc { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } @InternalTask_toEffect_583276bf45a8e97f112dfbc4f4d4d2a42a1119a510af9e76a5cba40a368d0({ { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %"13") !dbg !194 {
entry:
  ret { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %"13", !dbg !195
}

define internal fastcc i1 @Bool_structuralEq_4a74cf314ac9371a5ea518de15e620d82137397f51a1fa6eff156547f363(i64 %"#arg1", i64 %"#arg2") !dbg !197 {
entry:
  %eq_u64 = icmp eq i64 %"#arg1", %"#arg2", !dbg !198
  ret i1 %eq_u64, !dbg !198
}

define internal fastcc { %str.RocStr, {} } @InternalTask_fromEffect_594462766f77f828358545ebdadebc7d564d3daf466672cbde673babcf18c3c2({ %str.RocStr, {} } %effect) !dbg !200 {
entry:
  ret { %str.RocStr, {} } %effect, !dbg !201
}

define internal fastcc i128 @InternalDateTime_daysInMonth_4a2d194da1241ef3ca5a8139a734b29ae4efb20126643584c91fe6ded8e2c5a(i128 %year, i128 %month) !dbg !203 {
entry:
  %call_builtin = tail call ptr @roc_builtins.utils.allocate_with_refcount(i64 112, i32 16, i1 false), !dbg !204
  store i128 1, ptr %call_builtin, align 16, !dbg !204
  %index1 = getelementptr inbounds i128, ptr %call_builtin, i64 1, !dbg !204
  store i128 3, ptr %index1, align 16, !dbg !204
  %index2 = getelementptr inbounds i128, ptr %call_builtin, i64 2, !dbg !204
  store i128 5, ptr %index2, align 16, !dbg !204
  %index3 = getelementptr inbounds i128, ptr %call_builtin, i64 3, !dbg !204
  store i128 7, ptr %index3, align 16, !dbg !204
  %index4 = getelementptr inbounds i128, ptr %call_builtin, i64 4, !dbg !204
  store i128 8, ptr %index4, align 16, !dbg !204
  %index5 = getelementptr inbounds i128, ptr %call_builtin, i64 5, !dbg !204
  store i128 10, ptr %index5, align 16, !dbg !204
  %index6 = getelementptr inbounds i128, ptr %call_builtin, i64 6, !dbg !204
  store i128 12, ptr %index6, align 16, !dbg !204
  %insert_record_field = insertvalue %list.RocList zeroinitializer, ptr %call_builtin, 0, !dbg !204
  %insert_record_field7 = insertvalue %list.RocList %insert_record_field, i64 7, 1, !dbg !204
  %insert_record_field8 = insertvalue %list.RocList %insert_record_field7, i64 7, 2, !dbg !204
  %call = tail call fastcc i1 @List_contains_4fe2c0cee861629d2ef04c3f725dba5813b563598f88e6fe57cefd4dd1a133(%list.RocList %insert_record_field8, i128 %month), !dbg !204
  tail call fastcc void @"#Attr_#dec_6"(%list.RocList %insert_record_field8), !dbg !204
  br i1 %call, label %then_block, label %else_block, !dbg !204

then_block:                                       ; preds = %entry
  ret i128 31, !dbg !204

else_block:                                       ; preds = %entry
  %call_builtin9 = tail call ptr @roc_builtins.utils.allocate_with_refcount(i64 64, i32 16, i1 false), !dbg !204
  store i128 4, ptr %call_builtin9, align 16, !dbg !204
  %index11 = getelementptr inbounds i128, ptr %call_builtin9, i64 1, !dbg !204
  store i128 6, ptr %index11, align 16, !dbg !204
  %index12 = getelementptr inbounds i128, ptr %call_builtin9, i64 2, !dbg !204
  store i128 9, ptr %index12, align 16, !dbg !204
  %index13 = getelementptr inbounds i128, ptr %call_builtin9, i64 3, !dbg !204
  store i128 11, ptr %index13, align 16, !dbg !204
  %insert_record_field14 = insertvalue %list.RocList zeroinitializer, ptr %call_builtin9, 0, !dbg !204
  %insert_record_field15 = insertvalue %list.RocList %insert_record_field14, i64 4, 1, !dbg !204
  %insert_record_field16 = insertvalue %list.RocList %insert_record_field15, i64 4, 2, !dbg !204
  %call17 = tail call fastcc i1 @List_contains_4fe2c0cee861629d2ef04c3f725dba5813b563598f88e6fe57cefd4dd1a133(%list.RocList %insert_record_field16, i128 %month), !dbg !204
  tail call fastcc void @"#Attr_#dec_6"(%list.RocList %insert_record_field16), !dbg !204
  br i1 %call17, label %then_block19, label %else_block20, !dbg !204

then_block19:                                     ; preds = %else_block
  ret i128 30, !dbg !204

else_block20:                                     ; preds = %else_block
  %call21 = tail call fastcc i1 @Bool_structuralEq_2cc6e6d3c5a48a76ea218c439d44b6318e7bd267419a22dcb25b258a2c06a(i128 %month, i128 2), !dbg !204
  br i1 %call21, label %then_block23, label %else_block24, !dbg !204

then_block23:                                     ; preds = %else_block20
  %call25 = tail call fastcc i1 @InternalDateTime_isLeapYear_a9e685cc72fe3166dd93f93a27166ec5656562cf1d6d3e19f41a6cc3489(i128 %year), !dbg !204
  br i1 %call25, label %then_block27, label %else_block28, !dbg !204

else_block24:                                     ; preds = %else_block20
  ret i128 0, !dbg !204

then_block27:                                     ; preds = %then_block23
  ret i128 29, !dbg !204

else_block28:                                     ; preds = %then_block23
  ret i128 28, !dbg !204
}

define internal fastcc {} @Effect_effect_map_inner_c2d7201047722d5a148179c401bb3be69049c213c67ac89fa2daff2ad24745({} %"118", { %str.RocStr, {} } %"#arg_closure") !dbg !206 {
entry:
  %struct_field = alloca %str.RocStr, align 8, !dbg !207
  %struct_field_access_record_0 = extractvalue { %str.RocStr, {} } %"#arg_closure", 0, !dbg !207
  %struct_field_access_record_0.elt = extractvalue %str.RocStr %struct_field_access_record_0, 0, !dbg !207
  store ptr %struct_field_access_record_0.elt, ptr %struct_field, align 8, !dbg !207
  %struct_field.repack2 = getelementptr inbounds %str.RocStr, ptr %struct_field, i64 0, i32 1, !dbg !207
  %struct_field_access_record_0.elt3 = extractvalue %str.RocStr %struct_field_access_record_0, 1, !dbg !207
  store i64 %struct_field_access_record_0.elt3, ptr %struct_field.repack2, align 8, !dbg !207
  %struct_field.repack4 = getelementptr inbounds %str.RocStr, ptr %struct_field, i64 0, i32 2, !dbg !207
  %struct_field_access_record_0.elt5 = extractvalue %str.RocStr %struct_field_access_record_0, 2, !dbg !207
  store i64 %struct_field_access_record_0.elt5, ptr %struct_field.repack4, align 8, !dbg !207
  %call = call fastcc {} @Effect_effect_closure_stderrLine_a0d5c44a91521ccbe6cbe0ca2338db7878e8dda81a27912b861f86434c26c052({} zeroinitializer, ptr nonnull %struct_field), !dbg !207
  %call1 = call fastcc {} @Stderr_4_1979c8b7ef5f495fcd893830dae286517b20f9eb43379243d33155ade7a91({} %call), !dbg !207
  ret {} %call1, !dbg !207
}

define internal fastcc void @Effect_effect_after_inner_268182e6bf48c34ea8893d1d91dfdfbbcae7ca2eb5c9a5136f7f2958cb888df({} %"179", ptr %"#arg_closure", ptr %0) !dbg !209 {
entry:
  %result_value4 = alloca { %list.RocList, %list.RocList, i16 }, align 8, !dbg !210
  %result_value3 = alloca { %list.RocList, %list.RocList, i16 }, align 8, !dbg !210
  %result_value2 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !210
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !210
  %struct_field1 = alloca { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, align 8, !dbg !210
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %struct_field1, ptr noundef nonnull align 8 dereferenceable(120) %"#arg_closure", i64 120, i1 false), !dbg !210
  call fastcc void @Effect_effect_after_inner_aafde219d9d91ee7a575a5efa6c6154f3d42c85beb7780b41b4510548f4aaf({} zeroinitializer, ptr nonnull %struct_field1, ptr nonnull %result_value), !dbg !210
  call fastcc void @Task_53_d0954aeb42c3a999750fa5b4068c6679ed2537c3257fc7e6c4e91bdc4133ae0(ptr nonnull %result_value, {} poison, ptr nonnull %result_value2), !dbg !210
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %result_value2, i64 0, i32 2, !dbg !210
  %load_tag_id = load i8, ptr %tag_id_ptr, align 8, !dbg !210
  switch i8 %load_tag_id, label %default [
    i8 0, label %branch0
  ], !dbg !210

default:                                          ; preds = %entry
  call fastcc void @Effect_effect_always_inner_cd87b8ad69bc5b0a62f3f19932d2d2ba97fc6f54781f6533ef735e0b0235064({} zeroinitializer, ptr nonnull %result_value2, ptr nonnull %result_value4), !dbg !210
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %0, ptr noundef nonnull align 8 dereferenceable(56) %result_value4, i64 56, i1 false), !dbg !210
  ret void, !dbg !210

branch0:                                          ; preds = %entry
  call fastcc void @Effect_effect_after_inner_3c34ade886ecb9c29fd02363474d39cd94178ea81fd90fb2871dcdcb2a3aad({} zeroinitializer, ptr nonnull %result_value2, ptr nonnull %result_value3), !dbg !210
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %0, ptr noundef nonnull align 8 dereferenceable(56) %result_value3, i64 56, i1 false), !dbg !210
  ret void, !dbg !210
}

define internal fastcc void @InternalTask_toEffect_5eb6a2599d3097c754d93922b84522fd22c626afbfca9a48d724fa1945e3ca9(ptr %"13", ptr %0) !dbg !212 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(72) %0, ptr noundef nonnull align 8 dereferenceable(72) %"13", i64 72, i1 false), !dbg !213
  ret void, !dbg !213
}

define internal fastcc void @_respond_c919149ababf2a569c5e2b164c2465c785dc3bc7f566b8dcef7ec4ae86e8d57(ptr %request, ptr %boxedModel, ptr %0) !dbg !215 {
entry:
  %result_value4 = alloca { { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, {} }, align 8
  %result_value3 = alloca { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, align 8
  %result_value2 = alloca { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, align 8
  %result_value = alloca { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, align 8
  call fastcc void @InternalHttp_fromHostRequest_99ccc6754e07ea7cffe47524633bfb91dd0f5a5f04cc85ed764577b4b3a23(ptr %request, ptr nonnull %result_value), !dbg !216
  %call = call fastcc {} @Box_unbox_d394208415ac8fe0ce8aa0ddf6a845c7cc74d818698e3d25c85705ce311f5ec(ptr %boxedModel), !dbg !216
  %call1 = call fastcc { { { %str.RocStr, {} }, {} }, {} } @"#UserApp_server_52aff1341cf42f5e6559a2cf028663f7bbbc7576ac1948fc58784a0613b79"(), !dbg !216
  %struct_field_access_record_0 = extractvalue { { { %str.RocStr, {} }, {} }, {} } %call1, 0, !dbg !216
  call fastcc void @"#Attr_#dec_7"({ { %str.RocStr, {} }, {} } %struct_field_access_record_0), !dbg !216
  call fastcc void @"#UserApp_respond_8c3fdd6849785e1b32106ad9c6ae59845e2314f0a6799376d4e3e3b9be62d181"(ptr nonnull %result_value, {} %call, ptr nonnull %result_value2), !dbg !216
  call fastcc void @Task_result_19a01698b1f1f64ca782bce3c6b70dbfe2947aebabe3f6b126ebdf6166ecc31(ptr nonnull %result_value2, ptr nonnull %result_value3), !dbg !216
  call fastcc void @Task_await_55aa18fc3c82fe108fcf64fea07364ddba1e8c526b8d27b19692a7748519e1c(ptr nonnull %result_value3, {} zeroinitializer, ptr nonnull %result_value4), !dbg !216
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %result_value4, i64 120, i1 false), !dbg !216
  ret void, !dbg !216
}

define internal fastcc void @InternalDateTime_epochMillisToDateTime_4e6df5a280208f8027d8c0e0fd95af1adf299ebd3666b6c48551dc0cb3c3214(i128 %millis, ptr %0) !dbg !218 {
entry:
  %result_value = alloca { i128, i128, i128, i128, i128, i128 }, align 16, !dbg !219
  %struct_alloca = alloca { i128, i128, i128, i128, i128, i128 }, align 16, !dbg !219
  %call = tail call fastcc i128 @Num_divTrunc_cb411178cb7686889a4ee0e4b4c57e63975186dc9f1448b79e94c2721a21a2(i128 %millis, i128 1000), !dbg !219
  %call1 = tail call fastcc i128 @Num_divTrunc_cb411178cb7686889a4ee0e4b4c57e63975186dc9f1448b79e94c2721a21a2(i128 %call, i128 60), !dbg !219
  %call2 = tail call fastcc i128 @Num_divTrunc_cb411178cb7686889a4ee0e4b4c57e63975186dc9f1448b79e94c2721a21a2(i128 %call1, i128 60), !dbg !219
  %call3 = tail call fastcc i128 @Num_divTrunc_cb411178cb7686889a4ee0e4b4c57e63975186dc9f1448b79e94c2721a21a2(i128 %call2, i128 24), !dbg !219
  %call4 = tail call fastcc i128 @Num_add_669c1355a3e727bb53dd458f2e96e48571aa45dfabcfb4b7de1689484f11(i128 1, i128 %call3), !dbg !219
  %call5 = tail call fastcc i128 @Num_rem_cabb163ea8b383114bab450f2ea4bdf6f97d5dc22e57b593db81e3bce47(i128 %call2, i128 24), !dbg !219
  %call6 = tail call fastcc i128 @Num_rem_cabb163ea8b383114bab450f2ea4bdf6f97d5dc22e57b593db81e3bce47(i128 %call1, i128 60), !dbg !219
  %call7 = tail call fastcc i128 @Num_rem_cabb163ea8b383114bab450f2ea4bdf6f97d5dc22e57b593db81e3bce47(i128 %call, i128 60), !dbg !219
  store i128 %call4, ptr %struct_alloca, align 16, !dbg !219
  %struct_field_gep8 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca, i64 0, i32 1, !dbg !219
  store i128 %call5, ptr %struct_field_gep8, align 16, !dbg !219
  %struct_field_gep9 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca, i64 0, i32 2, !dbg !219
  store i128 %call6, ptr %struct_field_gep9, align 16, !dbg !219
  %struct_field_gep10 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca, i64 0, i32 3, !dbg !219
  store i128 1, ptr %struct_field_gep10, align 16, !dbg !219
  %struct_field_gep11 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca, i64 0, i32 4, !dbg !219
  store i128 %call7, ptr %struct_field_gep11, align 16, !dbg !219
  %struct_field_gep12 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca, i64 0, i32 5, !dbg !219
  store i128 1970, ptr %struct_field_gep12, align 16, !dbg !219
  call fastcc void @InternalDateTime_epochMillisToDateTimeHelp_684393a95528f29ba49a721c9e7bd2dbf82e1a92e5b742ec5b556b18be7657(ptr nonnull %struct_alloca, ptr nonnull %result_value), !dbg !219
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %0, ptr noundef nonnull align 16 dereferenceable(96) %result_value, i64 96, i1 false), !dbg !219
  ret void, !dbg !219
}

define internal fastcc void @Task_await_8e9956175ff8e3582c4b770a3b3c2388266676d8eb052d494e1a127bd7a9ad2({ { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %task, ptr %transform, ptr %0) !dbg !221 {
entry:
  %result_value1 = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !222
  %result_value = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !222
  %call = tail call fastcc { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } @InternalTask_toEffect_583276bf45a8e97f112dfbc4f4d4d2a42a1119a510af9e76a5cba40a368d0({ { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %task), !dbg !222
  call fastcc void @Effect_after_3c58d86b4437e7512e2b91aaabac14e86a30d0bfd8a27923c73b19fd673fff({ { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %call, ptr %transform, ptr nonnull %result_value), !dbg !222
  call fastcc void @InternalTask_fromEffect_d5c9642a64db206d88ab43bd2b9527b05aca746579abd7472d977da8e33ac(ptr nonnull %result_value, ptr nonnull %result_value1), !dbg !222
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %result_value1, i64 48, i1 false), !dbg !222
  ret void, !dbg !222
}

define internal fastcc void @Task_await_55aa18fc3c82fe108fcf64fea07364ddba1e8c526b8d27b19692a7748519e1c(ptr %task, {} %transform, ptr %0) !dbg !224 {
entry:
  %result_value2 = alloca { { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, {} }, align 8
  %result_value1 = alloca { { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, {} }, align 8
  %result_value = alloca { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, align 8
  call fastcc void @InternalTask_toEffect_8e7a40fb7cb2175e9c8b7aee60f44cef84959b742d3a14c483b6e3b14f05c2f(ptr %task, ptr nonnull %result_value), !dbg !225
  call fastcc void @Effect_after_4ec88c32b1d8d7e41af6fe2c3b1c519c1adff81ec271f8be7bf4ea491e1(ptr nonnull %result_value, {} %transform, ptr nonnull %result_value1), !dbg !225
  call fastcc void @InternalTask_fromEffect_ea724491503a37367f3396489f19ddb4ed26c1b122d1bb85553bb555a0a4d(ptr nonnull %result_value1, ptr nonnull %result_value2), !dbg !225
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %result_value2, i64 120, i1 false), !dbg !225
  ret void, !dbg !225
}

define internal fastcc void @Num_toStr_99e2ebbd98e8a2a4c7ed9bd71d205d9f7b5d7e7a9ddb68dab65f2ad1c2198b(i128 %"#arg1", ptr %0) !dbg !227 {
entry:
  %str_alloca = alloca %str.RocStr, align 8
  call void @roc_builtins.str.from_int.i128(ptr noalias nocapture nonnull sret(%str.RocStr) %str_alloca, i128 %"#arg1"), !dbg !228
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %str_alloca, i64 24, i1 false), !dbg !228
  ret void, !dbg !228
}

define internal fastcc { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } @InternalTask_fromEffect_3bfae27b50cc70419dec89ef8da341b1287d7bb7b3c4bb2481ba28b17a8ec4({ { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %effect) !dbg !230 {
entry:
  ret { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %effect, !dbg !231
}

define internal fastcc void @InternalTask_ok_ade2dc9e385e74c61c8d36210907131d7823a7fe8d06c7bd978c1f46a9d3830(ptr %a, ptr %0) !dbg !233 {
entry:
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  call fastcc void @Effect_always_deda9c07093181a3aee6f4559463a94ce2b31f038cb3d5548d0bb2aeba37e1(ptr %a, ptr nonnull %result_value), !dbg !234
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value, i64 64, i1 false), !dbg !234
  ret void, !dbg !234
}

define internal fastcc i1 @Bool_and_078eba49b7090dbd2c6fb82297218e6d2eb88883fa33ff213b919f6e68cc(i1 %"#arg1", i1 %"#arg2") !dbg !236 {
entry:
  %bool_and = and i1 %"#arg1", %"#arg2", !dbg !237
  ret i1 %bool_and, !dbg !237
}

define internal fastcc void @_152_55d628abedfcc0e78784ef0cac7a0c47c774ce17d4fb8ba44f37721d7f3d98({} %"154", { { { %str.RocStr, {} }, {} }, {} } %"#arg_closure", ptr %0) !dbg !239 {
entry:
  %result_value = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8
  call fastcc void @Effect_effect_after_inner_544c19588062ed4289757939f8edf854589b8a37c6e1b564139c3298a34d6({} %"154", { { { %str.RocStr, {} }, {} }, {} } %"#arg_closure", ptr nonnull %result_value), !dbg !240
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %result_value, i64 16, i1 false), !dbg !240
  ret void, !dbg !240
}

define internal fastcc void @InternalTask_toEffect_99494e9e9babe4dcb72b4144dc54d31ba956a4ee34496553143a5e7cb7dc78c4(ptr %"13", ptr %0) !dbg !242 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %"13", i64 64, i1 false), !dbg !243
  ret void, !dbg !243
}

define internal fastcc void @InternalDateTime_monthWithPaddedZeros_7bb22cd9f7ce9f3ea01a5cc21ef19af74a624ef91d31d1912f9a7744788c55c(i128 %month, ptr %0) !dbg !245 {
entry:
  %result_value1 = alloca %str.RocStr, align 8
  %const_str_store = alloca %str.RocStr, align 8
  %result_value = alloca %str.RocStr, align 8
  call fastcc void @Num_toStr_99e2ebbd98e8a2a4c7ed9bd71d205d9f7b5d7e7a9ddb68dab65f2ad1c2198b(i128 %month, ptr nonnull %result_value), !dbg !246
  %call = call fastcc i1 @Num_isLt_f273102d33b910ab8b1eda6e483bb587ec34372c3562cd9bfb68bcf889ba9cd(i128 %month, i128 10), !dbg !246
  br i1 %call, label %then_block, label %else_block, !dbg !246

then_block:                                       ; preds = %entry
  store ptr inttoptr (i64 48 to ptr), ptr %const_str_store, align 8, !dbg !246
  %const_str_store.repack2 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 1, !dbg !246
  store i64 0, ptr %const_str_store.repack2, align 8, !dbg !246
  %const_str_store.repack3 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 2, !dbg !246
  store i64 -9151314442816847872, ptr %const_str_store.repack3, align 8, !dbg !246
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %const_str_store, ptr nonnull %result_value, ptr nonnull %result_value1), !dbg !246
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value), !dbg !246
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %result_value1, i64 24, i1 false), !dbg !246
  ret void, !dbg !246

else_block:                                       ; preds = %entry
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %result_value, i64 24, i1 false), !dbg !246
  ret void, !dbg !246
}

define internal fastcc void @_19_b5dcd15815911a96b9d7e883b1723ec1e9f2a35835ca79db2284140ebd0aa83({} %"82", ptr %"#arg_closure", ptr %0) !dbg !248 {
entry:
  %result_value = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !249
  %get_opaque_data_ptr = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %"#arg_closure", i64 0, i32 1, !dbg !249
  %load_element = load i32, ptr %get_opaque_data_ptr, align 4, !dbg !249
  call fastcc void @Task_err_dbefccae6de790f8e3497ad3c6c1c58a12a744edb0d65ec1ec4ade8b1151a59b(i32 %load_element, ptr nonnull %result_value), !dbg !249
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %result_value, i64 16, i1 false), !dbg !249
  ret void, !dbg !249
}

define internal fastcc void @InternalTask_err_c3db9144e9e8a2aeb45a4287ca39a6b36f034de3f4c779c625aa44629cf92b4(i32 %a, ptr %0) !dbg !251 {
entry:
  %result_value = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !252
  %tag_alloca = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !252
  %data_buffer = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !252
  store i32 %a, ptr %data_buffer, align 8, !dbg !252
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !252
  store i8 0, ptr %tag_id_ptr, align 8, !dbg !252
  call fastcc void @Effect_always_94cb138d818e9947d7d69ef307378727ff7855e4de6723d27fc54d8e228050(ptr nonnull %tag_alloca, ptr nonnull %result_value), !dbg !252
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %result_value, i64 16, i1 false), !dbg !252
  ret void, !dbg !252
}

define internal fastcc void @Effect_always_3c159ccc72c9f6c2f9b343f7ee15555614903dc98bb4bf9da1d235172245b(ptr %effect_always_value, ptr %0) !dbg !254 {
entry:
  %tag_alloca = alloca { [0 x i64], [8 x i64], i8, [7 x i8] }, align 8
  %struct_alloca = alloca { { [0 x i64], [7 x i64], i8, [7 x i8] } }, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %struct_alloca, ptr noundef nonnull align 8 dereferenceable(64) %effect_always_value, i64 64, i1 false), !dbg !255
  %data_buffer = getelementptr inbounds { [0 x i64], [8 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !255
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %data_buffer, ptr noundef nonnull align 8 dereferenceable(64) %struct_alloca, i64 64, i1 false), !dbg !255
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [8 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !255
  store i8 1, ptr %tag_id_ptr, align 8, !dbg !255
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(72) %0, ptr noundef nonnull align 8 dereferenceable(72) %tag_alloca, i64 72, i1 false), !dbg !255
  ret void, !dbg !255
}

define internal fastcc i1 @Num_isLt_edaf1bd3d1c2ffcc44df55829c02f262426de2ffbea9be2cdf075ec12c528d(i64 %"#arg1", i64 %"#arg2") !dbg !257 {
entry:
  %lt_uint = icmp ult i64 %"#arg1", %"#arg2", !dbg !258
  ret i1 %lt_uint, !dbg !258
}

define internal fastcc void @_22_1484a21b4257566f7c1b3505e4f6c430eb1121cbfb946b32fb115b90b1ef50({} %"97", ptr %0) !dbg !260 {
entry:
  %result_value = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8
  call fastcc void @Task_err_dbefccae6de790f8e3497ad3c6c1c58a12a744edb0d65ec1ec4ade8b1151a59b(i32 1, ptr nonnull %result_value), !dbg !261
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %result_value, i64 16, i1 false), !dbg !261
  ret void, !dbg !261
}

define internal fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr %"#arg1", ptr %"#arg2", ptr %0) !dbg !263 {
entry:
  %str_alloca = alloca %str.RocStr, align 8
  call void @roc_builtins.str.concat(ptr noalias nocapture nonnull sret(%str.RocStr) %str_alloca, ptr nocapture readonly %"#arg1", ptr nocapture readonly %"#arg2"), !dbg !264
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %str_alloca, i64 24, i1 false), !dbg !264
  ret void, !dbg !264
}

define internal fastcc void @Effect_effect_always_inner_6e2f5c347617f02c84c4ee1199b6f064c2d91a5297c3fa525844f328c49949({} %"266", ptr %"#arg_closure", ptr %0) !dbg !266 {
entry:
  %load_element = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !267
  %get_opaque_data_ptr = getelementptr inbounds { [0 x i64], [5 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, !dbg !267
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %load_element, ptr noundef nonnull align 8 dereferenceable(16) %get_opaque_data_ptr, i64 16, i1 false), !dbg !267
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %load_element, i64 16, i1 false), !dbg !267
  ret void, !dbg !267
}

define internal fastcc void @Task_err_7f39af79a2c681124253a11db0202f701d4c3013db3c1272927c55405b9031(i32 %a, ptr %0) !dbg !269 {
entry:
  %result_value = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8
  call fastcc void @InternalTask_err_cd37899bb8a8d9e6a1967d5d098545d4623f55f4fb33fb81a429834acd2bca2(i32 %a, ptr nonnull %result_value), !dbg !270
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %result_value, i64 48, i1 false), !dbg !270
  ret void, !dbg !270
}

define internal fastcc void @Effect_effect_map_inner_d52f8c3ecf2e209e81e04dd415745749206b773d86c4d1b2bb2d3d8e8890c({} %"118", { { { {}, {} }, {} }, {} } %"#arg_closure", ptr %0) !dbg !272 {
entry:
  %result_value = alloca { [0 x i128], [4 x i64], i8, [15 x i8] }, align 16, !dbg !273
  %struct_field_access_record_0 = extractvalue { { { {}, {} }, {} }, {} } %"#arg_closure", 0, !dbg !273
  %call = tail call fastcc i128 @Effect_effect_map_inner_f2e0cf21cda4e3c878e1ab216b192b2e2825d82c3b48a3a8bb6d7de6e7e20e({} zeroinitializer, { { {}, {} }, {} } %struct_field_access_record_0), !dbg !273
  call fastcc void @Utc_12_131fc9d292b7c25af42a6c6deb3979c2144f1a7423d39eb46aef237b8f774b(i128 %call, ptr nonnull %result_value), !dbg !273
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(48) %0, ptr noundef nonnull align 16 dereferenceable(48) %result_value, i64 48, i1 false), !dbg !273
  ret void, !dbg !273
}

define internal fastcc void @List_looper_fb7917afe92ebaa35d275cfd557c2b25a5a46452e484a4eb8cac5175c61606d({} %"624", i128 %element, i128 %predicate, ptr %0) !dbg !275 {
entry:
  %tag_alloca1 = alloca { [0 x i8], [0 x i8], i8, [0 x i8] }, align 8, !dbg !276
  %tag_alloca = alloca { [0 x i8], [0 x i8], i8, [0 x i8] }, align 8, !dbg !276
  %call = tail call fastcc i1 @List_161_3bbacd33228bca14fe5573efe7278cde33c78fe9028ba98810cff368dece(i128 %element, i128 %predicate), !dbg !276
  br i1 %call, label %then_block, label %else_block, !dbg !276

then_block:                                       ; preds = %entry
  %tag_id_ptr = getelementptr inbounds { [0 x i8], [0 x i8], i8, [0 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !276
  store i8 0, ptr %tag_id_ptr, align 8, !dbg !276
  %1 = load i8, ptr %tag_alloca, align 8, !dbg !276
  store i8 %1, ptr %0, align 1, !dbg !276
  ret void, !dbg !276

else_block:                                       ; preds = %entry
  %tag_id_ptr3 = getelementptr inbounds { [0 x i8], [0 x i8], i8, [0 x i8] }, ptr %tag_alloca1, i64 0, i32 2, !dbg !276
  store i8 1, ptr %tag_id_ptr3, align 8, !dbg !276
  %2 = load i8, ptr %tag_alloca1, align 8, !dbg !276
  store i8 %2, ptr %0, align 1, !dbg !276
  ret void, !dbg !276
}

define internal fastcc { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } @Task_onErr_7544714fcb8fdf9ddf55315cce78cf57de5a2d6621b01a7739ff24d9f60ac({ %str.RocStr, {} } %task, ptr %transform) !dbg !278 {
entry:
  %call = tail call fastcc { %str.RocStr, {} } @InternalTask_toEffect_1b6b9e2f2c8025d6941d1d79426973c1ba899598ef8eecc9bea3f5f3657b4477({ %str.RocStr, {} } %task), !dbg !279
  %call1 = tail call fastcc { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } @Effect_after_a7deb1b6384ce9571721cd1522e1e931203f492c94f2dbf8138817d3824a({ %str.RocStr, {} } %call, ptr %transform), !dbg !279
  %call2 = tail call fastcc { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } @InternalTask_fromEffect_3bfae27b50cc70419dec89ef8da341b1287d7bb7b3c4bb2481ba28b17a8ec4({ { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %call1), !dbg !279
  ret { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %call2, !dbg !279
}

define internal fastcc void @Task_err_dbefccae6de790f8e3497ad3c6c1c58a12a744edb0d65ec1ec4ade8b1151a59b(i32 %a, ptr %0) !dbg !281 {
entry:
  %result_value = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8
  call fastcc void @InternalTask_err_c3db9144e9e8a2aeb45a4287ca39a6b36f034de3f4c779c625aa44629cf92b4(i32 %a, ptr nonnull %result_value), !dbg !282
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %result_value, i64 16, i1 false), !dbg !282
  ret void, !dbg !282
}

define internal fastcc { { { %str.RocStr, {} }, {} }, {} } @Task_attempt_dce3401669119d7f5da9e070669694c78f88efb14a471223494f7d677db1e7d({ { %str.RocStr, {} }, {} } %task, {} %transform) !dbg !284 {
entry:
  %call = tail call fastcc { { %str.RocStr, {} }, {} } @InternalTask_toEffect_a0ad3055de08c7e73da1974f4d9be666ee2daaab6969dd582bb59893cf022b0({ { %str.RocStr, {} }, {} } %task), !dbg !285
  %call1 = tail call fastcc { { { %str.RocStr, {} }, {} }, {} } @Effect_after_35d6cb78c74f84df82ab12c37bc71bbe5193f93e9d36506abc7c9c8ca124d1ab({ { %str.RocStr, {} }, {} } %call, {} %transform), !dbg !285
  %call2 = tail call fastcc { { { %str.RocStr, {} }, {} }, {} } @InternalTask_fromEffect_df2d999242c7383735614c1ca7894e355776837c47b5a1272ceceba5a498db({ { { %str.RocStr, {} }, {} }, {} } %call1), !dbg !285
  ret { { { %str.RocStr, {} }, {} }, {} } %call2, !dbg !285
}

define internal fastcc void @Effect_effect_always_inner_dbbb614026929029a924a622e5a645206e5e1277bd8c25cb7b78527df1a8c({} %"266", ptr %effect_always_value, ptr %0) !dbg !287 {
entry:
  %1 = load i64, ptr %effect_always_value, align 4, !dbg !288
  store i64 %1, ptr %0, align 4, !dbg !288
  ret void, !dbg !288
}

define internal fastcc void @InternalTask_err_5cbbff1635f59ae21a02af6cfe0157283a05fb77d9b6ef4377a9133a78ffbe5({ %str.RocStr, i32 } %a, ptr %0) !dbg !290 {
entry:
  %result_value = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !291
  %tag_alloca = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !291
  %data_buffer = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !291
  store { %str.RocStr, i32 } %a, ptr %data_buffer, align 8, !dbg !291
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !291
  store i8 0, ptr %tag_id_ptr, align 8, !dbg !291
  call fastcc void @Effect_always_aacdfa21c937a3152a4c9abafa557bcab3033c1362c20c33c558b64d99d3e5(ptr nonnull %tag_alloca, ptr nonnull %result_value), !dbg !291
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %result_value, i64 40, i1 false), !dbg !291
  ret void, !dbg !291
}

define internal fastcc void @Effect_effect_after_inner_3994ebd10847f51a1ba443e4f3b9fb75da3f81a354da59de9bd34aaa2e927d({} %"179", { { %str.RocStr, {} }, {} } %"#arg_closure", ptr %0) !dbg !293 {
entry:
  %result_value2 = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !294
  %result_value1 = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !294
  %result_value = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !294
  %struct_field_access_record_1 = extractvalue { { %str.RocStr, {} }, {} } %"#arg_closure", 1, !dbg !294
  %struct_field_access_record_0 = extractvalue { { %str.RocStr, {} }, {} } %"#arg_closure", 0, !dbg !294
  call fastcc void @Effect_effect_map_inner_e4a1eb19d38152fc193a183edc36566d275fa494bf9c69e26c29c318cc289d0({} zeroinitializer, { %str.RocStr, {} } %struct_field_access_record_0, ptr nonnull %result_value), !dbg !294
  call fastcc void @Task_53_5d84da6abaf677d342986d45e3605cfd5bd1528ee5196616226adfb513950(ptr nonnull %result_value, {} %struct_field_access_record_1, ptr nonnull %result_value1), !dbg !294
  call fastcc void @Effect_effect_always_inner_7ceb2e607d153edd175217b82e8ded113c6e4df27e27777d9f9694c716aa427({} zeroinitializer, ptr nonnull %result_value1, ptr nonnull %result_value2), !dbg !294
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %result_value2, i64 40, i1 false), !dbg !294
  ret void, !dbg !294
}

define internal fastcc void @"#UserApp_5_2c7d993eadf275d994a1f98b824972fece3cfca6b6ac52dd7bb717e1f5753"({} %"40", ptr %0) !dbg !296 {
entry:
  %result_value = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8
  call fastcc void @Task_ok_1971ed175c5339d8a493ee2a719f3ca8f50fbcc2a26feaf7b54a27898e3f({} zeroinitializer, ptr nonnull %result_value), !dbg !297
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %result_value, i64 40, i1 false), !dbg !297
  ret void, !dbg !297
}

define internal fastcc void @InternalDateTime_toIso8601Str_8cf693340558d3441d6232b3632a0e7d41f8065e5f4ec1b10ba263a7452d728(ptr %"90", ptr %0) !dbg !299 {
entry:
  %result_value29 = alloca %str.RocStr, align 8, !dbg !300
  %result_value28 = alloca %str.RocStr, align 8, !dbg !300
  %result_value27 = alloca %str.RocStr, align 8, !dbg !300
  %result_value26 = alloca %str.RocStr, align 8, !dbg !300
  %result_value25 = alloca %str.RocStr, align 8, !dbg !300
  %result_value24 = alloca %str.RocStr, align 8, !dbg !300
  %result_value23 = alloca %str.RocStr, align 8, !dbg !300
  %result_value22 = alloca %str.RocStr, align 8, !dbg !300
  %result_value21 = alloca %str.RocStr, align 8, !dbg !300
  %result_value20 = alloca %str.RocStr, align 8, !dbg !300
  %result_value19 = alloca %str.RocStr, align 8, !dbg !300
  %const_str_store18 = alloca %str.RocStr, align 8, !dbg !300
  %const_str_store17 = alloca %str.RocStr, align 8, !dbg !300
  %const_str_store16 = alloca %str.RocStr, align 8, !dbg !300
  %const_str_store15 = alloca %str.RocStr, align 8, !dbg !300
  %const_str_store14 = alloca %str.RocStr, align 8, !dbg !300
  %const_str_store = alloca %str.RocStr, align 8, !dbg !300
  %result_value13 = alloca %str.RocStr, align 8, !dbg !300
  %result_value11 = alloca %str.RocStr, align 8, !dbg !300
  %result_value9 = alloca %str.RocStr, align 8, !dbg !300
  %result_value7 = alloca %str.RocStr, align 8, !dbg !300
  %result_value6 = alloca %str.RocStr, align 8, !dbg !300
  %result_value = alloca %str.RocStr, align 8, !dbg !300
  %struct_field = load i128, ptr %"90", align 16, !dbg !300
  %struct_field_access_record_1 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %"90", i64 0, i32 1, !dbg !300
  %struct_field1 = load i128, ptr %struct_field_access_record_1, align 16, !dbg !300
  %struct_field_access_record_2 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %"90", i64 0, i32 2, !dbg !300
  %struct_field2 = load i128, ptr %struct_field_access_record_2, align 16, !dbg !300
  %struct_field_access_record_3 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %"90", i64 0, i32 3, !dbg !300
  %struct_field3 = load i128, ptr %struct_field_access_record_3, align 16, !dbg !300
  %struct_field_access_record_4 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %"90", i64 0, i32 4, !dbg !300
  %struct_field4 = load i128, ptr %struct_field_access_record_4, align 16, !dbg !300
  %struct_field_access_record_5 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %"90", i64 0, i32 5, !dbg !300
  %struct_field5 = load i128, ptr %struct_field_access_record_5, align 16, !dbg !300
  call fastcc void @InternalDateTime_yearWithPaddedZeros_c4a37e6d352bb35242daa87c613d86251be76cf677f327944a4ca87b5e276(i128 %struct_field5, ptr nonnull %result_value), !dbg !300
  call fastcc void @InternalDateTime_monthWithPaddedZeros_7bb22cd9f7ce9f3ea01a5cc21ef19af74a624ef91d31d1912f9a7744788c55c(i128 %struct_field3, ptr nonnull %result_value6), !dbg !300
  %call = call fastcc {} @InternalDateTime_dayWithPaddedZeros_7761c8128128ceb6e9a61eef6135bff7bcac2ab2ea5a7e1ad63b023aa1a8f68(), !dbg !300
  call fastcc void @InternalDateTime_monthWithPaddedZeros_7bb22cd9f7ce9f3ea01a5cc21ef19af74a624ef91d31d1912f9a7744788c55c(i128 %struct_field, ptr nonnull %result_value7), !dbg !300
  %call8 = call fastcc {} @InternalDateTime_hoursWithPaddedZeros_93b8def1d2984c6818ac4bcad643457a66cc713468a3a5225fa94a9b1b4933f0(), !dbg !300
  call fastcc void @InternalDateTime_monthWithPaddedZeros_7bb22cd9f7ce9f3ea01a5cc21ef19af74a624ef91d31d1912f9a7744788c55c(i128 %struct_field1, ptr nonnull %result_value9), !dbg !300
  %call10 = call fastcc {} @InternalDateTime_minutesWithPaddedZeros_44109459d64fcdac3ea0c7115c1a33caa6de3332a46a1f0819b84a1d3a6c9(), !dbg !300
  call fastcc void @InternalDateTime_monthWithPaddedZeros_7bb22cd9f7ce9f3ea01a5cc21ef19af74a624ef91d31d1912f9a7744788c55c(i128 %struct_field2, ptr nonnull %result_value11), !dbg !300
  %call12 = call fastcc {} @InternalDateTime_secondsWithPaddedZeros_5d26e7953422ce84aac56171b489e0deedf33db4e08b81dcad67e7427bff49(), !dbg !300
  call fastcc void @InternalDateTime_monthWithPaddedZeros_7bb22cd9f7ce9f3ea01a5cc21ef19af74a624ef91d31d1912f9a7744788c55c(i128 %struct_field4, ptr nonnull %result_value13), !dbg !300
  store ptr inttoptr (i64 45 to ptr), ptr %const_str_store, align 8, !dbg !300
  %const_str_store.repack30 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 1, !dbg !300
  store i64 0, ptr %const_str_store.repack30, align 8, !dbg !300
  %const_str_store.repack31 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 2, !dbg !300
  store i64 -9151314442816847872, ptr %const_str_store.repack31, align 8, !dbg !300
  store ptr inttoptr (i64 45 to ptr), ptr %const_str_store14, align 8, !dbg !300
  %const_str_store14.repack32 = getelementptr inbounds %str.RocStr, ptr %const_str_store14, i64 0, i32 1, !dbg !300
  store i64 0, ptr %const_str_store14.repack32, align 8, !dbg !300
  %const_str_store14.repack33 = getelementptr inbounds %str.RocStr, ptr %const_str_store14, i64 0, i32 2, !dbg !300
  store i64 -9151314442816847872, ptr %const_str_store14.repack33, align 8, !dbg !300
  store ptr inttoptr (i64 84 to ptr), ptr %const_str_store15, align 8, !dbg !300
  %const_str_store15.repack34 = getelementptr inbounds %str.RocStr, ptr %const_str_store15, i64 0, i32 1, !dbg !300
  store i64 0, ptr %const_str_store15.repack34, align 8, !dbg !300
  %const_str_store15.repack35 = getelementptr inbounds %str.RocStr, ptr %const_str_store15, i64 0, i32 2, !dbg !300
  store i64 -9151314442816847872, ptr %const_str_store15.repack35, align 8, !dbg !300
  store ptr inttoptr (i64 58 to ptr), ptr %const_str_store16, align 8, !dbg !300
  %const_str_store16.repack36 = getelementptr inbounds %str.RocStr, ptr %const_str_store16, i64 0, i32 1, !dbg !300
  store i64 0, ptr %const_str_store16.repack36, align 8, !dbg !300
  %const_str_store16.repack37 = getelementptr inbounds %str.RocStr, ptr %const_str_store16, i64 0, i32 2, !dbg !300
  store i64 -9151314442816847872, ptr %const_str_store16.repack37, align 8, !dbg !300
  store ptr inttoptr (i64 58 to ptr), ptr %const_str_store17, align 8, !dbg !300
  %const_str_store17.repack38 = getelementptr inbounds %str.RocStr, ptr %const_str_store17, i64 0, i32 1, !dbg !300
  store i64 0, ptr %const_str_store17.repack38, align 8, !dbg !300
  %const_str_store17.repack39 = getelementptr inbounds %str.RocStr, ptr %const_str_store17, i64 0, i32 2, !dbg !300
  store i64 -9151314442816847872, ptr %const_str_store17.repack39, align 8, !dbg !300
  store ptr inttoptr (i64 90 to ptr), ptr %const_str_store18, align 8, !dbg !300
  %const_str_store18.repack40 = getelementptr inbounds %str.RocStr, ptr %const_str_store18, i64 0, i32 1, !dbg !300
  store i64 0, ptr %const_str_store18.repack40, align 8, !dbg !300
  %const_str_store18.repack41 = getelementptr inbounds %str.RocStr, ptr %const_str_store18, i64 0, i32 2, !dbg !300
  store i64 -9151314442816847872, ptr %const_str_store18.repack41, align 8, !dbg !300
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %result_value13, ptr nonnull %const_str_store18, ptr nonnull %result_value19), !dbg !300
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %const_str_store18), !dbg !300
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %const_str_store17, ptr nonnull %result_value19, ptr nonnull %result_value20), !dbg !300
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value19), !dbg !300
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %result_value11, ptr nonnull %result_value20, ptr nonnull %result_value21), !dbg !300
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value20), !dbg !300
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %const_str_store16, ptr nonnull %result_value21, ptr nonnull %result_value22), !dbg !300
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value21), !dbg !300
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %result_value9, ptr nonnull %result_value22, ptr nonnull %result_value23), !dbg !300
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value22), !dbg !300
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %const_str_store15, ptr nonnull %result_value23, ptr nonnull %result_value24), !dbg !300
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value23), !dbg !300
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %result_value7, ptr nonnull %result_value24, ptr nonnull %result_value25), !dbg !300
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value24), !dbg !300
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %const_str_store14, ptr nonnull %result_value25, ptr nonnull %result_value26), !dbg !300
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value25), !dbg !300
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %result_value6, ptr nonnull %result_value26, ptr nonnull %result_value27), !dbg !300
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value26), !dbg !300
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %const_str_store, ptr nonnull %result_value27, ptr nonnull %result_value28), !dbg !300
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value27), !dbg !300
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %result_value, ptr nonnull %result_value28, ptr nonnull %result_value29), !dbg !300
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value28), !dbg !300
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %result_value29, i64 24, i1 false), !dbg !300
  ret void, !dbg !300
}

define internal fastcc void @Effect_stderrLine_a51293a4c3ce80beb92fd22c82b6b69bd26ee8bc815b483e3cf291f486236c(ptr %closure_arg_stderrLine_0, ptr %0) !dbg !302 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %closure_arg_stderrLine_0, i64 24, i1 false), !dbg !303
  ret void, !dbg !303
}

define internal fastcc i1 @Bool_structuralEq_2cc6e6d3c5a48a76ea218c439d44b6318e7bd267419a22dcb25b258a2c06a(i128 %"#arg1", i128 %"#arg2") !dbg !305 {
entry:
  %eq_i128 = icmp eq i128 %"#arg1", %"#arg2", !dbg !306
  ret i1 %eq_i128, !dbg !306
}

define internal fastcc { %str.RocStr, {} } @Stderr_line_4bd18bc73cee8d6c664141b2e49674ebb21216aa20f0f89293181ce7b14e(ptr %str) !dbg !308 {
entry:
  %result_value = alloca %str.RocStr, align 8
  call fastcc void @Effect_stderrLine_a51293a4c3ce80beb92fd22c82b6b69bd26ee8bc815b483e3cf291f486236c(ptr %str, ptr nonnull %result_value), !dbg !309
  %call = call fastcc { %str.RocStr, {} } @Effect_map_4bc296458c9e4dfa311cb236c399bfa4fbaacf1f1ce0be5dc9b3fb0e57fbf5(ptr nonnull %result_value, {} zeroinitializer), !dbg !309
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value), !dbg !309
  %call1 = call fastcc { %str.RocStr, {} } @InternalTask_fromEffect_edd459f1588e2edc4160caf3fec49aefc7d7fec1545146fd82c6ba52b293834({ %str.RocStr, {} } %call), !dbg !309
  ret { %str.RocStr, {} } %call1, !dbg !309
}

define internal fastcc i128 @Utc_nanosPerMilli_1bb73f6fafaa3656a8bf5796e2e6e6bdbd058375237d0b9be5834c8c9f54() !dbg !311 {
entry:
  ret i128 1000000, !dbg !312
}

define internal fastcc void @Task_53_5d84da6abaf677d342986d45e3605cfd5bd1528ee5196616226adfb513950(ptr %res, {} %transform, ptr %0) !dbg !314 {
entry:
  %result_value7 = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !315
  %result_value6 = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !315
  %result_value2 = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !315
  %result_value = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !315
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %res, i64 0, i32 2, !dbg !315
  %load_tag_id = load i8, ptr %tag_id_ptr, align 1, !dbg !315
  %eq_u8 = icmp eq i8 %load_tag_id, 1, !dbg !315
  br i1 %eq_u8, label %then_block, label %else_block, !dbg !315

then_block:                                       ; preds = %entry
  call fastcc void @"#UserApp_5_2c7d993eadf275d994a1f98b824972fece3cfca6b6ac52dd7bb717e1f5753"({} poison, ptr nonnull %result_value), !dbg !315
  call fastcc void @InternalTask_toEffect_10259c295470b0dd303c429b36412fb6f21861ad97f73a2722c7516d147991f(ptr nonnull %result_value, ptr nonnull %result_value2), !dbg !315
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %result_value2, i64 40, i1 false), !dbg !315
  ret void, !dbg !315

else_block:                                       ; preds = %entry
  %get_opaque_data_ptr3 = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %res, i64 0, i32 1, !dbg !315
  %load_element5 = load { %str.RocStr, i32 }, ptr %get_opaque_data_ptr3, align 8, !dbg !315
  call fastcc void @Task_err_b29e3b7af499d7231de5e31772f94a674636903232cb1b301cf274977992d8b({ %str.RocStr, i32 } %load_element5, ptr nonnull %result_value6), !dbg !315
  call fastcc void @InternalTask_toEffect_10259c295470b0dd303c429b36412fb6f21861ad97f73a2722c7516d147991f(ptr nonnull %result_value6, ptr nonnull %result_value7), !dbg !315
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %result_value7, i64 40, i1 false), !dbg !315
  ret void, !dbg !315
}

define internal fastcc void @Task_ok_47379a71f6fa75b326383965b5622141f57df12cc22d7140acdf38f0ac8dbc6d(ptr %a, ptr %0) !dbg !317 {
entry:
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  call fastcc void @InternalTask_ok_ade2dc9e385e74c61c8d36210907131d7823a7fe8d06c7bd978c1f46a9d3830(ptr %a, ptr nonnull %result_value), !dbg !318
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value, i64 64, i1 false), !dbg !318
  ret void, !dbg !318
}

define internal fastcc void @Effect_effect_after_inner_bac59821c43c0b53dd3438580b2599a5bf16c219b40a9d5e9a6e6a5390({} %"179", ptr %"#arg_closure", ptr %0) !dbg !320 {
entry:
  %result_value6 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !321
  %result_value5 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !321
  %result_value = alloca { [0 x i64], [3 x i64], i8, [7 x i8] }, align 8, !dbg !321
  %get_opaque_data_ptr2 = getelementptr inbounds { [0 x i64], [8 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, !dbg !321
  %load_element4.unpack.unpack = load ptr, ptr %get_opaque_data_ptr2, align 8, !dbg !321
  %1 = insertvalue %str.RocStr poison, ptr %load_element4.unpack.unpack, 0, !dbg !321
  %load_element4.unpack.elt10 = getelementptr inbounds { [0 x i64], [8 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, i64 1, !dbg !321
  %load_element4.unpack.unpack11 = load i64, ptr %load_element4.unpack.elt10, align 8, !dbg !321
  %2 = insertvalue %str.RocStr %1, i64 %load_element4.unpack.unpack11, 1, !dbg !321
  %load_element4.unpack.elt12 = getelementptr inbounds { [0 x i64], [8 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, i64 2, !dbg !321
  %load_element4.unpack.unpack13 = load i64, ptr %load_element4.unpack.elt12, align 8, !dbg !321
  %load_element4.unpack14 = insertvalue %str.RocStr %2, i64 %load_element4.unpack.unpack13, 2, !dbg !321
  %3 = insertvalue { %str.RocStr, {} } poison, %str.RocStr %load_element4.unpack14, 0, !dbg !321
  %load_element49 = insertvalue { %str.RocStr, {} } %3, {} poison, 1, !dbg !321
  call fastcc void @Effect_effect_map_inner_c8ee203993b19f9eeb79e6d9b9cb5c211fecc131b917baefe682bdc7d1dc7e({} zeroinitializer, { %str.RocStr, {} } %load_element49, ptr nonnull %result_value), !dbg !321
  call fastcc void @Task_53_3efb3241b6f76bcf29426c5d5647f69b665c3ac3b1fc474c237e0eea46afd1(ptr nonnull %result_value, {} poison, ptr nonnull %result_value5), !dbg !321
  call fastcc void @Effect_effect_always_inner_8256d790c99390129cd6628d4d43bc44f55cfb83af722d8248666b192be24d65({} zeroinitializer, ptr nonnull %result_value5, ptr nonnull %result_value6), !dbg !321
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value6, i64 64, i1 false), !dbg !321
  ret void, !dbg !321
}

define internal fastcc i8 @InternalHttp_methodFromStr_f2eb2e65858ef9a081c444e7b9b2cef1ed51b5a1e38027833034b9f057aa3131(ptr %str) !dbg !323 {
entry:
  %const_str_store41 = alloca %str.RocStr, align 8
  %const_str_store36 = alloca %str.RocStr, align 8
  %const_str_store31 = alloca %str.RocStr, align 8
  %const_str_store26 = alloca %str.RocStr, align 8
  %const_str_store21 = alloca %str.RocStr, align 8
  %const_str_store16 = alloca %str.RocStr, align 8
  %const_str_store11 = alloca %str.RocStr, align 8
  %const_str_store6 = alloca %str.RocStr, align 8
  %const_str_store1 = alloca %str.RocStr, align 8
  %const_str_store = alloca %str.RocStr, align 8
  store ptr inttoptr (i64 32491047111389263 to ptr), ptr %const_str_store, align 8, !dbg !324
  %const_str_store.repack42 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 1, !dbg !324
  store i64 0, ptr %const_str_store.repack42, align 8, !dbg !324
  %const_str_store.repack43 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 2, !dbg !324
  store i64 -8718968878589280256, ptr %const_str_store.repack43, align 8, !dbg !324
  %call_builtin = call i1 @roc_builtins.str.equal(ptr nocapture nonnull readonly %const_str_store, ptr nocapture readonly %str), !dbg !324
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %const_str_store), !dbg !324
  br i1 %call_builtin, label %then_block, label %else_block, !dbg !324

then_block:                                       ; preds = %entry
  ret i8 4, !dbg !324

else_block:                                       ; preds = %entry
  store ptr inttoptr (i64 7628103 to ptr), ptr %const_str_store1, align 8, !dbg !324
  %const_str_store1.repack44 = getelementptr inbounds %str.RocStr, ptr %const_str_store1, i64 0, i32 1, !dbg !324
  store i64 0, ptr %const_str_store1.repack44, align 8, !dbg !324
  %const_str_store1.repack45 = getelementptr inbounds %str.RocStr, ptr %const_str_store1, i64 0, i32 2, !dbg !324
  store i64 -9007199254740992000, ptr %const_str_store1.repack45, align 8, !dbg !324
  %call_builtin2 = call i1 @roc_builtins.str.equal(ptr nocapture nonnull readonly %const_str_store1, ptr nocapture readonly %str), !dbg !324
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %const_str_store1), !dbg !324
  br i1 %call_builtin2, label %then_block4, label %else_block5, !dbg !324

then_block4:                                      ; preds = %else_block
  ret i8 2, !dbg !324

else_block5:                                      ; preds = %else_block
  store ptr inttoptr (i64 1953722192 to ptr), ptr %const_str_store6, align 8, !dbg !324
  %const_str_store6.repack46 = getelementptr inbounds %str.RocStr, ptr %const_str_store6, i64 0, i32 1, !dbg !324
  store i64 0, ptr %const_str_store6.repack46, align 8, !dbg !324
  %const_str_store6.repack47 = getelementptr inbounds %str.RocStr, ptr %const_str_store6, i64 0, i32 2, !dbg !324
  store i64 -8935141660703064064, ptr %const_str_store6.repack47, align 8, !dbg !324
  %call_builtin7 = call i1 @roc_builtins.str.equal(ptr nocapture nonnull readonly %const_str_store6, ptr nocapture readonly %str), !dbg !324
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %const_str_store6), !dbg !324
  br i1 %call_builtin7, label %then_block9, label %else_block10, !dbg !324

then_block9:                                      ; preds = %else_block5
  ret i8 6, !dbg !324

else_block10:                                     ; preds = %else_block5
  store ptr inttoptr (i64 7632208 to ptr), ptr %const_str_store11, align 8, !dbg !324
  %const_str_store11.repack48 = getelementptr inbounds %str.RocStr, ptr %const_str_store11, i64 0, i32 1, !dbg !324
  store i64 0, ptr %const_str_store11.repack48, align 8, !dbg !324
  %const_str_store11.repack49 = getelementptr inbounds %str.RocStr, ptr %const_str_store11, i64 0, i32 2, !dbg !324
  store i64 -9007199254740992000, ptr %const_str_store11.repack49, align 8, !dbg !324
  %call_builtin12 = call i1 @roc_builtins.str.equal(ptr nocapture nonnull readonly %const_str_store11, ptr nocapture readonly %str), !dbg !324
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %const_str_store11), !dbg !324
  br i1 %call_builtin12, label %then_block14, label %else_block15, !dbg !324

then_block14:                                     ; preds = %else_block10
  ret i8 7, !dbg !324

else_block15:                                     ; preds = %else_block10
  store ptr inttoptr (i64 111550592214340 to ptr), ptr %const_str_store16, align 8, !dbg !324
  %const_str_store16.repack50 = getelementptr inbounds %str.RocStr, ptr %const_str_store16, i64 0, i32 1, !dbg !324
  store i64 0, ptr %const_str_store16.repack50, align 8, !dbg !324
  %const_str_store16.repack51 = getelementptr inbounds %str.RocStr, ptr %const_str_store16, i64 0, i32 2, !dbg !324
  store i64 -8791026472627208192, ptr %const_str_store16.repack51, align 8, !dbg !324
  %call_builtin17 = call i1 @roc_builtins.str.equal(ptr nocapture nonnull readonly %const_str_store16, ptr nocapture readonly %str), !dbg !324
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %const_str_store16), !dbg !324
  br i1 %call_builtin17, label %then_block19, label %else_block20, !dbg !324

then_block19:                                     ; preds = %else_block15
  ret i8 1, !dbg !324

else_block20:                                     ; preds = %else_block15
  store ptr inttoptr (i64 1684104520 to ptr), ptr %const_str_store21, align 8, !dbg !324
  %const_str_store21.repack52 = getelementptr inbounds %str.RocStr, ptr %const_str_store21, i64 0, i32 1, !dbg !324
  store i64 0, ptr %const_str_store21.repack52, align 8, !dbg !324
  %const_str_store21.repack53 = getelementptr inbounds %str.RocStr, ptr %const_str_store21, i64 0, i32 2, !dbg !324
  store i64 -8935141660703064064, ptr %const_str_store21.repack53, align 8, !dbg !324
  %call_builtin22 = call i1 @roc_builtins.str.equal(ptr nocapture nonnull readonly %const_str_store21, ptr nocapture readonly %str), !dbg !324
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %const_str_store21), !dbg !324
  br i1 %call_builtin22, label %then_block24, label %else_block25, !dbg !324

then_block24:                                     ; preds = %else_block20
  ret i8 3, !dbg !324

else_block25:                                     ; preds = %else_block20
  store ptr inttoptr (i64 435459027540 to ptr), ptr %const_str_store26, align 8, !dbg !324
  %const_str_store26.repack54 = getelementptr inbounds %str.RocStr, ptr %const_str_store26, i64 0, i32 1, !dbg !324
  store i64 0, ptr %const_str_store26.repack54, align 8, !dbg !324
  %const_str_store26.repack55 = getelementptr inbounds %str.RocStr, ptr %const_str_store26, i64 0, i32 2, !dbg !324
  store i64 -8863084066665136128, ptr %const_str_store26.repack55, align 8, !dbg !324
  %call_builtin27 = call i1 @roc_builtins.str.equal(ptr nocapture nonnull readonly %const_str_store26, ptr nocapture readonly %str), !dbg !324
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %const_str_store26), !dbg !324
  br i1 %call_builtin27, label %then_block29, label %else_block30, !dbg !324

then_block29:                                     ; preds = %else_block25
  ret i8 8, !dbg !324

else_block30:                                     ; preds = %else_block25
  store ptr inttoptr (i64 32760384594014019 to ptr), ptr %const_str_store31, align 8, !dbg !324
  %const_str_store31.repack56 = getelementptr inbounds %str.RocStr, ptr %const_str_store31, i64 0, i32 1, !dbg !324
  store i64 0, ptr %const_str_store31.repack56, align 8, !dbg !324
  %const_str_store31.repack57 = getelementptr inbounds %str.RocStr, ptr %const_str_store31, i64 0, i32 2, !dbg !324
  store i64 -8718968878589280256, ptr %const_str_store31.repack57, align 8, !dbg !324
  %call_builtin32 = call i1 @roc_builtins.str.equal(ptr nocapture nonnull readonly %const_str_store31, ptr nocapture readonly %str), !dbg !324
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %const_str_store31), !dbg !324
  br i1 %call_builtin32, label %then_block34, label %else_block35, !dbg !324

then_block34:                                     ; preds = %else_block30
  ret i8 0, !dbg !324

else_block35:                                     ; preds = %else_block30
  store ptr inttoptr (i64 448345170256 to ptr), ptr %const_str_store36, align 8, !dbg !324
  %const_str_store36.repack58 = getelementptr inbounds %str.RocStr, ptr %const_str_store36, i64 0, i32 1, !dbg !324
  store i64 0, ptr %const_str_store36.repack58, align 8, !dbg !324
  %const_str_store36.repack59 = getelementptr inbounds %str.RocStr, ptr %const_str_store36, i64 0, i32 2, !dbg !324
  store i64 -8863084066665136128, ptr %const_str_store36.repack59, align 8, !dbg !324
  %call_builtin37 = call i1 @roc_builtins.str.equal(ptr nocapture nonnull readonly %const_str_store36, ptr nocapture readonly %str), !dbg !324
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %const_str_store36), !dbg !324
  br i1 %call_builtin37, label %then_block39, label %else_block40, !dbg !324

then_block39:                                     ; preds = %else_block35
  ret i8 5, !dbg !324

else_block40:                                     ; preds = %else_block35
  store ptr getelementptr inbounds ([37 x i8], ptr @_str_literal_821981871794291864, i64 0, i64 8), ptr %const_str_store41, align 8, !dbg !324
  %const_str_store41.repack60 = getelementptr inbounds %str.RocStr, ptr %const_str_store41, i64 0, i32 1, !dbg !324
  store i64 29, ptr %const_str_store41.repack60, align 8, !dbg !324
  %const_str_store41.repack61 = getelementptr inbounds %str.RocStr, ptr %const_str_store41, i64 0, i32 2, !dbg !324
  store i64 29, ptr %const_str_store41.repack61, align 8, !dbg !324
  call void @roc_panic(ptr %const_str_store41, i32 1), !dbg !324
  unreachable, !dbg !324
}

define internal fastcc void @Task_ok_9d55cb5018ba494bcf5765953355c83e4ade148e5c95b280aacd826c59bea86(ptr %a, ptr %0) !dbg !326 {
entry:
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  call fastcc void @InternalTask_ok_b6812cd4831336785c4d2d6d371d74081a04d666ecb415ede62b278451858a9(ptr %a, ptr nonnull %result_value), !dbg !327
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value, i64 64, i1 false), !dbg !327
  ret void, !dbg !327
}

define internal fastcc void @Effect_after_4ec88c32b1d8d7e41af6fe2c3b1c519c1adff81ec271f8be7bf4ea491e1(ptr %"115", {} %effect_after_toEffect, ptr %0) !dbg !329 {
entry:
  %struct_alloca = alloca { { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, {} }, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %struct_alloca, ptr noundef nonnull align 8 dereferenceable(120) %"115", i64 120, i1 false), !dbg !330
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %struct_alloca, i64 120, i1 false), !dbg !330
  ret void, !dbg !330
}

define internal fastcc void @Task_53_3efb3241b6f76bcf29426c5d5647f69b665c3ac3b1fc474c237e0eea46afd1(ptr %res, {} %transform, ptr %0) !dbg !332 {
entry:
  %result_value7 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !333
  %result_value6 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !333
  %load_element5 = alloca %str.RocStr, align 8, !dbg !333
  %result_value2 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !333
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !333
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [3 x i64], i8, [7 x i8] }, ptr %res, i64 0, i32 2, !dbg !333
  %load_tag_id = load i8, ptr %tag_id_ptr, align 1, !dbg !333
  %eq_u8 = icmp eq i8 %load_tag_id, 1, !dbg !333
  br i1 %eq_u8, label %then_block, label %else_block, !dbg !333

then_block:                                       ; preds = %entry
  call fastcc void @"#UserApp_11_1fee66ad667b912c4d10ada5f77fb9e8b2dfe9a4124f957b34ae7bc684ecaf1"({} poison, ptr nonnull %result_value), !dbg !333
  call fastcc void @InternalTask_toEffect_8719a5fa4a4d2d7fe17773695c6c6d3ecd8b7cfffd135c8d4ca89f29f876d1f(ptr nonnull %result_value, ptr nonnull %result_value2), !dbg !333
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value2, i64 64, i1 false), !dbg !333
  ret void, !dbg !333

else_block:                                       ; preds = %entry
  %get_opaque_data_ptr3 = getelementptr inbounds { [0 x i64], [3 x i64], i8, [7 x i8] }, ptr %res, i64 0, i32 1, !dbg !333
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %load_element5, ptr noundef nonnull align 8 dereferenceable(24) %get_opaque_data_ptr3, i64 24, i1 false), !dbg !333
  call fastcc void @Task_err_e26b07323a88152db96f57cffd313b88dda6eb16db54bca99d36e02da3083(ptr nonnull %load_element5, ptr nonnull %result_value6), !dbg !333
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %load_element5), !dbg !333
  call fastcc void @InternalTask_toEffect_8719a5fa4a4d2d7fe17773695c6c6d3ecd8b7cfffd135c8d4ca89f29f876d1f(ptr nonnull %result_value6, ptr nonnull %result_value7), !dbg !333
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value7, i64 64, i1 false), !dbg !333
  ret void, !dbg !333
}

define internal fastcc { { { %str.RocStr, {} }, {} }, {} } @_init_c6e34737223a4b123e4ef4b086ad92b3ead64b519536ae28b552b4718b7124e() !dbg !335 {
entry:
  %call = tail call fastcc { { { %str.RocStr, {} }, {} }, {} } @"#UserApp_server_52aff1341cf42f5e6559a2cf028663f7bbbc7576ac1948fc58784a0613b79"(), !dbg !336
  %struct_field_access_record_0 = extractvalue { { { %str.RocStr, {} }, {} }, {} } %call, 0, !dbg !336
  %call1 = tail call fastcc { { { %str.RocStr, {} }, {} }, {} } @Task_attempt_dce3401669119d7f5da9e070669694c78f88efb14a471223494f7d677db1e7d({ { %str.RocStr, {} }, {} } %struct_field_access_record_0, {} zeroinitializer), !dbg !336
  ret { { { %str.RocStr, {} }, {} }, {} } %call1, !dbg !336
}

define internal fastcc { %str.RocStr, {} } @InternalTask_toEffect_260dec8de9897e99a5126b882cbb9d2ee2f32cd2b94c727fdd1aa87e467d({ %str.RocStr, {} } %"13") !dbg !338 {
entry:
  ret { %str.RocStr, {} } %"13", !dbg !339
}

define internal fastcc void @Task_44_12a8ad799c7b34402483623f9b421f07775e1054bb6bfcf2ae122184609a(ptr %res, {} %transform, ptr %0) !dbg !341 {
entry:
  %result_value12 = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !342
  %result_value11 = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !342
  %tag_alloca8 = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !342
  %result_value3 = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !342
  %result_value = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !342
  %tag_alloca = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !342
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %res, i64 0, i32 2, !dbg !342
  %load_tag_id = load i8, ptr %tag_id_ptr, align 1, !dbg !342
  %eq_u8 = icmp eq i8 %load_tag_id, 1, !dbg !342
  br i1 %eq_u8, label %then_block, label %else_block, !dbg !342

then_block:                                       ; preds = %entry
  %tag_id_ptr2 = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !342
  store i8 1, ptr %tag_id_ptr2, align 8, !dbg !342
  call fastcc void @_13_c852b6d75d2364d70d094699f8a9cda9129d5310ed82ea45564f47a9(ptr nonnull %tag_alloca, ptr nonnull %result_value), !dbg !342
  call fastcc void @InternalTask_toEffect_935229af12e1c6ee752a73f7b73add5a7c7a22cfba9e577e778e240ed627a(ptr nonnull %result_value, ptr nonnull %result_value3), !dbg !342
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %result_value3, i64 48, i1 false), !dbg !342
  ret void, !dbg !342

else_block:                                       ; preds = %entry
  %get_opaque_data_ptr4 = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %res, i64 0, i32 1, !dbg !342
  %load_element6 = load { %str.RocStr, i32 }, ptr %get_opaque_data_ptr4, align 8, !dbg !342
  %data_buffer9 = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %tag_alloca8, i64 0, i32 1, !dbg !342
  store { %str.RocStr, i32 } %load_element6, ptr %data_buffer9, align 8, !dbg !342
  %tag_id_ptr10 = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %tag_alloca8, i64 0, i32 2, !dbg !342
  store i8 0, ptr %tag_id_ptr10, align 8, !dbg !342
  call fastcc void @_13_c852b6d75d2364d70d094699f8a9cda9129d5310ed82ea45564f47a9(ptr nonnull %tag_alloca8, ptr nonnull %result_value11), !dbg !342
  call fastcc void @InternalTask_toEffect_935229af12e1c6ee752a73f7b73add5a7c7a22cfba9e577e778e240ed627a(ptr nonnull %result_value11, ptr nonnull %result_value12), !dbg !342
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %result_value12, i64 48, i1 false), !dbg !342
  ret void, !dbg !342
}

define internal fastcc void @Task_err_e26b07323a88152db96f57cffd313b88dda6eb16db54bca99d36e02da3083(ptr %a, ptr %0) !dbg !344 {
entry:
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  call fastcc void @InternalTask_err_61e5a13d423d566ac5e547894554a8bcf8bc44e60405c767b71c7c83a1e2c55(ptr %a, ptr nonnull %result_value), !dbg !345
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value, i64 64, i1 false), !dbg !345
  ret void, !dbg !345
}

define internal fastcc void @List_iterate_7cfa03e91e0ec9327f388a68dbd26ae2735e7e95165f9e519543e02299bee9(%list.RocList %list, {} %init, i128 %func, ptr %0) !dbg !347 {
entry:
  %result_value = alloca { [0 x i8], [0 x i8], i8, [0 x i8] }, align 8, !dbg !348
  %call = tail call fastcc i64 @List_len_e4f9cf3a6c4e3d6be9d05048391b2e3975855fa3e34f66d41fe2c9a84e5c7b(%list.RocList %list), !dbg !348
  call fastcc void @List_iterHelp_676ec9e417566a851359c2c6d5d5332f7d40742f8274a8672f3cad244846(%list.RocList %list, {} %init, i128 %func, i64 0, i64 %call, ptr nonnull %result_value), !dbg !348
  %1 = load i8, ptr %result_value, align 8, !dbg !348
  store i8 %1, ptr %0, align 1, !dbg !348
  ret void, !dbg !348
}

define internal fastcc i1 @List_contains_4fe2c0cee861629d2ef04c3f725dba5813b563598f88e6fe57cefd4dd1a133(%list.RocList %list, i128 %needle) !dbg !350 {
entry:
  %call = tail call fastcc i1 @List_any_926c4e1deae44cb32fa91b0fc2f966fdf98af98ee562517f2d5df6cc1b8bf0(%list.RocList %list, i128 %needle), !dbg !351
  ret i1 %call, !dbg !351
}

define internal fastcc void @InternalDateTime_epochMillisToDateTimeHelp_684393a95528f29ba49a721c9e7bd2dbf82e1a92e5b742ec5b556b18be7657(ptr %"67", ptr %0) !dbg !353 {
entry:
  %tmp_output_for_jmp178 = alloca { i128, i128, i128, i128, i128, i128 }, align 16
  %struct_alloca171 = alloca { i128, i128, i128, i128, i128, i128 }, align 16
  %tmp_output_for_jmp135 = alloca { i128, i128, i128, i128, i128, i128 }, align 16
  %struct_alloca128 = alloca { i128, i128, i128, i128, i128, i128 }, align 16
  %tmp_output_for_jmp107 = alloca { i128, i128, i128, i128, i128, i128 }, align 16
  %struct_alloca100 = alloca { i128, i128, i128, i128, i128, i128 }, align 16
  %tmp_output_for_jmp79 = alloca { i128, i128, i128, i128, i128, i128 }, align 16
  %struct_alloca72 = alloca { i128, i128, i128, i128, i128, i128 }, align 16
  %tmp_output_for_jmp51 = alloca { i128, i128, i128, i128, i128, i128 }, align 16
  %struct_alloca = alloca { i128, i128, i128, i128, i128, i128 }, align 16
  %tmp_output_for_jmp = alloca { i128, i128, i128, i128, i128, i128 }, align 16
  %joinpoint_arg_alloca = alloca { i128, i128, i128, i128, i128, i128 }, align 16
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %tmp_output_for_jmp, ptr noundef nonnull align 16 dereferenceable(96) %"67", i64 96, i1 false), !dbg !354
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %joinpoint_arg_alloca, ptr noundef nonnull align 16 dereferenceable(96) %tmp_output_for_jmp, i64 96, i1 false), !dbg !354
  br label %joinpointcont, !dbg !354

joinpointcont:                                    ; preds = %joinpointcont163, %then_block112, %then_block84, %then_block56, %joinpointcont38, %entry
  %struct_field_access_record_5 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 5, !dbg !354
  %struct_field = load i128, ptr %struct_field_access_record_5, align 16, !dbg !354
  %struct_field_access_record_3 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 3, !dbg !354
  %struct_field1 = load i128, ptr %struct_field_access_record_3, align 16, !dbg !354
  %call = tail call fastcc i128 @InternalDateTime_daysInMonth_4a2d194da1241ef3ca5a8139a734b29ae4efb20126643584c91fe6ded8e2c5a(i128 %struct_field, i128 %struct_field1), !dbg !354
  %call5 = tail call fastcc i1 @Bool_structuralEq_2cc6e6d3c5a48a76ea218c439d44b6318e7bd267419a22dcb25b258a2c06a(i128 %struct_field1, i128 1), !dbg !354
  br i1 %call5, label %then_block, label %else_block, !dbg !354

then_block:                                       ; preds = %joinpointcont
  %struct_field_access_record_56 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 5, !dbg !354
  %struct_field7 = load i128, ptr %struct_field_access_record_56, align 16, !dbg !354
  %call8 = tail call fastcc i128 @Num_sub_e84248fb50d0833361d0417df114b0b3b3448fff97c39cdde963b09a9aebb8(i128 %struct_field7, i128 1), !dbg !354
  %call9 = tail call fastcc i128 @InternalDateTime_daysInMonth_4a2d194da1241ef3ca5a8139a734b29ae4efb20126643584c91fe6ded8e2c5a(i128 %call8, i128 12), !dbg !354
  br label %joinpointcont2, !dbg !354

else_block:                                       ; preds = %joinpointcont
  %struct_field_access_record_510 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 5, !dbg !354
  %struct_field11 = load i128, ptr %struct_field_access_record_510, align 16, !dbg !354
  %struct_field_access_record_312 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 3, !dbg !354
  %struct_field13 = load i128, ptr %struct_field_access_record_312, align 16, !dbg !354
  %call14 = tail call fastcc i128 @Num_sub_e84248fb50d0833361d0417df114b0b3b3448fff97c39cdde963b09a9aebb8(i128 %struct_field13, i128 1), !dbg !354
  %call15 = tail call fastcc i128 @InternalDateTime_daysInMonth_4a2d194da1241ef3ca5a8139a734b29ae4efb20126643584c91fe6ded8e2c5a(i128 %struct_field11, i128 %call14), !dbg !354
  br label %joinpointcont2, !dbg !354

joinpointcont2:                                   ; preds = %else_block, %then_block
  %joinpointarg = phi i128 [ %call9, %then_block ], [ %call15, %else_block ], !dbg !354
  %struct_field16 = load i128, ptr %joinpoint_arg_alloca, align 16, !dbg !354
  %call17 = tail call fastcc i1 @Num_isLt_f273102d33b910ab8b1eda6e483bb587ec34372c3562cd9bfb68bcf889ba9cd(i128 %struct_field16, i128 1), !dbg !354
  br i1 %call17, label %then_block18, label %else_block19, !dbg !354

then_block18:                                     ; preds = %joinpointcont2
  %struct_field21 = load i128, ptr %joinpoint_arg_alloca, align 16, !dbg !354
  %struct_field_access_record_1 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 1, !dbg !354
  %struct_field22 = load i128, ptr %struct_field_access_record_1, align 16, !dbg !354
  %struct_field_access_record_2 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 2, !dbg !354
  %struct_field23 = load i128, ptr %struct_field_access_record_2, align 16, !dbg !354
  %struct_field_access_record_324 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 3, !dbg !354
  %struct_field25 = load i128, ptr %struct_field_access_record_324, align 16, !dbg !354
  %struct_field_access_record_4 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 4, !dbg !354
  %struct_field26 = load i128, ptr %struct_field_access_record_4, align 16, !dbg !354
  %struct_field_access_record_527 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 5, !dbg !354
  %struct_field28 = load i128, ptr %struct_field_access_record_527, align 16, !dbg !354
  %call31 = tail call fastcc i1 @Bool_structuralEq_2cc6e6d3c5a48a76ea218c439d44b6318e7bd267419a22dcb25b258a2c06a(i128 %struct_field25, i128 1), !dbg !354
  br i1 %call31, label %then_block33, label %else_block34, !dbg !354

else_block19:                                     ; preds = %joinpointcont2
  %struct_field_access_record_152 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 1, !dbg !354
  %struct_field53 = load i128, ptr %struct_field_access_record_152, align 16, !dbg !354
  %call54 = tail call fastcc i1 @Num_isLt_f273102d33b910ab8b1eda6e483bb587ec34372c3562cd9bfb68bcf889ba9cd(i128 %struct_field53, i128 0), !dbg !354
  br i1 %call54, label %then_block56, label %else_block57, !dbg !354

then_block33:                                     ; preds = %then_block18
  %call35 = tail call fastcc i128 @Num_sub_e84248fb50d0833361d0417df114b0b3b3448fff97c39cdde963b09a9aebb8(i128 %struct_field28, i128 1), !dbg !354
  br label %joinpointcont29, !dbg !354

else_block34:                                     ; preds = %then_block18
  %struct_field_access_record_536 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 5, !dbg !354
  %struct_field37 = load i128, ptr %struct_field_access_record_536, align 16, !dbg !354
  br label %joinpointcont29, !dbg !354

joinpointcont29:                                  ; preds = %else_block34, %then_block33
  %joinpointarg30 = phi i128 [ %call35, %then_block33 ], [ %struct_field37, %else_block34 ], !dbg !354
  %call40 = tail call fastcc i1 @Bool_structuralEq_2cc6e6d3c5a48a76ea218c439d44b6318e7bd267419a22dcb25b258a2c06a(i128 %struct_field25, i128 1), !dbg !354
  br i1 %call40, label %then_block42, label %else_block43, !dbg !354

then_block42:                                     ; preds = %joinpointcont29
  br label %joinpointcont38, !dbg !354

else_block43:                                     ; preds = %joinpointcont29
  %call44 = tail call fastcc i128 @Num_sub_e84248fb50d0833361d0417df114b0b3b3448fff97c39cdde963b09a9aebb8(i128 %struct_field25, i128 1), !dbg !354
  br label %joinpointcont38, !dbg !354

joinpointcont38:                                  ; preds = %else_block43, %then_block42
  %joinpointarg39 = phi i128 [ 12, %then_block42 ], [ %call44, %else_block43 ], !dbg !354
  %call45 = tail call fastcc i128 @Num_add_669c1355a3e727bb53dd458f2e96e48571aa45dfabcfb4b7de1689484f11(i128 %struct_field21, i128 %joinpointarg), !dbg !354
  store i128 %call45, ptr %struct_alloca, align 16, !dbg !354
  %struct_field_gep46 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca, i64 0, i32 1, !dbg !354
  store i128 %struct_field22, ptr %struct_field_gep46, align 16, !dbg !354
  %struct_field_gep47 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca, i64 0, i32 2, !dbg !354
  store i128 %struct_field23, ptr %struct_field_gep47, align 16, !dbg !354
  %struct_field_gep48 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca, i64 0, i32 3, !dbg !354
  store i128 %joinpointarg39, ptr %struct_field_gep48, align 16, !dbg !354
  %struct_field_gep49 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca, i64 0, i32 4, !dbg !354
  store i128 %struct_field26, ptr %struct_field_gep49, align 16, !dbg !354
  %struct_field_gep50 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca, i64 0, i32 5, !dbg !354
  store i128 %joinpointarg30, ptr %struct_field_gep50, align 16, !dbg !354
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %tmp_output_for_jmp51, ptr noundef nonnull align 16 dereferenceable(96) %struct_alloca, i64 96, i1 false), !dbg !354
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %joinpoint_arg_alloca, ptr noundef nonnull align 16 dereferenceable(96) %tmp_output_for_jmp51, i64 96, i1 false), !dbg !354
  br label %joinpointcont, !dbg !354

then_block56:                                     ; preds = %else_block19
  %struct_field59 = load i128, ptr %joinpoint_arg_alloca, align 16, !dbg !354
  %struct_field_access_record_160 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 1, !dbg !354
  %struct_field61 = load i128, ptr %struct_field_access_record_160, align 16, !dbg !354
  %struct_field_access_record_262 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 2, !dbg !354
  %struct_field63 = load i128, ptr %struct_field_access_record_262, align 16, !dbg !354
  %struct_field_access_record_364 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 3, !dbg !354
  %struct_field65 = load i128, ptr %struct_field_access_record_364, align 16, !dbg !354
  %struct_field_access_record_466 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 4, !dbg !354
  %struct_field67 = load i128, ptr %struct_field_access_record_466, align 16, !dbg !354
  %struct_field_access_record_568 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 5, !dbg !354
  %struct_field69 = load i128, ptr %struct_field_access_record_568, align 16, !dbg !354
  %call70 = tail call fastcc i128 @Num_add_669c1355a3e727bb53dd458f2e96e48571aa45dfabcfb4b7de1689484f11(i128 %struct_field61, i128 24), !dbg !354
  %call71 = tail call fastcc i128 @Num_sub_e84248fb50d0833361d0417df114b0b3b3448fff97c39cdde963b09a9aebb8(i128 %struct_field59, i128 1), !dbg !354
  store i128 %call71, ptr %struct_alloca72, align 16, !dbg !354
  %struct_field_gep74 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca72, i64 0, i32 1, !dbg !354
  store i128 %call70, ptr %struct_field_gep74, align 16, !dbg !354
  %struct_field_gep75 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca72, i64 0, i32 2, !dbg !354
  store i128 %struct_field63, ptr %struct_field_gep75, align 16, !dbg !354
  %struct_field_gep76 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca72, i64 0, i32 3, !dbg !354
  store i128 %struct_field65, ptr %struct_field_gep76, align 16, !dbg !354
  %struct_field_gep77 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca72, i64 0, i32 4, !dbg !354
  store i128 %struct_field67, ptr %struct_field_gep77, align 16, !dbg !354
  %struct_field_gep78 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca72, i64 0, i32 5, !dbg !354
  store i128 %struct_field69, ptr %struct_field_gep78, align 16, !dbg !354
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %tmp_output_for_jmp79, ptr noundef nonnull align 16 dereferenceable(96) %struct_alloca72, i64 96, i1 false), !dbg !354
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %joinpoint_arg_alloca, ptr noundef nonnull align 16 dereferenceable(96) %tmp_output_for_jmp79, i64 96, i1 false), !dbg !354
  br label %joinpointcont, !dbg !354

else_block57:                                     ; preds = %else_block19
  %struct_field_access_record_280 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 2, !dbg !354
  %struct_field81 = load i128, ptr %struct_field_access_record_280, align 16, !dbg !354
  %call82 = tail call fastcc i1 @Num_isLt_f273102d33b910ab8b1eda6e483bb587ec34372c3562cd9bfb68bcf889ba9cd(i128 %struct_field81, i128 0), !dbg !354
  br i1 %call82, label %then_block84, label %else_block85, !dbg !354

then_block84:                                     ; preds = %else_block57
  %struct_field87 = load i128, ptr %joinpoint_arg_alloca, align 16, !dbg !354
  %struct_field_access_record_188 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 1, !dbg !354
  %struct_field89 = load i128, ptr %struct_field_access_record_188, align 16, !dbg !354
  %struct_field_access_record_290 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 2, !dbg !354
  %struct_field91 = load i128, ptr %struct_field_access_record_290, align 16, !dbg !354
  %struct_field_access_record_392 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 3, !dbg !354
  %struct_field93 = load i128, ptr %struct_field_access_record_392, align 16, !dbg !354
  %struct_field_access_record_494 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 4, !dbg !354
  %struct_field95 = load i128, ptr %struct_field_access_record_494, align 16, !dbg !354
  %struct_field_access_record_596 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 5, !dbg !354
  %struct_field97 = load i128, ptr %struct_field_access_record_596, align 16, !dbg !354
  %call98 = tail call fastcc i128 @Num_add_669c1355a3e727bb53dd458f2e96e48571aa45dfabcfb4b7de1689484f11(i128 %struct_field91, i128 60), !dbg !354
  %call99 = tail call fastcc i128 @Num_sub_e84248fb50d0833361d0417df114b0b3b3448fff97c39cdde963b09a9aebb8(i128 %struct_field89, i128 1), !dbg !354
  store i128 %struct_field87, ptr %struct_alloca100, align 16, !dbg !354
  %struct_field_gep102 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca100, i64 0, i32 1, !dbg !354
  store i128 %call99, ptr %struct_field_gep102, align 16, !dbg !354
  %struct_field_gep103 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca100, i64 0, i32 2, !dbg !354
  store i128 %call98, ptr %struct_field_gep103, align 16, !dbg !354
  %struct_field_gep104 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca100, i64 0, i32 3, !dbg !354
  store i128 %struct_field93, ptr %struct_field_gep104, align 16, !dbg !354
  %struct_field_gep105 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca100, i64 0, i32 4, !dbg !354
  store i128 %struct_field95, ptr %struct_field_gep105, align 16, !dbg !354
  %struct_field_gep106 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca100, i64 0, i32 5, !dbg !354
  store i128 %struct_field97, ptr %struct_field_gep106, align 16, !dbg !354
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %tmp_output_for_jmp107, ptr noundef nonnull align 16 dereferenceable(96) %struct_alloca100, i64 96, i1 false), !dbg !354
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %joinpoint_arg_alloca, ptr noundef nonnull align 16 dereferenceable(96) %tmp_output_for_jmp107, i64 96, i1 false), !dbg !354
  br label %joinpointcont, !dbg !354

else_block85:                                     ; preds = %else_block57
  %struct_field_access_record_4108 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 4, !dbg !354
  %struct_field109 = load i128, ptr %struct_field_access_record_4108, align 16, !dbg !354
  %call110 = tail call fastcc i1 @Num_isLt_f273102d33b910ab8b1eda6e483bb587ec34372c3562cd9bfb68bcf889ba9cd(i128 %struct_field109, i128 0), !dbg !354
  br i1 %call110, label %then_block112, label %else_block113, !dbg !354

then_block112:                                    ; preds = %else_block85
  %struct_field115 = load i128, ptr %joinpoint_arg_alloca, align 16, !dbg !354
  %struct_field_access_record_1116 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 1, !dbg !354
  %struct_field117 = load i128, ptr %struct_field_access_record_1116, align 16, !dbg !354
  %struct_field_access_record_2118 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 2, !dbg !354
  %struct_field119 = load i128, ptr %struct_field_access_record_2118, align 16, !dbg !354
  %struct_field_access_record_3120 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 3, !dbg !354
  %struct_field121 = load i128, ptr %struct_field_access_record_3120, align 16, !dbg !354
  %struct_field_access_record_4122 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 4, !dbg !354
  %struct_field123 = load i128, ptr %struct_field_access_record_4122, align 16, !dbg !354
  %struct_field_access_record_5124 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 5, !dbg !354
  %struct_field125 = load i128, ptr %struct_field_access_record_5124, align 16, !dbg !354
  %call126 = tail call fastcc i128 @Num_add_669c1355a3e727bb53dd458f2e96e48571aa45dfabcfb4b7de1689484f11(i128 %struct_field123, i128 60), !dbg !354
  %call127 = tail call fastcc i128 @Num_sub_e84248fb50d0833361d0417df114b0b3b3448fff97c39cdde963b09a9aebb8(i128 %struct_field119, i128 1), !dbg !354
  store i128 %struct_field115, ptr %struct_alloca128, align 16, !dbg !354
  %struct_field_gep130 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca128, i64 0, i32 1, !dbg !354
  store i128 %struct_field117, ptr %struct_field_gep130, align 16, !dbg !354
  %struct_field_gep131 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca128, i64 0, i32 2, !dbg !354
  store i128 %call127, ptr %struct_field_gep131, align 16, !dbg !354
  %struct_field_gep132 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca128, i64 0, i32 3, !dbg !354
  store i128 %struct_field121, ptr %struct_field_gep132, align 16, !dbg !354
  %struct_field_gep133 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca128, i64 0, i32 4, !dbg !354
  store i128 %call126, ptr %struct_field_gep133, align 16, !dbg !354
  %struct_field_gep134 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca128, i64 0, i32 5, !dbg !354
  store i128 %struct_field125, ptr %struct_field_gep134, align 16, !dbg !354
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %tmp_output_for_jmp135, ptr noundef nonnull align 16 dereferenceable(96) %struct_alloca128, i64 96, i1 false), !dbg !354
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %joinpoint_arg_alloca, ptr noundef nonnull align 16 dereferenceable(96) %tmp_output_for_jmp135, i64 96, i1 false), !dbg !354
  br label %joinpointcont, !dbg !354

else_block113:                                    ; preds = %else_block85
  %struct_field137 = load i128, ptr %joinpoint_arg_alloca, align 16, !dbg !354
  %call138 = tail call fastcc i1 @Num_isGt_7f7e162ee4345c12acb2c8dddfd129c8c9ef562ecb31841cfff13d4789ffc2(i128 %struct_field137, i128 %call), !dbg !354
  br i1 %call138, label %then_block140, label %else_block141, !dbg !354

then_block140:                                    ; preds = %else_block113
  %struct_field143 = load i128, ptr %joinpoint_arg_alloca, align 16, !dbg !354
  %struct_field_access_record_1144 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 1, !dbg !354
  %struct_field145 = load i128, ptr %struct_field_access_record_1144, align 16, !dbg !354
  %struct_field_access_record_2146 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 2, !dbg !354
  %struct_field147 = load i128, ptr %struct_field_access_record_2146, align 16, !dbg !354
  %struct_field_access_record_3148 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 3, !dbg !354
  %struct_field149 = load i128, ptr %struct_field_access_record_3148, align 16, !dbg !354
  %struct_field_access_record_4150 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 4, !dbg !354
  %struct_field151 = load i128, ptr %struct_field_access_record_4150, align 16, !dbg !354
  %struct_field_access_record_5152 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 5, !dbg !354
  %struct_field153 = load i128, ptr %struct_field_access_record_5152, align 16, !dbg !354
  %call156 = tail call fastcc i1 @Bool_structuralEq_2cc6e6d3c5a48a76ea218c439d44b6318e7bd267419a22dcb25b258a2c06a(i128 %struct_field149, i128 12), !dbg !354
  br i1 %call156, label %then_block158, label %else_block159, !dbg !354

else_block141:                                    ; preds = %else_block113
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %0, ptr noundef nonnull align 16 dereferenceable(96) %joinpoint_arg_alloca, i64 96, i1 false), !dbg !354
  ret void, !dbg !354

then_block158:                                    ; preds = %then_block140
  %call160 = tail call fastcc i128 @Num_add_669c1355a3e727bb53dd458f2e96e48571aa45dfabcfb4b7de1689484f11(i128 %struct_field153, i128 1), !dbg !354
  br label %joinpointcont154, !dbg !354

else_block159:                                    ; preds = %then_block140
  %struct_field_access_record_5161 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %joinpoint_arg_alloca, i64 0, i32 5, !dbg !354
  %struct_field162 = load i128, ptr %struct_field_access_record_5161, align 16, !dbg !354
  br label %joinpointcont154, !dbg !354

joinpointcont154:                                 ; preds = %else_block159, %then_block158
  %joinpointarg155 = phi i128 [ %call160, %then_block158 ], [ %struct_field162, %else_block159 ], !dbg !354
  %call165 = tail call fastcc i1 @Bool_structuralEq_2cc6e6d3c5a48a76ea218c439d44b6318e7bd267419a22dcb25b258a2c06a(i128 %struct_field149, i128 12), !dbg !354
  br i1 %call165, label %then_block167, label %else_block168, !dbg !354

then_block167:                                    ; preds = %joinpointcont154
  br label %joinpointcont163, !dbg !354

else_block168:                                    ; preds = %joinpointcont154
  %call169 = tail call fastcc i128 @Num_add_669c1355a3e727bb53dd458f2e96e48571aa45dfabcfb4b7de1689484f11(i128 %struct_field149, i128 1), !dbg !354
  br label %joinpointcont163, !dbg !354

joinpointcont163:                                 ; preds = %else_block168, %then_block167
  %joinpointarg164 = phi i128 [ 1, %then_block167 ], [ %call169, %else_block168 ], !dbg !354
  %call170 = tail call fastcc i128 @Num_sub_e84248fb50d0833361d0417df114b0b3b3448fff97c39cdde963b09a9aebb8(i128 %struct_field143, i128 %call), !dbg !354
  store i128 %call170, ptr %struct_alloca171, align 16, !dbg !354
  %struct_field_gep173 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca171, i64 0, i32 1, !dbg !354
  store i128 %struct_field145, ptr %struct_field_gep173, align 16, !dbg !354
  %struct_field_gep174 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca171, i64 0, i32 2, !dbg !354
  store i128 %struct_field147, ptr %struct_field_gep174, align 16, !dbg !354
  %struct_field_gep175 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca171, i64 0, i32 3, !dbg !354
  store i128 %joinpointarg164, ptr %struct_field_gep175, align 16, !dbg !354
  %struct_field_gep176 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca171, i64 0, i32 4, !dbg !354
  store i128 %struct_field151, ptr %struct_field_gep176, align 16, !dbg !354
  %struct_field_gep177 = getelementptr inbounds { i128, i128, i128, i128, i128, i128 }, ptr %struct_alloca171, i64 0, i32 5, !dbg !354
  store i128 %joinpointarg155, ptr %struct_field_gep177, align 16, !dbg !354
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %tmp_output_for_jmp178, ptr noundef nonnull align 16 dereferenceable(96) %struct_alloca171, i64 96, i1 false), !dbg !354
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(96) %joinpoint_arg_alloca, ptr noundef nonnull align 16 dereferenceable(96) %tmp_output_for_jmp178, i64 96, i1 false), !dbg !354
  br label %joinpointcont, !dbg !354
}

define internal fastcc void @_149_481f1278f2de6c4b7025bbe3547d9acb112f26631793a1e4c8c76b99b179e0({} %"151", ptr %"#arg_closure", ptr %0) !dbg !356 {
entry:
  %result_value = alloca { %list.RocList, %list.RocList, i16 }, align 8
  call fastcc void @Effect_effect_after_inner_268182e6bf48c34ea8893d1d91dfdfbbcae7ca2eb5c9a5136f7f2958cb888df({} %"151", ptr %"#arg_closure", ptr nonnull %result_value), !dbg !357
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %0, ptr noundef nonnull align 8 dereferenceable(56) %result_value, i64 56, i1 false), !dbg !357
  ret void, !dbg !357
}

define internal fastcc {} @InternalDateTime_secondsWithPaddedZeros_5d26e7953422ce84aac56171b489e0deedf33db4e08b81dcad67e7427bff49() !dbg !359 {
entry:
  ret {} zeroinitializer, !dbg !360
}

define internal fastcc { { { { %str.RocStr, {} }, {} }, {} }, {} } @_forHost_494fd63e81fc5377dff396b856cc43fac283edbeae4d7cfbdd95aadb8479597() !dbg !362 {
entry:
  %call = tail call fastcc { { { %str.RocStr, {} }, {} }, {} } @_init_c6e34737223a4b123e4ef4b086ad92b3ead64b519536ae28b552b4718b7124e(), !dbg !363
  %insert_record_field = insertvalue { { { { %str.RocStr, {} }, {} }, {} }, {} } zeroinitializer, { { { %str.RocStr, {} }, {} }, {} } %call, 0, !dbg !363
  %insert_record_field1 = insertvalue { { { { %str.RocStr, {} }, {} }, {} }, {} } %insert_record_field, {} zeroinitializer, 1, !dbg !363
  ret { { { { %str.RocStr, {} }, {} }, {} }, {} } %insert_record_field1, !dbg !363
}

define void @roc__forHost_1_exposed_generic(ptr %0) !dbg !365 {
entry:
  %call = call fastcc { { { { %str.RocStr, {} }, {} }, {} }, {} } @_forHost_494fd63e81fc5377dff396b856cc43fac283edbeae4d7cfbdd95aadb8479597(), !dbg !366
  store { { { { %str.RocStr, {} }, {} }, {} }, {} } %call, ptr %0, align 8, !dbg !366
  ret void, !dbg !366
}

define void @roc__forHost_1_exposed(ptr sret({ { { { %str.RocStr, {} }, {} }, {} }, {} }) %0) !dbg !368 {
entry:
  %call = call fastcc { { { { %str.RocStr, {} }, {} }, {} }, {} } @_forHost_494fd63e81fc5377dff396b856cc43fac283edbeae4d7cfbdd95aadb8479597(), !dbg !369
  store { { { { %str.RocStr, {} }, {} }, {} }, {} } %call, ptr %0, align 8, !dbg !369
  ret void, !dbg !369
}

define i64 @roc__forHost_1_exposed_size() !dbg !371 {
entry:
  ret i64 ptrtoint (ptr getelementptr ({ { { { %str.RocStr, {} }, {} }, {} }, {} }, ptr null, i32 1) to i64), !dbg !372
}

define internal fastcc i1 @Bool_true_68697e959be5e5da06cc73b6f998e193cbf2d9b22efd0355a3d37129951b() !dbg !374 {
entry:
  ret i1 true, !dbg !375
}

define internal fastcc void @InternalTask_fromEffect_ea724491503a37367f3396489f19ddb4ed26c1b122d1bb85553bb555a0a4d(ptr %effect, ptr %0) !dbg !377 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %effect, i64 120, i1 false), !dbg !378
  ret void, !dbg !378
}

define internal fastcc i1 @List_161_3bbacd33228bca14fe5573efe7278cde33c78fe9028ba98810cff368dece(i128 %x, i128 %needle) !dbg !380 {
entry:
  %call = tail call fastcc i1 @Bool_structuralEq_2cc6e6d3c5a48a76ea218c439d44b6318e7bd267419a22dcb25b258a2c06a(i128 %x, i128 %needle), !dbg !381
  ret i1 %call, !dbg !381
}

define internal fastcc i1 @InternalDateTime_isLeapYear_a9e685cc72fe3166dd93f93a27166ec5656562cf1d6d3e19f41a6cc3489(i128 %year) !dbg !383 {
entry:
  %call = tail call fastcc i128 @Num_rem_cabb163ea8b383114bab450f2ea4bdf6f97d5dc22e57b593db81e3bce47(i128 %year, i128 4), !dbg !384
  %call1 = tail call fastcc i1 @Bool_structuralEq_2cc6e6d3c5a48a76ea218c439d44b6318e7bd267419a22dcb25b258a2c06a(i128 %call, i128 0), !dbg !384
  %call2 = tail call fastcc i128 @Num_rem_cabb163ea8b383114bab450f2ea4bdf6f97d5dc22e57b593db81e3bce47(i128 %year, i128 100), !dbg !384
  %call3 = tail call fastcc i1 @Bool_isNotEq_91183c4be76c8c6e9a1aca423ca6b7bdfddc155d7aac337b8db73395e0e64d(i128 %call2, i128 0), !dbg !384
  %call4 = tail call fastcc i128 @Num_rem_cabb163ea8b383114bab450f2ea4bdf6f97d5dc22e57b593db81e3bce47(i128 %year, i128 400), !dbg !384
  %call5 = tail call fastcc i1 @Bool_structuralEq_2cc6e6d3c5a48a76ea218c439d44b6318e7bd267419a22dcb25b258a2c06a(i128 %call4, i128 0), !dbg !384
  %call6 = tail call fastcc i1 @Bool_or_52459ae5e05017996bb4298dd9ac3944ffe997fa2e2ad98ba6fd7348395f63(i1 %call3, i1 %call5), !dbg !384
  %call7 = tail call fastcc i1 @Bool_and_078eba49b7090dbd2c6fb82297218e6d2eb88883fa33ff213b919f6e68cc(i1 %call1, i1 %call6), !dbg !384
  ret i1 %call7, !dbg !384
}

define internal fastcc void @InternalTask_ok_b6812cd4831336785c4d2d6d371d74081a04d666ecb415ede62b278451858a9(ptr %a, ptr %0) !dbg !386 {
entry:
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  %tag_alloca = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  %struct_alloca = alloca { { %list.RocList, %list.RocList, i16 } }, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %struct_alloca, ptr noundef nonnull align 8 dereferenceable(56) %a, i64 56, i1 false), !dbg !387
  %data_buffer = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !387
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %data_buffer, ptr noundef nonnull align 8 dereferenceable(56) %struct_alloca, i64 56, i1 false), !dbg !387
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !387
  store i8 1, ptr %tag_id_ptr, align 8, !dbg !387
  call fastcc void @Effect_always_deda9c07093181a3aee6f4559463a94ce2b31f038cb3d5548d0bb2aeba37e1(ptr nonnull %tag_alloca, ptr nonnull %result_value), !dbg !387
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value, i64 64, i1 false), !dbg !387
  ret void, !dbg !387
}

define internal fastcc void @Effect_effect_after_inner_1414869acb920f6db8ce61389f4b2ab8ee18505e1ddd7ea302888aec917e({} %"179", ptr %"#arg_closure", ptr %0) !dbg !389 {
entry:
  %result_value6 = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !390
  %result_value5 = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !390
  %result_value = alloca { [0 x i32], [4 x i8], i8, [3 x i8] }, align 8, !dbg !390
  %load_element = alloca { [0 x i32], [4 x i8], i8, [3 x i8] }, align 8, !dbg !390
  %get_opaque_data_ptr1 = getelementptr inbounds { [0 x i64], [5 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, i64 4, !dbg !390
  %1 = load i64, ptr %get_opaque_data_ptr1, align 4, !dbg !390
  store i64 %1, ptr %load_element, align 8, !dbg !390
  %get_opaque_data_ptr2 = getelementptr inbounds { [0 x i64], [5 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, !dbg !390
  %load_element4.unpack.unpack.unpack = load ptr, ptr %get_opaque_data_ptr2, align 8, !dbg !390
  %2 = insertvalue %str.RocStr poison, ptr %load_element4.unpack.unpack.unpack, 0, !dbg !390
  %load_element4.unpack.unpack.elt13 = getelementptr inbounds { [0 x i64], [5 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, i64 1, !dbg !390
  %load_element4.unpack.unpack.unpack14 = load i64, ptr %load_element4.unpack.unpack.elt13, align 8, !dbg !390
  %3 = insertvalue %str.RocStr %2, i64 %load_element4.unpack.unpack.unpack14, 1, !dbg !390
  %load_element4.unpack.unpack.elt15 = getelementptr inbounds { [0 x i64], [5 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, i64 2, !dbg !390
  %load_element4.unpack.unpack.unpack16 = load i64, ptr %load_element4.unpack.unpack.elt15, align 8, !dbg !390
  %load_element4.unpack.unpack17 = insertvalue %str.RocStr %3, i64 %load_element4.unpack.unpack.unpack16, 2, !dbg !390
  %4 = insertvalue { %str.RocStr, {} } poison, %str.RocStr %load_element4.unpack.unpack17, 0, !dbg !390
  %load_element4.unpack12 = insertvalue { %str.RocStr, {} } %4, {} poison, 1, !dbg !390
  %5 = insertvalue { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } poison, { %str.RocStr, {} } %load_element4.unpack12, 0, !dbg !390
  %load_element4.unpack8.elt18 = getelementptr inbounds { [0 x i64], [5 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, i64 3, !dbg !390
  %load_element4.unpack8.unpack19.unpack = load i8, ptr %load_element4.unpack8.elt18, align 8, !dbg !390
  %6 = insertvalue [4 x i8] poison, i8 %load_element4.unpack8.unpack19.unpack, 0, !dbg !390
  %load_element4.unpack8.unpack19.elt25 = getelementptr inbounds i8, ptr %"#arg_closure", i64 25, !dbg !390
  %load_element4.unpack8.unpack19.unpack26 = load i8, ptr %load_element4.unpack8.unpack19.elt25, align 1, !dbg !390
  %7 = insertvalue [4 x i8] %6, i8 %load_element4.unpack8.unpack19.unpack26, 1, !dbg !390
  %load_element4.unpack8.unpack19.elt27 = getelementptr inbounds i8, ptr %"#arg_closure", i64 26, !dbg !390
  %load_element4.unpack8.unpack19.unpack28 = load i8, ptr %load_element4.unpack8.unpack19.elt27, align 2, !dbg !390
  %8 = insertvalue [4 x i8] %7, i8 %load_element4.unpack8.unpack19.unpack28, 2, !dbg !390
  %load_element4.unpack8.unpack19.elt29 = getelementptr inbounds i8, ptr %"#arg_closure", i64 27, !dbg !390
  %load_element4.unpack8.unpack19.unpack30 = load i8, ptr %load_element4.unpack8.unpack19.elt29, align 1, !dbg !390
  %load_element4.unpack8.unpack1931 = insertvalue [4 x i8] %8, i8 %load_element4.unpack8.unpack19.unpack30, 3, !dbg !390
  %9 = insertvalue { [0 x i32], [4 x i8], i8, [3 x i8] } poison, [4 x i8] %load_element4.unpack8.unpack1931, 1, !dbg !390
  %load_element4.unpack8.elt20 = getelementptr inbounds i8, ptr %"#arg_closure", i64 28, !dbg !390
  %load_element4.unpack8.unpack21 = load i8, ptr %load_element4.unpack8.elt20, align 4, !dbg !390
  %10 = insertvalue { [0 x i32], [4 x i8], i8, [3 x i8] } %9, i8 %load_element4.unpack8.unpack21, 2, !dbg !390
  %load_element4.unpack8.elt22 = getelementptr inbounds i8, ptr %"#arg_closure", i64 29, !dbg !390
  %load_element4.unpack8.unpack23.unpack = load i8, ptr %load_element4.unpack8.elt22, align 1, !dbg !390
  %11 = insertvalue [3 x i8] poison, i8 %load_element4.unpack8.unpack23.unpack, 0, !dbg !390
  %load_element4.unpack8.unpack23.elt32 = getelementptr inbounds i8, ptr %"#arg_closure", i64 30, !dbg !390
  %load_element4.unpack8.unpack23.unpack33 = load i8, ptr %load_element4.unpack8.unpack23.elt32, align 1, !dbg !390
  %12 = insertvalue [3 x i8] %11, i8 %load_element4.unpack8.unpack23.unpack33, 1, !dbg !390
  %load_element4.unpack8.unpack23.elt34 = getelementptr inbounds i8, ptr %"#arg_closure", i64 31, !dbg !390
  %load_element4.unpack8.unpack23.unpack35 = load i8, ptr %load_element4.unpack8.unpack23.elt34, align 1, !dbg !390
  %load_element4.unpack8.unpack2336 = insertvalue [3 x i8] %12, i8 %load_element4.unpack8.unpack23.unpack35, 2, !dbg !390
  %load_element4.unpack824 = insertvalue { [0 x i32], [4 x i8], i8, [3 x i8] } %10, [3 x i8] %load_element4.unpack8.unpack2336, 3, !dbg !390
  %load_element49 = insertvalue { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %5, { [0 x i32], [4 x i8], i8, [3 x i8] } %load_element4.unpack824, 1, !dbg !390
  call fastcc void @Effect_effect_after_inner_4ef81b983bd7cde6bbc497dcbaeffcb1ff38a9d8bb9b208abb417910dc73a6d1({} zeroinitializer, { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %load_element49, ptr nonnull %result_value), !dbg !390
  call fastcc void @Task_53_48c2caee6f1010356bbec8845a6ee45f2928c63eece16acf25dc3f84dc5f6(ptr nonnull %result_value, ptr nonnull %load_element, ptr nonnull %result_value5), !dbg !390
  call fastcc void @Effect_effect_always_inner_8f804d847f17ce19e983ee3d457d4c97a1c72145f357931dcbff3cd6dbfe4c0({} zeroinitializer, ptr nonnull %result_value5, ptr nonnull %result_value6), !dbg !390
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %result_value6, i64 16, i1 false), !dbg !390
  ret void, !dbg !390
}

define internal fastcc void @Effect_always_6fe3723198a75889cb8af57c5c09ddd2b39fa52c21bf2b932afda892bd9e585(ptr %effect_always_value, ptr %0) !dbg !392 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %0, ptr noundef nonnull align 8 dereferenceable(56) %effect_always_value, i64 56, i1 false), !dbg !393
  ret void, !dbg !393
}

define internal fastcc void @Effect_always_94cb138d818e9947d7d69ef307378727ff7855e4de6723d27fc54d8e228050(ptr %effect_always_value, ptr %0) !dbg !395 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %effect_always_value, i64 16, i1 false), !dbg !396
  ret void, !dbg !396
}

define internal fastcc { { { %str.RocStr, {} }, {} }, {} } @"#UserApp_server_52aff1341cf42f5e6559a2cf028663f7bbbc7576ac1948fc58784a0613b79"() !dbg !398 {
entry:
  %call = tail call fastcc { { %str.RocStr, {} }, {} } @"#UserApp_init_8b8e749a7d5dc4035aed2d09b8b4ad59fac5ad694339521a2df23bf1ac35c3"(), !dbg !399
  %insert_record_field = insertvalue { { { %str.RocStr, {} }, {} }, {} } zeroinitializer, { { %str.RocStr, {} }, {} } %call, 0, !dbg !399
  %insert_record_field1 = insertvalue { { { %str.RocStr, {} }, {} }, {} } %insert_record_field, {} zeroinitializer, 1, !dbg !399
  ret { { { %str.RocStr, {} }, {} }, {} } %insert_record_field1, !dbg !399
}

define internal fastcc void @Effect_always_e7d224cfcafcc878740e4416f7931bf725f9fd3378f8c73d6a4dc1d8c8883f(ptr %effect_always_value, ptr %0) !dbg !401 {
entry:
  %tag_alloca = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !402
  %load_tag_to_put_in_struct.elt1 = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %effect_always_value, i64 0, i32 1, !dbg !402
  %load_tag_to_put_in_struct.unpack2.unpack = load i64, ptr %load_tag_to_put_in_struct.elt1, align 8, !dbg !402
  %load_tag_to_put_in_struct.elt3 = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %effect_always_value, i64 0, i32 2, !dbg !402
  %load_tag_to_put_in_struct.unpack4 = load i8, ptr %load_tag_to_put_in_struct.elt3, align 8, !dbg !402
  %load_tag_to_put_in_struct.elt5 = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %effect_always_value, i64 0, i32 3, !dbg !402
  %load_tag_to_put_in_struct.unpack6.unpack = load i8, ptr %load_tag_to_put_in_struct.elt5, align 1, !dbg !402
  %load_tag_to_put_in_struct.unpack6.elt9 = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %effect_always_value, i64 0, i32 3, i64 1, !dbg !402
  %load_tag_to_put_in_struct.unpack6.unpack10 = load i8, ptr %load_tag_to_put_in_struct.unpack6.elt9, align 1, !dbg !402
  %load_tag_to_put_in_struct.unpack6.elt11 = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %effect_always_value, i64 0, i32 3, i64 2, !dbg !402
  %load_tag_to_put_in_struct.unpack6.unpack12 = load i8, ptr %load_tag_to_put_in_struct.unpack6.elt11, align 1, !dbg !402
  %load_tag_to_put_in_struct.unpack6.elt13 = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %effect_always_value, i64 0, i32 3, i64 3, !dbg !402
  %load_tag_to_put_in_struct.unpack6.unpack14 = load i8, ptr %load_tag_to_put_in_struct.unpack6.elt13, align 1, !dbg !402
  %load_tag_to_put_in_struct.unpack6.elt15 = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %effect_always_value, i64 0, i32 3, i64 4, !dbg !402
  %load_tag_to_put_in_struct.unpack6.unpack16 = load i8, ptr %load_tag_to_put_in_struct.unpack6.elt15, align 1, !dbg !402
  %load_tag_to_put_in_struct.unpack6.elt17 = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %effect_always_value, i64 0, i32 3, i64 5, !dbg !402
  %load_tag_to_put_in_struct.unpack6.unpack18 = load i8, ptr %load_tag_to_put_in_struct.unpack6.elt17, align 1, !dbg !402
  %load_tag_to_put_in_struct.unpack6.elt19 = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %effect_always_value, i64 0, i32 3, i64 6, !dbg !402
  %load_tag_to_put_in_struct.unpack6.unpack20 = load i8, ptr %load_tag_to_put_in_struct.unpack6.elt19, align 1, !dbg !402
  store i64 %load_tag_to_put_in_struct.unpack2.unpack, ptr %tag_alloca, align 8, !dbg !402
  %data_buffer.repack24 = getelementptr inbounds { [0 x i64], [5 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, i64 1, !dbg !402
  store i8 %load_tag_to_put_in_struct.unpack4, ptr %data_buffer.repack24, align 8, !dbg !402
  %data_buffer.repack26 = getelementptr inbounds i8, ptr %tag_alloca, i64 9, !dbg !402
  store i8 %load_tag_to_put_in_struct.unpack6.unpack, ptr %data_buffer.repack26, align 1, !dbg !402
  %data_buffer.repack26.repack28 = getelementptr inbounds i8, ptr %tag_alloca, i64 10, !dbg !402
  store i8 %load_tag_to_put_in_struct.unpack6.unpack10, ptr %data_buffer.repack26.repack28, align 2, !dbg !402
  %data_buffer.repack26.repack30 = getelementptr inbounds i8, ptr %tag_alloca, i64 11, !dbg !402
  store i8 %load_tag_to_put_in_struct.unpack6.unpack12, ptr %data_buffer.repack26.repack30, align 1, !dbg !402
  %data_buffer.repack26.repack32 = getelementptr inbounds i8, ptr %tag_alloca, i64 12, !dbg !402
  store i8 %load_tag_to_put_in_struct.unpack6.unpack14, ptr %data_buffer.repack26.repack32, align 4, !dbg !402
  %data_buffer.repack26.repack34 = getelementptr inbounds i8, ptr %tag_alloca, i64 13, !dbg !402
  store i8 %load_tag_to_put_in_struct.unpack6.unpack16, ptr %data_buffer.repack26.repack34, align 1, !dbg !402
  %data_buffer.repack26.repack36 = getelementptr inbounds i8, ptr %tag_alloca, i64 14, !dbg !402
  store i8 %load_tag_to_put_in_struct.unpack6.unpack18, ptr %data_buffer.repack26.repack36, align 2, !dbg !402
  %data_buffer.repack26.repack38 = getelementptr inbounds i8, ptr %tag_alloca, i64 15, !dbg !402
  store i8 %load_tag_to_put_in_struct.unpack6.unpack20, ptr %data_buffer.repack26.repack38, align 1, !dbg !402
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [5 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !402
  store i8 1, ptr %tag_id_ptr, align 8, !dbg !402
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %tag_alloca, i64 48, i1 false), !dbg !402
  ret void, !dbg !402
}

define internal fastcc i64 @List_len_e4f9cf3a6c4e3d6be9d05048391b2e3975855fa3e34f66d41fe2c9a84e5c7b(%list.RocList %"#arg1") !dbg !404 {
entry:
  %list_len = extractvalue %list.RocList %"#arg1", 1, !dbg !405
  ret i64 %list_len, !dbg !405
}

define internal fastcc { { { %str.RocStr, {} }, {} }, {} } @InternalTask_fromEffect_df2d999242c7383735614c1ca7894e355776837c47b5a1272ceceba5a498db({ { { %str.RocStr, {} }, {} }, {} } %effect) !dbg !407 {
entry:
  ret { { { %str.RocStr, {} }, {} }, {} } %effect, !dbg !408
}

define internal fastcc void @Effect_effect_after_inner_aafde219d9d91ee7a575a5efa6c6154f3d42c85beb7780b41b4510548f4aaf({} %"179", ptr %"#arg_closure", ptr %0) !dbg !410 {
entry:
  %result_value3 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !411
  %result_value2 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !411
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !411
  %struct_field1 = alloca { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, align 8, !dbg !411
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %struct_field1, ptr noundef nonnull align 8 dereferenceable(120) %"#arg_closure", i64 120, i1 false), !dbg !411
  call fastcc void @Effect_effect_after_inner_dfab3e7e4dcf97947ada0f8abcfc248e78de1f269ac4599a46f8db36f6ed6aa({} zeroinitializer, ptr nonnull %struct_field1, ptr nonnull %result_value), !dbg !411
  call fastcc void @Task_92_42f43e247a90ff93dac3c860bb219ee18693539a6e942bad35bcb7297d6e16(ptr nonnull %result_value, ptr nonnull %result_value2), !dbg !411
  call fastcc void @Effect_effect_always_inner_8256d790c99390129cd6628d4d43bc44f55cfb83af722d8248666b192be24d65({} zeroinitializer, ptr nonnull %result_value2, ptr nonnull %result_value3), !dbg !411
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value3, i64 64, i1 false), !dbg !411
  ret void, !dbg !411
}

define internal fastcc { %str.RocStr, {} } @Effect_map_4bc296458c9e4dfa311cb236c399bfa4fbaacf1f1ce0be5dc9b3fb0e57fbf5(ptr %"116", {} %effect_map_mapper) !dbg !413 {
entry:
  tail call fastcc void @"#Attr_#inc_2"(ptr %"116", i64 1), !dbg !414
  %load_tag_to_put_in_struct.unpack = load ptr, ptr %"116", align 8, !dbg !414
  %0 = insertvalue %str.RocStr poison, ptr %load_tag_to_put_in_struct.unpack, 0, !dbg !414
  %load_tag_to_put_in_struct.elt2 = getelementptr inbounds %str.RocStr, ptr %"116", i64 0, i32 1, !dbg !414
  %load_tag_to_put_in_struct.unpack3 = load i64, ptr %load_tag_to_put_in_struct.elt2, align 8, !dbg !414
  %1 = insertvalue %str.RocStr %0, i64 %load_tag_to_put_in_struct.unpack3, 1, !dbg !414
  %load_tag_to_put_in_struct.elt4 = getelementptr inbounds %str.RocStr, ptr %"116", i64 0, i32 2, !dbg !414
  %load_tag_to_put_in_struct.unpack5 = load i64, ptr %load_tag_to_put_in_struct.elt4, align 8, !dbg !414
  %load_tag_to_put_in_struct6 = insertvalue %str.RocStr %1, i64 %load_tag_to_put_in_struct.unpack5, 2, !dbg !414
  %insert_record_field = insertvalue { %str.RocStr, {} } zeroinitializer, %str.RocStr %load_tag_to_put_in_struct6, 0, !dbg !414
  %insert_record_field1 = insertvalue { %str.RocStr, {} } %insert_record_field, {} %effect_map_mapper, 1, !dbg !414
  ret { %str.RocStr, {} } %insert_record_field1, !dbg !414
}

define internal fastcc i1 @Num_isGt_7f7e162ee4345c12acb2c8dddfd129c8c9ef562ecb31841cfff13d4789ffc2(i128 %"#arg1", i128 %"#arg2") !dbg !416 {
entry:
  %gt_int = icmp sgt i128 %"#arg1", %"#arg2", !dbg !417
  ret i1 %gt_int, !dbg !417
}

define internal fastcc void @Effect_effect_always_inner_6510a4d2b643dbf56ded4867b8cf49fe92c910e8961840e3a156bc971ee31a({} %"266", ptr %effect_always_value, ptr %0) !dbg !419 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %0, ptr noundef nonnull align 8 dereferenceable(56) %effect_always_value, i64 56, i1 false), !dbg !420
  ret void, !dbg !420
}

define internal fastcc void @Task_ok_4643e4e3b17ad449bf2144b916446512b17f621ba9fb35f1ed2ca53f5cb54e({} %a, ptr %0) !dbg !422 {
entry:
  %result_value = alloca { [0 x i32], [4 x i8], i8, [3 x i8] }, align 8
  call fastcc void @InternalTask_ok_21b5c7d5305aa5ff4df495f05c9e59c37d76367eacec9dd321a0e78143dfc4a3({} %a, ptr nonnull %result_value), !dbg !423
  %1 = load i64, ptr %result_value, align 8, !dbg !423
  store i64 %1, ptr %0, align 4, !dbg !423
  ret void, !dbg !423
}

define internal fastcc void @Task_ok_1971ed175c5339d8a493ee2a719f3ca8f50fbcc2a26feaf7b54a27898e3f({} %a, ptr %0) !dbg !425 {
entry:
  %result_value = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8
  call fastcc void @InternalTask_ok_1cd410b47325ca54fd4d13db9f372fff17944e80d3dc60ceb6fa212947a({} %a, ptr nonnull %result_value), !dbg !426
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %result_value, i64 40, i1 false), !dbg !426
  ret void, !dbg !426
}

define internal fastcc void @InternalTask_ok_a1fdfd7ca485c5e9436ed61186fef7b9b914edaf84deff48d9823fcadcd6ac(ptr %a, ptr %0) !dbg !428 {
entry:
  %result_value = alloca { %list.RocList, %list.RocList, i16 }, align 8
  call fastcc void @Effect_always_6fe3723198a75889cb8af57c5c09ddd2b39fa52c21bf2b932afda892bd9e585(ptr %a, ptr nonnull %result_value), !dbg !429
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %0, ptr noundef nonnull align 8 dereferenceable(56) %result_value, i64 56, i1 false), !dbg !429
  ret void, !dbg !429
}

define internal fastcc i128 @Effect_effect_map_inner_9bb8deca757dc2ac2fb673c9939099338c6d1fb2aae6cee85b52f30d7d2b2d8({} %"118", { {}, {} } %"#arg_closure") !dbg !431 {
entry:
  %call = tail call fastcc i128 @Effect_effect_closure_posixTime_1529b61b29181b37e427cd639d65060a33ef72662c4981e67e9c292331a({} zeroinitializer), !dbg !432
  %call1 = tail call fastcc i128 @Num_toI128_54b3c6d264e7c557f2fe74ef29431163e9a30a2e4aca38b681d4b9ee62de031(i128 %call), !dbg !432
  ret i128 %call1, !dbg !432
}

define internal fastcc i1 @Num_isZero_f57b151e8a6dfbc520c29ccc134c8fb5357cdd96058ecd185f0787f48b7a6(i128 %"#arg1") !dbg !434 {
entry:
  %eq_i128 = icmp eq i128 %"#arg1", 0, !dbg !435
  ret i1 %eq_i128, !dbg !435
}

define internal fastcc i1 @Num_isLt_f273102d33b910ab8b1eda6e483bb587ec34372c3562cd9bfb68bcf889ba9cd(i128 %"#arg1", i128 %"#arg2") !dbg !437 {
entry:
  %lt_int = icmp slt i128 %"#arg1", %"#arg2", !dbg !438
  ret i1 %lt_int, !dbg !438
}

define internal fastcc void @InternalTask_toEffect_28b81340646419744ffe2153acaa8e39d3c2d10c2a51eb5702318112c7c5(ptr %"13", ptr %0) !dbg !440 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %"13", i64 120, i1 false), !dbg !441
  ret void, !dbg !441
}

define internal fastcc i64 @Num_addWrap_e6845638e158b704aa8395d259110713932beb5d7a34137f5739ba7e3dd198(i64 %"#arg1", i64 %"#arg2") !dbg !443 {
entry:
  %add_int_wrap = add i64 %"#arg1", %"#arg2", !dbg !444
  ret i64 %add_int_wrap, !dbg !444
}

define internal fastcc void @_13_c852b6d75d2364d70d094699f8a9cda9129d5310ed82ea45564f47a9(ptr %res, ptr %0) !dbg !446 {
entry:
  %result_value17 = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !447
  %tag_alloca14 = alloca { [0 x i32], [4 x i8], i8, [3 x i8] }, align 8, !dbg !447
  %tag_alloca = alloca { [0 x i32], [4 x i8], i8, [3 x i8] }, align 8, !dbg !447
  %result_value9 = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !447
  %struct_field = alloca %str.RocStr, align 8, !dbg !447
  %result_value = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !447
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %res, i64 0, i32 2, !dbg !447
  %load_tag_id = load i8, ptr %tag_id_ptr, align 1, !dbg !447
  %eq_u8 = icmp eq i8 %load_tag_id, 1, !dbg !447
  br i1 %eq_u8, label %then_block, label %else_block, !dbg !447

then_block:                                       ; preds = %entry
  %call = tail call fastcc ptr @Box_box_d1a1e4356bd9fe6c31754def4c60a14042ade1c6c101618179cfd5d1c73189({} poison), !dbg !447
  call fastcc void @Task_ok_8445464738218c426e3b841f28ede2879d4391e6c33df6a616e872e199e47e(ptr %call, ptr nonnull %result_value), !dbg !447
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %result_value, i64 48, i1 false), !dbg !447
  ret void, !dbg !447

else_block:                                       ; preds = %entry
  %get_opaque_data_ptr2 = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %res, i64 0, i32 1, !dbg !447
  %load_element4 = load { %str.RocStr, i32 }, ptr %get_opaque_data_ptr2, align 8, !dbg !447
  %struct_field_access_record_0 = extractvalue { %str.RocStr, i32 } %load_element4, 0, !dbg !447
  %struct_field_access_record_0.elt = extractvalue %str.RocStr %struct_field_access_record_0, 0, !dbg !447
  store ptr %struct_field_access_record_0.elt, ptr %struct_field, align 8, !dbg !447
  %struct_field.repack34 = getelementptr inbounds %str.RocStr, ptr %struct_field, i64 0, i32 1, !dbg !447
  %struct_field_access_record_0.elt35 = extractvalue %str.RocStr %struct_field_access_record_0, 1, !dbg !447
  store i64 %struct_field_access_record_0.elt35, ptr %struct_field.repack34, align 8, !dbg !447
  %struct_field.repack36 = getelementptr inbounds %str.RocStr, ptr %struct_field, i64 0, i32 2, !dbg !447
  %struct_field_access_record_0.elt37 = extractvalue %str.RocStr %struct_field_access_record_0, 2, !dbg !447
  store i64 %struct_field_access_record_0.elt37, ptr %struct_field.repack36, align 8, !dbg !447
  %struct_field_access_record_1 = extractvalue { %str.RocStr, i32 } %load_element4, 1, !dbg !447
  %call5 = call fastcc i1 @Str_isEmpty_99aa979e4a9cadd6dbe48ea878ec84acb7696eb93470c375f6893f1da46c3772(ptr nonnull %struct_field), !dbg !447
  br i1 %call5, label %then_block7, label %else_block8, !dbg !447

then_block7:                                      ; preds = %else_block
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %struct_field), !dbg !447
  call fastcc void @Task_err_7f39af79a2c681124253a11db0202f701d4c3013db3c1272927c55405b9031(i32 %struct_field_access_record_1, ptr nonnull %result_value9), !dbg !447
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %result_value9, i64 48, i1 false), !dbg !447
  ret void, !dbg !447

else_block8:                                      ; preds = %else_block
  %call10 = call fastcc { %str.RocStr, {} } @Stderr_line_4bd18bc73cee8d6c664141b2e49674ebb21216aa20f0f89293181ce7b14e(ptr nonnull %struct_field), !dbg !447
  %data_buffer = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !447
  store i32 %struct_field_access_record_1, ptr %data_buffer, align 8, !dbg !447
  %tag_id_ptr11 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !447
  store i8 0, ptr %tag_id_ptr11, align 4, !dbg !447
  %call12 = call fastcc { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } @Task_onErr_7544714fcb8fdf9ddf55315cce78cf57de5a2d6621b01a7739ff24d9f60ac({ %str.RocStr, {} } %call10, ptr nonnull %tag_alloca), !dbg !447
  %data_buffer15 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %tag_alloca14, i64 0, i32 1, !dbg !447
  store i32 %struct_field_access_record_1, ptr %data_buffer15, align 8, !dbg !447
  %tag_id_ptr16 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %tag_alloca14, i64 0, i32 2, !dbg !447
  store i8 0, ptr %tag_id_ptr16, align 4, !dbg !447
  call fastcc void @Task_await_8e9956175ff8e3582c4b770a3b3c2388266676d8eb052d494e1a127bd7a9ad2({ { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %call12, ptr nonnull %tag_alloca14, ptr nonnull %result_value17), !dbg !447
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %result_value17, i64 48, i1 false), !dbg !447
  ret void, !dbg !447

joinpointcont:                                    ; No predecessors!
  ret void, !dbg !447
}

define internal fastcc i128 @Num_divTruncUnchecked_35bfe7dc6dba25ddadede12999f2a34775468912610779bf675f9c2d81ecac(i128 %"#arg1", i128 %"#arg2") !dbg !449 {
entry:
  %div_int = sdiv i128 %"#arg1", %"#arg2", !dbg !450
  ret i128 %div_int, !dbg !450
}

define internal fastcc i1 @Bool_false_4e123451c288c52798d3df0fc84811d2d957f324242982575c70dfd6d338df() !dbg !452 {
entry:
  ret i1 false, !dbg !453
}

define internal fastcc void @Effect_after_d9e2d7d318b97522751e8d862a897cd552d26040fa25d41678f9ac7b36cd7(ptr %"115", {} %effect_after_toEffect, ptr %0) !dbg !455 {
entry:
  %struct_alloca = alloca { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %struct_alloca, ptr noundef nonnull align 8 dereferenceable(120) %"115", i64 120, i1 false), !dbg !456
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %struct_alloca, i64 120, i1 false), !dbg !456
  ret void, !dbg !456
}

define internal fastcc i128 @Effect_effect_map_inner_f2e0cf21cda4e3c878e1ab216b192b2e2825d82c3b48a3a8bb6d7de6e7e20e({} %"118", { { {}, {} }, {} } %"#arg_closure") !dbg !458 {
entry:
  %struct_field_access_record_0 = extractvalue { { {}, {} }, {} } %"#arg_closure", 0, !dbg !459
  %call = tail call fastcc i128 @Effect_effect_map_inner_9bb8deca757dc2ac2fb673c9939099338c6d1fb2aae6cee85b52f30d7d2b2d8({} zeroinitializer, { {}, {} } %struct_field_access_record_0), !dbg !459
  %call1 = tail call fastcc i128 @Utc_11_edba1fc0cbfb8bc06ea89d458e5f5137027dfdf6bb865a3fbe3121562(i128 %call), !dbg !459
  ret i128 %call1, !dbg !459
}

define internal fastcc { %str.RocStr, {} } @InternalTask_toEffect_9c59e7328dd8975131b4ecbb517752a19f98ddf8f39456448f3da8e957ece54({ %str.RocStr, {} } %"13") !dbg !461 {
entry:
  ret { %str.RocStr, {} } %"13", !dbg !462
}

define internal fastcc void @Utc_toIso8601Str_46849c3b86f45f4f9e25198bc9b2ae6bcae76ebfbd692c6f18d9d9111cb9233c(i128 %"37", ptr %0) !dbg !464 {
entry:
  %result_value2 = alloca %str.RocStr, align 8, !dbg !465
  %result_value = alloca { i128, i128, i128, i128, i128, i128 }, align 16, !dbg !465
  %call = tail call fastcc i128 @Utc_nanosPerMilli_1bb73f6fafaa3656a8bf5796e2e6e6bdbd058375237d0b9be5834c8c9f54(), !dbg !465
  %call1 = tail call fastcc i128 @Num_divTrunc_cb411178cb7686889a4ee0e4b4c57e63975186dc9f1448b79e94c2721a21a2(i128 %"37", i128 %call), !dbg !465
  call fastcc void @InternalDateTime_epochMillisToDateTime_4e6df5a280208f8027d8c0e0fd95af1adf299ebd3666b6c48551dc0cb3c3214(i128 %call1, ptr nonnull %result_value), !dbg !465
  call fastcc void @InternalDateTime_toIso8601Str_8cf693340558d3441d6232b3632a0e7d41f8065e5f4ec1b10ba263a7452d728(ptr nonnull %result_value, ptr nonnull %result_value2), !dbg !465
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %result_value2, i64 24, i1 false), !dbg !465
  ret void, !dbg !465
}

define internal fastcc void @Task_await_c76509a58fbafc47f4d5fc1992204e92c831be8ebe1587d7baf160babfe2ad({ { { {}, {} }, {} }, {} } %task, ptr %transform, ptr %0) !dbg !467 {
entry:
  %result_value1 = alloca { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, align 8, !dbg !468
  %result_value = alloca { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, align 8, !dbg !468
  %call = tail call fastcc { { { {}, {} }, {} }, {} } @InternalTask_toEffect_c162bfc0bd74c841e2898960cc4e5160ab1032997985dd3fe7da33cf844631d({ { { {}, {} }, {} }, {} } %task), !dbg !468
  call fastcc void @Effect_after_f411d2d207cb75ff49124b128ee5a4cdec2daf8d1cf0a733c3c7d426729b6b({ { { {}, {} }, {} }, {} } %call, ptr %transform, ptr nonnull %result_value), !dbg !468
  call fastcc void @InternalTask_fromEffect_1a20a86e49e98265a07f2e3520fd72f1d5cc4a4259e669f8b2acf756122080(ptr nonnull %result_value, ptr nonnull %result_value1), !dbg !468
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %result_value1, i64 120, i1 false), !dbg !468
  ret void, !dbg !468
}

define internal fastcc void @InternalTask_toEffect_7e6da7233f16ea2c61d431e9d8c0a56499bf145a5210fb3d79ec4aba1f55c0a8(ptr %"13", ptr %0) !dbg !470 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %0, ptr noundef nonnull align 8 dereferenceable(56) %"13", i64 56, i1 false), !dbg !471
  ret void, !dbg !471
}

define internal fastcc { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } @Effect_after_a7deb1b6384ce9571721cd1522e1e931203f492c94f2dbf8138817d3824a({ %str.RocStr, {} } %"115", ptr %effect_after_toEffect) !dbg !473 {
entry:
  %load_tag_to_put_in_struct.elt2 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %effect_after_toEffect, i64 0, i32 1, !dbg !474
  %load_tag_to_put_in_struct.unpack3.unpack = load i8, ptr %load_tag_to_put_in_struct.elt2, align 4, !dbg !474
  %0 = insertvalue [4 x i8] poison, i8 %load_tag_to_put_in_struct.unpack3.unpack, 0, !dbg !474
  %load_tag_to_put_in_struct.unpack3.elt9 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %effect_after_toEffect, i64 0, i32 1, i64 1, !dbg !474
  %load_tag_to_put_in_struct.unpack3.unpack10 = load i8, ptr %load_tag_to_put_in_struct.unpack3.elt9, align 1, !dbg !474
  %1 = insertvalue [4 x i8] %0, i8 %load_tag_to_put_in_struct.unpack3.unpack10, 1, !dbg !474
  %load_tag_to_put_in_struct.unpack3.elt11 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %effect_after_toEffect, i64 0, i32 1, i64 2, !dbg !474
  %load_tag_to_put_in_struct.unpack3.unpack12 = load i8, ptr %load_tag_to_put_in_struct.unpack3.elt11, align 2, !dbg !474
  %2 = insertvalue [4 x i8] %1, i8 %load_tag_to_put_in_struct.unpack3.unpack12, 2, !dbg !474
  %load_tag_to_put_in_struct.unpack3.elt13 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %effect_after_toEffect, i64 0, i32 1, i64 3, !dbg !474
  %load_tag_to_put_in_struct.unpack3.unpack14 = load i8, ptr %load_tag_to_put_in_struct.unpack3.elt13, align 1, !dbg !474
  %load_tag_to_put_in_struct.unpack315 = insertvalue [4 x i8] %2, i8 %load_tag_to_put_in_struct.unpack3.unpack14, 3, !dbg !474
  %3 = insertvalue { [0 x i32], [4 x i8], i8, [3 x i8] } poison, [4 x i8] %load_tag_to_put_in_struct.unpack315, 1, !dbg !474
  %load_tag_to_put_in_struct.elt4 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %effect_after_toEffect, i64 0, i32 2, !dbg !474
  %load_tag_to_put_in_struct.unpack5 = load i8, ptr %load_tag_to_put_in_struct.elt4, align 4, !dbg !474
  %4 = insertvalue { [0 x i32], [4 x i8], i8, [3 x i8] } %3, i8 %load_tag_to_put_in_struct.unpack5, 2, !dbg !474
  %load_tag_to_put_in_struct.elt6 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %effect_after_toEffect, i64 0, i32 3, !dbg !474
  %load_tag_to_put_in_struct.unpack7.unpack = load i8, ptr %load_tag_to_put_in_struct.elt6, align 1, !dbg !474
  %5 = insertvalue [3 x i8] poison, i8 %load_tag_to_put_in_struct.unpack7.unpack, 0, !dbg !474
  %load_tag_to_put_in_struct.unpack7.elt16 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %effect_after_toEffect, i64 0, i32 3, i64 1, !dbg !474
  %load_tag_to_put_in_struct.unpack7.unpack17 = load i8, ptr %load_tag_to_put_in_struct.unpack7.elt16, align 1, !dbg !474
  %6 = insertvalue [3 x i8] %5, i8 %load_tag_to_put_in_struct.unpack7.unpack17, 1, !dbg !474
  %load_tag_to_put_in_struct.unpack7.elt18 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %effect_after_toEffect, i64 0, i32 3, i64 2, !dbg !474
  %load_tag_to_put_in_struct.unpack7.unpack19 = load i8, ptr %load_tag_to_put_in_struct.unpack7.elt18, align 1, !dbg !474
  %load_tag_to_put_in_struct.unpack720 = insertvalue [3 x i8] %6, i8 %load_tag_to_put_in_struct.unpack7.unpack19, 2, !dbg !474
  %load_tag_to_put_in_struct8 = insertvalue { [0 x i32], [4 x i8], i8, [3 x i8] } %4, [3 x i8] %load_tag_to_put_in_struct.unpack720, 3, !dbg !474
  %insert_record_field = insertvalue { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } zeroinitializer, { %str.RocStr, {} } %"115", 0, !dbg !474
  %insert_record_field1 = insertvalue { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %insert_record_field, { [0 x i32], [4 x i8], i8, [3 x i8] } %load_tag_to_put_in_struct8, 1, !dbg !474
  ret { { %str.RocStr, {} }, { [0 x i32], [4 x i8], i8, [3 x i8] } } %insert_record_field1, !dbg !474
}

define internal fastcc void @Effect_always_bc8306c1040a95f2dac252e82b64a88f9bbe8f51d564ae0c05ee47ab4dc64ec(ptr %effect_always_value, ptr %0) !dbg !476 {
entry:
  %tag_alloca = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  %struct_alloca = alloca { { %list.RocList, %list.RocList, i16 } }, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %struct_alloca, ptr noundef nonnull align 8 dereferenceable(56) %effect_always_value, i64 56, i1 false), !dbg !477
  %data_buffer = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !477
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %data_buffer, ptr noundef nonnull align 8 dereferenceable(56) %struct_alloca, i64 56, i1 false), !dbg !477
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !477
  store i8 1, ptr %tag_id_ptr, align 8, !dbg !477
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %tag_alloca, i64 64, i1 false), !dbg !477
  ret void, !dbg !477
}

define internal fastcc void @List_iterHelp_676ec9e417566a851359c2c6d5d5332f7d40742f8274a8672f3cad244846(%list.RocList %"86", {} %"87", i128 %"88", i64 %"89", i64 %"90", ptr %0) !dbg !479 {
entry:
  %tag_alloca16 = alloca { [0 x i8], [0 x i8], i8, [0 x i8] }, align 8, !dbg !480
  %tag_alloca = alloca { [0 x i8], [0 x i8], i8, [0 x i8] }, align 8, !dbg !480
  %result_value = alloca { [0 x i8], [0 x i8], i8, [0 x i8] }, align 8, !dbg !480
  tail call fastcc void @"#Attr_#inc_6"(%list.RocList %"86", i64 1), !dbg !480
  br label %joinpointcont, !dbg !480

joinpointcont:                                    ; preds = %then_block7, %entry
  %joinpointarg3 = phi i64 [ %"89", %entry ], [ %call10, %then_block7 ], !dbg !480
  %call = call fastcc i1 @Num_isLt_edaf1bd3d1c2ffcc44df55829c02f262426de2ffbea9be2cdf075ec12c528d(i64 %joinpointarg3, i64 %"90"), !dbg !480
  br i1 %call, label %then_block, label %else_block, !dbg !480

then_block:                                       ; preds = %joinpointcont
  %call5 = call fastcc i128 @List_getUnsafe_8acb95ddb9a746c2bf4dc0f4f96ce3b3e1f1e4f2559e7641b193db1f161d1c41(%list.RocList %"86", i64 %joinpointarg3), !dbg !480
  call fastcc void @List_looper_fb7917afe92ebaa35d275cfd557c2b25a5a46452e484a4eb8cac5175c61606d({} %"87", i128 %call5, i128 %"88", ptr nonnull %result_value), !dbg !480
  %tag_id_ptr = getelementptr inbounds { [0 x i8], [0 x i8], i8, [0 x i8] }, ptr %result_value, i64 0, i32 2, !dbg !480
  %load_tag_id = load i8, ptr %tag_id_ptr, align 8, !dbg !480
  %eq_u8 = icmp eq i8 %load_tag_id, 1, !dbg !480
  br i1 %eq_u8, label %then_block7, label %else_block8, !dbg !480

else_block:                                       ; preds = %joinpointcont
  call fastcc void @"#Attr_#dec_6"(%list.RocList %"86"), !dbg !480
  %tag_id_ptr18 = getelementptr inbounds { [0 x i8], [0 x i8], i8, [0 x i8] }, ptr %tag_alloca16, i64 0, i32 2, !dbg !480
  store i8 1, ptr %tag_id_ptr18, align 8, !dbg !480
  %1 = load i8, ptr %tag_alloca16, align 8, !dbg !480
  store i8 %1, ptr %0, align 1, !dbg !480
  ret void, !dbg !480

then_block7:                                      ; preds = %then_block
  %call10 = call fastcc i64 @Num_addWrap_e6845638e158b704aa8395d259110713932beb5d7a34137f5739ba7e3dd198(i64 %joinpointarg3, i64 1), !dbg !480
  br label %joinpointcont, !dbg !480

else_block8:                                      ; preds = %then_block
  call fastcc void @"#Attr_#dec_6"(%list.RocList %"86"), !dbg !480
  %tag_id_ptr14 = getelementptr inbounds { [0 x i8], [0 x i8], i8, [0 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !480
  store i8 0, ptr %tag_id_ptr14, align 8, !dbg !480
  %2 = load i8, ptr %tag_alloca, align 8, !dbg !480
  store i8 %2, ptr %0, align 1, !dbg !480
  ret void, !dbg !480
}

define internal fastcc i128 @Utc_11_edba1fc0cbfb8bc06ea89d458e5f5137027dfdf6bb865a3fbe3121562(i128 %"51") !dbg !482 {
entry:
  ret i128 %"51", !dbg !483
}

define internal fastcc {} @Effect_effect_closure_stderrLine_a0d5c44a91521ccbe6cbe0ca2338db7878e8dda81a27912b861f86434c26c052({} %"130", ptr %closure_arg_stderrLine_0) !dbg !485 {
entry:
  %call = tail call fastcc {} @roc_fx_stderrLine_fastcc_wrapper(ptr %closure_arg_stderrLine_0), !dbg !486
  tail call fastcc void @"#Attr_#dec_2"(ptr %closure_arg_stderrLine_0), !dbg !486
  ret {} %call, !dbg !486
}

define internal fastcc void @"#UserApp_11_1fee66ad667b912c4d10ada5f77fb9e8b2dfe9a4124f957b34ae7bc684ecaf1"({} %"21", ptr %0) !dbg !488 {
entry:
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  %struct_alloca = alloca { %list.RocList, %list.RocList, i16 }, align 8
  %const_str_store = alloca %str.RocStr, align 8
  store ptr inttoptr (i64 8028911417954296380 to ptr), ptr %const_str_store, align 8, !dbg !489
  %const_str_store.repack3 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 1, !dbg !489
  store i64 2406167339674837036, ptr %const_str_store.repack3, align 8, !dbg !489
  %const_str_store.repack4 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 2, !dbg !489
  store i64 -7710162518061994180, ptr %const_str_store.repack4, align 8, !dbg !489
  %call = call fastcc %list.RocList @Str_toUtf8_eabc27640eff330d625cb2f6435f5dccaec45dd590ad64015fdca105b70(ptr nonnull %const_str_store), !dbg !489
  %call.elt = extractvalue %list.RocList %call, 0, !dbg !489
  store ptr %call.elt, ptr %struct_alloca, align 8, !dbg !489
  %struct_alloca.repack5 = getelementptr inbounds %list.RocList, ptr %struct_alloca, i64 0, i32 1, !dbg !489
  %call.elt6 = extractvalue %list.RocList %call, 1, !dbg !489
  store i64 %call.elt6, ptr %struct_alloca.repack5, align 8, !dbg !489
  %struct_alloca.repack7 = getelementptr inbounds %list.RocList, ptr %struct_alloca, i64 0, i32 2, !dbg !489
  %call.elt8 = extractvalue %list.RocList %call, 2, !dbg !489
  store i64 %call.elt8, ptr %struct_alloca.repack7, align 8, !dbg !489
  %struct_field_gep1 = getelementptr inbounds { %list.RocList, %list.RocList, i16 }, ptr %struct_alloca, i64 0, i32 1, !dbg !489
  store ptr null, ptr %struct_field_gep1, align 8, !dbg !489
  %struct_field_gep1.repack9 = getelementptr inbounds { %list.RocList, %list.RocList, i16 }, ptr %struct_alloca, i64 0, i32 1, i32 1, !dbg !489
  store i64 0, ptr %struct_field_gep1.repack9, align 8, !dbg !489
  %struct_field_gep1.repack10 = getelementptr inbounds { %list.RocList, %list.RocList, i16 }, ptr %struct_alloca, i64 0, i32 1, i32 2, !dbg !489
  store i64 0, ptr %struct_field_gep1.repack10, align 8, !dbg !489
  %struct_field_gep2 = getelementptr inbounds { %list.RocList, %list.RocList, i16 }, ptr %struct_alloca, i64 0, i32 2, !dbg !489
  store i16 200, ptr %struct_field_gep2, align 8, !dbg !489
  call fastcc void @Task_ok_9d55cb5018ba494bcf5765953355c83e4ade148e5c95b280aacd826c59bea86(ptr nonnull %struct_alloca, ptr nonnull %result_value), !dbg !489
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value, i64 64, i1 false), !dbg !489
  ret void, !dbg !489
}

define internal fastcc void @Stdout_4_b7aa9f7d377b2692ada596045493ead6d491b934dc9015fcbdd1a8e01477d({} %"15", ptr %0) !dbg !491 {
entry:
  %tag_alloca = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [4 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !492
  store i8 1, ptr %tag_id_ptr, align 8, !dbg !492
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %tag_alloca, i64 40, i1 false), !dbg !492
  ret void, !dbg !492
}

define internal fastcc void @Effect_effect_map_inner_e4a1eb19d38152fc193a183edc36566d275fa494bf9c69e26c29c318cc289d0({} %"118", { %str.RocStr, {} } %"#arg_closure", ptr %0) !dbg !494 {
entry:
  %result_value = alloca { [0 x i64], [4 x i64], i8, [7 x i8] }, align 8, !dbg !495
  %struct_field = alloca %str.RocStr, align 8, !dbg !495
  %struct_field_access_record_0 = extractvalue { %str.RocStr, {} } %"#arg_closure", 0, !dbg !495
  %struct_field_access_record_0.elt = extractvalue %str.RocStr %struct_field_access_record_0, 0, !dbg !495
  store ptr %struct_field_access_record_0.elt, ptr %struct_field, align 8, !dbg !495
  %struct_field.repack1 = getelementptr inbounds %str.RocStr, ptr %struct_field, i64 0, i32 1, !dbg !495
  %struct_field_access_record_0.elt2 = extractvalue %str.RocStr %struct_field_access_record_0, 1, !dbg !495
  store i64 %struct_field_access_record_0.elt2, ptr %struct_field.repack1, align 8, !dbg !495
  %struct_field.repack3 = getelementptr inbounds %str.RocStr, ptr %struct_field, i64 0, i32 2, !dbg !495
  %struct_field_access_record_0.elt4 = extractvalue %str.RocStr %struct_field_access_record_0, 2, !dbg !495
  store i64 %struct_field_access_record_0.elt4, ptr %struct_field.repack3, align 8, !dbg !495
  %call = call fastcc {} @Effect_effect_closure_stdoutLine_622c9f939ebee86f480d73fdef56611b8899ab7e93ac9da07aeba3373394a({} zeroinitializer, ptr nonnull %struct_field), !dbg !495
  call fastcc void @Stdout_4_b7aa9f7d377b2692ada596045493ead6d491b934dc9015fcbdd1a8e01477d({} %call, ptr nonnull %result_value), !dbg !495
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %result_value, i64 40, i1 false), !dbg !495
  ret void, !dbg !495
}

define internal fastcc i128 @Num_add_669c1355a3e727bb53dd458f2e96e48571aa45dfabcfb4b7de1689484f11(i128 %"#arg1", i128 %"#arg2") !dbg !497 {
entry:
  %call = tail call { i128, i1 } @llvm.sadd.with.overflow.i128(i128 %"#arg1", i128 %"#arg2"), !dbg !498
  %has_overflowed = extractvalue { i128, i1 } %call, 1, !dbg !498
  br i1 %has_overflowed, label %throw_block, label %then_block, !dbg !498

then_block:                                       ; preds = %entry
  %operation_result = extractvalue { i128, i1 } %call, 0, !dbg !498
  ret i128 %operation_result, !dbg !498

throw_block:                                      ; preds = %entry
  tail call fastcc void @throw_on_overflow(), !dbg !498
  unreachable, !dbg !498
}

define internal fastcc { { { {}, {} }, {} }, {} } @InternalTask_toEffect_c162bfc0bd74c841e2898960cc4e5160ab1032997985dd3fe7da33cf844631d({ { { {}, {} }, {} }, {} } %"13") !dbg !500 {
entry:
  ret { { { {}, {} }, {} }, {} } %"13", !dbg !501
}

define internal fastcc { %str.RocStr, {} } @Effect_map_8523cacf79b3ae26b5b5ddfebda64fc7e54c53c82e133fab2e0abee3a1046(ptr %"116", {} %effect_map_mapper) !dbg !503 {
entry:
  tail call fastcc void @"#Attr_#inc_2"(ptr %"116", i64 1), !dbg !504
  %load_tag_to_put_in_struct.unpack = load ptr, ptr %"116", align 8, !dbg !504
  %0 = insertvalue %str.RocStr poison, ptr %load_tag_to_put_in_struct.unpack, 0, !dbg !504
  %load_tag_to_put_in_struct.elt2 = getelementptr inbounds %str.RocStr, ptr %"116", i64 0, i32 1, !dbg !504
  %load_tag_to_put_in_struct.unpack3 = load i64, ptr %load_tag_to_put_in_struct.elt2, align 8, !dbg !504
  %1 = insertvalue %str.RocStr %0, i64 %load_tag_to_put_in_struct.unpack3, 1, !dbg !504
  %load_tag_to_put_in_struct.elt4 = getelementptr inbounds %str.RocStr, ptr %"116", i64 0, i32 2, !dbg !504
  %load_tag_to_put_in_struct.unpack5 = load i64, ptr %load_tag_to_put_in_struct.elt4, align 8, !dbg !504
  %load_tag_to_put_in_struct6 = insertvalue %str.RocStr %1, i64 %load_tag_to_put_in_struct.unpack5, 2, !dbg !504
  %insert_record_field = insertvalue { %str.RocStr, {} } zeroinitializer, %str.RocStr %load_tag_to_put_in_struct6, 0, !dbg !504
  %insert_record_field1 = insertvalue { %str.RocStr, {} } %insert_record_field, {} %effect_map_mapper, 1, !dbg !504
  ret { %str.RocStr, {} } %insert_record_field1, !dbg !504
}

define internal fastcc void @Effect_effect_always_inner_7ceb2e607d153edd175217b82e8ded113c6e4df27e27777d9f9694c716aa427({} %"266", ptr %effect_always_value, ptr %0) !dbg !506 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %effect_always_value, i64 40, i1 false), !dbg !507
  ret void, !dbg !507
}

define internal fastcc i1 @List_any_926c4e1deae44cb32fa91b0fc2f966fdf98af98ee562517f2d5df6cc1b8bf0(%list.RocList %list, i128 %predicate) !dbg !509 {
entry:
  %result_value = alloca { [0 x i8], [0 x i8], i8, [0 x i8] }, align 8
  call fastcc void @List_iterate_7cfa03e91e0ec9327f388a68dbd26ae2735e7e95165f9e519543e02299bee9(%list.RocList %list, {} zeroinitializer, i128 %predicate, ptr nonnull %result_value), !dbg !510
  %tag_id_ptr = getelementptr inbounds { [0 x i8], [0 x i8], i8, [0 x i8] }, ptr %result_value, i64 0, i32 2, !dbg !510
  %load_tag_id = load i8, ptr %tag_id_ptr, align 8, !dbg !510
  %eq_u8 = icmp eq i8 %load_tag_id, 1, !dbg !510
  br i1 %eq_u8, label %then_block, label %else_block, !dbg !510

then_block:                                       ; preds = %entry
  %call = call fastcc i1 @Bool_false_4e123451c288c52798d3df0fc84811d2d957f324242982575c70dfd6d338df(), !dbg !510
  ret i1 %call, !dbg !510

else_block:                                       ; preds = %entry
  %call1 = call fastcc i1 @Bool_true_68697e959be5e5da06cc73b6f998e193cbf2d9b22efd0355a3d37129951b(), !dbg !510
  ret i1 %call1, !dbg !510
}

define internal fastcc {} @InternalDateTime_minutesWithPaddedZeros_44109459d64fcdac3ea0c7115c1a33caa6de3332a46a1f0819b84a1d3a6c9() !dbg !512 {
entry:
  ret {} zeroinitializer, !dbg !513
}

define internal fastcc i128 @Num_remUnchecked_dc3f621de1221c7c53a19e877c377561ede91cdd88b1a687d310a39785a(i128 %"#arg1", i128 %"#arg2") !dbg !515 {
entry:
  %rem_int = srem i128 %"#arg1", %"#arg2", !dbg !516
  ret i128 %rem_int, !dbg !516
}

define internal fastcc void @InternalTask_err_cd37899bb8a8d9e6a1967d5d098545d4623f55f4fb33fb81a429834acd2bca2(i32 %a, ptr %0) !dbg !518 {
entry:
  %result_value = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8, !dbg !519
  %tag_alloca = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !519
  %data_buffer = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !519
  store i32 %a, ptr %data_buffer, align 8, !dbg !519
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !519
  store i8 0, ptr %tag_id_ptr, align 8, !dbg !519
  call fastcc void @Effect_always_e7d224cfcafcc878740e4416f7931bf725f9fd3378f8c73d6a4dc1d8c8883f(ptr nonnull %tag_alloca, ptr nonnull %result_value), !dbg !519
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %result_value, i64 48, i1 false), !dbg !519
  ret void, !dbg !519
}

define internal fastcc void @Effect_effect_map_inner_c8ee203993b19f9eeb79e6d9b9cb5c211fecc131b917baefe682bdc7d1dc7e({} %"118", { %str.RocStr, {} } %"#arg_closure", ptr %0) !dbg !521 {
entry:
  %result_value = alloca { [0 x i64], [3 x i64], i8, [7 x i8] }, align 8, !dbg !522
  %struct_field = alloca %str.RocStr, align 8, !dbg !522
  %struct_field_access_record_0 = extractvalue { %str.RocStr, {} } %"#arg_closure", 0, !dbg !522
  %struct_field_access_record_0.elt = extractvalue %str.RocStr %struct_field_access_record_0, 0, !dbg !522
  store ptr %struct_field_access_record_0.elt, ptr %struct_field, align 8, !dbg !522
  %struct_field.repack1 = getelementptr inbounds %str.RocStr, ptr %struct_field, i64 0, i32 1, !dbg !522
  %struct_field_access_record_0.elt2 = extractvalue %str.RocStr %struct_field_access_record_0, 1, !dbg !522
  store i64 %struct_field_access_record_0.elt2, ptr %struct_field.repack1, align 8, !dbg !522
  %struct_field.repack3 = getelementptr inbounds %str.RocStr, ptr %struct_field, i64 0, i32 2, !dbg !522
  %struct_field_access_record_0.elt4 = extractvalue %str.RocStr %struct_field_access_record_0, 2, !dbg !522
  store i64 %struct_field_access_record_0.elt4, ptr %struct_field.repack3, align 8, !dbg !522
  %call = call fastcc {} @Effect_effect_closure_stdoutLine_622c9f939ebee86f480d73fdef56611b8899ab7e93ac9da07aeba3373394a({} zeroinitializer, ptr nonnull %struct_field), !dbg !522
  call fastcc void @Stdout_4_bad96aa871ccf5b068b2a1da7544fd3d07a932588efb92244e692b8beda99ce({} %call, ptr nonnull %result_value), !dbg !522
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(32) %0, ptr noundef nonnull align 8 dereferenceable(32) %result_value, i64 32, i1 false), !dbg !522
  ret void, !dbg !522
}

define internal fastcc void @InternalTask_toEffect_4d841bd57979ccceddece07dcf2dbc9edd3191f365637aa1e5efefa18c6c7ca3(ptr %"13", ptr %0) !dbg !524 {
entry:
  %1 = load i64, ptr %"13", align 4, !dbg !525
  store i64 %1, ptr %0, align 4, !dbg !525
  ret void, !dbg !525
}

define internal fastcc void @Task_60_e19be4977dae6e316e964ccb3f3519dc19317486f4e86b58a231a1854931186({} %res, ptr %transform, ptr %0) !dbg !527 {
entry:
  %result_value1 = alloca { [0 x i32], [4 x i8], i8, [3 x i8] }, align 8
  %result_value = alloca { [0 x i32], [4 x i8], i8, [3 x i8] }, align 8
  call fastcc void @Task_ok_4643e4e3b17ad449bf2144b916446512b17f621ba9fb35f1ed2ca53f5cb54e({} %res, ptr nonnull %result_value), !dbg !528
  call fastcc void @InternalTask_toEffect_4d841bd57979ccceddece07dcf2dbc9edd3191f365637aa1e5efefa18c6c7ca3(ptr nonnull %result_value, ptr nonnull %result_value1), !dbg !528
  %1 = load i64, ptr %result_value1, align 8, !dbg !528
  store i64 %1, ptr %0, align 4, !dbg !528
  ret void, !dbg !528
}

define internal fastcc { { %str.RocStr, {} }, {} } @InternalTask_toEffect_a0ad3055de08c7e73da1974f4d9be666ee2daaab6969dd582bb59893cf022b0({ { %str.RocStr, {} }, {} } %"13") !dbg !530 {
entry:
  ret { { %str.RocStr, {} }, {} } %"13", !dbg !531
}

define internal fastcc i128 @List_getUnsafe_8acb95ddb9a746c2bf4dc0f4f96ce3b3e1f1e4f2559e7641b193db1f161d1c41(%list.RocList %"#arg1", i64 %"#arg2") !dbg !533 {
entry:
  %read_list_ptr = extractvalue %list.RocList %"#arg1", 0, !dbg !534
  %list_get_element = getelementptr inbounds i128, ptr %read_list_ptr, i64 %"#arg2", !dbg !534
  %list_get_load_element = load i128, ptr %list_get_element, align 16, !dbg !534
  ret i128 %list_get_load_element, !dbg !534
}

define internal fastcc void @Effect_effect_always_inner_8256d790c99390129cd6628d4d43bc44f55cfb83af722d8248666b192be24d65({} %"266", ptr %effect_always_value, ptr %0) !dbg !536 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %effect_always_value, i64 64, i1 false), !dbg !537
  ret void, !dbg !537
}

define internal fastcc void @Task_err_9cc9ac536c41c72f38d2273c43b034822641cbb47ea8853416c10d132561319(ptr %a, ptr %0) !dbg !539 {
entry:
  %result_value = alloca { [0 x i64], [8 x i64], i8, [7 x i8] }, align 8
  call fastcc void @InternalTask_err_66a53c5bb7482a7975e058b703753a62aee74dcb3ed8c2fbfc227399ea738e(ptr %a, ptr nonnull %result_value), !dbg !540
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(72) %0, ptr noundef nonnull align 8 dereferenceable(72) %result_value, i64 72, i1 false), !dbg !540
  ret void, !dbg !540
}

define internal fastcc void @"#UserApp_respond_8c3fdd6849785e1b32106ad9c6ae59845e2314f0a6799376d4e3e3b9be62d181"(ptr %req, {} %"12", ptr %0) !dbg !542 {
entry:
  %result_value = alloca { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, align 8, !dbg !543
  %call = tail call fastcc { { { {}, {} }, {} }, {} } @Utc_now_c773168b5a79ac91672eeb52ab4405228b6e1da8f6c62d3ec2af603fa2ad92(), !dbg !543
  call fastcc void @Task_await_c76509a58fbafc47f4d5fc1992204e92c831be8ebe1587d7baf160babfe2ad({ { { {}, {} }, {} }, {} } %call, ptr %req, ptr nonnull %result_value), !dbg !543
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %result_value, i64 120, i1 false), !dbg !543
  ret void, !dbg !543
}

define internal fastcc void @InternalTask_toEffect_8e7a40fb7cb2175e9c8b7aee60f44cef84959b742d3a14c483b6e3b14f05c2f(ptr %"13", ptr %0) !dbg !545 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %"13", i64 120, i1 false), !dbg !546
  ret void, !dbg !546
}

define internal fastcc void @InternalTask_err_66a53c5bb7482a7975e058b703753a62aee74dcb3ed8c2fbfc227399ea738e(ptr %a, ptr %0) !dbg !548 {
entry:
  %result_value = alloca { [0 x i64], [8 x i64], i8, [7 x i8] }, align 8, !dbg !549
  %tag_alloca = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !549
  tail call fastcc void @"#Attr_#inc_2"(ptr %a, i64 1), !dbg !549
  %load_tag_to_put_in_struct.unpack = load ptr, ptr %a, align 8, !dbg !549
  %load_tag_to_put_in_struct.elt1 = getelementptr inbounds %str.RocStr, ptr %a, i64 0, i32 1, !dbg !549
  %load_tag_to_put_in_struct.unpack2 = load i64, ptr %load_tag_to_put_in_struct.elt1, align 8, !dbg !549
  %load_tag_to_put_in_struct.elt3 = getelementptr inbounds %str.RocStr, ptr %a, i64 0, i32 2, !dbg !549
  %load_tag_to_put_in_struct.unpack4 = load i64, ptr %load_tag_to_put_in_struct.elt3, align 8, !dbg !549
  %data_buffer = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !549
  store ptr %load_tag_to_put_in_struct.unpack, ptr %data_buffer, align 8, !dbg !549
  %data_buffer.repack6 = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, i64 1, !dbg !549
  store i64 %load_tag_to_put_in_struct.unpack2, ptr %data_buffer.repack6, align 8, !dbg !549
  %data_buffer.repack8 = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, i64 2, !dbg !549
  store i64 %load_tag_to_put_in_struct.unpack4, ptr %data_buffer.repack8, align 8, !dbg !549
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !549
  store i8 0, ptr %tag_id_ptr, align 8, !dbg !549
  call fastcc void @Effect_always_3c159ccc72c9f6c2f9b343f7ee15555614903dc98bb4bf9da1d235172245b(ptr nonnull %tag_alloca, ptr nonnull %result_value), !dbg !549
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(72) %0, ptr noundef nonnull align 8 dereferenceable(72) %result_value, i64 72, i1 false), !dbg !549
  ret void, !dbg !549
}

define internal fastcc { {}, {} } @Effect_map_3780de15a3a832596a21b52356ca78cefe1f05b661333fe4053d5b87a27e0({} %"116", {} %effect_map_mapper) !dbg !551 {
entry:
  %insert_record_field = insertvalue { {}, {} } zeroinitializer, {} %"116", 0, !dbg !552
  %insert_record_field1 = insertvalue { {}, {} } %insert_record_field, {} %effect_map_mapper, 1, !dbg !552
  ret { {}, {} } %insert_record_field1, !dbg !552
}

define internal fastcc { { %str.RocStr, {} }, {} } @Effect_after_c5b690bc22238d3ac9e996befafbf2c431a107de306ea8b8318875c9fcba16({ %str.RocStr, {} } %"115", {} %effect_after_toEffect) !dbg !554 {
entry:
  %insert_record_field = insertvalue { { %str.RocStr, {} }, {} } zeroinitializer, { %str.RocStr, {} } %"115", 0, !dbg !555
  %insert_record_field1 = insertvalue { { %str.RocStr, {} }, {} } %insert_record_field, {} %effect_after_toEffect, 1, !dbg !555
  ret { { %str.RocStr, {} }, {} } %insert_record_field1, !dbg !555
}

define internal fastcc void @_155_9b7306a2e571f3d11e34b901a57455c3e32e69a2f8fde813ed1c4300e12712(ptr %"157", ptr %"158", {} %"#arg_closure", ptr %0) !dbg !557 {
entry:
  %result_value = alloca { { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, {} }, align 8
  call fastcc void @_respond_c919149ababf2a569c5e2b164c2465c785dc3bc7f566b8dcef7ec4ae86e8d57(ptr %"157", ptr %"158", ptr nonnull %result_value), !dbg !558
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %result_value, i64 120, i1 false), !dbg !558
  ret void, !dbg !558
}

define internal fastcc {} @InternalDateTime_hoursWithPaddedZeros_93b8def1d2984c6818ac4bcad643457a66cc713468a3a5225fa94a9b1b4933f0() !dbg !560 {
entry:
  ret {} zeroinitializer, !dbg !561
}

define internal fastcc void @Task_await_ca98df76e744faeef21fb76918295997c9c1b552a2e623d6fc162a11de8fae({ %str.RocStr, {} } %task, {} %transform, ptr %0) !dbg !563 {
entry:
  %result_value1 = alloca { [0 x i64], [8 x i64], i8, [7 x i8] }, align 8, !dbg !564
  %result_value = alloca { [0 x i64], [8 x i64], i8, [7 x i8] }, align 8, !dbg !564
  %call = tail call fastcc { %str.RocStr, {} } @InternalTask_toEffect_9c59e7328dd8975131b4ecbb517752a19f98ddf8f39456448f3da8e957ece54({ %str.RocStr, {} } %task), !dbg !564
  call fastcc void @Effect_after_0ecd2fa884bf65d7bc12fe6d21fb068cfa330b949298476bb016904fd3f({ %str.RocStr, {} } %call, {} %transform, ptr nonnull %result_value), !dbg !564
  call fastcc void @InternalTask_fromEffect_50e8e06555163661d37576e08a187bc1a82c34c685bbe84f89594e81f9565960(ptr nonnull %result_value, ptr nonnull %result_value1), !dbg !564
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(72) %0, ptr noundef nonnull align 8 dereferenceable(72) %result_value1, i64 72, i1 false), !dbg !564
  ret void, !dbg !564
}

define internal fastcc void @Effect_always_deda9c07093181a3aee6f4559463a94ce2b31f038cb3d5548d0bb2aeba37e1(ptr %effect_always_value, ptr %0) !dbg !566 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %effect_always_value, i64 64, i1 false), !dbg !567
  ret void, !dbg !567
}

define internal fastcc i128 @Num_sub_e84248fb50d0833361d0417df114b0b3b3448fff97c39cdde963b09a9aebb8(i128 %"#arg1", i128 %"#arg2") !dbg !569 {
entry:
  %call = tail call { i128, i1 } @llvm.ssub.with.overflow.i128(i128 %"#arg1", i128 %"#arg2"), !dbg !570
  %has_overflowed = extractvalue { i128, i1 } %call, 1, !dbg !570
  br i1 %has_overflowed, label %throw_block, label %then_block, !dbg !570

then_block:                                       ; preds = %entry
  %operation_result = extractvalue { i128, i1 } %call, 0, !dbg !570
  ret i128 %operation_result, !dbg !570

throw_block:                                      ; preds = %entry
  tail call fastcc void @throw_on_overflow(), !dbg !570
  unreachable, !dbg !570
}

define internal fastcc void @InternalTask_fromEffect_4f1fdebc72623b7987dfbf57d7b81537b885c9e4ce317a63dbf262856adf(ptr %effect, ptr %0) !dbg !572 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %effect, i64 120, i1 false), !dbg !573
  ret void, !dbg !573
}

define internal fastcc void @Effect_always_a472f7aba8f6717343f24da54150b124829637a3f252c7e04811e4754b343d0(ptr %effect_always_value, ptr %0) !dbg !575 {
entry:
  %1 = load i64, ptr %effect_always_value, align 4, !dbg !576
  store i64 %1, ptr %0, align 4, !dbg !576
  ret void, !dbg !576
}

define internal fastcc { %str.RocStr, {} } @InternalTask_fromEffect_7f755070a828d5b0991fd43175b6036d1cb7ecf871d1b823a8797b553d92bc({ %str.RocStr, {} } %effect) !dbg !578 {
entry:
  ret { %str.RocStr, {} } %effect, !dbg !579
}

define internal fastcc void @InternalTask_fromEffect_50e8e06555163661d37576e08a187bc1a82c34c685bbe84f89594e81f9565960(ptr %effect, ptr %0) !dbg !581 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(72) %0, ptr noundef nonnull align 8 dereferenceable(72) %effect, i64 72, i1 false), !dbg !582
  ret void, !dbg !582
}

define internal fastcc void @InternalTask_err_61e5a13d423d566ac5e547894554a8bcf8bc44e60405c767b71c7c83a1e2c55(ptr %a, ptr %0) !dbg !584 {
entry:
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !585
  %tag_alloca = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !585
  tail call fastcc void @"#Attr_#inc_2"(ptr %a, i64 1), !dbg !585
  %load_tag_to_put_in_struct.unpack = load ptr, ptr %a, align 8, !dbg !585
  %load_tag_to_put_in_struct.elt1 = getelementptr inbounds %str.RocStr, ptr %a, i64 0, i32 1, !dbg !585
  %load_tag_to_put_in_struct.unpack2 = load i64, ptr %load_tag_to_put_in_struct.elt1, align 8, !dbg !585
  %load_tag_to_put_in_struct.elt3 = getelementptr inbounds %str.RocStr, ptr %a, i64 0, i32 2, !dbg !585
  %load_tag_to_put_in_struct.unpack4 = load i64, ptr %load_tag_to_put_in_struct.elt3, align 8, !dbg !585
  %data_buffer = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !585
  store ptr %load_tag_to_put_in_struct.unpack, ptr %data_buffer, align 8, !dbg !585
  %data_buffer.repack6 = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, i64 1, !dbg !585
  store i64 %load_tag_to_put_in_struct.unpack2, ptr %data_buffer.repack6, align 8, !dbg !585
  %data_buffer.repack8 = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, i64 2, !dbg !585
  store i64 %load_tag_to_put_in_struct.unpack4, ptr %data_buffer.repack8, align 8, !dbg !585
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !585
  store i8 0, ptr %tag_id_ptr, align 8, !dbg !585
  call fastcc void @Effect_always_deda9c07093181a3aee6f4559463a94ce2b31f038cb3d5548d0bb2aeba37e1(ptr nonnull %tag_alloca, ptr nonnull %result_value), !dbg !585
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value, i64 64, i1 false), !dbg !585
  ret void, !dbg !585
}

define internal fastcc void @Task_ok_8445464738218c426e3b841f28ede2879d4391e6c33df6a616e872e199e47e(ptr %a, ptr %0) !dbg !587 {
entry:
  %result_value = alloca { [0 x i64], [5 x i64], i8, [7 x i8] }, align 8
  call fastcc void @InternalTask_ok_789661f33c6ea1791479ecf1f52dd93e21b779364a5197d9de3459113903b9c(ptr %a, ptr nonnull %result_value), !dbg !588
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %result_value, i64 48, i1 false), !dbg !588
  ret void, !dbg !588
}

define internal fastcc void @InternalTask_toEffect_8719a5fa4a4d2d7fe17773695c6c6d3ecd8b7cfffd135c8d4ca89f29f876d1f(ptr %"13", ptr %0) !dbg !590 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %"13", i64 64, i1 false), !dbg !591
  ret void, !dbg !591
}

define internal fastcc i1 @Str_isEmpty_99aa979e4a9cadd6dbe48ea878ec84acb7696eb93470c375f6893f1da46c3772(ptr %"#arg1") !dbg !593 {
entry:
  %call_builtin = tail call i64 @roc_builtins.str.number_of_bytes(ptr nocapture readonly %"#arg1"), !dbg !594
  %str_len_is_zero = icmp eq i64 %call_builtin, 0, !dbg !594
  ret i1 %str_len_is_zero, !dbg !594
}

define internal fastcc void @Effect_effect_always_inner_8f804d847f17ce19e983ee3d457d4c97a1c72145f357931dcbff3cd6dbfe4c0({} %"266", ptr %effect_always_value, ptr %0) !dbg !596 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %effect_always_value, i64 16, i1 false), !dbg !597
  ret void, !dbg !597
}

define internal fastcc void @Task_53_f752fd971dee73f4bef39e126f15a0a84437112755ca589db8702463ce739a({} %res, i1 %transform, ptr %0) !dbg !599 {
entry:
  %result_value3 = alloca { %list.RocList, %list.RocList, i16 }, align 8
  %tmp_output_for_jmp2 = alloca { %list.RocList, %list.RocList, i16 }, align 8
  %result_value1 = alloca { %list.RocList, %list.RocList, i16 }, align 8
  %tmp_output_for_jmp = alloca { %list.RocList, %list.RocList, i16 }, align 8
  %result_value = alloca { %list.RocList, %list.RocList, i16 }, align 8
  %joinpoint_arg_alloca = alloca { %list.RocList, %list.RocList, i16 }, align 8
  br i1 %transform, label %then_block, label %else_block, !dbg !600

then_block:                                       ; preds = %entry
  call fastcc void @_33_aad9a2f5f9418b386cce489a0bac8cb5bba34171864909e4dfec1ea4e26bfb7({} %res, ptr nonnull %result_value), !dbg !600
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %tmp_output_for_jmp, ptr noundef nonnull align 8 dereferenceable(56) %result_value, i64 56, i1 false), !dbg !600
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %joinpoint_arg_alloca, ptr noundef nonnull align 8 dereferenceable(56) %tmp_output_for_jmp, i64 56, i1 false), !dbg !600
  br label %joinpointcont, !dbg !600

else_block:                                       ; preds = %entry
  call fastcc void @_30_4dcdd9fc1c563c9592918682f5bb9bfbff249c75cdcf934a994231c5c3a018({} %res, ptr nonnull %result_value1), !dbg !600
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %tmp_output_for_jmp2, ptr noundef nonnull align 8 dereferenceable(56) %result_value1, i64 56, i1 false), !dbg !600
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %joinpoint_arg_alloca, ptr noundef nonnull align 8 dereferenceable(56) %tmp_output_for_jmp2, i64 56, i1 false), !dbg !600
  br label %joinpointcont, !dbg !600

joinpointcont:                                    ; preds = %else_block, %then_block
  call fastcc void @InternalTask_toEffect_7e6da7233f16ea2c61d431e9d8c0a56499bf145a5210fb3d79ec4aba1f55c0a8(ptr nonnull %joinpoint_arg_alloca, ptr nonnull %result_value3), !dbg !600
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %0, ptr noundef nonnull align 8 dereferenceable(56) %result_value3, i64 56, i1 false), !dbg !600
  ret void, !dbg !600
}

define internal fastcc void @Effect_after_ac6315adde982c4b62c768a77be738d224267f4f9e6f1a02f3bc60549578c({ %str.RocStr, {} } %"115", i1 %effect_after_toEffect, ptr %0) !dbg !602 {
entry:
  %tag_alloca = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !603
  %insert_record_field = insertvalue { { %str.RocStr, {} }, i1 } zeroinitializer, { %str.RocStr, {} } %"115", 0, !dbg !603
  %insert_record_field1 = insertvalue { { %str.RocStr, {} }, i1 } %insert_record_field, i1 %effect_after_toEffect, 1, !dbg !603
  %data_buffer = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !603
  store { { %str.RocStr, {} }, i1 } %insert_record_field1, ptr %data_buffer, align 8, !dbg !603
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !603
  store i8 0, ptr %tag_id_ptr, align 8, !dbg !603
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %tag_alloca, i64 64, i1 false), !dbg !603
  ret void, !dbg !603
}

define internal fastcc i128 @Effect_effect_closure_posixTime_1529b61b29181b37e427cd639d65060a33ef72662c4981e67e9c292331a({} %"158") !dbg !605 {
entry:
  %call = tail call fastcc i128 @roc_fx_posixTime_fastcc_wrapper(), !dbg !606
  ret i128 %call, !dbg !606
}

define internal fastcc void @InternalTask_fromEffect_d5c9642a64db206d88ab43bd2b9527b05aca746579abd7472d977da8e33ac(ptr %effect, ptr %0) !dbg !608 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %0, ptr noundef nonnull align 8 dereferenceable(48) %effect, i64 48, i1 false), !dbg !609
  ret void, !dbg !609
}

define internal fastcc { %str.RocStr, {} } @Stdout_line_99c9f773566b1d5d689233ef7949cf16c8797c970a4668678361d8c89d24f20(ptr %str) !dbg !611 {
entry:
  %result_value = alloca %str.RocStr, align 8
  call fastcc void @Effect_stdoutLine_b57223634213b1c687e1cf06fef47be7eed4c64d12c154ffb6abc557b2b473(ptr %str, ptr nonnull %result_value), !dbg !612
  %call = call fastcc { %str.RocStr, {} } @Effect_map_8523cacf79b3ae26b5b5ddfebda64fc7e54c53c82e133fab2e0abee3a1046(ptr nonnull %result_value, {} zeroinitializer), !dbg !612
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value), !dbg !612
  %call1 = call fastcc { %str.RocStr, {} } @InternalTask_fromEffect_594462766f77f828358545ebdadebc7d564d3daf466672cbde673babcf18c3c2({ %str.RocStr, {} } %call), !dbg !612
  ret { %str.RocStr, {} } %call1, !dbg !612
}

define internal fastcc {} @Effect_effect_closure_stdoutLine_622c9f939ebee86f480d73fdef56611b8899ab7e93ac9da07aeba3373394a({} %"173", ptr %closure_arg_stdoutLine_0) !dbg !614 {
entry:
  %call = tail call fastcc {} @roc_fx_stdoutLine_fastcc_wrapper(ptr %closure_arg_stdoutLine_0), !dbg !615
  tail call fastcc void @"#Attr_#dec_2"(ptr %closure_arg_stdoutLine_0), !dbg !615
  ret {} %call, !dbg !615
}

define internal fastcc void @Effect_after_0ecd2fa884bf65d7bc12fe6d21fb068cfa330b949298476bb016904fd3f({ %str.RocStr, {} } %"115", {} %effect_after_toEffect, ptr %0) !dbg !617 {
entry:
  %tag_alloca = alloca { [0 x i64], [8 x i64], i8, [7 x i8] }, align 8, !dbg !618
  %data_buffer = getelementptr inbounds { [0 x i64], [8 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, !dbg !618
  %"115.elt" = extractvalue { %str.RocStr, {} } %"115", 0, !dbg !618
  %"115.elt.elt" = extractvalue %str.RocStr %"115.elt", 0, !dbg !618
  store ptr %"115.elt.elt", ptr %data_buffer, align 8, !dbg !618
  %data_buffer.repack6 = getelementptr inbounds { [0 x i64], [8 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, i64 1, !dbg !618
  %"115.elt.elt7" = extractvalue %str.RocStr %"115.elt", 1, !dbg !618
  store i64 %"115.elt.elt7", ptr %data_buffer.repack6, align 8, !dbg !618
  %data_buffer.repack8 = getelementptr inbounds { [0 x i64], [8 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 1, i64 2, !dbg !618
  %"115.elt.elt9" = extractvalue %str.RocStr %"115.elt", 2, !dbg !618
  store i64 %"115.elt.elt9", ptr %data_buffer.repack8, align 8, !dbg !618
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [8 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !618
  store i8 0, ptr %tag_id_ptr, align 8, !dbg !618
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(72) %0, ptr noundef nonnull align 8 dereferenceable(72) %tag_alloca, i64 72, i1 false), !dbg !618
  ret void, !dbg !618
}

define internal fastcc i128 @Num_toI128_54b3c6d264e7c557f2fe74ef29431163e9a30a2e4aca38b681d4b9ee62de031(i128 %"#arg1") !dbg !620 {
entry:
  ret i128 %"#arg1", !dbg !621
}

define internal fastcc void @_25_1c44a9ca60e694ea5bce656141adb8728c249dc46543e7c34883c1136ab140(ptr %"#!5_arg", ptr %0) !dbg !623 {
entry:
  %result_value5 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !624
  %load_element4 = alloca %str.RocStr, align 8, !dbg !624
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !624
  %load_element = alloca { %list.RocList, %list.RocList, i16 }, align 8, !dbg !624
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %"#!5_arg", i64 0, i32 2, !dbg !624
  %load_tag_id = load i8, ptr %tag_id_ptr, align 1, !dbg !624
  %eq_u8 = icmp eq i8 %load_tag_id, 1, !dbg !624
  br i1 %eq_u8, label %then_block, label %else_block, !dbg !624

then_block:                                       ; preds = %entry
  %get_opaque_data_ptr = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %"#!5_arg", i64 0, i32 1, !dbg !624
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %load_element, ptr noundef nonnull align 8 dereferenceable(56) %get_opaque_data_ptr, i64 56, i1 false), !dbg !624
  call fastcc void @Task_ok_f79740875a4d32b5abcf43deaad586f61fe4062a6785757475b34d82a82(ptr nonnull %load_element, ptr nonnull %result_value), !dbg !624
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value, i64 64, i1 false), !dbg !624
  ret void, !dbg !624

else_block:                                       ; preds = %entry
  %get_opaque_data_ptr2 = getelementptr inbounds { [0 x i64], [7 x i64], i8, [7 x i8] }, ptr %"#!5_arg", i64 0, i32 1, !dbg !624
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %load_element4, ptr noundef nonnull align 8 dereferenceable(24) %get_opaque_data_ptr2, i64 24, i1 false), !dbg !624
  %call = call fastcc { %str.RocStr, {} } @Stderr_line_4bd18bc73cee8d6c664141b2e49674ebb21216aa20f0f89293181ce7b14e(ptr nonnull %load_element4), !dbg !624
  call fastcc void @Task_await_13f5c26ce0b5e6eebef533619a72113f96d1ebc7728f2a7c4631d56ba55ad7c({ %str.RocStr, {} } %call, i1 false, ptr nonnull %result_value5), !dbg !624
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value5, i64 64, i1 false), !dbg !624
  ret void, !dbg !624

joinpointcont:                                    ; No predecessors!
  ret void, !dbg !624
}

define internal fastcc void @Effect_after_f411d2d207cb75ff49124b128ee5a4cdec2daf8d1cf0a733c3c7d426729b6b({ { { {}, {} }, {} }, {} } %"115", ptr %effect_after_toEffect, ptr %0) !dbg !626 {
entry:
  %struct_alloca = alloca { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %struct_alloca, ptr noundef nonnull align 8 dereferenceable(120) %effect_after_toEffect, i64 120, i1 false), !dbg !627
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %struct_alloca, i64 120, i1 false), !dbg !627
  ret void, !dbg !627
}

define internal fastcc { { { {}, {} }, {} }, {} } @Utc_now_c773168b5a79ac91672eeb52ab4405228b6e1da8f6c62d3ec2af603fa2ad92() !dbg !629 {
entry:
  %call = tail call fastcc {} @Effect_posixTime_229c75d6969a8a8a593eb2c44e915f34577963371a1cc7e544a8418a694a1e2(), !dbg !630
  %call1 = tail call fastcc { {}, {} } @Effect_map_3780de15a3a832596a21b52356ca78cefe1f05b661333fe4053d5b87a27e0({} %call, {} zeroinitializer), !dbg !630
  %call2 = tail call fastcc { { {}, {} }, {} } @Effect_map_1841486258dadc6565ddb7a1717e1e68e57abb67c121aeb72cb4d456026a9({ {}, {} } %call1, {} zeroinitializer), !dbg !630
  %call3 = tail call fastcc { { { {}, {} }, {} }, {} } @Effect_map_56ecce6137ef1a8b7fa2d1462a14bcff563458ace807157c68c36b8f837c2({ { {}, {} }, {} } %call2, {} zeroinitializer), !dbg !630
  %call4 = tail call fastcc { { { {}, {} }, {} }, {} } @InternalTask_fromEffect_a1b37f834fad683b855edbbe46b2d4d8d04bfe3fdda176d9a70679e9ca0caf({ { { {}, {} }, {} }, {} } %call3), !dbg !630
  ret { { { {}, {} }, {} }, {} } %call4, !dbg !630
}

define internal fastcc void @Task_ok_f79740875a4d32b5abcf43deaad586f61fe4062a6785757475b34d82a82(ptr %a, ptr %0) !dbg !632 {
entry:
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  call fastcc void @InternalTask_ok_c84245e9d5a8bbcea28f19811f38b2e7a05f277c949080724954fddcea11aca3(ptr %a, ptr nonnull %result_value), !dbg !633
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value, i64 64, i1 false), !dbg !633
  ret void, !dbg !633
}

define internal fastcc %list.RocList @Str_toUtf8_eabc27640eff330d625cb2f6435f5dccaec45dd590ad64015fdca105b70(ptr %"#arg1") !dbg !635 {
entry:
  %list_alloca = alloca %list.RocList, align 8
  call void @roc_builtins.str.to_utf8(ptr noalias nocapture nonnull sret(%list.RocList) %list_alloca, ptr nocapture readonly %"#arg1"), !dbg !636
  %load_list.unpack = load ptr, ptr %list_alloca, align 8, !dbg !636
  %0 = insertvalue %list.RocList poison, ptr %load_list.unpack, 0, !dbg !636
  %load_list.elt1 = getelementptr inbounds %list.RocList, ptr %list_alloca, i64 0, i32 1, !dbg !636
  %load_list.unpack2 = load i64, ptr %load_list.elt1, align 8, !dbg !636
  %1 = insertvalue %list.RocList %0, i64 %load_list.unpack2, 1, !dbg !636
  %load_list.elt3 = getelementptr inbounds %list.RocList, ptr %list_alloca, i64 0, i32 2, !dbg !636
  %load_list.unpack4 = load i64, ptr %load_list.elt3, align 8, !dbg !636
  %load_list5 = insertvalue %list.RocList %1, i64 %load_list.unpack4, 2, !dbg !636
  ret %list.RocList %load_list5, !dbg !636
}

define internal fastcc { { { {}, {} }, {} }, {} } @InternalTask_fromEffect_a1b37f834fad683b855edbbe46b2d4d8d04bfe3fdda176d9a70679e9ca0caf({ { { {}, {} }, {} }, {} } %effect) !dbg !638 {
entry:
  ret { { { {}, {} }, {} }, {} } %effect, !dbg !639
}

define internal fastcc { { { {}, {} }, {} }, {} } @Effect_map_56ecce6137ef1a8b7fa2d1462a14bcff563458ace807157c68c36b8f837c2({ { {}, {} }, {} } %"116", {} %effect_map_mapper) !dbg !641 {
entry:
  %insert_record_field = insertvalue { { { {}, {} }, {} }, {} } zeroinitializer, { { {}, {} }, {} } %"116", 0, !dbg !642
  %insert_record_field1 = insertvalue { { { {}, {} }, {} }, {} } %insert_record_field, {} %effect_map_mapper, 1, !dbg !642
  ret { { { {}, {} }, {} }, {} } %insert_record_field1, !dbg !642
}

define internal fastcc { { { %str.RocStr, {} }, {} }, {} } @Effect_after_35d6cb78c74f84df82ab12c37bc71bbe5193f93e9d36506abc7c9c8ca124d1ab({ { %str.RocStr, {} }, {} } %"115", {} %effect_after_toEffect) !dbg !644 {
entry:
  %insert_record_field = insertvalue { { { %str.RocStr, {} }, {} }, {} } zeroinitializer, { { %str.RocStr, {} }, {} } %"115", 0, !dbg !645
  %insert_record_field1 = insertvalue { { { %str.RocStr, {} }, {} }, {} } %insert_record_field, {} %effect_after_toEffect, 1, !dbg !645
  ret { { { %str.RocStr, {} }, {} }, {} } %insert_record_field1, !dbg !645
}

define internal fastcc void @Stdout_4_bad96aa871ccf5b068b2a1da7544fd3d07a932588efb92244e692b8beda99ce({} %"15", ptr %0) !dbg !647 {
entry:
  %tag_alloca = alloca { [0 x i64], [3 x i64], i8, [7 x i8] }, align 8
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [3 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !648
  store i8 1, ptr %tag_id_ptr, align 8, !dbg !648
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(32) %0, ptr noundef nonnull align 8 dereferenceable(32) %tag_alloca, i64 32, i1 false), !dbg !648
  ret void, !dbg !648
}

define internal fastcc { { %str.RocStr, {} }, {} } @"#UserApp_init_8b8e749a7d5dc4035aed2d09b8b4ad59fac5ad694339521a2df23bf1ac35c3"() !dbg !650 {
entry:
  %const_str_store = alloca %str.RocStr, align 8
  store ptr getelementptr inbounds ([60 x i8], ptr @_str_literal_10601663616719294079, i64 0, i64 8), ptr %const_str_store, align 8, !dbg !651
  %const_str_store.repack2 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 1, !dbg !651
  store i64 52, ptr %const_str_store.repack2, align 8, !dbg !651
  %const_str_store.repack3 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 2, !dbg !651
  store i64 52, ptr %const_str_store.repack3, align 8, !dbg !651
  %call = call fastcc { %str.RocStr, {} } @Stdout_line_1e4d2f1e6b4984301a1489b71481ade3a818d1fae80b8f87ea525c7bff923(ptr nonnull %const_str_store), !dbg !651
  %call1 = call fastcc { { %str.RocStr, {} }, {} } @Task_await_7988d89080438f51df37e0664fee86ae858164dcb95eaeb555d2849513259182({ %str.RocStr, {} } %call, {} zeroinitializer), !dbg !651
  ret { { %str.RocStr, {} }, {} } %call1, !dbg !651
}

define internal fastcc { %str.RocStr, {} } @InternalTask_toEffect_1b6b9e2f2c8025d6941d1d79426973c1ba899598ef8eecc9bea3f5f3657b4477({ %str.RocStr, {} } %"13") !dbg !653 {
entry:
  ret { %str.RocStr, {} } %"13", !dbg !654
}

define internal fastcc void @Task_53_48c2caee6f1010356bbec8845a6ee45f2928c63eece16acf25dc3f84dc5f6(ptr %res, ptr %transform, ptr %0) !dbg !656 {
entry:
  %result_value12 = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !657
  %result_value11 = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !657
  %result_value7 = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !657
  %tmp_output_for_jmp6 = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !657
  %result_value5 = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !657
  %tmp_output_for_jmp = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !657
  %result_value = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !657
  %joinpoint_arg_alloca = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !657
  %tag_id_ptr = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %res, i64 0, i32 2, !dbg !657
  %load_tag_id = load i8, ptr %tag_id_ptr, align 1, !dbg !657
  %eq_u8 = icmp eq i8 %load_tag_id, 1, !dbg !657
  br i1 %eq_u8, label %then_block, label %else_block, !dbg !657

then_block:                                       ; preds = %entry
  %tag_id_ptr2 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %transform, i64 0, i32 2, !dbg !657
  %load_tag_id3 = load i8, ptr %tag_id_ptr2, align 1, !dbg !657
  switch i8 %load_tag_id3, label %default [
    i8 0, label %branch0
  ], !dbg !657

else_block:                                       ; preds = %entry
  %get_opaque_data_ptr8 = getelementptr inbounds { [0 x i32], [4 x i8], i8, [3 x i8] }, ptr %res, i64 0, i32 1, !dbg !657
  %load_element10 = load i32, ptr %get_opaque_data_ptr8, align 4, !dbg !657
  call fastcc void @Task_err_dbefccae6de790f8e3497ad3c6c1c58a12a744edb0d65ec1ec4ade8b1151a59b(i32 %load_element10, ptr nonnull %result_value11), !dbg !657
  call fastcc void @InternalTask_toEffect_405afdd54e1519581be52a8c8268ff856d1e183e22d746e36b8e1e892557df7(ptr nonnull %result_value11, ptr nonnull %result_value12), !dbg !657
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %result_value12, i64 16, i1 false), !dbg !657
  ret void, !dbg !657

default:                                          ; preds = %then_block
  call fastcc void @_22_1484a21b4257566f7c1b3505e4f6c430eb1121cbfb946b32fb115b90b1ef50({} poison, ptr nonnull %result_value5), !dbg !657
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %tmp_output_for_jmp6, ptr noundef nonnull align 8 dereferenceable(16) %result_value5, i64 16, i1 false), !dbg !657
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %joinpoint_arg_alloca, ptr noundef nonnull align 8 dereferenceable(16) %tmp_output_for_jmp6, i64 16, i1 false), !dbg !657
  br label %joinpointcont, !dbg !657

joinpointcont:                                    ; preds = %default, %branch0
  call fastcc void @InternalTask_toEffect_405afdd54e1519581be52a8c8268ff856d1e183e22d746e36b8e1e892557df7(ptr nonnull %joinpoint_arg_alloca, ptr nonnull %result_value7), !dbg !657
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %result_value7, i64 16, i1 false), !dbg !657
  ret void, !dbg !657

branch0:                                          ; preds = %then_block
  call fastcc void @_19_b5dcd15815911a96b9d7e883b1723ec1e9f2a35835ca79db2284140ebd0aa83({} poison, ptr %transform, ptr nonnull %result_value), !dbg !657
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %tmp_output_for_jmp, ptr noundef nonnull align 8 dereferenceable(16) %result_value, i64 16, i1 false), !dbg !657
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %joinpoint_arg_alloca, ptr noundef nonnull align 8 dereferenceable(16) %tmp_output_for_jmp, i64 16, i1 false), !dbg !657
  br label %joinpointcont, !dbg !657
}

define internal fastcc void @Task_53_6c6ac529604932be9f613389ac656fb39037eb79cbe1d537d9bdd99c2563108d(ptr %res, ptr %transform, ptr %0) !dbg !659 {
entry:
  %result_value7 = alloca { [0 x i64], [8 x i64], i8, [7 x i8] }, align 8, !dbg !660
  %result_value6 = alloca { [0 x i64], [8 x i64], i8, [7 x i8] }, align 8, !dbg !660
  %load_element5 = alloca %str.RocStr, align 8, !dbg !660
  %result_value2 = alloca { [0 x i64], [8 x i64], i8, [7 x i8] }, align 8, !dbg !660
  %result_value = alloca { [0 x i64], [8 x i64], i8, [7 x i8] }, align 8, !dbg !660
  %tag_id_ptr = getelementptr inbounds { [0 x i128], [4 x i64], i8, [15 x i8] }, ptr %res, i64 0, i32 2, !dbg !660
  %load_tag_id = load i8, ptr %tag_id_ptr, align 1, !dbg !660
  %eq_u8 = icmp eq i8 %load_tag_id, 1, !dbg !660
  br i1 %eq_u8, label %then_block, label %else_block, !dbg !660

then_block:                                       ; preds = %entry
  %get_opaque_data_ptr = getelementptr inbounds { [0 x i128], [4 x i64], i8, [15 x i8] }, ptr %res, i64 0, i32 1, !dbg !660
  %load_element = load i128, ptr %get_opaque_data_ptr, align 16, !dbg !660
  call fastcc void @"#UserApp_7_13b85edde3cd334a6265af1614664111ffe13ba3b2be97d0f8e38d9c799cb7"(i128 %load_element, ptr %transform, ptr nonnull %result_value), !dbg !660
  call fastcc void @InternalTask_toEffect_5eb6a2599d3097c754d93922b84522fd22c626afbfca9a48d724fa1945e3ca9(ptr nonnull %result_value, ptr nonnull %result_value2), !dbg !660
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(72) %0, ptr noundef nonnull align 8 dereferenceable(72) %result_value2, i64 72, i1 false), !dbg !660
  ret void, !dbg !660

else_block:                                       ; preds = %entry
  tail call fastcc void @"#Attr_#dec_17"(ptr %transform), !dbg !660
  %get_opaque_data_ptr3 = getelementptr inbounds { [0 x i128], [4 x i64], i8, [15 x i8] }, ptr %res, i64 0, i32 1, !dbg !660
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %load_element5, ptr noundef nonnull align 8 dereferenceable(24) %get_opaque_data_ptr3, i64 24, i1 false), !dbg !660
  call fastcc void @Task_err_9cc9ac536c41c72f38d2273c43b034822641cbb47ea8853416c10d132561319(ptr nonnull %load_element5, ptr nonnull %result_value6), !dbg !660
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %load_element5), !dbg !660
  call fastcc void @InternalTask_toEffect_5eb6a2599d3097c754d93922b84522fd22c626afbfca9a48d724fa1945e3ca9(ptr nonnull %result_value6, ptr nonnull %result_value7), !dbg !660
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(72) %0, ptr noundef nonnull align 8 dereferenceable(72) %result_value7, i64 72, i1 false), !dbg !660
  ret void, !dbg !660
}

define internal fastcc void @Effect_effect_after_inner_dfab3e7e4dcf97947ada0f8abcfc248e78de1f269ac4599a46f8db36f6ed6aa({} %"179", ptr %"#arg_closure", ptr %0) !dbg !662 {
entry:
  %result_value4 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !663
  %result_value3 = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !663
  %result_value2 = alloca { [0 x i64], [8 x i64], i8, [7 x i8] }, align 8, !dbg !663
  %result_value = alloca { [0 x i128], [4 x i64], i8, [15 x i8] }, align 16, !dbg !663
  %struct_field1 = alloca { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, align 8, !dbg !663
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %struct_field1, ptr noundef nonnull align 8 dereferenceable(120) %"#arg_closure", i64 120, i1 false), !dbg !663
  call fastcc void @Effect_effect_map_inner_d52f8c3ecf2e209e81e04dd415745749206b773d86c4d1b2bb2d3d8e8890c({} zeroinitializer, { { { {}, {} }, {} }, {} } poison, ptr nonnull %result_value), !dbg !663
  call fastcc void @Task_53_6c6ac529604932be9f613389ac656fb39037eb79cbe1d537d9bdd99c2563108d(ptr nonnull %result_value, ptr nonnull %struct_field1, ptr nonnull %result_value2), !dbg !663
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [8 x i64], i8, [7 x i8] }, ptr %result_value2, i64 0, i32 2, !dbg !663
  %load_tag_id = load i8, ptr %tag_id_ptr, align 8, !dbg !663
  switch i8 %load_tag_id, label %default [
    i8 0, label %branch0
  ], !dbg !663

default:                                          ; preds = %entry
  call fastcc void @Effect_effect_always_inner_6fdff3e812be393e397a32aeb76ae96155b45793f22c8c7f8b12de3628ba863({} zeroinitializer, ptr nonnull %result_value2, ptr nonnull %result_value4), !dbg !663
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value4, i64 64, i1 false), !dbg !663
  ret void, !dbg !663

branch0:                                          ; preds = %entry
  call fastcc void @Effect_effect_after_inner_bac59821c43c0b53dd3438580b2599a5bf16c219b40a9d5e9a6e6a5390({} zeroinitializer, ptr nonnull %result_value2, ptr nonnull %result_value3), !dbg !663
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value3, i64 64, i1 false), !dbg !663
  ret void, !dbg !663
}

define internal fastcc { { {}, {} }, {} } @Effect_map_1841486258dadc6565ddb7a1717e1e68e57abb67c121aeb72cb4d456026a9({ {}, {} } %"116", {} %effect_map_mapper) !dbg !665 {
entry:
  %insert_record_field = insertvalue { { {}, {} }, {} } zeroinitializer, { {}, {} } %"116", 0, !dbg !666
  %insert_record_field1 = insertvalue { { {}, {} }, {} } %insert_record_field, {} %effect_map_mapper, 1, !dbg !666
  ret { { {}, {} }, {} } %insert_record_field1, !dbg !666
}

define internal fastcc void @InternalTask_fromEffect_1a20a86e49e98265a07f2e3520fd72f1d5cc4a4259e669f8b2acf756122080(ptr %effect, ptr %0) !dbg !668 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %effect, i64 120, i1 false), !dbg !669
  ret void, !dbg !669
}

define internal fastcc void @_30_4dcdd9fc1c563c9592918682f5bb9bfbff249c75cdcf934a994231c5c3a018({} %"42", ptr %0) !dbg !671 {
entry:
  %result_value = alloca { %list.RocList, %list.RocList, i16 }, align 8
  %struct_alloca = alloca { %list.RocList, %list.RocList, i16 }, align 8
  store ptr null, ptr %struct_alloca, align 8, !dbg !672
  %struct_alloca.repack3 = getelementptr inbounds %list.RocList, ptr %struct_alloca, i64 0, i32 1, !dbg !672
  store i64 0, ptr %struct_alloca.repack3, align 8, !dbg !672
  %struct_alloca.repack4 = getelementptr inbounds %list.RocList, ptr %struct_alloca, i64 0, i32 2, !dbg !672
  store i64 0, ptr %struct_alloca.repack4, align 8, !dbg !672
  %struct_field_gep1 = getelementptr inbounds { %list.RocList, %list.RocList, i16 }, ptr %struct_alloca, i64 0, i32 1, !dbg !672
  store ptr null, ptr %struct_field_gep1, align 8, !dbg !672
  %struct_field_gep1.repack5 = getelementptr inbounds { %list.RocList, %list.RocList, i16 }, ptr %struct_alloca, i64 0, i32 1, i32 1, !dbg !672
  store i64 0, ptr %struct_field_gep1.repack5, align 8, !dbg !672
  %struct_field_gep1.repack6 = getelementptr inbounds { %list.RocList, %list.RocList, i16 }, ptr %struct_alloca, i64 0, i32 1, i32 2, !dbg !672
  store i64 0, ptr %struct_field_gep1.repack6, align 8, !dbg !672
  %struct_field_gep2 = getelementptr inbounds { %list.RocList, %list.RocList, i16 }, ptr %struct_alloca, i64 0, i32 2, !dbg !672
  store i16 500, ptr %struct_field_gep2, align 8, !dbg !672
  call fastcc void @InternalTask_ok_a1fdfd7ca485c5e9436ed61186fef7b9b914edaf84deff48d9823fcadcd6ac(ptr nonnull %struct_alloca, ptr nonnull %result_value), !dbg !672
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(56) %0, ptr noundef nonnull align 8 dereferenceable(56) %result_value, i64 56, i1 false), !dbg !672
  ret void, !dbg !672
}

define internal fastcc i128 @Num_divTrunc_cb411178cb7686889a4ee0e4b4c57e63975186dc9f1448b79e94c2721a21a2(i128 %a, i128 %b) !dbg !674 {
entry:
  %const_str_store = alloca %str.RocStr, align 8, !dbg !675
  %call = tail call fastcc i1 @Num_isZero_f57b151e8a6dfbc520c29ccc134c8fb5357cdd96058ecd185f0787f48b7a6(i128 %b), !dbg !675
  br i1 %call, label %then_block, label %else_block, !dbg !675

then_block:                                       ; preds = %entry
  store ptr inttoptr (i64 2338042651316874825 to ptr), ptr %const_str_store, align 8, !dbg !675
  %const_str_store.repack2 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 1, !dbg !675
  store i64 7957695010998479204, ptr %const_str_store.repack2, align 8, !dbg !675
  %const_str_store.repack3 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 2, !dbg !675
  store i64 -7638068477433388512, ptr %const_str_store.repack3, align 8, !dbg !675
  call void @roc_panic(ptr %const_str_store, i32 1), !dbg !675
  unreachable, !dbg !675

else_block:                                       ; preds = %entry
  %call1 = tail call fastcc i128 @Num_divTruncUnchecked_35bfe7dc6dba25ddadede12999f2a34775468912610779bf675f9c2d81ecac(i128 %a, i128 %b), !dbg !675
  ret i128 %call1, !dbg !675
}

define internal fastcc void @Task_result_19a01698b1f1f64ca782bce3c6b70dbfe2947aebabe3f6b126ebdf6166ecc31(ptr %task, ptr %0) !dbg !677 {
entry:
  %result_value2 = alloca { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, align 8
  %result_value1 = alloca { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, align 8
  %result_value = alloca { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, align 8
  call fastcc void @InternalTask_toEffect_28b81340646419744ffe2153acaa8e39d3c2d10c2a51eb5702318112c7c5(ptr %task, ptr nonnull %result_value), !dbg !678
  call fastcc void @Effect_after_d9e2d7d318b97522751e8d862a897cd552d26040fa25d41678f9ac7b36cd7(ptr nonnull %result_value, {} zeroinitializer, ptr nonnull %result_value1), !dbg !678
  call fastcc void @InternalTask_fromEffect_4f1fdebc72623b7987dfbf57d7b81537b885c9e4ce317a63dbf262856adf(ptr nonnull %result_value1, ptr nonnull %result_value2), !dbg !678
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %result_value2, i64 120, i1 false), !dbg !678
  ret void, !dbg !678
}

define internal fastcc void @InternalTask_toEffect_405afdd54e1519581be52a8c8268ff856d1e183e22d746e36b8e1e892557df7(ptr %"13", ptr %0) !dbg !680 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %"13", i64 16, i1 false), !dbg !681
  ret void, !dbg !681
}

define internal fastcc void @Effect_effect_always_inner_6fdff3e812be393e397a32aeb76ae96155b45793f22c8c7f8b12de3628ba863({} %"266", ptr %"#arg_closure", ptr %0) !dbg !683 {
entry:
  %load_element = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8, !dbg !684
  %get_opaque_data_ptr = getelementptr inbounds { [0 x i64], [8 x i64], i8, [7 x i8] }, ptr %"#arg_closure", i64 0, i32 1, !dbg !684
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %load_element, ptr noundef nonnull align 8 dereferenceable(64) %get_opaque_data_ptr, i64 64, i1 false), !dbg !684
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %load_element, i64 64, i1 false), !dbg !684
  ret void, !dbg !684
}

define internal fastcc {} @Stderr_4_1979c8b7ef5f495fcd893830dae286517b20f9eb43379243d33155ade7a91({} %"15") !dbg !686 {
entry:
  ret {} zeroinitializer, !dbg !687
}

define internal fastcc void @InternalDateTime_yearWithPaddedZeros_c4a37e6d352bb35242daa87c613d86251be76cf677f327944a4ca87b5e276(i128 %year, ptr %0) !dbg !689 {
entry:
  %result_value13 = alloca %str.RocStr, align 8
  %const_str_store12 = alloca %str.RocStr, align 8
  %result_value7 = alloca %str.RocStr, align 8
  %const_str_store6 = alloca %str.RocStr, align 8
  %result_value1 = alloca %str.RocStr, align 8
  %const_str_store = alloca %str.RocStr, align 8
  %result_value = alloca %str.RocStr, align 8
  call fastcc void @Num_toStr_99e2ebbd98e8a2a4c7ed9bd71d205d9f7b5d7e7a9ddb68dab65f2ad1c2198b(i128 %year, ptr nonnull %result_value), !dbg !690
  %call = call fastcc i1 @Num_isLt_f273102d33b910ab8b1eda6e483bb587ec34372c3562cd9bfb68bcf889ba9cd(i128 %year, i128 10), !dbg !690
  br i1 %call, label %then_block, label %else_block, !dbg !690

then_block:                                       ; preds = %entry
  store ptr inttoptr (i64 3158064 to ptr), ptr %const_str_store, align 8, !dbg !690
  %const_str_store.repack18 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 1, !dbg !690
  store i64 0, ptr %const_str_store.repack18, align 8, !dbg !690
  %const_str_store.repack19 = getelementptr inbounds %str.RocStr, ptr %const_str_store, i64 0, i32 2, !dbg !690
  store i64 -9007199254740992000, ptr %const_str_store.repack19, align 8, !dbg !690
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %const_str_store, ptr nonnull %result_value, ptr nonnull %result_value1), !dbg !690
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value), !dbg !690
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %result_value1, i64 24, i1 false), !dbg !690
  ret void, !dbg !690

else_block:                                       ; preds = %entry
  %call2 = call fastcc i1 @Num_isLt_f273102d33b910ab8b1eda6e483bb587ec34372c3562cd9bfb68bcf889ba9cd(i128 %year, i128 100), !dbg !690
  br i1 %call2, label %then_block4, label %else_block5, !dbg !690

then_block4:                                      ; preds = %else_block
  store ptr inttoptr (i64 12336 to ptr), ptr %const_str_store6, align 8, !dbg !690
  %const_str_store6.repack16 = getelementptr inbounds %str.RocStr, ptr %const_str_store6, i64 0, i32 1, !dbg !690
  store i64 0, ptr %const_str_store6.repack16, align 8, !dbg !690
  %const_str_store6.repack17 = getelementptr inbounds %str.RocStr, ptr %const_str_store6, i64 0, i32 2, !dbg !690
  store i64 -9079256848778919936, ptr %const_str_store6.repack17, align 8, !dbg !690
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %const_str_store6, ptr nonnull %result_value, ptr nonnull %result_value7), !dbg !690
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value), !dbg !690
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %result_value7, i64 24, i1 false), !dbg !690
  ret void, !dbg !690

else_block5:                                      ; preds = %else_block
  %call8 = call fastcc i1 @Num_isLt_f273102d33b910ab8b1eda6e483bb587ec34372c3562cd9bfb68bcf889ba9cd(i128 %year, i128 1000), !dbg !690
  br i1 %call8, label %then_block10, label %else_block11, !dbg !690

then_block10:                                     ; preds = %else_block5
  store ptr inttoptr (i64 48 to ptr), ptr %const_str_store12, align 8, !dbg !690
  %const_str_store12.repack14 = getelementptr inbounds %str.RocStr, ptr %const_str_store12, i64 0, i32 1, !dbg !690
  store i64 0, ptr %const_str_store12.repack14, align 8, !dbg !690
  %const_str_store12.repack15 = getelementptr inbounds %str.RocStr, ptr %const_str_store12, i64 0, i32 2, !dbg !690
  store i64 -9151314442816847872, ptr %const_str_store12.repack15, align 8, !dbg !690
  call fastcc void @Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b(ptr nonnull %const_str_store12, ptr nonnull %result_value, ptr nonnull %result_value13), !dbg !690
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %result_value), !dbg !690
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %result_value13, i64 24, i1 false), !dbg !690
  ret void, !dbg !690

else_block11:                                     ; preds = %else_block5
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %0, ptr noundef nonnull align 8 dereferenceable(24) %result_value, i64 24, i1 false), !dbg !690
  ret void, !dbg !690
}

define internal fastcc void @InternalTask_ok_c84245e9d5a8bbcea28f19811f38b2e7a05f277c949080724954fddcea11aca3(ptr %a, ptr %0) !dbg !692 {
entry:
  %result_value = alloca { [0 x i64], [7 x i64], i8, [7 x i8] }, align 8
  call fastcc void @Effect_always_bc8306c1040a95f2dac252e82b64a88f9bbe8f51d564ae0c05ee47ab4dc64ec(ptr %a, ptr nonnull %result_value), !dbg !693
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) %result_value, i64 64, i1 false), !dbg !693
  ret void, !dbg !693
}

define internal fastcc {} @Box_unbox_d394208415ac8fe0ce8aa0ddf6a845c7cc74d818698e3d25c85705ce311f5ec(ptr %"#arg1") !dbg !695 {
entry:
  tail call fastcc void @"#Attr_#dec_18"(ptr %"#arg1"), !dbg !696
  ret {} poison, !dbg !696
}

define internal fastcc void @Effect_always_aacdfa21c937a3152a4c9abafa557bcab3033c1362c20c33c558b64d99d3e5(ptr %effect_always_value, ptr %0) !dbg !698 {
entry:
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %0, ptr noundef nonnull align 8 dereferenceable(40) %effect_always_value, i64 40, i1 false), !dbg !699
  ret void, !dbg !699
}

define internal fastcc i1 @Bool_structuralNotEq_53eef38977ca9e3af29e8b6fc9f50f557be9bbd173abd2118eb5488f19fb2(i128 %"#arg1", i128 %"#arg2") !dbg !701 {
entry:
  %neq_i128 = icmp ne i128 %"#arg1", %"#arg2", !dbg !702
  ret i1 %neq_i128, !dbg !702
}

define internal fastcc void @InternalHttp_fromHostRequest_99ccc6754e07ea7cffe47524633bfb91dd0f5a5f04cc85ed764577b4b3a23(ptr %"83", ptr %0) !dbg !704 {
entry:
  %struct_alloca = alloca { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, align 8, !dbg !705
  %tmp_output_for_jmp9 = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !705
  %tag_alloca6 = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !705
  %tmp_output_for_jmp = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !705
  %tag_alloca = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !705
  %joinpoint_arg_alloca = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !705
  %struct_field5 = alloca %str.RocStr, align 8, !dbg !705
  %struct_field3 = alloca %str.RocStr, align 8, !dbg !705
  %struct_field2 = alloca %str.RocStr, align 8, !dbg !705
  %struct_field.unpack = load ptr, ptr %"83", align 8, !dbg !705
  %struct_field.elt16 = getelementptr inbounds %list.RocList, ptr %"83", i64 0, i32 1, !dbg !705
  %struct_field.unpack17 = load i64, ptr %struct_field.elt16, align 8, !dbg !705
  %struct_field.elt18 = getelementptr inbounds %list.RocList, ptr %"83", i64 0, i32 2, !dbg !705
  %struct_field.unpack19 = load i64, ptr %struct_field.elt18, align 8, !dbg !705
  %struct_field_access_record_1 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, %str.RocStr, i64, %str.RocStr }, ptr %"83", i64 0, i32 1, !dbg !705
  %struct_field1.unpack = load ptr, ptr %struct_field_access_record_1, align 8, !dbg !705
  %struct_field1.elt21 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, %str.RocStr, i64, %str.RocStr }, ptr %"83", i64 0, i32 1, i32 1, !dbg !705
  %struct_field1.unpack22 = load i64, ptr %struct_field1.elt21, align 8, !dbg !705
  %struct_field1.elt23 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, %str.RocStr, i64, %str.RocStr }, ptr %"83", i64 0, i32 1, i32 2, !dbg !705
  %struct_field1.unpack24 = load i64, ptr %struct_field1.elt23, align 8, !dbg !705
  %struct_field_access_record_2 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, %str.RocStr, i64, %str.RocStr }, ptr %"83", i64 0, i32 2, !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %struct_field2, ptr noundef nonnull align 8 dereferenceable(24) %struct_field_access_record_2, i64 24, i1 false), !dbg !705
  %struct_field_access_record_3 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, %str.RocStr, i64, %str.RocStr }, ptr %"83", i64 0, i32 3, !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %struct_field3, ptr noundef nonnull align 8 dereferenceable(24) %struct_field_access_record_3, i64 24, i1 false), !dbg !705
  %struct_field_access_record_4 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, %str.RocStr, i64, %str.RocStr }, ptr %"83", i64 0, i32 4, !dbg !705
  %struct_field4 = load i64, ptr %struct_field_access_record_4, align 8, !dbg !705
  %struct_field_access_record_5 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, %str.RocStr, i64, %str.RocStr }, ptr %"83", i64 0, i32 5, !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %struct_field5, ptr noundef nonnull align 8 dereferenceable(24) %struct_field_access_record_5, i64 24, i1 false), !dbg !705
  %call = tail call fastcc i1 @Bool_structuralEq_4a74cf314ac9371a5ea518de15e620d82137397f51a1fa6eff156547f363(i64 %struct_field4, i64 0), !dbg !705
  br i1 %call, label %then_block, label %else_block, !dbg !705

then_block:                                       ; preds = %entry
  %tag_id_ptr = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %tag_alloca, i64 0, i32 2, !dbg !705
  store i8 0, ptr %tag_id_ptr, align 8, !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %tmp_output_for_jmp, ptr noundef nonnull align 8 dereferenceable(16) %tag_alloca, i64 16, i1 false), !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %joinpoint_arg_alloca, ptr noundef nonnull align 8 dereferenceable(16) %tmp_output_for_jmp, i64 16, i1 false), !dbg !705
  br label %joinpointcont, !dbg !705

else_block:                                       ; preds = %entry
  %data_buffer7 = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %tag_alloca6, i64 0, i32 1, !dbg !705
  store i64 %struct_field4, ptr %data_buffer7, align 8, !dbg !705
  %tag_id_ptr8 = getelementptr inbounds { [0 x i64], [1 x i64], i8, [7 x i8] }, ptr %tag_alloca6, i64 0, i32 2, !dbg !705
  store i8 1, ptr %tag_id_ptr8, align 8, !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %tmp_output_for_jmp9, ptr noundef nonnull align 8 dereferenceable(16) %tag_alloca6, i64 16, i1 false), !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %joinpoint_arg_alloca, ptr noundef nonnull align 8 dereferenceable(16) %tmp_output_for_jmp9, i64 16, i1 false), !dbg !705
  br label %joinpointcont, !dbg !705

joinpointcont:                                    ; preds = %else_block, %then_block
  %call10 = call fastcc i8 @InternalHttp_methodFromStr_f2eb2e65858ef9a081c444e7b9b2cef1ed51b5a1e38027833034b9f057aa3131(ptr nonnull %struct_field2), !dbg !705
  call fastcc void @"#Attr_#dec_2"(ptr nonnull %struct_field2), !dbg !705
  store ptr %struct_field.unpack, ptr %struct_alloca, align 8, !dbg !705
  %struct_alloca.repack26 = getelementptr inbounds %list.RocList, ptr %struct_alloca, i64 0, i32 1, !dbg !705
  store i64 %struct_field.unpack17, ptr %struct_alloca.repack26, align 8, !dbg !705
  %struct_alloca.repack28 = getelementptr inbounds %list.RocList, ptr %struct_alloca, i64 0, i32 2, !dbg !705
  store i64 %struct_field.unpack19, ptr %struct_alloca.repack28, align 8, !dbg !705
  %struct_field_gep11 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %struct_alloca, i64 0, i32 1, !dbg !705
  store ptr %struct_field1.unpack, ptr %struct_field_gep11, align 8, !dbg !705
  %struct_field_gep11.repack30 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %struct_alloca, i64 0, i32 1, i32 1, !dbg !705
  store i64 %struct_field1.unpack22, ptr %struct_field_gep11.repack30, align 8, !dbg !705
  %struct_field_gep11.repack32 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %struct_alloca, i64 0, i32 1, i32 2, !dbg !705
  store i64 %struct_field1.unpack24, ptr %struct_field_gep11.repack32, align 8, !dbg !705
  %struct_field_gep12 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %struct_alloca, i64 0, i32 2, !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %struct_field_gep12, ptr noundef nonnull align 8 dereferenceable(24) %struct_field3, i64 24, i1 false), !dbg !705
  %struct_field_gep13 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %struct_alloca, i64 0, i32 3, !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %struct_field_gep13, ptr noundef nonnull align 8 dereferenceable(16) %joinpoint_arg_alloca, i64 16, i1 false), !dbg !705
  %struct_field_gep14 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %struct_alloca, i64 0, i32 4, !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %struct_field_gep14, ptr noundef nonnull align 8 dereferenceable(24) %struct_field5, i64 24, i1 false), !dbg !705
  %struct_field_gep15 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %struct_alloca, i64 0, i32 5, !dbg !705
  store i8 %call10, ptr %struct_field_gep15, align 8, !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(120) %0, ptr noundef nonnull align 8 dereferenceable(120) %struct_alloca, i64 120, i1 false), !dbg !705
  ret void, !dbg !705
}

define private fastcc void @"#Attr_#dec_2"(ptr %"#arg1") !dbg !707 {
entry:
  %load_str_to_stack = load %str.RocStr, ptr %"#arg1", align 8, !dbg !708
  %read_str_capacity = extractvalue %str.RocStr %load_str_to_stack, 2, !dbg !708
  %is_big_str = icmp sgt i64 %read_str_capacity, 0, !dbg !708
  br i1 %is_big_str, label %modify_rc, label %modify_rc_str_cont, !dbg !708

modify_rc_str_cont:                               ; preds = %modify_rc, %entry
  ret void, !dbg !708

modify_rc:                                        ; preds = %entry
  %call_builtin = call ptr @roc_builtins.str.allocation_ptr(ptr nocapture readonly %"#arg1"), !dbg !708
  %get_rc_ptr = getelementptr inbounds i64, ptr %call_builtin, i64 -1, !dbg !708
  call fastcc void @decrement_refcounted_ptr_8(ptr %get_rc_ptr), !dbg !708
  br label %modify_rc_str_cont, !dbg !708
}

define internal fastcc void @decrement_refcounted_ptr_8(ptr %0) !dbg !710 {
entry:
  %1 = load i64, ptr %0, align 8, !dbg !711
  %.not.i = icmp eq i64 %1, 0, !dbg !711
  br i1 %.not.i, label %2, label %3, !dbg !711

2:                                                ; preds = %3, %entry
  br label %roc_builtins.utils.decref_rc_ptr.exit, !dbg !711

3:                                                ; preds = %entry
  %4 = add i64 %1, -1, !dbg !711
  store i64 %4, ptr %0, align 8, !dbg !711
  %5 = icmp eq i64 %1, -9223372036854775808, !dbg !711
  br i1 %5, label %6, label %2, !dbg !711

6:                                                ; preds = %3
  call void @roc_dealloc(ptr nonnull align 1 %0, i32 8), !dbg !711
  br label %roc_builtins.utils.decref_rc_ptr.exit, !dbg !711

roc_builtins.utils.decref_rc_ptr.exit:            ; preds = %6, %2
  ret void, !dbg !711
}

define private fastcc void @"#Attr_#inc_2"(ptr %"#arg1", i64 %0) !dbg !713 {
entry:
  %load_str_to_stack = load %str.RocStr, ptr %"#arg1", align 8, !dbg !714
  %read_str_capacity = extractvalue %str.RocStr %load_str_to_stack, 2, !dbg !714
  %is_big_str = icmp sgt i64 %read_str_capacity, 0, !dbg !714
  br i1 %is_big_str, label %modify_rc, label %modify_rc_str_cont, !dbg !714

modify_rc_str_cont:                               ; preds = %roc_builtins.utils.incref_rc_ptr.exit, %entry
  ret void, !dbg !714

modify_rc:                                        ; preds = %entry
  %call_builtin = call ptr @roc_builtins.str.allocation_ptr(ptr nocapture readonly %"#arg1"), !dbg !714
  %get_rc_ptr = getelementptr inbounds i64, ptr %call_builtin, i64 -1, !dbg !714
  %1 = load i64, ptr %get_rc_ptr, align 8, !dbg !714
  %.not.i = icmp eq i64 %1, 0, !dbg !714
  br i1 %.not.i, label %roc_builtins.utils.incref_rc_ptr.exit, label %2, !dbg !714

2:                                                ; preds = %modify_rc
  %3 = add nsw i64 %1, %0, !dbg !714
  store i64 %3, ptr %get_rc_ptr, align 8, !dbg !714
  br label %roc_builtins.utils.incref_rc_ptr.exit, !dbg !714

roc_builtins.utils.incref_rc_ptr.exit:            ; preds = %modify_rc, %2
  br label %modify_rc_str_cont, !dbg !714
}

define private fastcc void @"#Attr_#dec_3"(%list.RocList %"#arg1") !dbg !716 {
entry:
  %list_alloca = alloca %list.RocList, align 8
  store %list.RocList %"#arg1", ptr %list_alloca, align 8, !dbg !717
  %.sroa.0.0.copyload.i = load ptr, ptr %list_alloca, align 8, !dbg !717
  %.sroa.3.0..sroa_idx.i = getelementptr inbounds i8, ptr %list_alloca, i64 8, !dbg !717
  %.sroa.3.0.copyload.i = load i64, ptr %.sroa.3.0..sroa_idx.i, align 8, !dbg !717
  %.sroa.4.0..sroa_idx.i = getelementptr inbounds i8, ptr %list_alloca, i64 16, !dbg !717
  %.sroa.4.0.copyload.i = load i64, ptr %.sroa.4.0..sroa_idx.i, align 8, !dbg !717
  %.pre.i = ptrtoint ptr %.sroa.0.0.copyload.i to i64, !dbg !717
  %.pre2.i = shl i64 %.sroa.4.0.copyload.i, 1, !dbg !717
  %isneg.i.i.i = icmp slt i64 %.sroa.4.0.copyload.i, 0, !dbg !717
  %0 = select i1 %isneg.i.i.i, i64 %.pre2.i, i64 %.pre.i, !dbg !717
  %1 = icmp ne i64 %.sroa.4.0.copyload.i, 0, !dbg !717
  %2 = icmp ne i64 %0, 0, !dbg !717
  %or.cond.i.i.i = select i1 %1, i1 %2, i1 false, !dbg !717
  br i1 %or.cond.i.i.i, label %3, label %list.RocList.decref.exit.i, !dbg !717

3:                                                ; preds = %entry
  %4 = inttoptr i64 %0 to ptr, !dbg !717
  %5 = getelementptr inbounds i64, ptr %4, i64 -1, !dbg !717
  %6 = load i64, ptr %5, align 8, !dbg !717
  %.not.i.i.i = icmp eq i64 %6, 0, !dbg !717
  br i1 %.not.i.i.i, label %list.RocList.decref.exit.i, label %7, !dbg !717

7:                                                ; preds = %3
  %8 = add i64 %6, -1, !dbg !717
  store i64 %8, ptr %5, align 8, !dbg !717
  %9 = icmp eq i64 %6, -9223372036854775808, !dbg !717
  br i1 %9, label %10, label %list.RocList.decref.exit.i, !dbg !717

10:                                               ; preds = %7
  call void @roc_dealloc(ptr nonnull align 1 %5, i32 8), !dbg !717
  br label %roc_builtins.list.decref.exit, !dbg !717

list.RocList.decref.exit.i:                       ; preds = %7, %3, %entry
  br label %roc_builtins.list.decref.exit, !dbg !717

roc_builtins.list.decref.exit:                    ; preds = %list.RocList.decref.exit.i, %10
  ret void, !dbg !717
}

define private fastcc void @"#Attr_#dec_4"(%list.RocList %"#arg1") !dbg !719 {
entry:
  %list_alloca = alloca %list.RocList, align 8
  store %list.RocList %"#arg1", ptr %list_alloca, align 8, !dbg !720
  %.sroa.0.0.copyload.i = load ptr, ptr %list_alloca, align 8, !dbg !720
  %.sroa.3.0..sroa_idx.i = getelementptr inbounds i8, ptr %list_alloca, i64 8, !dbg !720
  %.sroa.3.0.copyload.i = load i64, ptr %.sroa.3.0..sroa_idx.i, align 8, !dbg !720
  %.sroa.4.0..sroa_idx.i = getelementptr inbounds i8, ptr %list_alloca, i64 16, !dbg !720
  %.sroa.4.0.copyload.i = load i64, ptr %.sroa.4.0..sroa_idx.i, align 8, !dbg !720
  %isneg.i.i.i.i.i = icmp slt i64 %.sroa.4.0.copyload.i, 0, !dbg !720
  %0 = call i64 @llvm.smax.i64(i64 %.sroa.4.0.copyload.i, i64 0), !dbg !720
  %1 = select i1 %isneg.i.i.i.i.i, i64 %.sroa.3.0.copyload.i, i64 0, !dbg !720
  %2 = or i64 %1, %0, !dbg !720
  %3 = icmp ne i64 %2, 0, !dbg !720
  %brmerge.i.i.i.i = select i1 %3, i1 true, i1 %isneg.i.i.i.i.i, !dbg !720
  %4 = ptrtoint ptr %.sroa.0.0.copyload.i to i64, !dbg !720
  %5 = shl i64 %.sroa.4.0.copyload.i, 1, !dbg !720
  br i1 %brmerge.i.i.i.i, label %list.RocList.isUnique.exit.i.i, label %list.RocList.isUnique.exit.thread.i.i, !dbg !720

.critedge.i.i:                                    ; preds = %.lr.ph.i.i, %list.RocList.getAllocationElementCount.exit.i.i, %list.RocList.isUnique.exit.thread.i.i, %list.RocList.isUnique.exit.i.i
  %.pre-phi.i = phi i64 [ %31, %list.RocList.getAllocationElementCount.exit.i.i ], [ %25, %list.RocList.isUnique.exit.thread.i.i ], [ %18, %list.RocList.isUnique.exit.i.i ], [ %32, %.lr.ph.i.i ], !dbg !720
  %isneg.i.i.i = icmp slt i64 %.sroa.4.0.copyload.i, 0, !dbg !720
  %6 = select i1 %isneg.i.i.i, i64 %5, i64 %.pre-phi.i, !dbg !720
  %7 = icmp ne i64 %.sroa.4.0.copyload.i, 0, !dbg !720
  %8 = icmp ne i64 %6, 0, !dbg !720
  %or.cond.i.i.i = select i1 %7, i1 %8, i1 false, !dbg !720
  br i1 %or.cond.i.i.i, label %9, label %list.RocList.decref.exit.i, !dbg !720

9:                                                ; preds = %.critedge.i.i
  %10 = inttoptr i64 %6 to ptr, !dbg !720
  %11 = getelementptr inbounds i64, ptr %10, i64 -1, !dbg !720
  %12 = load i64, ptr %11, align 8, !dbg !720
  %.not.i.i.i = icmp eq i64 %12, 0, !dbg !720
  br i1 %.not.i.i.i, label %list.RocList.decref.exit.i, label %13, !dbg !720

13:                                               ; preds = %9
  %14 = add i64 %12, -1, !dbg !720
  store i64 %14, ptr %11, align 8, !dbg !720
  %15 = icmp eq i64 %12, -9223372036854775808, !dbg !720
  br i1 %15, label %16, label %list.RocList.decref.exit.i, !dbg !720

16:                                               ; preds = %13
  %17 = getelementptr inbounds i8, ptr %11, i64 -8, !dbg !720
  call void @roc_dealloc(ptr nonnull align 1 %17, i32 8), !dbg !720
  br label %roc_builtins.list.decref.exit, !dbg !720

list.RocList.isUnique.exit.i.i:                   ; preds = %entry
  %18 = ptrtoint ptr %.sroa.0.0.copyload.i to i64, !dbg !720
  %19 = icmp slt i64 %.sroa.4.0.copyload.i, 0, !dbg !720
  %20 = select i1 %19, i64 %5, i64 %18, !dbg !720
  %21 = inttoptr i64 %20 to ptr, !dbg !720
  %22 = getelementptr inbounds i64, ptr %21, i64 -1, !dbg !720
  %23 = load i64, ptr %22, align 8, !dbg !720
  %24 = icmp eq i64 %23, -9223372036854775808, !dbg !720
  br i1 %24, label %list.RocList.isUnique.exit.thread.i.i, label %.critedge.i.i, !dbg !720

list.RocList.isUnique.exit.thread.i.i:            ; preds = %list.RocList.isUnique.exit.i.i, %entry
  %.pre-phi22.i.i = phi ptr [ %21, %list.RocList.isUnique.exit.i.i ], [ %.sroa.0.0.copyload.i, %entry ], !dbg !720
  %.pre-phi20.i.i = phi i64 [ %20, %list.RocList.isUnique.exit.i.i ], [ %4, %entry ], !dbg !720
  %25 = ptrtoint ptr %.sroa.0.0.copyload.i to i64, !dbg !720
  %.not.i.i = icmp eq i64 %.pre-phi20.i.i, 0, !dbg !720
  br i1 %.not.i.i, label %.critedge.i.i, label %26, !dbg !720

26:                                               ; preds = %list.RocList.isUnique.exit.thread.i.i
  %27 = icmp slt i64 %.sroa.4.0.copyload.i, 0, !dbg !720
  br i1 %27, label %28, label %list.RocList.getAllocationElementCount.exit.i.i, !dbg !720

28:                                               ; preds = %26
  %29 = inttoptr i64 %5 to ptr, !dbg !720
  %30 = getelementptr inbounds i64, ptr %29, i64 -2, !dbg !720
  %common.ret.op.in.i.sroa.speculate.load.10.i.i = load i64, ptr %30, align 8, !dbg !720
  br label %list.RocList.getAllocationElementCount.exit.i.i, !dbg !720

list.RocList.getAllocationElementCount.exit.i.i:  ; preds = %28, %26
  %common.ret.op.in.i.sroa.speculated.i.i = phi i64 [ %common.ret.op.in.i.sroa.speculate.load.10.i.i, %28 ], [ %.sroa.3.0.copyload.i, %26 ], !dbg !720
  %31 = ptrtoint ptr %.sroa.0.0.copyload.i to i64, !dbg !720
  %.not16.i.i = icmp eq i64 %common.ret.op.in.i.sroa.speculated.i.i, 0, !dbg !720
  br i1 %.not16.i.i, label %.critedge.i.i, label %.lr.ph.i.preheader.i, !dbg !720

.lr.ph.i.preheader.i:                             ; preds = %list.RocList.getAllocationElementCount.exit.i.i
  br label %.lr.ph.i.i, !dbg !720

.lr.ph.i.i:                                       ; preds = %.lr.ph.i.i, %.lr.ph.i.preheader.i
  %lsr.iv4.i = phi ptr [ %.pre-phi22.i.i, %.lr.ph.i.preheader.i ], [ %uglygep.i, %.lr.ph.i.i ], !dbg !720
  %lsr.iv.i = phi i64 [ %common.ret.op.in.i.sroa.speculated.i.i, %.lr.ph.i.preheader.i ], [ %lsr.iv.next.i, %.lr.ph.i.i ], !dbg !720
  %32 = ptrtoint ptr %.sroa.0.0.copyload.i to i64, !dbg !720
  call fastcc void @"#Attr_#dec_5"(ptr %lsr.iv4.i) #14, !dbg !722
  %lsr.iv.next.i = add i64 %lsr.iv.i, -1, !dbg !720
  %uglygep.i = getelementptr i8, ptr %lsr.iv4.i, i64 48, !dbg !720
  %exitcond.not.i.i = icmp eq i64 %lsr.iv.next.i, 0, !dbg !720
  br i1 %exitcond.not.i.i, label %.critedge.i.i, label %.lr.ph.i.i, !dbg !720

list.RocList.decref.exit.i:                       ; preds = %13, %9, %.critedge.i.i
  br label %roc_builtins.list.decref.exit, !dbg !720

roc_builtins.list.decref.exit:                    ; preds = %list.RocList.decref.exit.i, %16
  ret void, !dbg !720
}

define private fastcc void @"#Attr_#dec_5"(ptr %"#arg1") !dbg !726 {
entry:
  %struct_field1 = alloca %str.RocStr, align 8, !dbg !727
  %struct_field = alloca %str.RocStr, align 8, !dbg !727
  %struct_field_access_record_0 = getelementptr inbounds { %str.RocStr, %str.RocStr }, ptr %"#arg1", i32 0, i32 0, !dbg !727
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %struct_field, ptr align 8 %struct_field_access_record_0, i64 ptrtoint (ptr getelementptr (%str.RocStr, ptr null, i32 1) to i64), i1 false), !dbg !727
  call fastcc void @"#Attr_#dec_2"(ptr %struct_field), !dbg !727
  %struct_field_access_record_1 = getelementptr inbounds { %str.RocStr, %str.RocStr }, ptr %"#arg1", i32 0, i32 1, !dbg !727
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %struct_field1, ptr align 8 %struct_field_access_record_1, i64 ptrtoint (ptr getelementptr (%str.RocStr, ptr null, i32 1) to i64), i1 false), !dbg !727
  call fastcc void @"#Attr_#dec_2"(ptr %struct_field1), !dbg !727
  ret void, !dbg !727
}

define private fastcc void @"#Attr_#dec_6"(%list.RocList %"#arg1") !dbg !729 {
entry:
  %list_alloca = alloca %list.RocList, align 8
  store %list.RocList %"#arg1", ptr %list_alloca, align 8, !dbg !730
  %.sroa.0.0.copyload.i = load ptr, ptr %list_alloca, align 8, !dbg !730
  %.sroa.3.0..sroa_idx.i = getelementptr inbounds i8, ptr %list_alloca, i64 8, !dbg !730
  %.sroa.3.0.copyload.i = load i64, ptr %.sroa.3.0..sroa_idx.i, align 8, !dbg !730
  %.sroa.4.0..sroa_idx.i = getelementptr inbounds i8, ptr %list_alloca, i64 16, !dbg !730
  %.sroa.4.0.copyload.i = load i64, ptr %.sroa.4.0..sroa_idx.i, align 8, !dbg !730
  %.pre.i = ptrtoint ptr %.sroa.0.0.copyload.i to i64, !dbg !730
  %.pre2.i = shl i64 %.sroa.4.0.copyload.i, 1, !dbg !730
  %isneg.i.i.i = icmp slt i64 %.sroa.4.0.copyload.i, 0, !dbg !730
  %0 = select i1 %isneg.i.i.i, i64 %.pre2.i, i64 %.pre.i, !dbg !730
  %1 = icmp ne i64 %.sroa.4.0.copyload.i, 0, !dbg !730
  %2 = icmp ne i64 %0, 0, !dbg !730
  %or.cond.i.i.i = select i1 %1, i1 %2, i1 false, !dbg !730
  br i1 %or.cond.i.i.i, label %3, label %list.RocList.decref.exit.i, !dbg !730

3:                                                ; preds = %entry
  %4 = inttoptr i64 %0 to ptr, !dbg !730
  %5 = getelementptr inbounds i64, ptr %4, i64 -1, !dbg !730
  %6 = load i64, ptr %5, align 8, !dbg !730
  %.not.i.i.i = icmp eq i64 %6, 0, !dbg !730
  br i1 %.not.i.i.i, label %list.RocList.decref.exit.i, label %7, !dbg !730

7:                                                ; preds = %3
  %8 = add i64 %6, -1, !dbg !730
  store i64 %8, ptr %5, align 8, !dbg !730
  %9 = icmp eq i64 %6, -9223372036854775808, !dbg !730
  br i1 %9, label %10, label %list.RocList.decref.exit.i, !dbg !730

10:                                               ; preds = %7
  %11 = getelementptr inbounds i8, ptr %5, i64 -8, !dbg !730
  call void @roc_dealloc(ptr nonnull align 1 %11, i32 16), !dbg !730
  br label %roc_builtins.list.decref.exit, !dbg !730

list.RocList.decref.exit.i:                       ; preds = %7, %3, %entry
  br label %roc_builtins.list.decref.exit, !dbg !730

roc_builtins.list.decref.exit:                    ; preds = %list.RocList.decref.exit.i, %10
  ret void, !dbg !730
}

define private fastcc void @"#Attr_#dec_7"({ { %str.RocStr, {} }, {} } %"#arg1") !dbg !732 {
entry:
  %struct_field_access_record_0 = extractvalue { { %str.RocStr, {} }, {} } %"#arg1", 0, !dbg !733
  call fastcc void @"#Attr_#dec_8"({ %str.RocStr, {} } %struct_field_access_record_0), !dbg !733
  ret void, !dbg !733
}

define private fastcc void @"#Attr_#dec_8"({ %str.RocStr, {} } %"#arg1") !dbg !735 {
entry:
  %struct_field = alloca %str.RocStr, align 8, !dbg !736
  %struct_field_access_record_0 = extractvalue { %str.RocStr, {} } %"#arg1", 0, !dbg !736
  store %str.RocStr %struct_field_access_record_0, ptr %struct_field, align 8, !dbg !736
  call fastcc void @"#Attr_#dec_2"(ptr %struct_field), !dbg !736
  ret void, !dbg !736
}

define private fastcc void @"#Attr_#inc_6"(%list.RocList %"#arg1", i64 %"#arg2") !dbg !738 {
entry:
  %list_alloca = alloca %list.RocList, align 8
  store %list.RocList %"#arg1", ptr %list_alloca, align 8, !dbg !739
  %.sroa.0.0.copyload.i = load ptr, ptr %list_alloca, align 8, !dbg !739
  %.sroa.3.0..sroa_idx.i = getelementptr inbounds i8, ptr %list_alloca, i64 8, !dbg !739
  %.sroa.3.0.copyload.i = load i64, ptr %.sroa.3.0..sroa_idx.i, align 8, !dbg !739
  %.sroa.4.0..sroa_idx.i = getelementptr inbounds i8, ptr %list_alloca, i64 16, !dbg !739
  %.sroa.4.0.copyload.i = load i64, ptr %.sroa.4.0..sroa_idx.i, align 8, !dbg !739
  %0 = ptrtoint ptr %.sroa.0.0.copyload.i to i64, !dbg !739
  %1 = shl i64 %.sroa.4.0.copyload.i, 1, !dbg !739
  %isneg.i.i.i = icmp slt i64 %.sroa.4.0.copyload.i, 0, !dbg !739
  %2 = select i1 %isneg.i.i.i, i64 %1, i64 %0, !dbg !739
  %.not.i.i.i = icmp eq i64 %2, 0, !dbg !739
  br i1 %.not.i.i.i, label %roc_builtins.list.incref.exit, label %3, !dbg !739

3:                                                ; preds = %entry
  %4 = and i64 %2, -8, !dbg !739
  %5 = add i64 %4, -8, !dbg !739
  %6 = inttoptr i64 %5 to ptr, !dbg !739
  %7 = load i64, ptr %6, align 8, !dbg !739
  %.not.i.i.i.i = icmp eq i64 %7, 0, !dbg !739
  br i1 %.not.i.i.i.i, label %roc_builtins.list.incref.exit, label %8, !dbg !739

8:                                                ; preds = %3
  %9 = add nsw i64 %7, %"#arg2", !dbg !739
  %sunkaddr.i = inttoptr i64 %4 to ptr, !dbg !739
  %sunkaddr2.i = getelementptr i8, ptr %sunkaddr.i, i64 -8, !dbg !739
  store i64 %9, ptr %sunkaddr2.i, align 8, !dbg !739
  br label %roc_builtins.list.incref.exit, !dbg !739

roc_builtins.list.incref.exit:                    ; preds = %entry, %3, %8
  ret void, !dbg !739
}

declare void @roc_fx_stderrLine(ptr)

define internal fastcc {} @roc_fx_stderrLine_fastcc_wrapper(ptr %0) {
entry:
  %return_value = alloca {}, align 8
  call void @roc_fx_stderrLine(ptr %0), !dbg !486
  ret {} zeroinitializer, !dbg !486
}

; Function Attrs: cold noinline noreturn
define internal fastcc void @throw_on_overflow() #13 {
entry:
  %const_str_store = alloca %str.RocStr, align 8
  store %str.RocStr { ptr getelementptr inbounds (i8, ptr @_str_literal_13609154173082167094, i64 8), i64 28, i64 28 }, ptr %const_str_store, align 8, !dbg !498
  call void @roc_panic(ptr %const_str_store, i32 0), !dbg !498
  unreachable, !dbg !498
}

declare i128 @roc_fx_posixTime()

define internal fastcc i128 @roc_fx_posixTime_fastcc_wrapper() {
entry:
  %return_value = alloca i128, align 16
  %tmp = call i128 @roc_fx_posixTime(), !dbg !606
  ret i128 %tmp, !dbg !606
}

declare void @roc_fx_stdoutLine(ptr)

define internal fastcc {} @roc_fx_stdoutLine_fastcc_wrapper(ptr %0) {
entry:
  %return_value = alloca {}, align 8
  call void @roc_fx_stdoutLine(ptr %0), !dbg !615
  ret {} zeroinitializer, !dbg !615
}

define private fastcc void @"#Attr_#dec_17"(ptr %"#arg1") !dbg !741 {
entry:
  %struct_field3 = alloca %str.RocStr, align 8, !dbg !742
  %struct_field2 = alloca %str.RocStr, align 8, !dbg !742
  %struct_field_access_record_0 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %"#arg1", i32 0, i32 0, !dbg !742
  %struct_field = load %list.RocList, ptr %struct_field_access_record_0, align 8, !dbg !742
  call fastcc void @"#Attr_#dec_3"(%list.RocList %struct_field), !dbg !742
  %struct_field_access_record_1 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %"#arg1", i32 0, i32 1, !dbg !742
  %struct_field1 = load %list.RocList, ptr %struct_field_access_record_1, align 8, !dbg !742
  call fastcc void @"#Attr_#dec_4"(%list.RocList %struct_field1), !dbg !742
  %struct_field_access_record_2 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %"#arg1", i32 0, i32 2, !dbg !742
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %struct_field2, ptr align 8 %struct_field_access_record_2, i64 ptrtoint (ptr getelementptr (%str.RocStr, ptr null, i32 1) to i64), i1 false), !dbg !742
  call fastcc void @"#Attr_#dec_2"(ptr %struct_field2), !dbg !742
  %struct_field_access_record_4 = getelementptr inbounds { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, ptr %"#arg1", i32 0, i32 4, !dbg !742
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %struct_field3, ptr align 8 %struct_field_access_record_4, i64 ptrtoint (ptr getelementptr (%str.RocStr, ptr null, i32 1) to i64), i1 false), !dbg !742
  call fastcc void @"#Attr_#dec_2"(ptr %struct_field3), !dbg !742
  ret void, !dbg !742
}

define private fastcc void @"#Attr_#dec_18"(ptr %"#arg1") !dbg !744 {
entry:
  br label %should_recurse, !dbg !745

should_recurse:                                   ; preds = %entry
  %get_rc_ptr = getelementptr inbounds i64, ptr %"#arg1", i64 -1, !dbg !745
  %get_refcount = load i64, ptr %get_rc_ptr, align 8, !dbg !745
  %is_one = icmp eq i64 %get_refcount, -9223372036854775808, !dbg !745
  br i1 %is_one, label %do_recurse, label %no_recurse, !dbg !745

do_recurse:                                       ; preds = %should_recurse
  br label %tag_id_decrement, !dbg !745

no_recurse:                                       ; preds = %should_recurse
  call fastcc void @decrement_refcounted_ptr_8(ptr %get_rc_ptr), !dbg !745
  ret void, !dbg !745

tag_id_decrement:                                 ; preds = %do_recurse
  call fastcc void @decrement_refcounted_ptr_8(ptr %get_rc_ptr), !dbg !745
  ret void, !dbg !745
}

define void @roc__forHost_2_caller(ptr %0, ptr %1, ptr %2) {
entry:
  %result_value = alloca { %list.RocList, %list.RocList, i16 }, align 8, !dbg !705
  %load_param = load {}, ptr %0, align 1, !dbg !705
  call fastcc void @_149_481f1278f2de6c4b7025bbe3547d9acb112f26631793a1e4c8c76b99b179e0({} %load_param, ptr %1, ptr %result_value), !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %2, ptr align 8 %result_value, i64 ptrtoint (ptr getelementptr ({ %list.RocList, %list.RocList, i16 }, ptr null, i32 1) to i64), i1 false), !dbg !705
  ret void, !dbg !705
}

define i64 @roc__forHost_2_result_size() {
entry:
  ret i64 ptrtoint (ptr getelementptr ({ %list.RocList, %list.RocList, i16 }, ptr null, i32 1) to i64), !dbg !705
}

define i64 @roc__forHost_2_size() {
entry:
  ret i64 ptrtoint (ptr getelementptr ({ { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, {} }, ptr null, i32 1) to i64), !dbg !705
}

define void @roc__forHost_0_caller(ptr %0, ptr %1, ptr %2) {
entry:
  %result_value = alloca { [0 x i64], [1 x i64], i8, [7 x i8] }, align 8, !dbg !705
  %load_param = load {}, ptr %0, align 1, !dbg !705
  %load_param1 = load { { { %str.RocStr, {} }, {} }, {} }, ptr %1, align 8, !dbg !705
  call fastcc void @_152_55d628abedfcc0e78784ef0cac7a0c47c774ce17d4fb8ba44f37721d7f3d98({} %load_param, { { { %str.RocStr, {} }, {} }, {} } %load_param1, ptr %result_value), !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %2, ptr align 8 %result_value, i64 ptrtoint (ptr getelementptr ({ [0 x i64], [1 x i64], i8, [7 x i8] }, ptr null, i32 1) to i64), i1 false), !dbg !705
  ret void, !dbg !705
}

define i64 @roc__forHost_0_result_size() {
entry:
  ret i64 ptrtoint (ptr getelementptr ({ [0 x i64], [1 x i64], i8, [7 x i8] }, ptr null, i32 1) to i64), !dbg !705
}

define i64 @roc__forHost_0_size() {
entry:
  ret i64 ptrtoint (ptr getelementptr ({ { { %str.RocStr, {} }, {} }, {} }, ptr null, i32 1) to i64), !dbg !705
}

define void @roc__forHost_1_caller(ptr %0, ptr %1, ptr %2, ptr %3) {
entry:
  %result_value = alloca { { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, {} }, align 8, !dbg !705
  %load_param = load ptr, ptr %1, align 8, !dbg !705
  %load_param1 = load {}, ptr %2, align 1, !dbg !705
  call fastcc void @_155_9b7306a2e571f3d11e34b901a57455c3e32e69a2f8fde813ed1c4300e12712(ptr %0, ptr %load_param, {} %load_param1, ptr %result_value), !dbg !705
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %3, ptr align 8 %result_value, i64 ptrtoint (ptr getelementptr ({ { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, {} }, ptr null, i32 1) to i64), i1 false), !dbg !705
  ret void, !dbg !705
}

define i64 @roc__forHost_1_result_size() {
entry:
  ret i64 ptrtoint (ptr getelementptr ({ { { { %list.RocList, %list.RocList, %str.RocStr, { [0 x i64], [1 x i64], i8, [7 x i8] }, %str.RocStr, i8 }, { { { {}, {} }, {} }, {} } }, {} }, {} }, ptr null, i32 1) to i64), !dbg !705
}

define i64 @roc__forHost_1_size() {
entry:
  ret i64 ptrtoint (ptr getelementptr ({}, ptr null, i32 1) to i64), !dbg !705
}

attributes #0 = { nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #1 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #2 = { nocallback nofree nounwind willreturn memory(argmem: write) }
attributes #3 = { mustprogress nofree nosync nounwind willreturn memory(argmem: readwrite) uwtable "frame-pointer"="none" "target-cpu"="generic" "target-features"="-a510,-a65,-a710,-a76,-a78,-a78c,-aes,-aggressive-fma,-alternate-sextload-cvt-f32-pattern,-altnzcv,-am,-amvs,-arith-bcc-fusion,-arith-cbz-fusion,-ascend-store-address,-b16b16,-balance-fp-ops,-bf16,-brbe,-bti,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-ccdp,-ccidx,-ccpp,-clrbhb,-cmp-bcc-fusion,-complxnum,-CONTEXTIDREL2,-cortex-r82,-crc,-crypto,-cssc,-custom-cheap-as-move,-d128,-disable-latency-sched-heuristic,-dit,-dotprod,-ecv,-el2vmsa,-el3,+enable-select-opt,+ete,-exynos-cheap-as-move,-f32mm,-f64mm,-fgt,-fix-cortex-a53-835769,-flagm,-fmv,-force-32bit-jump-tables,-fp16fml,+fp-armv8,-fptoint,-fullfp16,-fuse-address,+fuse-adrp-add,+fuse-aes,-fuse-arith-logic,-fuse-crypto-eor,-fuse-csel,-fuse-literals,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-hcx,-i8mm,-ite,-jsconv,-lor,-ls64,-lse,-lse128,-lse2,-lsl-fast,-mec,-mops,-mpam,-mte,+neon,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-zcz-fp,-nv,-outline-atomics,-pan,-pan-rwv,-pauth,-perfmon,-predictable-select-expensive,-predres,-prfm-slc-target,-rand,-ras,-rasv2,-rcpc,-rcpc3,-rcpc-immo,-rdm,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x30,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-sb,-sel2,-sha2,-sha3,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme,-sme2,-sme2p1,-sme-f16f16,-sme-f64f64,-sme-i16i64,-spe,-spe-eef,-specres2,-specrestrict,-ssbs,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-tagged-globals,-the,-tlb-rmi,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tracev8.4,+trbe,-uaops,-use-experimental-zeroing-pseudos,+use-postra-scheduler,-use-reciprocal-square-root,-use-scalar-inc-vl,-v8.1a,-v8.2a,-v8.3a,-v8.4a,-v8.5a,-v8.6a,-v8.7a,-v8.8a,-v8.9a,-v8a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9a,-vh,-wfxt,-xs,-zcm,-zcz,-zcz-fp-workaround,-zcz-gp" }
attributes #4 = { nounwind uwtable "frame-pointer"="none" "target-cpu"="generic" "target-features"="-a510,-a65,-a710,-a76,-a78,-a78c,-aes,-aggressive-fma,-alternate-sextload-cvt-f32-pattern,-altnzcv,-am,-amvs,-arith-bcc-fusion,-arith-cbz-fusion,-ascend-store-address,-b16b16,-balance-fp-ops,-bf16,-brbe,-bti,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-ccdp,-ccidx,-ccpp,-clrbhb,-cmp-bcc-fusion,-complxnum,-CONTEXTIDREL2,-cortex-r82,-crc,-crypto,-cssc,-custom-cheap-as-move,-d128,-disable-latency-sched-heuristic,-dit,-dotprod,-ecv,-el2vmsa,-el3,+enable-select-opt,+ete,-exynos-cheap-as-move,-f32mm,-f64mm,-fgt,-fix-cortex-a53-835769,-flagm,-fmv,-force-32bit-jump-tables,-fp16fml,+fp-armv8,-fptoint,-fullfp16,-fuse-address,+fuse-adrp-add,+fuse-aes,-fuse-arith-logic,-fuse-crypto-eor,-fuse-csel,-fuse-literals,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-hcx,-i8mm,-ite,-jsconv,-lor,-ls64,-lse,-lse128,-lse2,-lsl-fast,-mec,-mops,-mpam,-mte,+neon,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-zcz-fp,-nv,-outline-atomics,-pan,-pan-rwv,-pauth,-perfmon,-predictable-select-expensive,-predres,-prfm-slc-target,-rand,-ras,-rasv2,-rcpc,-rcpc3,-rcpc-immo,-rdm,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x30,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-sb,-sel2,-sha2,-sha3,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme,-sme2,-sme2p1,-sme-f16f16,-sme-f64f64,-sme-i16i64,-spe,-spe-eef,-specres2,-specrestrict,-ssbs,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-tagged-globals,-the,-tlb-rmi,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tracev8.4,+trbe,-uaops,-use-experimental-zeroing-pseudos,+use-postra-scheduler,-use-reciprocal-square-root,-use-scalar-inc-vl,-v8.1a,-v8.2a,-v8.3a,-v8.4a,-v8.5a,-v8.6a,-v8.7a,-v8.8a,-v8.9a,-v8a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9a,-vh,-wfxt,-xs,-zcm,-zcz,-zcz-fp-workaround,-zcz-gp" }
attributes #5 = { nofree nosync nounwind memory(read, argmem: readwrite, inaccessiblemem: none) uwtable "frame-pointer"="none" "target-cpu"="generic" "target-features"="-a510,-a65,-a710,-a76,-a78,-a78c,-aes,-aggressive-fma,-alternate-sextload-cvt-f32-pattern,-altnzcv,-am,-amvs,-arith-bcc-fusion,-arith-cbz-fusion,-ascend-store-address,-b16b16,-balance-fp-ops,-bf16,-brbe,-bti,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-ccdp,-ccidx,-ccpp,-clrbhb,-cmp-bcc-fusion,-complxnum,-CONTEXTIDREL2,-cortex-r82,-crc,-crypto,-cssc,-custom-cheap-as-move,-d128,-disable-latency-sched-heuristic,-dit,-dotprod,-ecv,-el2vmsa,-el3,+enable-select-opt,+ete,-exynos-cheap-as-move,-f32mm,-f64mm,-fgt,-fix-cortex-a53-835769,-flagm,-fmv,-force-32bit-jump-tables,-fp16fml,+fp-armv8,-fptoint,-fullfp16,-fuse-address,+fuse-adrp-add,+fuse-aes,-fuse-arith-logic,-fuse-crypto-eor,-fuse-csel,-fuse-literals,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-hcx,-i8mm,-ite,-jsconv,-lor,-ls64,-lse,-lse128,-lse2,-lsl-fast,-mec,-mops,-mpam,-mte,+neon,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-zcz-fp,-nv,-outline-atomics,-pan,-pan-rwv,-pauth,-perfmon,-predictable-select-expensive,-predres,-prfm-slc-target,-rand,-ras,-rasv2,-rcpc,-rcpc3,-rcpc-immo,-rdm,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x30,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-sb,-sel2,-sha2,-sha3,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme,-sme2,-sme2p1,-sme-f16f16,-sme-f64f64,-sme-i16i64,-spe,-spe-eef,-specres2,-specrestrict,-ssbs,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-tagged-globals,-the,-tlb-rmi,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tracev8.4,+trbe,-uaops,-use-experimental-zeroing-pseudos,+use-postra-scheduler,-use-reciprocal-square-root,-use-scalar-inc-vl,-v8.1a,-v8.2a,-v8.3a,-v8.4a,-v8.5a,-v8.6a,-v8.7a,-v8.8a,-v8.9a,-v8a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9a,-vh,-wfxt,-xs,-zcm,-zcz,-zcz-fp-workaround,-zcz-gp" }
attributes #6 = { noreturn nounwind uwtable "frame-pointer"="none" "target-cpu"="generic" "target-features"="-a510,-a65,-a710,-a76,-a78,-a78c,-aes,-aggressive-fma,-alternate-sextload-cvt-f32-pattern,-altnzcv,-am,-amvs,-arith-bcc-fusion,-arith-cbz-fusion,-ascend-store-address,-b16b16,-balance-fp-ops,-bf16,-brbe,-bti,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-ccdp,-ccidx,-ccpp,-clrbhb,-cmp-bcc-fusion,-complxnum,-CONTEXTIDREL2,-cortex-r82,-crc,-crypto,-cssc,-custom-cheap-as-move,-d128,-disable-latency-sched-heuristic,-dit,-dotprod,-ecv,-el2vmsa,-el3,+enable-select-opt,+ete,-exynos-cheap-as-move,-f32mm,-f64mm,-fgt,-fix-cortex-a53-835769,-flagm,-fmv,-force-32bit-jump-tables,-fp16fml,+fp-armv8,-fptoint,-fullfp16,-fuse-address,+fuse-adrp-add,+fuse-aes,-fuse-arith-logic,-fuse-crypto-eor,-fuse-csel,-fuse-literals,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-hcx,-i8mm,-ite,-jsconv,-lor,-ls64,-lse,-lse128,-lse2,-lsl-fast,-mec,-mops,-mpam,-mte,+neon,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-zcz-fp,-nv,-outline-atomics,-pan,-pan-rwv,-pauth,-perfmon,-predictable-select-expensive,-predres,-prfm-slc-target,-rand,-ras,-rasv2,-rcpc,-rcpc3,-rcpc-immo,-rdm,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x30,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-sb,-sel2,-sha2,-sha3,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme,-sme2,-sme2p1,-sme-f16f16,-sme-f64f64,-sme-i16i64,-spe,-spe-eef,-specres2,-specrestrict,-ssbs,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-tagged-globals,-the,-tlb-rmi,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tracev8.4,+trbe,-uaops,-use-experimental-zeroing-pseudos,+use-postra-scheduler,-use-reciprocal-square-root,-use-scalar-inc-vl,-v8.1a,-v8.2a,-v8.3a,-v8.4a,-v8.5a,-v8.6a,-v8.7a,-v8.8a,-v8.9a,-v8a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9a,-vh,-wfxt,-xs,-zcm,-zcz,-zcz-fp-workaround,-zcz-gp" }
attributes #7 = { nofree nosync nounwind memory(argmem: write) uwtable "frame-pointer"="none" "target-cpu"="generic" "target-features"="-a510,-a65,-a710,-a76,-a78,-a78c,-aes,-aggressive-fma,-alternate-sextload-cvt-f32-pattern,-altnzcv,-am,-amvs,-arith-bcc-fusion,-arith-cbz-fusion,-ascend-store-address,-b16b16,-balance-fp-ops,-bf16,-brbe,-bti,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-ccdp,-ccidx,-ccpp,-clrbhb,-cmp-bcc-fusion,-complxnum,-CONTEXTIDREL2,-cortex-r82,-crc,-crypto,-cssc,-custom-cheap-as-move,-d128,-disable-latency-sched-heuristic,-dit,-dotprod,-ecv,-el2vmsa,-el3,+enable-select-opt,+ete,-exynos-cheap-as-move,-f32mm,-f64mm,-fgt,-fix-cortex-a53-835769,-flagm,-fmv,-force-32bit-jump-tables,-fp16fml,+fp-armv8,-fptoint,-fullfp16,-fuse-address,+fuse-adrp-add,+fuse-aes,-fuse-arith-logic,-fuse-crypto-eor,-fuse-csel,-fuse-literals,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-hcx,-i8mm,-ite,-jsconv,-lor,-ls64,-lse,-lse128,-lse2,-lsl-fast,-mec,-mops,-mpam,-mte,+neon,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-zcz-fp,-nv,-outline-atomics,-pan,-pan-rwv,-pauth,-perfmon,-predictable-select-expensive,-predres,-prfm-slc-target,-rand,-ras,-rasv2,-rcpc,-rcpc3,-rcpc-immo,-rdm,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x30,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-sb,-sel2,-sha2,-sha3,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme,-sme2,-sme2p1,-sme-f16f16,-sme-f64f64,-sme-i16i64,-spe,-spe-eef,-specres2,-specrestrict,-ssbs,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-tagged-globals,-the,-tlb-rmi,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tracev8.4,+trbe,-uaops,-use-experimental-zeroing-pseudos,+use-postra-scheduler,-use-reciprocal-square-root,-use-scalar-inc-vl,-v8.1a,-v8.2a,-v8.3a,-v8.4a,-v8.5a,-v8.6a,-v8.7a,-v8.8a,-v8.9a,-v8a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9a,-vh,-wfxt,-xs,-zcm,-zcz,-zcz-fp-workaround,-zcz-gp" }
attributes #8 = { nofree nosync nounwind memory(argmem: readwrite, inaccessiblemem: readwrite) uwtable "frame-pointer"="none" "target-cpu"="generic" "target-features"="-a510,-a65,-a710,-a76,-a78,-a78c,-aes,-aggressive-fma,-alternate-sextload-cvt-f32-pattern,-altnzcv,-am,-amvs,-arith-bcc-fusion,-arith-cbz-fusion,-ascend-store-address,-b16b16,-balance-fp-ops,-bf16,-brbe,-bti,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-ccdp,-ccidx,-ccpp,-clrbhb,-cmp-bcc-fusion,-complxnum,-CONTEXTIDREL2,-cortex-r82,-crc,-crypto,-cssc,-custom-cheap-as-move,-d128,-disable-latency-sched-heuristic,-dit,-dotprod,-ecv,-el2vmsa,-el3,+enable-select-opt,+ete,-exynos-cheap-as-move,-f32mm,-f64mm,-fgt,-fix-cortex-a53-835769,-flagm,-fmv,-force-32bit-jump-tables,-fp16fml,+fp-armv8,-fptoint,-fullfp16,-fuse-address,+fuse-adrp-add,+fuse-aes,-fuse-arith-logic,-fuse-crypto-eor,-fuse-csel,-fuse-literals,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-hcx,-i8mm,-ite,-jsconv,-lor,-ls64,-lse,-lse128,-lse2,-lsl-fast,-mec,-mops,-mpam,-mte,+neon,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-zcz-fp,-nv,-outline-atomics,-pan,-pan-rwv,-pauth,-perfmon,-predictable-select-expensive,-predres,-prfm-slc-target,-rand,-ras,-rasv2,-rcpc,-rcpc3,-rcpc-immo,-rdm,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x30,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-sb,-sel2,-sha2,-sha3,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme,-sme2,-sme2p1,-sme-f16f16,-sme-f64f64,-sme-i16i64,-spe,-spe-eef,-specres2,-specrestrict,-ssbs,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-tagged-globals,-the,-tlb-rmi,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tracev8.4,+trbe,-uaops,-use-experimental-zeroing-pseudos,+use-postra-scheduler,-use-reciprocal-square-root,-use-scalar-inc-vl,-v8.1a,-v8.2a,-v8.3a,-v8.4a,-v8.5a,-v8.6a,-v8.7a,-v8.8a,-v8.9a,-v8a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9a,-vh,-wfxt,-xs,-zcm,-zcz,-zcz-fp-workaround,-zcz-gp" }
attributes #9 = { mustprogress nofree nosync nounwind willreturn memory(argmem: readwrite, inaccessiblemem: readwrite) uwtable "frame-pointer"="none" "target-cpu"="generic" "target-features"="-a510,-a65,-a710,-a76,-a78,-a78c,-aes,-aggressive-fma,-alternate-sextload-cvt-f32-pattern,-altnzcv,-am,-amvs,-arith-bcc-fusion,-arith-cbz-fusion,-ascend-store-address,-b16b16,-balance-fp-ops,-bf16,-brbe,-bti,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-ccdp,-ccidx,-ccpp,-clrbhb,-cmp-bcc-fusion,-complxnum,-CONTEXTIDREL2,-cortex-r82,-crc,-crypto,-cssc,-custom-cheap-as-move,-d128,-disable-latency-sched-heuristic,-dit,-dotprod,-ecv,-el2vmsa,-el3,+enable-select-opt,+ete,-exynos-cheap-as-move,-f32mm,-f64mm,-fgt,-fix-cortex-a53-835769,-flagm,-fmv,-force-32bit-jump-tables,-fp16fml,+fp-armv8,-fptoint,-fullfp16,-fuse-address,+fuse-adrp-add,+fuse-aes,-fuse-arith-logic,-fuse-crypto-eor,-fuse-csel,-fuse-literals,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-hcx,-i8mm,-ite,-jsconv,-lor,-ls64,-lse,-lse128,-lse2,-lsl-fast,-mec,-mops,-mpam,-mte,+neon,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-zcz-fp,-nv,-outline-atomics,-pan,-pan-rwv,-pauth,-perfmon,-predictable-select-expensive,-predres,-prfm-slc-target,-rand,-ras,-rasv2,-rcpc,-rcpc3,-rcpc-immo,-rdm,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x30,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-sb,-sel2,-sha2,-sha3,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme,-sme2,-sme2p1,-sme-f16f16,-sme-f64f64,-sme-i16i64,-spe,-spe-eef,-specres2,-specrestrict,-ssbs,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-tagged-globals,-the,-tlb-rmi,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tracev8.4,+trbe,-uaops,-use-experimental-zeroing-pseudos,+use-postra-scheduler,-use-reciprocal-square-root,-use-scalar-inc-vl,-v8.1a,-v8.2a,-v8.3a,-v8.4a,-v8.5a,-v8.6a,-v8.7a,-v8.8a,-v8.9a,-v8a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9a,-vh,-wfxt,-xs,-zcm,-zcz,-zcz-fp-workaround,-zcz-gp" }
attributes #10 = { nofree nosync nounwind uwtable "frame-pointer"="none" "target-cpu"="generic" "target-features"="-a510,-a65,-a710,-a76,-a78,-a78c,-aes,-aggressive-fma,-alternate-sextload-cvt-f32-pattern,-altnzcv,-am,-amvs,-arith-bcc-fusion,-arith-cbz-fusion,-ascend-store-address,-b16b16,-balance-fp-ops,-bf16,-brbe,-bti,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-ccdp,-ccidx,-ccpp,-clrbhb,-cmp-bcc-fusion,-complxnum,-CONTEXTIDREL2,-cortex-r82,-crc,-crypto,-cssc,-custom-cheap-as-move,-d128,-disable-latency-sched-heuristic,-dit,-dotprod,-ecv,-el2vmsa,-el3,+enable-select-opt,+ete,-exynos-cheap-as-move,-f32mm,-f64mm,-fgt,-fix-cortex-a53-835769,-flagm,-fmv,-force-32bit-jump-tables,-fp16fml,+fp-armv8,-fptoint,-fullfp16,-fuse-address,+fuse-adrp-add,+fuse-aes,-fuse-arith-logic,-fuse-crypto-eor,-fuse-csel,-fuse-literals,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-hcx,-i8mm,-ite,-jsconv,-lor,-ls64,-lse,-lse128,-lse2,-lsl-fast,-mec,-mops,-mpam,-mte,+neon,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-zcz-fp,-nv,-outline-atomics,-pan,-pan-rwv,-pauth,-perfmon,-predictable-select-expensive,-predres,-prfm-slc-target,-rand,-ras,-rasv2,-rcpc,-rcpc3,-rcpc-immo,-rdm,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x30,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-sb,-sel2,-sha2,-sha3,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme,-sme2,-sme2p1,-sme-f16f16,-sme-f64f64,-sme-i16i64,-spe,-spe-eef,-specres2,-specrestrict,-ssbs,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-tagged-globals,-the,-tlb-rmi,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tracev8.4,+trbe,-uaops,-use-experimental-zeroing-pseudos,+use-postra-scheduler,-use-reciprocal-square-root,-use-scalar-inc-vl,-v8.1a,-v8.2a,-v8.3a,-v8.4a,-v8.5a,-v8.6a,-v8.7a,-v8.8a,-v8.9a,-v8a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9a,-vh,-wfxt,-xs,-zcm,-zcz,-zcz-fp-workaround,-zcz-gp" }
attributes #11 = { nofree nosync nounwind memory(readwrite, inaccessiblemem: none) uwtable "frame-pointer"="none" "target-cpu"="generic" "target-features"="-a510,-a65,-a710,-a76,-a78,-a78c,-aes,-aggressive-fma,-alternate-sextload-cvt-f32-pattern,-altnzcv,-am,-amvs,-arith-bcc-fusion,-arith-cbz-fusion,-ascend-store-address,-b16b16,-balance-fp-ops,-bf16,-brbe,-bti,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-ccdp,-ccidx,-ccpp,-clrbhb,-cmp-bcc-fusion,-complxnum,-CONTEXTIDREL2,-cortex-r82,-crc,-crypto,-cssc,-custom-cheap-as-move,-d128,-disable-latency-sched-heuristic,-dit,-dotprod,-ecv,-el2vmsa,-el3,+enable-select-opt,+ete,-exynos-cheap-as-move,-f32mm,-f64mm,-fgt,-fix-cortex-a53-835769,-flagm,-fmv,-force-32bit-jump-tables,-fp16fml,+fp-armv8,-fptoint,-fullfp16,-fuse-address,+fuse-adrp-add,+fuse-aes,-fuse-arith-logic,-fuse-crypto-eor,-fuse-csel,-fuse-literals,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-hcx,-i8mm,-ite,-jsconv,-lor,-ls64,-lse,-lse128,-lse2,-lsl-fast,-mec,-mops,-mpam,-mte,+neon,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-zcz-fp,-nv,-outline-atomics,-pan,-pan-rwv,-pauth,-perfmon,-predictable-select-expensive,-predres,-prfm-slc-target,-rand,-ras,-rasv2,-rcpc,-rcpc3,-rcpc-immo,-rdm,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x30,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-sb,-sel2,-sha2,-sha3,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme,-sme2,-sme2p1,-sme-f16f16,-sme-f64f64,-sme-i16i64,-spe,-spe-eef,-specres2,-specrestrict,-ssbs,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-tagged-globals,-the,-tlb-rmi,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tracev8.4,+trbe,-uaops,-use-experimental-zeroing-pseudos,+use-postra-scheduler,-use-reciprocal-square-root,-use-scalar-inc-vl,-v8.1a,-v8.2a,-v8.3a,-v8.4a,-v8.5a,-v8.6a,-v8.7a,-v8.8a,-v8.9a,-v8a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9a,-vh,-wfxt,-xs,-zcm,-zcz,-zcz-fp-workaround,-zcz-gp" }
attributes #12 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #13 = { cold noinline noreturn }
attributes #14 = { nounwind }

!llvm.module.flags = !{!0, !1, !2}
!llvm.dbg.cu = !{!3}

!0 = !{i32 8, !"PIC Level", i32 2}
!1 = !{i32 7, !"PIE Level", i32 2}
!2 = !{i32 2, !"Debug Info Version", i32 3}
!3 = distinct !DICompileUnit(language: DW_LANG_C, file: !4, producer: "my llvm compiler frontend", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, splitDebugInlining: false)
!4 = !DIFile(filename: "roc_app", directory: ".")
!5 = !{!6}
!6 = distinct !{!6, !7, !"list.RocList.empty: argument 0"}
!7 = distinct !{!7, !"list.RocList.empty"}
!8 = !{!9}
!9 = distinct !{!9, !10, !"fmt.bufPrint__anon_10744: argument 0"}
!10 = distinct !{!10, !"fmt.bufPrint__anon_10744"}
!11 = !{!12}
!12 = distinct !{!12, !13, !"io.fixed_buffer_stream.FixedBufferStream([]u8).writer: argument 0"}
!13 = distinct !{!13, !"io.fixed_buffer_stream.FixedBufferStream([]u8).writer"}
!14 = !{!15, !9}
!15 = distinct !{!15, !16, !"fmt.digits2: argument 0"}
!16 = distinct !{!16, !"fmt.digits2"}
!17 = !{!18, !9}
!18 = distinct !{!18, !19, !"fmt.digits2: argument 0"}
!19 = distinct !{!19, !"fmt.digits2"}
!20 = !{!21, !23, !25}
!21 = distinct !{!21, !22, !"str.RocStr.allocateBig: argument 0"}
!22 = distinct !{!22, !"str.RocStr.allocateBig"}
!23 = distinct !{!23, !24, !"str.RocStr.allocate: argument 0"}
!24 = distinct !{!24, !"str.RocStr.allocate"}
!25 = distinct !{!25, !26, !"str.RocStr.init: argument 0"}
!26 = distinct !{!26, !"str.RocStr.init"}
!27 = !{!25}
!28 = !{i64 0, i64 65}
!29 = distinct !{!29, !30, !31}
!30 = !{!"llvm.loop.isvectorized", i32 1}
!31 = !{!"llvm.loop.unroll.runtime.disable"}
!32 = distinct !{!32, !30, !31}
!33 = distinct !{!33, !31, !30}
!34 = distinct !{!34, !30, !31}
!35 = distinct !{!35, !30, !31}
!36 = distinct !{!36, !31, !30}
!37 = !{!38}
!38 = distinct !{!38, !39, !"unicode.utf8Decode2: argument 0"}
!39 = distinct !{!39, !"unicode.utf8Decode2"}
!40 = !{!41}
!41 = distinct !{!41, !42, !"unicode.utf8Decode3: argument 0"}
!42 = distinct !{!42, !"unicode.utf8Decode3"}
!43 = !{!44}
!44 = distinct !{!44, !45, !"unicode.utf8Decode4: argument 0"}
!45 = distinct !{!45, !"unicode.utf8Decode4"}
!46 = !{!47, !49}
!47 = distinct !{!47, !48, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write: argument 0"}
!48 = distinct !{!48, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write"}
!49 = distinct !{!49, !50, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write: argument 0"}
!50 = distinct !{!50, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write"}
!51 = !{!52, !54}
!52 = distinct !{!52, !53, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write: argument 0"}
!53 = distinct !{!53, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write"}
!54 = distinct !{!54, !55, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write: argument 0"}
!55 = distinct !{!55, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write"}
!56 = !{!57, !59}
!57 = distinct !{!57, !58, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write: argument 0"}
!58 = distinct !{!58, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write"}
!59 = distinct !{!59, !60, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write: argument 0"}
!60 = distinct !{!60, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write"}
!61 = !{!62, !64}
!62 = distinct !{!62, !63, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write: argument 0"}
!63 = distinct !{!63, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write"}
!64 = distinct !{!64, !65, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write: argument 0"}
!65 = distinct !{!65, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write"}
!66 = !{!67, !69}
!67 = distinct !{!67, !68, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write: argument 0"}
!68 = distinct !{!68, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write"}
!69 = distinct !{!69, !70, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write: argument 0"}
!70 = distinct !{!70, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write"}
!71 = !{!72, !74}
!72 = distinct !{!72, !73, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write: argument 0"}
!73 = distinct !{!73, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write"}
!74 = distinct !{!74, !75, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write: argument 0"}
!75 = distinct !{!75, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write"}
!76 = !{!77, !79}
!77 = distinct !{!77, !78, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write: argument 0"}
!78 = distinct !{!78, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write"}
!79 = distinct !{!79, !80, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write: argument 0"}
!80 = distinct !{!80, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write"}
!81 = !{!82, !84}
!82 = distinct !{!82, !83, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write: argument 0"}
!83 = distinct !{!83, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write"}
!84 = distinct !{!84, !85, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write: argument 0"}
!85 = distinct !{!85, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write"}
!86 = !{!87, !89}
!87 = distinct !{!87, !88, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write: argument 0"}
!88 = distinct !{!88, !"io.fixed_buffer_stream.FixedBufferStream([]u8).write"}
!89 = distinct !{!89, !90, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write: argument 0"}
!90 = distinct !{!90, !"io.writer.Writer(*io.fixed_buffer_stream.FixedBufferStream([]u8),error{NoSpaceLeft},(function 'write')).write"}
!91 = !{!92}
!92 = distinct !{!92, !93, !"str.RocStr.allocateBig: argument 0"}
!93 = distinct !{!93, !"str.RocStr.allocateBig"}
!94 = distinct !{!94, !30, !31}
!95 = distinct !{!95, !30, !31}
!96 = distinct !{!96, !30}
!97 = distinct !DISubprogram(name: "Stdout_line_1e4d2f1e6b4984301a1489b71481ade3a818d1fae80b8f87ea525c7bff923", linkageName: "Stdout_line_1e4d2f1e6b4984301a1489b71481ade3a818d1fae80b8f87ea525c7bff923", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!98 = !DISubroutineType(flags: DIFlagPublic, types: !99)
!99 = !{!100}
!100 = !DIBasicType(name: "type_name", flags: DIFlagPublic)
!101 = !{}
!102 = !DILocation(line: 0, scope: !103)
!103 = distinct !DILexicalBlock(scope: !97, file: !4)
!104 = distinct !DISubprogram(name: "InternalTask_ok_789661f33c6ea1791479ecf1f52dd93e21b779364a5197d9de3459113903b9c", linkageName: "InternalTask_ok_789661f33c6ea1791479ecf1f52dd93e21b779364a5197d9de3459113903b9c", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!105 = !DILocation(line: 0, scope: !106)
!106 = distinct !DILexicalBlock(scope: !104, file: !4)
!107 = distinct !DISubprogram(name: "Task_await_13f5c26ce0b5e6eebef533619a72113f96d1ebc7728f2a7c4631d56ba55ad7c", linkageName: "Task_await_13f5c26ce0b5e6eebef533619a72113f96d1ebc7728f2a7c4631d56ba55ad7c", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!108 = !DILocation(line: 0, scope: !109)
!109 = distinct !DILexicalBlock(scope: !107, file: !4)
!110 = distinct !DISubprogram(name: "Http_methodToStr_172247c57cf29182b738e1647bff697cbe655ff06cf0aee2ca31b6b397327385", linkageName: "Http_methodToStr_172247c57cf29182b738e1647bff697cbe655ff06cf0aee2ca31b6b397327385", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!111 = !DILocation(line: 0, scope: !112)
!112 = distinct !DILexicalBlock(scope: !110, file: !4)
!113 = distinct !DISubprogram(name: "Effect_after_3c58d86b4437e7512e2b91aaabac14e86a30d0bfd8a27923c73b19fd673fff", linkageName: "Effect_after_3c58d86b4437e7512e2b91aaabac14e86a30d0bfd8a27923c73b19fd673fff", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!114 = !DILocation(line: 0, scope: !115)
!115 = distinct !DILexicalBlock(scope: !113, file: !4)
!116 = distinct !DISubprogram(name: "Effect_effect_after_inner_544c19588062ed4289757939f8edf854589b8a37c6e1b564139c3298a34d6", linkageName: "Effect_effect_after_inner_544c19588062ed4289757939f8edf854589b8a37c6e1b564139c3298a34d6", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!117 = !DILocation(line: 0, scope: !118)
!118 = distinct !DILexicalBlock(scope: !116, file: !4)
!119 = distinct !DISubprogram(name: "Box_box_d1a1e4356bd9fe6c31754def4c60a14042ade1c6c101618179cfd5d1c73189", linkageName: "Box_box_d1a1e4356bd9fe6c31754def4c60a14042ade1c6c101618179cfd5d1c73189", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!120 = !DILocation(line: 0, scope: !121)
!121 = distinct !DILexicalBlock(scope: !119, file: !4)
!122 = distinct !DISubprogram(name: "InternalDateTime_dayWithPaddedZeros_7761c8128128ceb6e9a61eef6135bff7bcac2ab2ea5a7e1ad63b023aa1a8f68", linkageName: "InternalDateTime_dayWithPaddedZeros_7761c8128128ceb6e9a61eef6135bff7bcac2ab2ea5a7e1ad63b023aa1a8f68", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!123 = !DILocation(line: 0, scope: !124)
!124 = distinct !DILexicalBlock(scope: !122, file: !4)
!125 = distinct !DISubprogram(name: "Num_rem_cabb163ea8b383114bab450f2ea4bdf6f97d5dc22e57b593db81e3bce47", linkageName: "Num_rem_cabb163ea8b383114bab450f2ea4bdf6f97d5dc22e57b593db81e3bce47", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!126 = !DILocation(line: 0, scope: !127)
!127 = distinct !DILexicalBlock(scope: !125, file: !4)
!128 = distinct !DISubprogram(name: "Task_err_b29e3b7af499d7231de5e31772f94a674636903232cb1b301cf274977992d8b", linkageName: "Task_err_b29e3b7af499d7231de5e31772f94a674636903232cb1b301cf274977992d8b", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!129 = !DILocation(line: 0, scope: !130)
!130 = distinct !DILexicalBlock(scope: !128, file: !4)
!131 = distinct !DISubprogram(name: "InternalTask_toEffect_10259c295470b0dd303c429b36412fb6f21861ad97f73a2722c7516d147991f", linkageName: "InternalTask_toEffect_10259c295470b0dd303c429b36412fb6f21861ad97f73a2722c7516d147991f", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!132 = !DILocation(line: 0, scope: !133)
!133 = distinct !DILexicalBlock(scope: !131, file: !4)
!134 = distinct !DISubprogram(name: "InternalTask_toEffect_935229af12e1c6ee752a73f7b73add5a7c7a22cfba9e577e778e240ed627a", linkageName: "InternalTask_toEffect_935229af12e1c6ee752a73f7b73add5a7c7a22cfba9e577e778e240ed627a", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!135 = !DILocation(line: 0, scope: !136)
!136 = distinct !DILexicalBlock(scope: !134, file: !4)
!137 = distinct !DISubprogram(name: "_33_aad9a2f5f9418b386cce489a0bac8cb5bba34171864909e4dfec1ea4e26bfb7", linkageName: "_33_aad9a2f5f9418b386cce489a0bac8cb5bba34171864909e4dfec1ea4e26bfb7", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!138 = !DILocation(line: 0, scope: !139)
!139 = distinct !DILexicalBlock(scope: !137, file: !4)
!140 = distinct !DISubprogram(name: "InternalTask_fromEffect_af58df284beb8fc541e167d520a5c53bd3e05fcd2fb56799b9aee4cfc3ed3f", linkageName: "InternalTask_fromEffect_af58df284beb8fc541e167d520a5c53bd3e05fcd2fb56799b9aee4cfc3ed3f", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!141 = !DILocation(line: 0, scope: !142)
!142 = distinct !DILexicalBlock(scope: !140, file: !4)
!143 = distinct !DISubprogram(name: "InternalTask_ok_1cd410b47325ca54fd4d13db9f372fff17944e80d3dc60ceb6fa212947a", linkageName: "InternalTask_ok_1cd410b47325ca54fd4d13db9f372fff17944e80d3dc60ceb6fa212947a", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!144 = !DILocation(line: 0, scope: !145)
!145 = distinct !DILexicalBlock(scope: !143, file: !4)
!146 = distinct !DISubprogram(name: "Effect_effect_after_inner_3c34ade886ecb9c29fd02363474d39cd94178ea81fd90fb2871dcdcb2a3aad", linkageName: "Effect_effect_after_inner_3c34ade886ecb9c29fd02363474d39cd94178ea81fd90fb2871dcdcb2a3aad", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!147 = !DILocation(line: 0, scope: !148)
!148 = distinct !DILexicalBlock(scope: !146, file: !4)
!149 = distinct !DISubprogram(name: "Effect_posixTime_229c75d6969a8a8a593eb2c44e915f34577963371a1cc7e544a8418a694a1e2", linkageName: "Effect_posixTime_229c75d6969a8a8a593eb2c44e915f34577963371a1cc7e544a8418a694a1e2", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!150 = !DILocation(line: 0, scope: !151)
!151 = distinct !DILexicalBlock(scope: !149, file: !4)
!152 = distinct !DISubprogram(name: "Utc_12_131fc9d292b7c25af42a6c6deb3979c2144f1a7423d39eb46aef237b8f774b", linkageName: "Utc_12_131fc9d292b7c25af42a6c6deb3979c2144f1a7423d39eb46aef237b8f774b", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!153 = !DILocation(line: 0, scope: !154)
!154 = distinct !DILexicalBlock(scope: !152, file: !4)
!155 = distinct !DISubprogram(name: "Effect_map_78e95374ca5c3ffeb4c3c6d1fee15f4627b4cb8e78c83389fa66fa17b11860", linkageName: "Effect_map_78e95374ca5c3ffeb4c3c6d1fee15f4627b4cb8e78c83389fa66fa17b11860", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!156 = !DILocation(line: 0, scope: !157)
!157 = distinct !DILexicalBlock(scope: !155, file: !4)
!158 = distinct !DISubprogram(name: "Task_await_7988d89080438f51df37e0664fee86ae858164dcb95eaeb555d2849513259182", linkageName: "Task_await_7988d89080438f51df37e0664fee86ae858164dcb95eaeb555d2849513259182", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!159 = !DILocation(line: 0, scope: !160)
!160 = distinct !DILexicalBlock(scope: !158, file: !4)
!161 = distinct !DISubprogram(name: "InternalTask_fromEffect_edd459f1588e2edc4160caf3fec49aefc7d7fec1545146fd82c6ba52b293834", linkageName: "InternalTask_fromEffect_edd459f1588e2edc4160caf3fec49aefc7d7fec1545146fd82c6ba52b293834", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!162 = !DILocation(line: 0, scope: !163)
!163 = distinct !DILexicalBlock(scope: !161, file: !4)
!164 = distinct !DISubprogram(name: "Effect_effect_after_inner_4ef81b983bd7cde6bbc497dcbaeffcb1ff38a9d8bb9b208abb417910dc73a6d1", linkageName: "Effect_effect_after_inner_4ef81b983bd7cde6bbc497dcbaeffcb1ff38a9d8bb9b208abb417910dc73a6d1", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!165 = !DILocation(line: 0, scope: !166)
!166 = distinct !DILexicalBlock(scope: !164, file: !4)
!167 = distinct !DISubprogram(name: "#UserApp_7_13b85edde3cd334a6265af1614664111ffe13ba3b2be97d0f8e38d9c799cb7", linkageName: "#UserApp_7_13b85edde3cd334a6265af1614664111ffe13ba3b2be97d0f8e38d9c799cb7", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!168 = !DILocation(line: 0, scope: !169)
!169 = distinct !DILexicalBlock(scope: !167, file: !4)
!170 = distinct !DISubprogram(name: "Task_92_42f43e247a90ff93dac3c860bb219ee18693539a6e942bad35bcb7297d6e16", linkageName: "Task_92_42f43e247a90ff93dac3c860bb219ee18693539a6e942bad35bcb7297d6e16", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!171 = !DILocation(line: 0, scope: !172)
!172 = distinct !DILexicalBlock(scope: !170, file: !4)
!173 = distinct !DISubprogram(name: "Effect_effect_always_inner_cd87b8ad69bc5b0a62f3f19932d2d2ba97fc6f54781f6533ef735e0b0235064", linkageName: "Effect_effect_always_inner_cd87b8ad69bc5b0a62f3f19932d2d2ba97fc6f54781f6533ef735e0b0235064", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!174 = !DILocation(line: 0, scope: !175)
!175 = distinct !DILexicalBlock(scope: !173, file: !4)
!176 = distinct !DISubprogram(name: "InternalTask_ok_21b5c7d5305aa5ff4df495f05c9e59c37d76367eacec9dd321a0e78143dfc4a3", linkageName: "InternalTask_ok_21b5c7d5305aa5ff4df495f05c9e59c37d76367eacec9dd321a0e78143dfc4a3", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!177 = !DILocation(line: 0, scope: !178)
!178 = distinct !DILexicalBlock(scope: !176, file: !4)
!179 = distinct !DISubprogram(name: "InternalTask_fromEffect_dc6b1b42abfea2844b7c4985e150c54b77c535b47ead6acd59d6a08b80d2", linkageName: "InternalTask_fromEffect_dc6b1b42abfea2844b7c4985e150c54b77c535b47ead6acd59d6a08b80d2", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!180 = !DILocation(line: 0, scope: !181)
!181 = distinct !DILexicalBlock(scope: !179, file: !4)
!182 = distinct !DISubprogram(name: "Bool_or_52459ae5e05017996bb4298dd9ac3944ffe997fa2e2ad98ba6fd7348395f63", linkageName: "Bool_or_52459ae5e05017996bb4298dd9ac3944ffe997fa2e2ad98ba6fd7348395f63", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!183 = !DILocation(line: 0, scope: !184)
!184 = distinct !DILexicalBlock(scope: !182, file: !4)
!185 = distinct !DISubprogram(name: "Bool_isNotEq_91183c4be76c8c6e9a1aca423ca6b7bdfddc155d7aac337b8db73395e0e64d", linkageName: "Bool_isNotEq_91183c4be76c8c6e9a1aca423ca6b7bdfddc155d7aac337b8db73395e0e64d", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!186 = !DILocation(line: 0, scope: !187)
!187 = distinct !DILexicalBlock(scope: !185, file: !4)
!188 = distinct !DISubprogram(name: "Task_53_d0954aeb42c3a999750fa5b4068c6679ed2537c3257fc7e6c4e91bdc4133ae0", linkageName: "Task_53_d0954aeb42c3a999750fa5b4068c6679ed2537c3257fc7e6c4e91bdc4133ae0", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!189 = !DILocation(line: 0, scope: !190)
!190 = distinct !DILexicalBlock(scope: !188, file: !4)
!191 = distinct !DISubprogram(name: "Effect_stdoutLine_b57223634213b1c687e1cf06fef47be7eed4c64d12c154ffb6abc557b2b473", linkageName: "Effect_stdoutLine_b57223634213b1c687e1cf06fef47be7eed4c64d12c154ffb6abc557b2b473", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!192 = !DILocation(line: 0, scope: !193)
!193 = distinct !DILexicalBlock(scope: !191, file: !4)
!194 = distinct !DISubprogram(name: "InternalTask_toEffect_583276bf45a8e97f112dfbc4f4d4d2a42a1119a510af9e76a5cba40a368d0", linkageName: "InternalTask_toEffect_583276bf45a8e97f112dfbc4f4d4d2a42a1119a510af9e76a5cba40a368d0", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!195 = !DILocation(line: 0, scope: !196)
!196 = distinct !DILexicalBlock(scope: !194, file: !4)
!197 = distinct !DISubprogram(name: "Bool_structuralEq_4a74cf314ac9371a5ea518de15e620d82137397f51a1fa6eff156547f363", linkageName: "Bool_structuralEq_4a74cf314ac9371a5ea518de15e620d82137397f51a1fa6eff156547f363", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!198 = !DILocation(line: 0, scope: !199)
!199 = distinct !DILexicalBlock(scope: !197, file: !4)
!200 = distinct !DISubprogram(name: "InternalTask_fromEffect_594462766f77f828358545ebdadebc7d564d3daf466672cbde673babcf18c3c2", linkageName: "InternalTask_fromEffect_594462766f77f828358545ebdadebc7d564d3daf466672cbde673babcf18c3c2", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!201 = !DILocation(line: 0, scope: !202)
!202 = distinct !DILexicalBlock(scope: !200, file: !4)
!203 = distinct !DISubprogram(name: "InternalDateTime_daysInMonth_4a2d194da1241ef3ca5a8139a734b29ae4efb20126643584c91fe6ded8e2c5a", linkageName: "InternalDateTime_daysInMonth_4a2d194da1241ef3ca5a8139a734b29ae4efb20126643584c91fe6ded8e2c5a", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!204 = !DILocation(line: 0, scope: !205)
!205 = distinct !DILexicalBlock(scope: !203, file: !4)
!206 = distinct !DISubprogram(name: "Effect_effect_map_inner_c2d7201047722d5a148179c401bb3be69049c213c67ac89fa2daff2ad24745", linkageName: "Effect_effect_map_inner_c2d7201047722d5a148179c401bb3be69049c213c67ac89fa2daff2ad24745", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!207 = !DILocation(line: 0, scope: !208)
!208 = distinct !DILexicalBlock(scope: !206, file: !4)
!209 = distinct !DISubprogram(name: "Effect_effect_after_inner_268182e6bf48c34ea8893d1d91dfdfbbcae7ca2eb5c9a5136f7f2958cb888df", linkageName: "Effect_effect_after_inner_268182e6bf48c34ea8893d1d91dfdfbbcae7ca2eb5c9a5136f7f2958cb888df", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!210 = !DILocation(line: 0, scope: !211)
!211 = distinct !DILexicalBlock(scope: !209, file: !4)
!212 = distinct !DISubprogram(name: "InternalTask_toEffect_5eb6a2599d3097c754d93922b84522fd22c626afbfca9a48d724fa1945e3ca9", linkageName: "InternalTask_toEffect_5eb6a2599d3097c754d93922b84522fd22c626afbfca9a48d724fa1945e3ca9", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!213 = !DILocation(line: 0, scope: !214)
!214 = distinct !DILexicalBlock(scope: !212, file: !4)
!215 = distinct !DISubprogram(name: "_respond_c919149ababf2a569c5e2b164c2465c785dc3bc7f566b8dcef7ec4ae86e8d57", linkageName: "_respond_c919149ababf2a569c5e2b164c2465c785dc3bc7f566b8dcef7ec4ae86e8d57", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!216 = !DILocation(line: 0, scope: !217)
!217 = distinct !DILexicalBlock(scope: !215, file: !4)
!218 = distinct !DISubprogram(name: "InternalDateTime_epochMillisToDateTime_4e6df5a280208f8027d8c0e0fd95af1adf299ebd3666b6c48551dc0cb3c3214", linkageName: "InternalDateTime_epochMillisToDateTime_4e6df5a280208f8027d8c0e0fd95af1adf299ebd3666b6c48551dc0cb3c3214", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!219 = !DILocation(line: 0, scope: !220)
!220 = distinct !DILexicalBlock(scope: !218, file: !4)
!221 = distinct !DISubprogram(name: "Task_await_8e9956175ff8e3582c4b770a3b3c2388266676d8eb052d494e1a127bd7a9ad2", linkageName: "Task_await_8e9956175ff8e3582c4b770a3b3c2388266676d8eb052d494e1a127bd7a9ad2", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!222 = !DILocation(line: 0, scope: !223)
!223 = distinct !DILexicalBlock(scope: !221, file: !4)
!224 = distinct !DISubprogram(name: "Task_await_55aa18fc3c82fe108fcf64fea07364ddba1e8c526b8d27b19692a7748519e1c", linkageName: "Task_await_55aa18fc3c82fe108fcf64fea07364ddba1e8c526b8d27b19692a7748519e1c", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!225 = !DILocation(line: 0, scope: !226)
!226 = distinct !DILexicalBlock(scope: !224, file: !4)
!227 = distinct !DISubprogram(name: "Num_toStr_99e2ebbd98e8a2a4c7ed9bd71d205d9f7b5d7e7a9ddb68dab65f2ad1c2198b", linkageName: "Num_toStr_99e2ebbd98e8a2a4c7ed9bd71d205d9f7b5d7e7a9ddb68dab65f2ad1c2198b", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!228 = !DILocation(line: 0, scope: !229)
!229 = distinct !DILexicalBlock(scope: !227, file: !4)
!230 = distinct !DISubprogram(name: "InternalTask_fromEffect_3bfae27b50cc70419dec89ef8da341b1287d7bb7b3c4bb2481ba28b17a8ec4", linkageName: "InternalTask_fromEffect_3bfae27b50cc70419dec89ef8da341b1287d7bb7b3c4bb2481ba28b17a8ec4", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!231 = !DILocation(line: 0, scope: !232)
!232 = distinct !DILexicalBlock(scope: !230, file: !4)
!233 = distinct !DISubprogram(name: "InternalTask_ok_ade2dc9e385e74c61c8d36210907131d7823a7fe8d06c7bd978c1f46a9d3830", linkageName: "InternalTask_ok_ade2dc9e385e74c61c8d36210907131d7823a7fe8d06c7bd978c1f46a9d3830", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!234 = !DILocation(line: 0, scope: !235)
!235 = distinct !DILexicalBlock(scope: !233, file: !4)
!236 = distinct !DISubprogram(name: "Bool_and_078eba49b7090dbd2c6fb82297218e6d2eb88883fa33ff213b919f6e68cc", linkageName: "Bool_and_078eba49b7090dbd2c6fb82297218e6d2eb88883fa33ff213b919f6e68cc", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!237 = !DILocation(line: 0, scope: !238)
!238 = distinct !DILexicalBlock(scope: !236, file: !4)
!239 = distinct !DISubprogram(name: "_152_55d628abedfcc0e78784ef0cac7a0c47c774ce17d4fb8ba44f37721d7f3d98", linkageName: "_152_55d628abedfcc0e78784ef0cac7a0c47c774ce17d4fb8ba44f37721d7f3d98", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!240 = !DILocation(line: 0, scope: !241)
!241 = distinct !DILexicalBlock(scope: !239, file: !4)
!242 = distinct !DISubprogram(name: "InternalTask_toEffect_99494e9e9babe4dcb72b4144dc54d31ba956a4ee34496553143a5e7cb7dc78c4", linkageName: "InternalTask_toEffect_99494e9e9babe4dcb72b4144dc54d31ba956a4ee34496553143a5e7cb7dc78c4", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!243 = !DILocation(line: 0, scope: !244)
!244 = distinct !DILexicalBlock(scope: !242, file: !4)
!245 = distinct !DISubprogram(name: "InternalDateTime_monthWithPaddedZeros_7bb22cd9f7ce9f3ea01a5cc21ef19af74a624ef91d31d1912f9a7744788c55c", linkageName: "InternalDateTime_monthWithPaddedZeros_7bb22cd9f7ce9f3ea01a5cc21ef19af74a624ef91d31d1912f9a7744788c55c", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!246 = !DILocation(line: 0, scope: !247)
!247 = distinct !DILexicalBlock(scope: !245, file: !4)
!248 = distinct !DISubprogram(name: "_19_b5dcd15815911a96b9d7e883b1723ec1e9f2a35835ca79db2284140ebd0aa83", linkageName: "_19_b5dcd15815911a96b9d7e883b1723ec1e9f2a35835ca79db2284140ebd0aa83", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!249 = !DILocation(line: 0, scope: !250)
!250 = distinct !DILexicalBlock(scope: !248, file: !4)
!251 = distinct !DISubprogram(name: "InternalTask_err_c3db9144e9e8a2aeb45a4287ca39a6b36f034de3f4c779c625aa44629cf92b4", linkageName: "InternalTask_err_c3db9144e9e8a2aeb45a4287ca39a6b36f034de3f4c779c625aa44629cf92b4", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!252 = !DILocation(line: 0, scope: !253)
!253 = distinct !DILexicalBlock(scope: !251, file: !4)
!254 = distinct !DISubprogram(name: "Effect_always_3c159ccc72c9f6c2f9b343f7ee15555614903dc98bb4bf9da1d235172245b", linkageName: "Effect_always_3c159ccc72c9f6c2f9b343f7ee15555614903dc98bb4bf9da1d235172245b", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!255 = !DILocation(line: 0, scope: !256)
!256 = distinct !DILexicalBlock(scope: !254, file: !4)
!257 = distinct !DISubprogram(name: "Num_isLt_edaf1bd3d1c2ffcc44df55829c02f262426de2ffbea9be2cdf075ec12c528d", linkageName: "Num_isLt_edaf1bd3d1c2ffcc44df55829c02f262426de2ffbea9be2cdf075ec12c528d", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!258 = !DILocation(line: 0, scope: !259)
!259 = distinct !DILexicalBlock(scope: !257, file: !4)
!260 = distinct !DISubprogram(name: "_22_1484a21b4257566f7c1b3505e4f6c430eb1121cbfb946b32fb115b90b1ef50", linkageName: "_22_1484a21b4257566f7c1b3505e4f6c430eb1121cbfb946b32fb115b90b1ef50", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!261 = !DILocation(line: 0, scope: !262)
!262 = distinct !DILexicalBlock(scope: !260, file: !4)
!263 = distinct !DISubprogram(name: "Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b", linkageName: "Str_concat_392aebc0773ca1163ead8eb210e2c2aabca4fe4ded9f2b122a7dab30d082d98b", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!264 = !DILocation(line: 0, scope: !265)
!265 = distinct !DILexicalBlock(scope: !263, file: !4)
!266 = distinct !DISubprogram(name: "Effect_effect_always_inner_6e2f5c347617f02c84c4ee1199b6f064c2d91a5297c3fa525844f328c49949", linkageName: "Effect_effect_always_inner_6e2f5c347617f02c84c4ee1199b6f064c2d91a5297c3fa525844f328c49949", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!267 = !DILocation(line: 0, scope: !268)
!268 = distinct !DILexicalBlock(scope: !266, file: !4)
!269 = distinct !DISubprogram(name: "Task_err_7f39af79a2c681124253a11db0202f701d4c3013db3c1272927c55405b9031", linkageName: "Task_err_7f39af79a2c681124253a11db0202f701d4c3013db3c1272927c55405b9031", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!270 = !DILocation(line: 0, scope: !271)
!271 = distinct !DILexicalBlock(scope: !269, file: !4)
!272 = distinct !DISubprogram(name: "Effect_effect_map_inner_d52f8c3ecf2e209e81e04dd415745749206b773d86c4d1b2bb2d3d8e8890c", linkageName: "Effect_effect_map_inner_d52f8c3ecf2e209e81e04dd415745749206b773d86c4d1b2bb2d3d8e8890c", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!273 = !DILocation(line: 0, scope: !274)
!274 = distinct !DILexicalBlock(scope: !272, file: !4)
!275 = distinct !DISubprogram(name: "List_looper_fb7917afe92ebaa35d275cfd557c2b25a5a46452e484a4eb8cac5175c61606d", linkageName: "List_looper_fb7917afe92ebaa35d275cfd557c2b25a5a46452e484a4eb8cac5175c61606d", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!276 = !DILocation(line: 0, scope: !277)
!277 = distinct !DILexicalBlock(scope: !275, file: !4)
!278 = distinct !DISubprogram(name: "Task_onErr_7544714fcb8fdf9ddf55315cce78cf57de5a2d6621b01a7739ff24d9f60ac", linkageName: "Task_onErr_7544714fcb8fdf9ddf55315cce78cf57de5a2d6621b01a7739ff24d9f60ac", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!279 = !DILocation(line: 0, scope: !280)
!280 = distinct !DILexicalBlock(scope: !278, file: !4)
!281 = distinct !DISubprogram(name: "Task_err_dbefccae6de790f8e3497ad3c6c1c58a12a744edb0d65ec1ec4ade8b1151a59b", linkageName: "Task_err_dbefccae6de790f8e3497ad3c6c1c58a12a744edb0d65ec1ec4ade8b1151a59b", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!282 = !DILocation(line: 0, scope: !283)
!283 = distinct !DILexicalBlock(scope: !281, file: !4)
!284 = distinct !DISubprogram(name: "Task_attempt_dce3401669119d7f5da9e070669694c78f88efb14a471223494f7d677db1e7d", linkageName: "Task_attempt_dce3401669119d7f5da9e070669694c78f88efb14a471223494f7d677db1e7d", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!285 = !DILocation(line: 0, scope: !286)
!286 = distinct !DILexicalBlock(scope: !284, file: !4)
!287 = distinct !DISubprogram(name: "Effect_effect_always_inner_dbbb614026929029a924a622e5a645206e5e1277bd8c25cb7b78527df1a8c", linkageName: "Effect_effect_always_inner_dbbb614026929029a924a622e5a645206e5e1277bd8c25cb7b78527df1a8c", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!288 = !DILocation(line: 0, scope: !289)
!289 = distinct !DILexicalBlock(scope: !287, file: !4)
!290 = distinct !DISubprogram(name: "InternalTask_err_5cbbff1635f59ae21a02af6cfe0157283a05fb77d9b6ef4377a9133a78ffbe5", linkageName: "InternalTask_err_5cbbff1635f59ae21a02af6cfe0157283a05fb77d9b6ef4377a9133a78ffbe5", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!291 = !DILocation(line: 0, scope: !292)
!292 = distinct !DILexicalBlock(scope: !290, file: !4)
!293 = distinct !DISubprogram(name: "Effect_effect_after_inner_3994ebd10847f51a1ba443e4f3b9fb75da3f81a354da59de9bd34aaa2e927d", linkageName: "Effect_effect_after_inner_3994ebd10847f51a1ba443e4f3b9fb75da3f81a354da59de9bd34aaa2e927d", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!294 = !DILocation(line: 0, scope: !295)
!295 = distinct !DILexicalBlock(scope: !293, file: !4)
!296 = distinct !DISubprogram(name: "#UserApp_5_2c7d993eadf275d994a1f98b824972fece3cfca6b6ac52dd7bb717e1f5753", linkageName: "#UserApp_5_2c7d993eadf275d994a1f98b824972fece3cfca6b6ac52dd7bb717e1f5753", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!297 = !DILocation(line: 0, scope: !298)
!298 = distinct !DILexicalBlock(scope: !296, file: !4)
!299 = distinct !DISubprogram(name: "InternalDateTime_toIso8601Str_8cf693340558d3441d6232b3632a0e7d41f8065e5f4ec1b10ba263a7452d728", linkageName: "InternalDateTime_toIso8601Str_8cf693340558d3441d6232b3632a0e7d41f8065e5f4ec1b10ba263a7452d728", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!300 = !DILocation(line: 0, scope: !301)
!301 = distinct !DILexicalBlock(scope: !299, file: !4)
!302 = distinct !DISubprogram(name: "Effect_stderrLine_a51293a4c3ce80beb92fd22c82b6b69bd26ee8bc815b483e3cf291f486236c", linkageName: "Effect_stderrLine_a51293a4c3ce80beb92fd22c82b6b69bd26ee8bc815b483e3cf291f486236c", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!303 = !DILocation(line: 0, scope: !304)
!304 = distinct !DILexicalBlock(scope: !302, file: !4)
!305 = distinct !DISubprogram(name: "Bool_structuralEq_2cc6e6d3c5a48a76ea218c439d44b6318e7bd267419a22dcb25b258a2c06a", linkageName: "Bool_structuralEq_2cc6e6d3c5a48a76ea218c439d44b6318e7bd267419a22dcb25b258a2c06a", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!306 = !DILocation(line: 0, scope: !307)
!307 = distinct !DILexicalBlock(scope: !305, file: !4)
!308 = distinct !DISubprogram(name: "Stderr_line_4bd18bc73cee8d6c664141b2e49674ebb21216aa20f0f89293181ce7b14e", linkageName: "Stderr_line_4bd18bc73cee8d6c664141b2e49674ebb21216aa20f0f89293181ce7b14e", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!309 = !DILocation(line: 0, scope: !310)
!310 = distinct !DILexicalBlock(scope: !308, file: !4)
!311 = distinct !DISubprogram(name: "Utc_nanosPerMilli_1bb73f6fafaa3656a8bf5796e2e6e6bdbd058375237d0b9be5834c8c9f54", linkageName: "Utc_nanosPerMilli_1bb73f6fafaa3656a8bf5796e2e6e6bdbd058375237d0b9be5834c8c9f54", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!312 = !DILocation(line: 0, scope: !313)
!313 = distinct !DILexicalBlock(scope: !311, file: !4)
!314 = distinct !DISubprogram(name: "Task_53_5d84da6abaf677d342986d45e3605cfd5bd1528ee5196616226adfb513950", linkageName: "Task_53_5d84da6abaf677d342986d45e3605cfd5bd1528ee5196616226adfb513950", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!315 = !DILocation(line: 0, scope: !316)
!316 = distinct !DILexicalBlock(scope: !314, file: !4)
!317 = distinct !DISubprogram(name: "Task_ok_47379a71f6fa75b326383965b5622141f57df12cc22d7140acdf38f0ac8dbc6d", linkageName: "Task_ok_47379a71f6fa75b326383965b5622141f57df12cc22d7140acdf38f0ac8dbc6d", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!318 = !DILocation(line: 0, scope: !319)
!319 = distinct !DILexicalBlock(scope: !317, file: !4)
!320 = distinct !DISubprogram(name: "Effect_effect_after_inner_bac59821c43c0b53dd3438580b2599a5bf16c219b40a9d5e9a6e6a5390", linkageName: "Effect_effect_after_inner_bac59821c43c0b53dd3438580b2599a5bf16c219b40a9d5e9a6e6a5390", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!321 = !DILocation(line: 0, scope: !322)
!322 = distinct !DILexicalBlock(scope: !320, file: !4)
!323 = distinct !DISubprogram(name: "InternalHttp_methodFromStr_f2eb2e65858ef9a081c444e7b9b2cef1ed51b5a1e38027833034b9f057aa3131", linkageName: "InternalHttp_methodFromStr_f2eb2e65858ef9a081c444e7b9b2cef1ed51b5a1e38027833034b9f057aa3131", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!324 = !DILocation(line: 0, scope: !325)
!325 = distinct !DILexicalBlock(scope: !323, file: !4)
!326 = distinct !DISubprogram(name: "Task_ok_9d55cb5018ba494bcf5765953355c83e4ade148e5c95b280aacd826c59bea86", linkageName: "Task_ok_9d55cb5018ba494bcf5765953355c83e4ade148e5c95b280aacd826c59bea86", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!327 = !DILocation(line: 0, scope: !328)
!328 = distinct !DILexicalBlock(scope: !326, file: !4)
!329 = distinct !DISubprogram(name: "Effect_after_4ec88c32b1d8d7e41af6fe2c3b1c519c1adff81ec271f8be7bf4ea491e1", linkageName: "Effect_after_4ec88c32b1d8d7e41af6fe2c3b1c519c1adff81ec271f8be7bf4ea491e1", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!330 = !DILocation(line: 0, scope: !331)
!331 = distinct !DILexicalBlock(scope: !329, file: !4)
!332 = distinct !DISubprogram(name: "Task_53_3efb3241b6f76bcf29426c5d5647f69b665c3ac3b1fc474c237e0eea46afd1", linkageName: "Task_53_3efb3241b6f76bcf29426c5d5647f69b665c3ac3b1fc474c237e0eea46afd1", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!333 = !DILocation(line: 0, scope: !334)
!334 = distinct !DILexicalBlock(scope: !332, file: !4)
!335 = distinct !DISubprogram(name: "_init_c6e34737223a4b123e4ef4b086ad92b3ead64b519536ae28b552b4718b7124e", linkageName: "_init_c6e34737223a4b123e4ef4b086ad92b3ead64b519536ae28b552b4718b7124e", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!336 = !DILocation(line: 0, scope: !337)
!337 = distinct !DILexicalBlock(scope: !335, file: !4)
!338 = distinct !DISubprogram(name: "InternalTask_toEffect_260dec8de9897e99a5126b882cbb9d2ee2f32cd2b94c727fdd1aa87e467d", linkageName: "InternalTask_toEffect_260dec8de9897e99a5126b882cbb9d2ee2f32cd2b94c727fdd1aa87e467d", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!339 = !DILocation(line: 0, scope: !340)
!340 = distinct !DILexicalBlock(scope: !338, file: !4)
!341 = distinct !DISubprogram(name: "Task_44_12a8ad799c7b34402483623f9b421f07775e1054bb6bfcf2ae122184609a", linkageName: "Task_44_12a8ad799c7b34402483623f9b421f07775e1054bb6bfcf2ae122184609a", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!342 = !DILocation(line: 0, scope: !343)
!343 = distinct !DILexicalBlock(scope: !341, file: !4)
!344 = distinct !DISubprogram(name: "Task_err_e26b07323a88152db96f57cffd313b88dda6eb16db54bca99d36e02da3083", linkageName: "Task_err_e26b07323a88152db96f57cffd313b88dda6eb16db54bca99d36e02da3083", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!345 = !DILocation(line: 0, scope: !346)
!346 = distinct !DILexicalBlock(scope: !344, file: !4)
!347 = distinct !DISubprogram(name: "List_iterate_7cfa03e91e0ec9327f388a68dbd26ae2735e7e95165f9e519543e02299bee9", linkageName: "List_iterate_7cfa03e91e0ec9327f388a68dbd26ae2735e7e95165f9e519543e02299bee9", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!348 = !DILocation(line: 0, scope: !349)
!349 = distinct !DILexicalBlock(scope: !347, file: !4)
!350 = distinct !DISubprogram(name: "List_contains_4fe2c0cee861629d2ef04c3f725dba5813b563598f88e6fe57cefd4dd1a133", linkageName: "List_contains_4fe2c0cee861629d2ef04c3f725dba5813b563598f88e6fe57cefd4dd1a133", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!351 = !DILocation(line: 0, scope: !352)
!352 = distinct !DILexicalBlock(scope: !350, file: !4)
!353 = distinct !DISubprogram(name: "InternalDateTime_epochMillisToDateTimeHelp_684393a95528f29ba49a721c9e7bd2dbf82e1a92e5b742ec5b556b18be7657", linkageName: "InternalDateTime_epochMillisToDateTimeHelp_684393a95528f29ba49a721c9e7bd2dbf82e1a92e5b742ec5b556b18be7657", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!354 = !DILocation(line: 0, scope: !355)
!355 = distinct !DILexicalBlock(scope: !353, file: !4)
!356 = distinct !DISubprogram(name: "_149_481f1278f2de6c4b7025bbe3547d9acb112f26631793a1e4c8c76b99b179e0", linkageName: "_149_481f1278f2de6c4b7025bbe3547d9acb112f26631793a1e4c8c76b99b179e0", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!357 = !DILocation(line: 0, scope: !358)
!358 = distinct !DILexicalBlock(scope: !356, file: !4)
!359 = distinct !DISubprogram(name: "InternalDateTime_secondsWithPaddedZeros_5d26e7953422ce84aac56171b489e0deedf33db4e08b81dcad67e7427bff49", linkageName: "InternalDateTime_secondsWithPaddedZeros_5d26e7953422ce84aac56171b489e0deedf33db4e08b81dcad67e7427bff49", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!360 = !DILocation(line: 0, scope: !361)
!361 = distinct !DILexicalBlock(scope: !359, file: !4)
!362 = distinct !DISubprogram(name: "_forHost_494fd63e81fc5377dff396b856cc43fac283edbeae4d7cfbdd95aadb8479597", linkageName: "_forHost_494fd63e81fc5377dff396b856cc43fac283edbeae4d7cfbdd95aadb8479597", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!363 = !DILocation(line: 0, scope: !364)
!364 = distinct !DILexicalBlock(scope: !362, file: !4)
!365 = distinct !DISubprogram(name: "roc__forHost_1_exposed_generic", linkageName: "roc__forHost_1_exposed_generic", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!366 = !DILocation(line: 0, scope: !367)
!367 = distinct !DILexicalBlock(scope: !365, file: !4)
!368 = distinct !DISubprogram(name: "roc__forHost_1_exposed", linkageName: "roc__forHost_1_exposed", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!369 = !DILocation(line: 0, scope: !370)
!370 = distinct !DILexicalBlock(scope: !368, file: !4)
!371 = distinct !DISubprogram(name: "roc__forHost_1_exposed_size", linkageName: "roc__forHost_1_exposed_size", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!372 = !DILocation(line: 0, scope: !373)
!373 = distinct !DILexicalBlock(scope: !371, file: !4)
!374 = distinct !DISubprogram(name: "Bool_true_68697e959be5e5da06cc73b6f998e193cbf2d9b22efd0355a3d37129951b", linkageName: "Bool_true_68697e959be5e5da06cc73b6f998e193cbf2d9b22efd0355a3d37129951b", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!375 = !DILocation(line: 0, scope: !376)
!376 = distinct !DILexicalBlock(scope: !374, file: !4)
!377 = distinct !DISubprogram(name: "InternalTask_fromEffect_ea724491503a37367f3396489f19ddb4ed26c1b122d1bb85553bb555a0a4d", linkageName: "InternalTask_fromEffect_ea724491503a37367f3396489f19ddb4ed26c1b122d1bb85553bb555a0a4d", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!378 = !DILocation(line: 0, scope: !379)
!379 = distinct !DILexicalBlock(scope: !377, file: !4)
!380 = distinct !DISubprogram(name: "List_161_3bbacd33228bca14fe5573efe7278cde33c78fe9028ba98810cff368dece", linkageName: "List_161_3bbacd33228bca14fe5573efe7278cde33c78fe9028ba98810cff368dece", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!381 = !DILocation(line: 0, scope: !382)
!382 = distinct !DILexicalBlock(scope: !380, file: !4)
!383 = distinct !DISubprogram(name: "InternalDateTime_isLeapYear_a9e685cc72fe3166dd93f93a27166ec5656562cf1d6d3e19f41a6cc3489", linkageName: "InternalDateTime_isLeapYear_a9e685cc72fe3166dd93f93a27166ec5656562cf1d6d3e19f41a6cc3489", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!384 = !DILocation(line: 0, scope: !385)
!385 = distinct !DILexicalBlock(scope: !383, file: !4)
!386 = distinct !DISubprogram(name: "InternalTask_ok_b6812cd4831336785c4d2d6d371d74081a04d666ecb415ede62b278451858a9", linkageName: "InternalTask_ok_b6812cd4831336785c4d2d6d371d74081a04d666ecb415ede62b278451858a9", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!387 = !DILocation(line: 0, scope: !388)
!388 = distinct !DILexicalBlock(scope: !386, file: !4)
!389 = distinct !DISubprogram(name: "Effect_effect_after_inner_1414869acb920f6db8ce61389f4b2ab8ee18505e1ddd7ea302888aec917e", linkageName: "Effect_effect_after_inner_1414869acb920f6db8ce61389f4b2ab8ee18505e1ddd7ea302888aec917e", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!390 = !DILocation(line: 0, scope: !391)
!391 = distinct !DILexicalBlock(scope: !389, file: !4)
!392 = distinct !DISubprogram(name: "Effect_always_6fe3723198a75889cb8af57c5c09ddd2b39fa52c21bf2b932afda892bd9e585", linkageName: "Effect_always_6fe3723198a75889cb8af57c5c09ddd2b39fa52c21bf2b932afda892bd9e585", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!393 = !DILocation(line: 0, scope: !394)
!394 = distinct !DILexicalBlock(scope: !392, file: !4)
!395 = distinct !DISubprogram(name: "Effect_always_94cb138d818e9947d7d69ef307378727ff7855e4de6723d27fc54d8e228050", linkageName: "Effect_always_94cb138d818e9947d7d69ef307378727ff7855e4de6723d27fc54d8e228050", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!396 = !DILocation(line: 0, scope: !397)
!397 = distinct !DILexicalBlock(scope: !395, file: !4)
!398 = distinct !DISubprogram(name: "#UserApp_server_52aff1341cf42f5e6559a2cf028663f7bbbc7576ac1948fc58784a0613b79", linkageName: "#UserApp_server_52aff1341cf42f5e6559a2cf028663f7bbbc7576ac1948fc58784a0613b79", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!399 = !DILocation(line: 0, scope: !400)
!400 = distinct !DILexicalBlock(scope: !398, file: !4)
!401 = distinct !DISubprogram(name: "Effect_always_e7d224cfcafcc878740e4416f7931bf725f9fd3378f8c73d6a4dc1d8c8883f", linkageName: "Effect_always_e7d224cfcafcc878740e4416f7931bf725f9fd3378f8c73d6a4dc1d8c8883f", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!402 = !DILocation(line: 0, scope: !403)
!403 = distinct !DILexicalBlock(scope: !401, file: !4)
!404 = distinct !DISubprogram(name: "List_len_e4f9cf3a6c4e3d6be9d05048391b2e3975855fa3e34f66d41fe2c9a84e5c7b", linkageName: "List_len_e4f9cf3a6c4e3d6be9d05048391b2e3975855fa3e34f66d41fe2c9a84e5c7b", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!405 = !DILocation(line: 0, scope: !406)
!406 = distinct !DILexicalBlock(scope: !404, file: !4)
!407 = distinct !DISubprogram(name: "InternalTask_fromEffect_df2d999242c7383735614c1ca7894e355776837c47b5a1272ceceba5a498db", linkageName: "InternalTask_fromEffect_df2d999242c7383735614c1ca7894e355776837c47b5a1272ceceba5a498db", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!408 = !DILocation(line: 0, scope: !409)
!409 = distinct !DILexicalBlock(scope: !407, file: !4)
!410 = distinct !DISubprogram(name: "Effect_effect_after_inner_aafde219d9d91ee7a575a5efa6c6154f3d42c85beb7780b41b4510548f4aaf", linkageName: "Effect_effect_after_inner_aafde219d9d91ee7a575a5efa6c6154f3d42c85beb7780b41b4510548f4aaf", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!411 = !DILocation(line: 0, scope: !412)
!412 = distinct !DILexicalBlock(scope: !410, file: !4)
!413 = distinct !DISubprogram(name: "Effect_map_4bc296458c9e4dfa311cb236c399bfa4fbaacf1f1ce0be5dc9b3fb0e57fbf5", linkageName: "Effect_map_4bc296458c9e4dfa311cb236c399bfa4fbaacf1f1ce0be5dc9b3fb0e57fbf5", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!414 = !DILocation(line: 0, scope: !415)
!415 = distinct !DILexicalBlock(scope: !413, file: !4)
!416 = distinct !DISubprogram(name: "Num_isGt_7f7e162ee4345c12acb2c8dddfd129c8c9ef562ecb31841cfff13d4789ffc2", linkageName: "Num_isGt_7f7e162ee4345c12acb2c8dddfd129c8c9ef562ecb31841cfff13d4789ffc2", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!417 = !DILocation(line: 0, scope: !418)
!418 = distinct !DILexicalBlock(scope: !416, file: !4)
!419 = distinct !DISubprogram(name: "Effect_effect_always_inner_6510a4d2b643dbf56ded4867b8cf49fe92c910e8961840e3a156bc971ee31a", linkageName: "Effect_effect_always_inner_6510a4d2b643dbf56ded4867b8cf49fe92c910e8961840e3a156bc971ee31a", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!420 = !DILocation(line: 0, scope: !421)
!421 = distinct !DILexicalBlock(scope: !419, file: !4)
!422 = distinct !DISubprogram(name: "Task_ok_4643e4e3b17ad449bf2144b916446512b17f621ba9fb35f1ed2ca53f5cb54e", linkageName: "Task_ok_4643e4e3b17ad449bf2144b916446512b17f621ba9fb35f1ed2ca53f5cb54e", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!423 = !DILocation(line: 0, scope: !424)
!424 = distinct !DILexicalBlock(scope: !422, file: !4)
!425 = distinct !DISubprogram(name: "Task_ok_1971ed175c5339d8a493ee2a719f3ca8f50fbcc2a26feaf7b54a27898e3f", linkageName: "Task_ok_1971ed175c5339d8a493ee2a719f3ca8f50fbcc2a26feaf7b54a27898e3f", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!426 = !DILocation(line: 0, scope: !427)
!427 = distinct !DILexicalBlock(scope: !425, file: !4)
!428 = distinct !DISubprogram(name: "InternalTask_ok_a1fdfd7ca485c5e9436ed61186fef7b9b914edaf84deff48d9823fcadcd6ac", linkageName: "InternalTask_ok_a1fdfd7ca485c5e9436ed61186fef7b9b914edaf84deff48d9823fcadcd6ac", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!429 = !DILocation(line: 0, scope: !430)
!430 = distinct !DILexicalBlock(scope: !428, file: !4)
!431 = distinct !DISubprogram(name: "Effect_effect_map_inner_9bb8deca757dc2ac2fb673c9939099338c6d1fb2aae6cee85b52f30d7d2b2d8", linkageName: "Effect_effect_map_inner_9bb8deca757dc2ac2fb673c9939099338c6d1fb2aae6cee85b52f30d7d2b2d8", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!432 = !DILocation(line: 0, scope: !433)
!433 = distinct !DILexicalBlock(scope: !431, file: !4)
!434 = distinct !DISubprogram(name: "Num_isZero_f57b151e8a6dfbc520c29ccc134c8fb5357cdd96058ecd185f0787f48b7a6", linkageName: "Num_isZero_f57b151e8a6dfbc520c29ccc134c8fb5357cdd96058ecd185f0787f48b7a6", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!435 = !DILocation(line: 0, scope: !436)
!436 = distinct !DILexicalBlock(scope: !434, file: !4)
!437 = distinct !DISubprogram(name: "Num_isLt_f273102d33b910ab8b1eda6e483bb587ec34372c3562cd9bfb68bcf889ba9cd", linkageName: "Num_isLt_f273102d33b910ab8b1eda6e483bb587ec34372c3562cd9bfb68bcf889ba9cd", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!438 = !DILocation(line: 0, scope: !439)
!439 = distinct !DILexicalBlock(scope: !437, file: !4)
!440 = distinct !DISubprogram(name: "InternalTask_toEffect_28b81340646419744ffe2153acaa8e39d3c2d10c2a51eb5702318112c7c5", linkageName: "InternalTask_toEffect_28b81340646419744ffe2153acaa8e39d3c2d10c2a51eb5702318112c7c5", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!441 = !DILocation(line: 0, scope: !442)
!442 = distinct !DILexicalBlock(scope: !440, file: !4)
!443 = distinct !DISubprogram(name: "Num_addWrap_e6845638e158b704aa8395d259110713932beb5d7a34137f5739ba7e3dd198", linkageName: "Num_addWrap_e6845638e158b704aa8395d259110713932beb5d7a34137f5739ba7e3dd198", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!444 = !DILocation(line: 0, scope: !445)
!445 = distinct !DILexicalBlock(scope: !443, file: !4)
!446 = distinct !DISubprogram(name: "_13_c852b6d75d2364d70d094699f8a9cda9129d5310ed82ea45564f47a9", linkageName: "_13_c852b6d75d2364d70d094699f8a9cda9129d5310ed82ea45564f47a9", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!447 = !DILocation(line: 0, scope: !448)
!448 = distinct !DILexicalBlock(scope: !446, file: !4)
!449 = distinct !DISubprogram(name: "Num_divTruncUnchecked_35bfe7dc6dba25ddadede12999f2a34775468912610779bf675f9c2d81ecac", linkageName: "Num_divTruncUnchecked_35bfe7dc6dba25ddadede12999f2a34775468912610779bf675f9c2d81ecac", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!450 = !DILocation(line: 0, scope: !451)
!451 = distinct !DILexicalBlock(scope: !449, file: !4)
!452 = distinct !DISubprogram(name: "Bool_false_4e123451c288c52798d3df0fc84811d2d957f324242982575c70dfd6d338df", linkageName: "Bool_false_4e123451c288c52798d3df0fc84811d2d957f324242982575c70dfd6d338df", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!453 = !DILocation(line: 0, scope: !454)
!454 = distinct !DILexicalBlock(scope: !452, file: !4)
!455 = distinct !DISubprogram(name: "Effect_after_d9e2d7d318b97522751e8d862a897cd552d26040fa25d41678f9ac7b36cd7", linkageName: "Effect_after_d9e2d7d318b97522751e8d862a897cd552d26040fa25d41678f9ac7b36cd7", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!456 = !DILocation(line: 0, scope: !457)
!457 = distinct !DILexicalBlock(scope: !455, file: !4)
!458 = distinct !DISubprogram(name: "Effect_effect_map_inner_f2e0cf21cda4e3c878e1ab216b192b2e2825d82c3b48a3a8bb6d7de6e7e20e", linkageName: "Effect_effect_map_inner_f2e0cf21cda4e3c878e1ab216b192b2e2825d82c3b48a3a8bb6d7de6e7e20e", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!459 = !DILocation(line: 0, scope: !460)
!460 = distinct !DILexicalBlock(scope: !458, file: !4)
!461 = distinct !DISubprogram(name: "InternalTask_toEffect_9c59e7328dd8975131b4ecbb517752a19f98ddf8f39456448f3da8e957ece54", linkageName: "InternalTask_toEffect_9c59e7328dd8975131b4ecbb517752a19f98ddf8f39456448f3da8e957ece54", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!462 = !DILocation(line: 0, scope: !463)
!463 = distinct !DILexicalBlock(scope: !461, file: !4)
!464 = distinct !DISubprogram(name: "Utc_toIso8601Str_46849c3b86f45f4f9e25198bc9b2ae6bcae76ebfbd692c6f18d9d9111cb9233c", linkageName: "Utc_toIso8601Str_46849c3b86f45f4f9e25198bc9b2ae6bcae76ebfbd692c6f18d9d9111cb9233c", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!465 = !DILocation(line: 0, scope: !466)
!466 = distinct !DILexicalBlock(scope: !464, file: !4)
!467 = distinct !DISubprogram(name: "Task_await_c76509a58fbafc47f4d5fc1992204e92c831be8ebe1587d7baf160babfe2ad", linkageName: "Task_await_c76509a58fbafc47f4d5fc1992204e92c831be8ebe1587d7baf160babfe2ad", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!468 = !DILocation(line: 0, scope: !469)
!469 = distinct !DILexicalBlock(scope: !467, file: !4)
!470 = distinct !DISubprogram(name: "InternalTask_toEffect_7e6da7233f16ea2c61d431e9d8c0a56499bf145a5210fb3d79ec4aba1f55c0a8", linkageName: "InternalTask_toEffect_7e6da7233f16ea2c61d431e9d8c0a56499bf145a5210fb3d79ec4aba1f55c0a8", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!471 = !DILocation(line: 0, scope: !472)
!472 = distinct !DILexicalBlock(scope: !470, file: !4)
!473 = distinct !DISubprogram(name: "Effect_after_a7deb1b6384ce9571721cd1522e1e931203f492c94f2dbf8138817d3824a", linkageName: "Effect_after_a7deb1b6384ce9571721cd1522e1e931203f492c94f2dbf8138817d3824a", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!474 = !DILocation(line: 0, scope: !475)
!475 = distinct !DILexicalBlock(scope: !473, file: !4)
!476 = distinct !DISubprogram(name: "Effect_always_bc8306c1040a95f2dac252e82b64a88f9bbe8f51d564ae0c05ee47ab4dc64ec", linkageName: "Effect_always_bc8306c1040a95f2dac252e82b64a88f9bbe8f51d564ae0c05ee47ab4dc64ec", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!477 = !DILocation(line: 0, scope: !478)
!478 = distinct !DILexicalBlock(scope: !476, file: !4)
!479 = distinct !DISubprogram(name: "List_iterHelp_676ec9e417566a851359c2c6d5d5332f7d40742f8274a8672f3cad244846", linkageName: "List_iterHelp_676ec9e417566a851359c2c6d5d5332f7d40742f8274a8672f3cad244846", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!480 = !DILocation(line: 0, scope: !481)
!481 = distinct !DILexicalBlock(scope: !479, file: !4)
!482 = distinct !DISubprogram(name: "Utc_11_edba1fc0cbfb8bc06ea89d458e5f5137027dfdf6bb865a3fbe3121562", linkageName: "Utc_11_edba1fc0cbfb8bc06ea89d458e5f5137027dfdf6bb865a3fbe3121562", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!483 = !DILocation(line: 0, scope: !484)
!484 = distinct !DILexicalBlock(scope: !482, file: !4)
!485 = distinct !DISubprogram(name: "Effect_effect_closure_stderrLine_a0d5c44a91521ccbe6cbe0ca2338db7878e8dda81a27912b861f86434c26c052", linkageName: "Effect_effect_closure_stderrLine_a0d5c44a91521ccbe6cbe0ca2338db7878e8dda81a27912b861f86434c26c052", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!486 = !DILocation(line: 0, scope: !487)
!487 = distinct !DILexicalBlock(scope: !485, file: !4)
!488 = distinct !DISubprogram(name: "#UserApp_11_1fee66ad667b912c4d10ada5f77fb9e8b2dfe9a4124f957b34ae7bc684ecaf1", linkageName: "#UserApp_11_1fee66ad667b912c4d10ada5f77fb9e8b2dfe9a4124f957b34ae7bc684ecaf1", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!489 = !DILocation(line: 0, scope: !490)
!490 = distinct !DILexicalBlock(scope: !488, file: !4)
!491 = distinct !DISubprogram(name: "Stdout_4_b7aa9f7d377b2692ada596045493ead6d491b934dc9015fcbdd1a8e01477d", linkageName: "Stdout_4_b7aa9f7d377b2692ada596045493ead6d491b934dc9015fcbdd1a8e01477d", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!492 = !DILocation(line: 0, scope: !493)
!493 = distinct !DILexicalBlock(scope: !491, file: !4)
!494 = distinct !DISubprogram(name: "Effect_effect_map_inner_e4a1eb19d38152fc193a183edc36566d275fa494bf9c69e26c29c318cc289d0", linkageName: "Effect_effect_map_inner_e4a1eb19d38152fc193a183edc36566d275fa494bf9c69e26c29c318cc289d0", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!495 = !DILocation(line: 0, scope: !496)
!496 = distinct !DILexicalBlock(scope: !494, file: !4)
!497 = distinct !DISubprogram(name: "Num_add_669c1355a3e727bb53dd458f2e96e48571aa45dfabcfb4b7de1689484f11", linkageName: "Num_add_669c1355a3e727bb53dd458f2e96e48571aa45dfabcfb4b7de1689484f11", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!498 = !DILocation(line: 0, scope: !499)
!499 = distinct !DILexicalBlock(scope: !497, file: !4)
!500 = distinct !DISubprogram(name: "InternalTask_toEffect_c162bfc0bd74c841e2898960cc4e5160ab1032997985dd3fe7da33cf844631d", linkageName: "InternalTask_toEffect_c162bfc0bd74c841e2898960cc4e5160ab1032997985dd3fe7da33cf844631d", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!501 = !DILocation(line: 0, scope: !502)
!502 = distinct !DILexicalBlock(scope: !500, file: !4)
!503 = distinct !DISubprogram(name: "Effect_map_8523cacf79b3ae26b5b5ddfebda64fc7e54c53c82e133fab2e0abee3a1046", linkageName: "Effect_map_8523cacf79b3ae26b5b5ddfebda64fc7e54c53c82e133fab2e0abee3a1046", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!504 = !DILocation(line: 0, scope: !505)
!505 = distinct !DILexicalBlock(scope: !503, file: !4)
!506 = distinct !DISubprogram(name: "Effect_effect_always_inner_7ceb2e607d153edd175217b82e8ded113c6e4df27e27777d9f9694c716aa427", linkageName: "Effect_effect_always_inner_7ceb2e607d153edd175217b82e8ded113c6e4df27e27777d9f9694c716aa427", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!507 = !DILocation(line: 0, scope: !508)
!508 = distinct !DILexicalBlock(scope: !506, file: !4)
!509 = distinct !DISubprogram(name: "List_any_926c4e1deae44cb32fa91b0fc2f966fdf98af98ee562517f2d5df6cc1b8bf0", linkageName: "List_any_926c4e1deae44cb32fa91b0fc2f966fdf98af98ee562517f2d5df6cc1b8bf0", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!510 = !DILocation(line: 0, scope: !511)
!511 = distinct !DILexicalBlock(scope: !509, file: !4)
!512 = distinct !DISubprogram(name: "InternalDateTime_minutesWithPaddedZeros_44109459d64fcdac3ea0c7115c1a33caa6de3332a46a1f0819b84a1d3a6c9", linkageName: "InternalDateTime_minutesWithPaddedZeros_44109459d64fcdac3ea0c7115c1a33caa6de3332a46a1f0819b84a1d3a6c9", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!513 = !DILocation(line: 0, scope: !514)
!514 = distinct !DILexicalBlock(scope: !512, file: !4)
!515 = distinct !DISubprogram(name: "Num_remUnchecked_dc3f621de1221c7c53a19e877c377561ede91cdd88b1a687d310a39785a", linkageName: "Num_remUnchecked_dc3f621de1221c7c53a19e877c377561ede91cdd88b1a687d310a39785a", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!516 = !DILocation(line: 0, scope: !517)
!517 = distinct !DILexicalBlock(scope: !515, file: !4)
!518 = distinct !DISubprogram(name: "InternalTask_err_cd37899bb8a8d9e6a1967d5d098545d4623f55f4fb33fb81a429834acd2bca2", linkageName: "InternalTask_err_cd37899bb8a8d9e6a1967d5d098545d4623f55f4fb33fb81a429834acd2bca2", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!519 = !DILocation(line: 0, scope: !520)
!520 = distinct !DILexicalBlock(scope: !518, file: !4)
!521 = distinct !DISubprogram(name: "Effect_effect_map_inner_c8ee203993b19f9eeb79e6d9b9cb5c211fecc131b917baefe682bdc7d1dc7e", linkageName: "Effect_effect_map_inner_c8ee203993b19f9eeb79e6d9b9cb5c211fecc131b917baefe682bdc7d1dc7e", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!522 = !DILocation(line: 0, scope: !523)
!523 = distinct !DILexicalBlock(scope: !521, file: !4)
!524 = distinct !DISubprogram(name: "InternalTask_toEffect_4d841bd57979ccceddece07dcf2dbc9edd3191f365637aa1e5efefa18c6c7ca3", linkageName: "InternalTask_toEffect_4d841bd57979ccceddece07dcf2dbc9edd3191f365637aa1e5efefa18c6c7ca3", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!525 = !DILocation(line: 0, scope: !526)
!526 = distinct !DILexicalBlock(scope: !524, file: !4)
!527 = distinct !DISubprogram(name: "Task_60_e19be4977dae6e316e964ccb3f3519dc19317486f4e86b58a231a1854931186", linkageName: "Task_60_e19be4977dae6e316e964ccb3f3519dc19317486f4e86b58a231a1854931186", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!528 = !DILocation(line: 0, scope: !529)
!529 = distinct !DILexicalBlock(scope: !527, file: !4)
!530 = distinct !DISubprogram(name: "InternalTask_toEffect_a0ad3055de08c7e73da1974f4d9be666ee2daaab6969dd582bb59893cf022b0", linkageName: "InternalTask_toEffect_a0ad3055de08c7e73da1974f4d9be666ee2daaab6969dd582bb59893cf022b0", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!531 = !DILocation(line: 0, scope: !532)
!532 = distinct !DILexicalBlock(scope: !530, file: !4)
!533 = distinct !DISubprogram(name: "List_getUnsafe_8acb95ddb9a746c2bf4dc0f4f96ce3b3e1f1e4f2559e7641b193db1f161d1c41", linkageName: "List_getUnsafe_8acb95ddb9a746c2bf4dc0f4f96ce3b3e1f1e4f2559e7641b193db1f161d1c41", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!534 = !DILocation(line: 0, scope: !535)
!535 = distinct !DILexicalBlock(scope: !533, file: !4)
!536 = distinct !DISubprogram(name: "Effect_effect_always_inner_8256d790c99390129cd6628d4d43bc44f55cfb83af722d8248666b192be24d65", linkageName: "Effect_effect_always_inner_8256d790c99390129cd6628d4d43bc44f55cfb83af722d8248666b192be24d65", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!537 = !DILocation(line: 0, scope: !538)
!538 = distinct !DILexicalBlock(scope: !536, file: !4)
!539 = distinct !DISubprogram(name: "Task_err_9cc9ac536c41c72f38d2273c43b034822641cbb47ea8853416c10d132561319", linkageName: "Task_err_9cc9ac536c41c72f38d2273c43b034822641cbb47ea8853416c10d132561319", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!540 = !DILocation(line: 0, scope: !541)
!541 = distinct !DILexicalBlock(scope: !539, file: !4)
!542 = distinct !DISubprogram(name: "#UserApp_respond_8c3fdd6849785e1b32106ad9c6ae59845e2314f0a6799376d4e3e3b9be62d181", linkageName: "#UserApp_respond_8c3fdd6849785e1b32106ad9c6ae59845e2314f0a6799376d4e3e3b9be62d181", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!543 = !DILocation(line: 0, scope: !544)
!544 = distinct !DILexicalBlock(scope: !542, file: !4)
!545 = distinct !DISubprogram(name: "InternalTask_toEffect_8e7a40fb7cb2175e9c8b7aee60f44cef84959b742d3a14c483b6e3b14f05c2f", linkageName: "InternalTask_toEffect_8e7a40fb7cb2175e9c8b7aee60f44cef84959b742d3a14c483b6e3b14f05c2f", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!546 = !DILocation(line: 0, scope: !547)
!547 = distinct !DILexicalBlock(scope: !545, file: !4)
!548 = distinct !DISubprogram(name: "InternalTask_err_66a53c5bb7482a7975e058b703753a62aee74dcb3ed8c2fbfc227399ea738e", linkageName: "InternalTask_err_66a53c5bb7482a7975e058b703753a62aee74dcb3ed8c2fbfc227399ea738e", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!549 = !DILocation(line: 0, scope: !550)
!550 = distinct !DILexicalBlock(scope: !548, file: !4)
!551 = distinct !DISubprogram(name: "Effect_map_3780de15a3a832596a21b52356ca78cefe1f05b661333fe4053d5b87a27e0", linkageName: "Effect_map_3780de15a3a832596a21b52356ca78cefe1f05b661333fe4053d5b87a27e0", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!552 = !DILocation(line: 0, scope: !553)
!553 = distinct !DILexicalBlock(scope: !551, file: !4)
!554 = distinct !DISubprogram(name: "Effect_after_c5b690bc22238d3ac9e996befafbf2c431a107de306ea8b8318875c9fcba16", linkageName: "Effect_after_c5b690bc22238d3ac9e996befafbf2c431a107de306ea8b8318875c9fcba16", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!555 = !DILocation(line: 0, scope: !556)
!556 = distinct !DILexicalBlock(scope: !554, file: !4)
!557 = distinct !DISubprogram(name: "_155_9b7306a2e571f3d11e34b901a57455c3e32e69a2f8fde813ed1c4300e12712", linkageName: "_155_9b7306a2e571f3d11e34b901a57455c3e32e69a2f8fde813ed1c4300e12712", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!558 = !DILocation(line: 0, scope: !559)
!559 = distinct !DILexicalBlock(scope: !557, file: !4)
!560 = distinct !DISubprogram(name: "InternalDateTime_hoursWithPaddedZeros_93b8def1d2984c6818ac4bcad643457a66cc713468a3a5225fa94a9b1b4933f0", linkageName: "InternalDateTime_hoursWithPaddedZeros_93b8def1d2984c6818ac4bcad643457a66cc713468a3a5225fa94a9b1b4933f0", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!561 = !DILocation(line: 0, scope: !562)
!562 = distinct !DILexicalBlock(scope: !560, file: !4)
!563 = distinct !DISubprogram(name: "Task_await_ca98df76e744faeef21fb76918295997c9c1b552a2e623d6fc162a11de8fae", linkageName: "Task_await_ca98df76e744faeef21fb76918295997c9c1b552a2e623d6fc162a11de8fae", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!564 = !DILocation(line: 0, scope: !565)
!565 = distinct !DILexicalBlock(scope: !563, file: !4)
!566 = distinct !DISubprogram(name: "Effect_always_deda9c07093181a3aee6f4559463a94ce2b31f038cb3d5548d0bb2aeba37e1", linkageName: "Effect_always_deda9c07093181a3aee6f4559463a94ce2b31f038cb3d5548d0bb2aeba37e1", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!567 = !DILocation(line: 0, scope: !568)
!568 = distinct !DILexicalBlock(scope: !566, file: !4)
!569 = distinct !DISubprogram(name: "Num_sub_e84248fb50d0833361d0417df114b0b3b3448fff97c39cdde963b09a9aebb8", linkageName: "Num_sub_e84248fb50d0833361d0417df114b0b3b3448fff97c39cdde963b09a9aebb8", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!570 = !DILocation(line: 0, scope: !571)
!571 = distinct !DILexicalBlock(scope: !569, file: !4)
!572 = distinct !DISubprogram(name: "InternalTask_fromEffect_4f1fdebc72623b7987dfbf57d7b81537b885c9e4ce317a63dbf262856adf", linkageName: "InternalTask_fromEffect_4f1fdebc72623b7987dfbf57d7b81537b885c9e4ce317a63dbf262856adf", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!573 = !DILocation(line: 0, scope: !574)
!574 = distinct !DILexicalBlock(scope: !572, file: !4)
!575 = distinct !DISubprogram(name: "Effect_always_a472f7aba8f6717343f24da54150b124829637a3f252c7e04811e4754b343d0", linkageName: "Effect_always_a472f7aba8f6717343f24da54150b124829637a3f252c7e04811e4754b343d0", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!576 = !DILocation(line: 0, scope: !577)
!577 = distinct !DILexicalBlock(scope: !575, file: !4)
!578 = distinct !DISubprogram(name: "InternalTask_fromEffect_7f755070a828d5b0991fd43175b6036d1cb7ecf871d1b823a8797b553d92bc", linkageName: "InternalTask_fromEffect_7f755070a828d5b0991fd43175b6036d1cb7ecf871d1b823a8797b553d92bc", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!579 = !DILocation(line: 0, scope: !580)
!580 = distinct !DILexicalBlock(scope: !578, file: !4)
!581 = distinct !DISubprogram(name: "InternalTask_fromEffect_50e8e06555163661d37576e08a187bc1a82c34c685bbe84f89594e81f9565960", linkageName: "InternalTask_fromEffect_50e8e06555163661d37576e08a187bc1a82c34c685bbe84f89594e81f9565960", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!582 = !DILocation(line: 0, scope: !583)
!583 = distinct !DILexicalBlock(scope: !581, file: !4)
!584 = distinct !DISubprogram(name: "InternalTask_err_61e5a13d423d566ac5e547894554a8bcf8bc44e60405c767b71c7c83a1e2c55", linkageName: "InternalTask_err_61e5a13d423d566ac5e547894554a8bcf8bc44e60405c767b71c7c83a1e2c55", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!585 = !DILocation(line: 0, scope: !586)
!586 = distinct !DILexicalBlock(scope: !584, file: !4)
!587 = distinct !DISubprogram(name: "Task_ok_8445464738218c426e3b841f28ede2879d4391e6c33df6a616e872e199e47e", linkageName: "Task_ok_8445464738218c426e3b841f28ede2879d4391e6c33df6a616e872e199e47e", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!588 = !DILocation(line: 0, scope: !589)
!589 = distinct !DILexicalBlock(scope: !587, file: !4)
!590 = distinct !DISubprogram(name: "InternalTask_toEffect_8719a5fa4a4d2d7fe17773695c6c6d3ecd8b7cfffd135c8d4ca89f29f876d1f", linkageName: "InternalTask_toEffect_8719a5fa4a4d2d7fe17773695c6c6d3ecd8b7cfffd135c8d4ca89f29f876d1f", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!591 = !DILocation(line: 0, scope: !592)
!592 = distinct !DILexicalBlock(scope: !590, file: !4)
!593 = distinct !DISubprogram(name: "Str_isEmpty_99aa979e4a9cadd6dbe48ea878ec84acb7696eb93470c375f6893f1da46c3772", linkageName: "Str_isEmpty_99aa979e4a9cadd6dbe48ea878ec84acb7696eb93470c375f6893f1da46c3772", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!594 = !DILocation(line: 0, scope: !595)
!595 = distinct !DILexicalBlock(scope: !593, file: !4)
!596 = distinct !DISubprogram(name: "Effect_effect_always_inner_8f804d847f17ce19e983ee3d457d4c97a1c72145f357931dcbff3cd6dbfe4c0", linkageName: "Effect_effect_always_inner_8f804d847f17ce19e983ee3d457d4c97a1c72145f357931dcbff3cd6dbfe4c0", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!597 = !DILocation(line: 0, scope: !598)
!598 = distinct !DILexicalBlock(scope: !596, file: !4)
!599 = distinct !DISubprogram(name: "Task_53_f752fd971dee73f4bef39e126f15a0a84437112755ca589db8702463ce739a", linkageName: "Task_53_f752fd971dee73f4bef39e126f15a0a84437112755ca589db8702463ce739a", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!600 = !DILocation(line: 0, scope: !601)
!601 = distinct !DILexicalBlock(scope: !599, file: !4)
!602 = distinct !DISubprogram(name: "Effect_after_ac6315adde982c4b62c768a77be738d224267f4f9e6f1a02f3bc60549578c", linkageName: "Effect_after_ac6315adde982c4b62c768a77be738d224267f4f9e6f1a02f3bc60549578c", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!603 = !DILocation(line: 0, scope: !604)
!604 = distinct !DILexicalBlock(scope: !602, file: !4)
!605 = distinct !DISubprogram(name: "Effect_effect_closure_posixTime_1529b61b29181b37e427cd639d65060a33ef72662c4981e67e9c292331a", linkageName: "Effect_effect_closure_posixTime_1529b61b29181b37e427cd639d65060a33ef72662c4981e67e9c292331a", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!606 = !DILocation(line: 0, scope: !607)
!607 = distinct !DILexicalBlock(scope: !605, file: !4)
!608 = distinct !DISubprogram(name: "InternalTask_fromEffect_d5c9642a64db206d88ab43bd2b9527b05aca746579abd7472d977da8e33ac", linkageName: "InternalTask_fromEffect_d5c9642a64db206d88ab43bd2b9527b05aca746579abd7472d977da8e33ac", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!609 = !DILocation(line: 0, scope: !610)
!610 = distinct !DILexicalBlock(scope: !608, file: !4)
!611 = distinct !DISubprogram(name: "Stdout_line_99c9f773566b1d5d689233ef7949cf16c8797c970a4668678361d8c89d24f20", linkageName: "Stdout_line_99c9f773566b1d5d689233ef7949cf16c8797c970a4668678361d8c89d24f20", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!612 = !DILocation(line: 0, scope: !613)
!613 = distinct !DILexicalBlock(scope: !611, file: !4)
!614 = distinct !DISubprogram(name: "Effect_effect_closure_stdoutLine_622c9f939ebee86f480d73fdef56611b8899ab7e93ac9da07aeba3373394a", linkageName: "Effect_effect_closure_stdoutLine_622c9f939ebee86f480d73fdef56611b8899ab7e93ac9da07aeba3373394a", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!615 = !DILocation(line: 0, scope: !616)
!616 = distinct !DILexicalBlock(scope: !614, file: !4)
!617 = distinct !DISubprogram(name: "Effect_after_0ecd2fa884bf65d7bc12fe6d21fb068cfa330b949298476bb016904fd3f", linkageName: "Effect_after_0ecd2fa884bf65d7bc12fe6d21fb068cfa330b949298476bb016904fd3f", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!618 = !DILocation(line: 0, scope: !619)
!619 = distinct !DILexicalBlock(scope: !617, file: !4)
!620 = distinct !DISubprogram(name: "Num_toI128_54b3c6d264e7c557f2fe74ef29431163e9a30a2e4aca38b681d4b9ee62de031", linkageName: "Num_toI128_54b3c6d264e7c557f2fe74ef29431163e9a30a2e4aca38b681d4b9ee62de031", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!621 = !DILocation(line: 0, scope: !622)
!622 = distinct !DILexicalBlock(scope: !620, file: !4)
!623 = distinct !DISubprogram(name: "_25_1c44a9ca60e694ea5bce656141adb8728c249dc46543e7c34883c1136ab140", linkageName: "_25_1c44a9ca60e694ea5bce656141adb8728c249dc46543e7c34883c1136ab140", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!624 = !DILocation(line: 0, scope: !625)
!625 = distinct !DILexicalBlock(scope: !623, file: !4)
!626 = distinct !DISubprogram(name: "Effect_after_f411d2d207cb75ff49124b128ee5a4cdec2daf8d1cf0a733c3c7d426729b6b", linkageName: "Effect_after_f411d2d207cb75ff49124b128ee5a4cdec2daf8d1cf0a733c3c7d426729b6b", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!627 = !DILocation(line: 0, scope: !628)
!628 = distinct !DILexicalBlock(scope: !626, file: !4)
!629 = distinct !DISubprogram(name: "Utc_now_c773168b5a79ac91672eeb52ab4405228b6e1da8f6c62d3ec2af603fa2ad92", linkageName: "Utc_now_c773168b5a79ac91672eeb52ab4405228b6e1da8f6c62d3ec2af603fa2ad92", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!630 = !DILocation(line: 0, scope: !631)
!631 = distinct !DILexicalBlock(scope: !629, file: !4)
!632 = distinct !DISubprogram(name: "Task_ok_f79740875a4d32b5abcf43deaad586f61fe4062a6785757475b34d82a82", linkageName: "Task_ok_f79740875a4d32b5abcf43deaad586f61fe4062a6785757475b34d82a82", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!633 = !DILocation(line: 0, scope: !634)
!634 = distinct !DILexicalBlock(scope: !632, file: !4)
!635 = distinct !DISubprogram(name: "Str_toUtf8_eabc27640eff330d625cb2f6435f5dccaec45dd590ad64015fdca105b70", linkageName: "Str_toUtf8_eabc27640eff330d625cb2f6435f5dccaec45dd590ad64015fdca105b70", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!636 = !DILocation(line: 0, scope: !637)
!637 = distinct !DILexicalBlock(scope: !635, file: !4)
!638 = distinct !DISubprogram(name: "InternalTask_fromEffect_a1b37f834fad683b855edbbe46b2d4d8d04bfe3fdda176d9a70679e9ca0caf", linkageName: "InternalTask_fromEffect_a1b37f834fad683b855edbbe46b2d4d8d04bfe3fdda176d9a70679e9ca0caf", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!639 = !DILocation(line: 0, scope: !640)
!640 = distinct !DILexicalBlock(scope: !638, file: !4)
!641 = distinct !DISubprogram(name: "Effect_map_56ecce6137ef1a8b7fa2d1462a14bcff563458ace807157c68c36b8f837c2", linkageName: "Effect_map_56ecce6137ef1a8b7fa2d1462a14bcff563458ace807157c68c36b8f837c2", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!642 = !DILocation(line: 0, scope: !643)
!643 = distinct !DILexicalBlock(scope: !641, file: !4)
!644 = distinct !DISubprogram(name: "Effect_after_35d6cb78c74f84df82ab12c37bc71bbe5193f93e9d36506abc7c9c8ca124d1ab", linkageName: "Effect_after_35d6cb78c74f84df82ab12c37bc71bbe5193f93e9d36506abc7c9c8ca124d1ab", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!645 = !DILocation(line: 0, scope: !646)
!646 = distinct !DILexicalBlock(scope: !644, file: !4)
!647 = distinct !DISubprogram(name: "Stdout_4_bad96aa871ccf5b068b2a1da7544fd3d07a932588efb92244e692b8beda99ce", linkageName: "Stdout_4_bad96aa871ccf5b068b2a1da7544fd3d07a932588efb92244e692b8beda99ce", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!648 = !DILocation(line: 0, scope: !649)
!649 = distinct !DILexicalBlock(scope: !647, file: !4)
!650 = distinct !DISubprogram(name: "#UserApp_init_8b8e749a7d5dc4035aed2d09b8b4ad59fac5ad694339521a2df23bf1ac35c3", linkageName: "#UserApp_init_8b8e749a7d5dc4035aed2d09b8b4ad59fac5ad694339521a2df23bf1ac35c3", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!651 = !DILocation(line: 0, scope: !652)
!652 = distinct !DILexicalBlock(scope: !650, file: !4)
!653 = distinct !DISubprogram(name: "InternalTask_toEffect_1b6b9e2f2c8025d6941d1d79426973c1ba899598ef8eecc9bea3f5f3657b4477", linkageName: "InternalTask_toEffect_1b6b9e2f2c8025d6941d1d79426973c1ba899598ef8eecc9bea3f5f3657b4477", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!654 = !DILocation(line: 0, scope: !655)
!655 = distinct !DILexicalBlock(scope: !653, file: !4)
!656 = distinct !DISubprogram(name: "Task_53_48c2caee6f1010356bbec8845a6ee45f2928c63eece16acf25dc3f84dc5f6", linkageName: "Task_53_48c2caee6f1010356bbec8845a6ee45f2928c63eece16acf25dc3f84dc5f6", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!657 = !DILocation(line: 0, scope: !658)
!658 = distinct !DILexicalBlock(scope: !656, file: !4)
!659 = distinct !DISubprogram(name: "Task_53_6c6ac529604932be9f613389ac656fb39037eb79cbe1d537d9bdd99c2563108d", linkageName: "Task_53_6c6ac529604932be9f613389ac656fb39037eb79cbe1d537d9bdd99c2563108d", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!660 = !DILocation(line: 0, scope: !661)
!661 = distinct !DILexicalBlock(scope: !659, file: !4)
!662 = distinct !DISubprogram(name: "Effect_effect_after_inner_dfab3e7e4dcf97947ada0f8abcfc248e78de1f269ac4599a46f8db36f6ed6aa", linkageName: "Effect_effect_after_inner_dfab3e7e4dcf97947ada0f8abcfc248e78de1f269ac4599a46f8db36f6ed6aa", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!663 = !DILocation(line: 0, scope: !664)
!664 = distinct !DILexicalBlock(scope: !662, file: !4)
!665 = distinct !DISubprogram(name: "Effect_map_1841486258dadc6565ddb7a1717e1e68e57abb67c121aeb72cb4d456026a9", linkageName: "Effect_map_1841486258dadc6565ddb7a1717e1e68e57abb67c121aeb72cb4d456026a9", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!666 = !DILocation(line: 0, scope: !667)
!667 = distinct !DILexicalBlock(scope: !665, file: !4)
!668 = distinct !DISubprogram(name: "InternalTask_fromEffect_1a20a86e49e98265a07f2e3520fd72f1d5cc4a4259e669f8b2acf756122080", linkageName: "InternalTask_fromEffect_1a20a86e49e98265a07f2e3520fd72f1d5cc4a4259e669f8b2acf756122080", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!669 = !DILocation(line: 0, scope: !670)
!670 = distinct !DILexicalBlock(scope: !668, file: !4)
!671 = distinct !DISubprogram(name: "_30_4dcdd9fc1c563c9592918682f5bb9bfbff249c75cdcf934a994231c5c3a018", linkageName: "_30_4dcdd9fc1c563c9592918682f5bb9bfbff249c75cdcf934a994231c5c3a018", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!672 = !DILocation(line: 0, scope: !673)
!673 = distinct !DILexicalBlock(scope: !671, file: !4)
!674 = distinct !DISubprogram(name: "Num_divTrunc_cb411178cb7686889a4ee0e4b4c57e63975186dc9f1448b79e94c2721a21a2", linkageName: "Num_divTrunc_cb411178cb7686889a4ee0e4b4c57e63975186dc9f1448b79e94c2721a21a2", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!675 = !DILocation(line: 0, scope: !676)
!676 = distinct !DILexicalBlock(scope: !674, file: !4)
!677 = distinct !DISubprogram(name: "Task_result_19a01698b1f1f64ca782bce3c6b70dbfe2947aebabe3f6b126ebdf6166ecc31", linkageName: "Task_result_19a01698b1f1f64ca782bce3c6b70dbfe2947aebabe3f6b126ebdf6166ecc31", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!678 = !DILocation(line: 0, scope: !679)
!679 = distinct !DILexicalBlock(scope: !677, file: !4)
!680 = distinct !DISubprogram(name: "InternalTask_toEffect_405afdd54e1519581be52a8c8268ff856d1e183e22d746e36b8e1e892557df7", linkageName: "InternalTask_toEffect_405afdd54e1519581be52a8c8268ff856d1e183e22d746e36b8e1e892557df7", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!681 = !DILocation(line: 0, scope: !682)
!682 = distinct !DILexicalBlock(scope: !680, file: !4)
!683 = distinct !DISubprogram(name: "Effect_effect_always_inner_6fdff3e812be393e397a32aeb76ae96155b45793f22c8c7f8b12de3628ba863", linkageName: "Effect_effect_always_inner_6fdff3e812be393e397a32aeb76ae96155b45793f22c8c7f8b12de3628ba863", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!684 = !DILocation(line: 0, scope: !685)
!685 = distinct !DILexicalBlock(scope: !683, file: !4)
!686 = distinct !DISubprogram(name: "Stderr_4_1979c8b7ef5f495fcd893830dae286517b20f9eb43379243d33155ade7a91", linkageName: "Stderr_4_1979c8b7ef5f495fcd893830dae286517b20f9eb43379243d33155ade7a91", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!687 = !DILocation(line: 0, scope: !688)
!688 = distinct !DILexicalBlock(scope: !686, file: !4)
!689 = distinct !DISubprogram(name: "InternalDateTime_yearWithPaddedZeros_c4a37e6d352bb35242daa87c613d86251be76cf677f327944a4ca87b5e276", linkageName: "InternalDateTime_yearWithPaddedZeros_c4a37e6d352bb35242daa87c613d86251be76cf677f327944a4ca87b5e276", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!690 = !DILocation(line: 0, scope: !691)
!691 = distinct !DILexicalBlock(scope: !689, file: !4)
!692 = distinct !DISubprogram(name: "InternalTask_ok_c84245e9d5a8bbcea28f19811f38b2e7a05f277c949080724954fddcea11aca3", linkageName: "InternalTask_ok_c84245e9d5a8bbcea28f19811f38b2e7a05f277c949080724954fddcea11aca3", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!693 = !DILocation(line: 0, scope: !694)
!694 = distinct !DILexicalBlock(scope: !692, file: !4)
!695 = distinct !DISubprogram(name: "Box_unbox_d394208415ac8fe0ce8aa0ddf6a845c7cc74d818698e3d25c85705ce311f5ec", linkageName: "Box_unbox_d394208415ac8fe0ce8aa0ddf6a845c7cc74d818698e3d25c85705ce311f5ec", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!696 = !DILocation(line: 0, scope: !697)
!697 = distinct !DILexicalBlock(scope: !695, file: !4)
!698 = distinct !DISubprogram(name: "Effect_always_aacdfa21c937a3152a4c9abafa557bcab3033c1362c20c33c558b64d99d3e5", linkageName: "Effect_always_aacdfa21c937a3152a4c9abafa557bcab3033c1362c20c33c558b64d99d3e5", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!699 = !DILocation(line: 0, scope: !700)
!700 = distinct !DILexicalBlock(scope: !698, file: !4)
!701 = distinct !DISubprogram(name: "Bool_structuralNotEq_53eef38977ca9e3af29e8b6fc9f50f557be9bbd173abd2118eb5488f19fb2", linkageName: "Bool_structuralNotEq_53eef38977ca9e3af29e8b6fc9f50f557be9bbd173abd2118eb5488f19fb2", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!702 = !DILocation(line: 0, scope: !703)
!703 = distinct !DILexicalBlock(scope: !701, file: !4)
!704 = distinct !DISubprogram(name: "InternalHttp_fromHostRequest_99ccc6754e07ea7cffe47524633bfb91dd0f5a5f04cc85ed764577b4b3a23", linkageName: "InternalHttp_fromHostRequest_99ccc6754e07ea7cffe47524633bfb91dd0f5a5f04cc85ed764577b4b3a23", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!705 = !DILocation(line: 0, scope: !706)
!706 = distinct !DILexicalBlock(scope: !704, file: !4)
!707 = distinct !DISubprogram(name: "#Attr_#dec_2", linkageName: "#Attr_#dec_2", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!708 = !DILocation(line: 0, scope: !709)
!709 = distinct !DILexicalBlock(scope: !707, file: !4)
!710 = distinct !DISubprogram(name: "decrement_refcounted_ptr_8", linkageName: "decrement_refcounted_ptr_8", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!711 = !DILocation(line: 0, scope: !712)
!712 = distinct !DILexicalBlock(scope: !710, file: !4)
!713 = distinct !DISubprogram(name: "#Attr_#inc_2", linkageName: "#Attr_#inc_2", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!714 = !DILocation(line: 0, scope: !715)
!715 = distinct !DILexicalBlock(scope: !713, file: !4)
!716 = distinct !DISubprogram(name: "#Attr_#dec_3", linkageName: "#Attr_#dec_3", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!717 = !DILocation(line: 0, scope: !718)
!718 = distinct !DILexicalBlock(scope: !716, file: !4)
!719 = distinct !DISubprogram(name: "#Attr_#dec_4", linkageName: "#Attr_#dec_4", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!720 = !DILocation(line: 0, scope: !721)
!721 = distinct !DILexicalBlock(scope: !719, file: !4)
!722 = !DILocation(line: 0, scope: !723, inlinedAt: !725)
!723 = distinct !DILexicalBlock(scope: !724, file: !4)
!724 = distinct !DISubprogram(name: "#Attr_#generic_rc_by_ref_3_dec", linkageName: "#Attr_#generic_rc_by_ref_3_dec", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!725 = distinct !DILocation(line: 0, scope: !721)
!726 = distinct !DISubprogram(name: "#Attr_#dec_5", linkageName: "#Attr_#dec_5", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!727 = !DILocation(line: 0, scope: !728)
!728 = distinct !DILexicalBlock(scope: !726, file: !4)
!729 = distinct !DISubprogram(name: "#Attr_#dec_6", linkageName: "#Attr_#dec_6", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!730 = !DILocation(line: 0, scope: !731)
!731 = distinct !DILexicalBlock(scope: !729, file: !4)
!732 = distinct !DISubprogram(name: "#Attr_#dec_7", linkageName: "#Attr_#dec_7", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!733 = !DILocation(line: 0, scope: !734)
!734 = distinct !DILexicalBlock(scope: !732, file: !4)
!735 = distinct !DISubprogram(name: "#Attr_#dec_8", linkageName: "#Attr_#dec_8", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!736 = !DILocation(line: 0, scope: !737)
!737 = distinct !DILexicalBlock(scope: !735, file: !4)
!738 = distinct !DISubprogram(name: "#Attr_#inc_6", linkageName: "#Attr_#inc_6", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!739 = !DILocation(line: 0, scope: !740)
!740 = distinct !DILexicalBlock(scope: !738, file: !4)
!741 = distinct !DISubprogram(name: "#Attr_#dec_17", linkageName: "#Attr_#dec_17", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!742 = !DILocation(line: 0, scope: !743)
!743 = distinct !DILexicalBlock(scope: !741, file: !4)
!744 = distinct !DISubprogram(name: "#Attr_#dec_18", linkageName: "#Attr_#dec_18", scope: !4, file: !4, type: !98, flags: DIFlagPublic, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !3, retainedNodes: !101)
!745 = !DILocation(line: 0, scope: !746)
!746 = distinct !DILexicalBlock(scope: !744, file: !4)
