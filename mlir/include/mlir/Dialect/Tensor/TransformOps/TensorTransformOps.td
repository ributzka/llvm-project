//===- TensorTransformOps.td - Tensor transformation ops ---*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef TENSOR_TRANSFORM_OPS
#define TENSOR_TRANSFORM_OPS

include "mlir/Dialect/Transform/IR/TransformDialect.td"
include "mlir/Dialect/Transform/Interfaces/TransformInterfaces.td"
include "mlir/Dialect/Transform/IR/TransformTypes.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "mlir/IR/OpBase.td"

def ApplyDecomposeTensorConcatPatternsOp : Op<Transform_Dialect,
    "apply_patterns.tensor.decompose_concat",
    [DeclareOpInterfaceMethods<PatternDescriptorOpInterface>]> {
  let description = [{
    Indicates that tensor.concat ops should be decomposed into a chain of
    tensor.insert_slice operations inserting into a materialized destination.
  }];

  let assemblyFormat = "attr-dict";
}


def ApplyDropRedundantInsertSliceRankExpansionPatternsOp : Op<Transform_Dialect,
    "apply_patterns.tensor.drop_redundant_insert_slice_rank_expansion",
    [DeclareOpInterfaceMethods<PatternDescriptorOpInterface>]> {
  let description = [{
    Indicates that redundant tensor.insert_slice rank reductions should be
    dropped. E.g., cases where a tensor.extract_slice rank reduction immediately
    follows an inverse tensor.insert_slice rank expansion.
  }];

  let assemblyFormat = "attr-dict";
}

def ApplyFoldTensorEmptyPatternsOp : Op<Transform_Dialect,
    "apply_patterns.tensor.fold_tensor_empty",
    [DeclareOpInterfaceMethods<PatternDescriptorOpInterface>]> {
  let description = [{
    Indicates that tensor.extract_slice and reassociative reshapes should be
    folded into tensor.empty.

    If `fold_single_use_only` is set to "true", only tensor.empty that have a
    single use are folded.
  }];

  let arguments = (ins DefaultValuedAttr<BoolAttr, "false">:$fold_single_use_only);
  let assemblyFormat = "attr-dict";
}

def ApplyFoldTensorSubsetOpsPatternsOp : Op<Transform_Dialect,
    "apply_patterns.tensor.fold_tensor_subset_ops",
    [DeclareOpInterfaceMethods<PatternDescriptorOpInterface>]> {
  let description = [{
    Indicates that tensor.empty should be folded with tensor.extract_slice,
    tensor.expand_shape and tensor.collapse_shape.
  }];

  let assemblyFormat = "attr-dict";
}

def ApplyFoldTensorSubsetOpsIntoVectorTransfersPatternsOp : Op<Transform_Dialect,
    "apply_patterns.tensor.fold_tensor_subset_ops_into_vector_transfers",
    [DeclareOpInterfaceMethods<PatternDescriptorOpInterface>]> {
  let description = [{
    Indicates that tensor.extract_slice -> vector.transfer_read and
    vector.transfer_write -> tensor.insert_slice op chains should be folded into
    vector tranfer read and write ops
  }];

  let assemblyFormat = "attr-dict";
}

def ApplyMergeConsecutiveInsertExtractSlicePatternsOp : Op<Transform_Dialect,
    "apply_patterns.tensor.merge_consecutive_insert_extract_slice",
    [DeclareOpInterfaceMethods<PatternDescriptorOpInterface>]> {
  let description = [{
    Indicates that consecutive tensor.extract_slice/tensor.insert_slice ops
    should be merged into a single op. These patterns are not canonicalizations
    because the bufferization is sensitive to IR structure.
  }];

  let assemblyFormat = "attr-dict";
}

def ApplyReassociativeReshapeFoldingPatternsOp : Op<Transform_Dialect,
    "apply_patterns.tensor.reassociative_reshape_folding",
    [DeclareOpInterfaceMethods<PatternDescriptorOpInterface>]> {
  let description = [{
    Indicates that reassociative reshapes (tensor.collapse_shape /
    tensor.expand_shape) should be folded with inverse rank expansions / rank
    reductions (via tensor.insert_slice / tensor.extract_slice).
  }];

  let assemblyFormat = "attr-dict";
}

def ApplyBubbleUpExtractSlicePatternsOp : Op<Transform_Dialect,
    "apply_patterns.tensor.bubble_up_extract_slice",
    [DeclareOpInterfaceMethods<PatternDescriptorOpInterface>]> {
  let description = [{
    Indicates that producers of tensor.extract_slice should swap and operate on 
    the result of the slice.
  }];

  let assemblyFormat = "attr-dict";
}

def ApplyRewriteTensorOpsAsConstantPatternsOp : Op<Transform_Dialect,
    "apply_patterns.tensor.rewrite_as_constant",
    [DeclareOpInterfaceMethods<PatternDescriptorOpInterface>]> {
  let arguments = (ins UnitAttr:$aggressive);
  let description = [{
    Indicates that tensor ops (such as tensor.generate) should be replaced with
    constants (arith.constant) when possible.
  }];

  let assemblyFormat =
      "(`aggressive` $aggressive^)? attr-dict";
}

def Transform_TensorPadOp : Transform_ConcreteOpType<"tensor.pad">;

def MakeLoopIndependentOp
    : Op<Transform_Dialect, "tensor.make_loop_independent",
         [FunctionalStyleTransformOpTrait, MemoryEffectsOpInterface,
          TransformOpInterface, TransformEachOpTrait]> {
  let description = [{
    Rewrite the targeted ops such that their index-typed operands no longer
    depend on any loop induction variable of the `num_loop` enclosing `scf.for`
    loops. I.e., compute an upper bound that is independent of any such loop IV
    for every tensor dimension. The transformed op could then be hoisted from
    the `num_loop` enclosing loops. To preserve the original semantics, place a
    `tensor.extract_slice` inside the loop.

    Currently supported operations are:
    - tensor.empty: Replaced with a new tensor.empty with upper bound sizes,
      followed by a tensor.extract_slice.
    - tensor.pad: Replaced by an upper bound padding, followed by a
      tensor.extract_slice.

    #### Return modes

    This operation fails if at least one induction variable could not be
    eliminated. In case the targeted op is already independent of induction
    variables, this transform succeeds and returns the unmodified target op.

    Otherwise, the returned handle points to a subset of the produced ops:
    - tensor.empty: The returned handle points to the tensor.extract_slice op.
    - tensor.pad: The returned handle points to the tensor.extract_slice op.

    This transform op consumes the target handle and produces a result handle.
  }];

  let arguments = (ins TransformHandleTypeInterface:$target, I64Attr:$num_loops);
  let results = (outs TransformHandleTypeInterface:$transformed);
  let assemblyFormat =
      "$target attr-dict `:` functional-type($target, $transformed)";

  let extraClassDeclaration = [{
    ::mlir::DiagnosedSilenceableFailure applyToOne(
        ::mlir::transform::TransformRewriter &rewriter,
        ::mlir::Operation *target,
        ::mlir::transform::ApplyToEachResultList &results,
        ::mlir::transform::TransformState &state);
  }];
}

def TypeConversionCastShapeDynamicDimsOp : Op<Transform_Dialect,
    "type_conversion.tensor.cast_shape_dynamic_dims",
    [DeclareOpInterfaceMethods<TypeConverterBuilderOpInterface,
                               ["populateTypeMaterializations"]>]> {
  let description = [{
    Populates a type converter with conversion materialization functions that
    cast a tensor value between two cast-compatible tensors. See `tensor.cast`
    for more information on cast compatibility between tensors.

    If `ignore_dynamic_info` is not set, this will set an additional constraint
    that source materializations do not cast dynamic dimensions to static ones.
  }];
  let arguments = (ins UnitAttr:$ignore_dynamic_info);

  let assemblyFormat =
      "(`ignore_dynamic_info` $ignore_dynamic_info^)? attr-dict";
}

#endif // TENSOR_TRANSFORM_OPS
