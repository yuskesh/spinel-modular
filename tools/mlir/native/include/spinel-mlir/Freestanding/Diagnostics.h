// Freestanding refusal stages and categories are closed enums.

#ifndef SPINEL_MLIR_FREESTANDING_DIAGNOSTICS_H
#define SPINEL_MLIR_FREESTANDING_DIAGNOSTICS_H

#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/StringRef.h"

#include <string>

namespace spinel_mlir::freestanding {

// P0 resolves a profile through the platform ledger, distinct from P1 checking
// the YAML already read. G checks generated objects' undefined-symbol policy,
// distinct from P1/P2 input declarations and B/C body-subset validation.
enum class Stage { P0, P1, P2, D1, D2, B, C, G };

// The initial ten contract categories. Keep BadBoundaryType and BadExternType
// separate: boundary declarations admit nine scalar types, externs five.
// For example :i8 is valid in freestanding_def but not platform.externs; merging
// the categories could conceal a refusal on the side that should accept it.
enum class Category {
  UnknownProfileKey,
  AbiWidthMismatch,
  BadBoundaryType,
  BadExternType,
  BufferDirectionViolation,
  BufferLenGovernance,
  BufferElemMismatch,
  ExternSignatureMismatch,
  UndeclaredPlatformExtern,
  UndefAllowlistViolation,
  BadExportSymbol,
  // A helper is reachable from roots with incompatible overflow policies.
  // Report a mismatch between the declaration and the method body.
  OverflowPolicyConflict,
  // Platform-first resolution failed: unknown platform, wrong architecture, invalid supplies or
  // missing base. Stage P0.
  ProfileError,
  // A top-level reopening of a builtin class the declared methods' operators
  // belong to. Reopening can replace an operator that lowering assumes is built in.
  ReopenedBuiltin,
  // A required file that does not parse on its own: a definition, block or
  // `end` crosses into the file that requires it. Rejecting this keeps source
  // locations and declaration boundaries local to each file.
  SplitAcrossFiles,
  /// the CORE checkers' spellings.
  ConflictingIntrinsic,
  UnsupportedIntrinsicCall,
};

llvm::StringRef stageName(Stage stage);
llvm::StringRef categoryName(Category category);

// One refusal. subject names an extern, declaration or profile key, but may be
// empty for an unknown extern key.
struct Rejection {
  Stage stage;
  Category category;
  std::string subject;
  int argPos = 0;
  std::string detail;
};

using FsDiagnosticFn = llvm::function_ref<void(const Rejection &)>;

// One line: spinel-fs:<stage>: <category>: <subject|-> [arg=<n> ]<detail>.
// The A/B runner reads this spelling verbatim.
std::string formatRejection(const Rejection &rejection);

// Format user-facing freestanding errors.
std::string formatRejectionMlirgen(const Rejection &rejection);

} // namespace spinel_mlir::freestanding

#endif // SPINEL_MLIR_FREESTANDING_DIAGNOSTICS_H
