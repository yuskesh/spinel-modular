# Profile/declaration/buffer checker depends only on LLVMSupport and Contract, not MLIR: it answers
# admission, not IR construction. ScalarAst.h accessors require the Frontend/Scalar header path but
# no library link.
add_library(SpinelMLIRFreestanding STATIC
  Diagnostics.cpp
  ProfileReader.cpp
  PlatformLedger.cpp
  Declaration.cpp)
target_include_directories(SpinelMLIRFreestanding PUBLIC
  ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(SpinelMLIRFreestanding PUBLIC
  SpinelMLIRContract
  LLVMSupport)

# The undefined-symbol gate uses LLVMObject independently of MLIR emission.
add_library(SpinelMLIRFreestandingUndef STATIC UndefGate.cpp)
target_include_directories(SpinelMLIRFreestandingUndef PUBLIC
  ${CMAKE_SOURCE_DIR}/include
  ${CMAKE_BINARY_DIR}/include)
target_link_libraries(SpinelMLIRFreestandingUndef PUBLIC
  LLVMObject
  SpinelMLIRFreestanding)

add_library(SpinelMLIRFreestandingEmit STATIC
  Emit.cpp)
target_include_directories(SpinelMLIRFreestandingEmit PUBLIC
  ${CMAKE_SOURCE_DIR}/include
  # Generated allocation vocabulary: AllocVocabulary.inc.
  ${CMAKE_BINARY_DIR}/include)
# The checked-arithmetic pass lowers trap through target=freestanding-hook. Since the library owns
# the pipeline, it also links that pass.
target_link_libraries(SpinelMLIRFreestandingEmit PUBLIC
  LLVMObject
  SpinelCorePrelude
  SpinelMLIRFreestandingUndef
  SpinelMLIRFreestanding
  SpinelMLIRScalar
  MLIRSpinelToLLVM
  MLIRFuncToLLVM
  MLIRArithToLLVM
  MLIRControlFlowToLLVM
  MLIRReconcileUnrealizedCasts
  MLIRTargetLLVMIRExport
  MLIRLLVMToLLVMIRTranslation
  MLIRBuiltinToLLVMIRTranslation
  MLIRPass
  MLIRFuncDialect
  MLIRArithDialect
  MLIRControlFlowDialect
  MLIRLLVMDialect)

# The machine-code step, for spinel-fs-codegen only: the cflags table, the
# optimisation pipeline and the five backends the profiles name. The emitter
# stops at LLVM IR and runs spinel-fs-codegen, so it links no backend. No MLIR here either.
add_library(SpinelMLIRFreestandingCodegen STATIC Codegen.cpp)
target_include_directories(SpinelMLIRFreestandingCodegen PUBLIC
  ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(SpinelMLIRFreestandingCodegen PUBLIC
  LLVMPasses
  LLVMipo
  LLVMTarget
  LLVMCodeGen
  LLVMMC
  LLVMTargetParser
  LLVMARMCodeGen LLVMARMDesc LLVMARMInfo
  LLVMRISCVCodeGen LLVMRISCVDesc LLVMRISCVInfo
  LLVMWebAssemblyCodeGen LLVMWebAssemblyDesc LLVMWebAssemblyInfo
  LLVMX86CodeGen LLVMX86Desc LLVMX86Info
  LLVMAArch64CodeGen LLVMAArch64Desc LLVMAArch64Info)
