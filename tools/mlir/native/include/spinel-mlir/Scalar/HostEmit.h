// Hosted LLVM IR and object emission.
#ifndef SPINEL_MLIR_SCALAR_HOSTEMIT_H
#define SPINEL_MLIR_SCALAR_HOSTEMIT_H

#include "spinel-mlir/Conversion/SpinelToLLVM/Passes.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/StringRef.h"

#include <string>
#include <vector>

namespace mlir { class PassManager; }

namespace spinel_mlir::scalar {

// The CLI owns subprocess execution, as for freestanding. product-optin.test lane 14 checks
// lib/Frontend contains no spawning code; the library only requests operations.
using RunToolFn = llvm::function_ref<int(
    llvm::StringRef tool, llvm::ArrayRef<llvm::StringRef> argv,
    llvm::StringRef stdoutPath, llvm::StringRef stderrPath)>;

// The CLI owns temporary filenames and directory lifetime.
using TempPathFn = llvm::function_ref<std::string(llvm::StringRef name)>;

// Imported module -> LLVM dialect, defined once for both lanes. hookSymbol
// matters only for FreestandingHook; the pass refuses it on other targets.
// Hosted passes an empty hook. The stage expanding only spinel.checked_*
// Native must print at that same point and run the remaining passes afterward.
void buildCheckedArithStage(mlir::PassManager &pm,
                            mlir::spinel::CheckedArithmeticTarget target,
                            llvm::StringRef hookSymbol);

void buildLoweringPipeline(mlir::PassManager &pm,
                           mlir::spinel::CheckedArithmeticTarget target,
                           llvm::StringRef hookSymbol);

struct HostEmitRequest {
  // Output kinds. .bc maps to Obj just like .o; callers requesting bitcode must
  // also pass --lto.
  enum class Kind { Mlir, Ll, Obj };
  Kind kind = Kind::Mlir;
  // Final output: Mlir prints the module, Ll prints LLVM IR, Obj supplies clang -o.
  std::string outputPath;
  // Read only for Obj. Empty means caller resolution failed and must be reported.
  std::string clangPath;
  bool lto = false;                    ///< `-flto=thin`
  /// Mark every emitted function `sanitize_address` in the LLVM IR.
  ///
  /// `-fsanitize=address` is a FRONTEND flag: on C input clang gives each
  /// function the attribute and the pass instruments it. The input here is
  /// already IR, so the pass runs -- the object gains ASan's module
  /// constructor -- and instruments nothing, because no function carries the
  /// attribute. Measured: the object had `__asan_init` and not one
  /// `__asan_report_load`, so a sanitiser run over it watched only the harness
  /// around it. The caller sets this when it compiles with the sanitiser.
  bool sanitizeAddress = false;
  /// Mark every emitted function `nounwind` in the LLVM IR.
  ///
  /// Set this explicitly so ARM objects do not acquire an unwind dependency
  /// when optimisation is disabled.
  bool noUnwind = false;
  std::vector<std::string> clangArgs;  ///< Contents of -- <clang args>.
  /// When non-empty and `kind` is `Obj`, emit in TWO STEPS and leave the
  /// optimised IR here: clang runs the middle end and writes this file, then a
  /// second clang generates the object from it with the middle end disabled.
  ///
  /// Stack measurement requires the final call graph to
  /// come from "the IR that code generation consumed", and a graph read from
  /// the IR handed to a one-step clang is the graph BEFORE optimisation and
  /// inlining -- which is the wrong graph, because an inlined call has no
  /// frame. Splitting the invocation makes that IR exist.
  ///
  /// MEASURED, 2026-09-20, before this was written: the two steps reproduce
  /// the one-step object BYTE FOR BYTE on `col` (1,824 B), `stepall`
  /// (1,788,296 B) and `renderall` (1,220,168 B). So the saved IR is what
  /// produced the object.

  ///
  /// Empty is the one-step path, unchanged, which is what every other caller
  /// of this function uses.
  std::string optimisedIrPath;
};

// Write module as requested; true on success, otherwise one diagnostic line
// and false. Do not promise atomic artifact creation: clang failures may leave
// partial files; callers must check status. Do not set triple or data layout,
// Both pass
// -Wno-override-module, suppressing that mismatch warning. Freestanding instead
// sets these from its profile because its target differs from the host.
bool emitHostModule(mlir::ModuleOp module, const HostEmitRequest &req,
                    RunToolFn runTool, TempPathFn tempPath,
                    llvm::function_ref<void(llvm::StringRef)> diag);

} // namespace spinel_mlir::scalar

#endif // SPINEL_MLIR_SCALAR_HOSTEMIT_H
