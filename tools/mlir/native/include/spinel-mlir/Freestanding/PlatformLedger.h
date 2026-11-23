// Expand platform-first profiles using the board ledger.
#ifndef SPINEL_MLIR_FREESTANDING_PLATFORMLEDGER_H
#define SPINEL_MLIR_FREESTANDING_PLATFORMLEDGER_H

#include "spinel-mlir/Freestanding/Diagnostics.h"
#include "spinel-mlir/Freestanding/Profile.h"

#include "llvm/ADT/StringRef.h"

#include <memory>
#include <string>

namespace spinel_mlir::freestanding {

// Sole resolution entry: expand platform-first profiles via the ledger; legacy
// profiles use readFreestandingProfile with identical spelling/order. Invalid
// input returns nullptr with P0/P1/P2 Rejection through diag. Unreadable ledger
// or base, or malformed ledger structure, sets infraError and returns nullptr
// without calling diag. Legacy profiles never read ledgerPath.
std::unique_ptr<FreestandingProfile>
resolveFreestandingProfile(llvm::StringRef profilePath, llvm::StringRef yamlText,
                           llvm::StringRef ledgerPath, FsDiagnosticFn diag,
                           std::string *infraError);

// Walk upward from the executable's real path to the first
// tools/platform/menus.yaml; return empty if absent. build/build-asan22/
// build-stage-d are in-tree, so use spinel-fs-check's defaultTypedumpPath approach.
std::string locateDefaultLedger(const char *argv0);

} // namespace spinel_mlir::freestanding

#endif // SPINEL_MLIR_FREESTANDING_PLATFORMLEDGER_H
