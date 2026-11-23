// Classify undefined symbols in a completed freestanding object with LLVMObject.
// The classification runs after profile, declaration and body checks.
#ifndef SPINEL_MLIR_FREESTANDING_UNDEFGATE_H
#define SPINEL_MLIR_FREESTANDING_UNDEFGATE_H

#include "spinel-mlir/Freestanding/Profile.h"

#include "llvm/ADT/StringRef.h"

#include <string>
#include <vector>

namespace spinel_mlir::freestanding {

// One TSV row.
struct UndefRow {
  std::string verdict; ///< ALLOW | DENY
  std::string object;  ///< Object basename; omit paths for environment independence.
  std::string symbol;
  std::string reason;
};

// Policy values only. Only the reader can construct FreestandingProfile, but
// spinel-fs-check --undef must also work without a profile or with CLI overrides,
// The gate reads only these five fields; use
// this struct without weakening the profile's construction invariant.
struct UndefPolicy {
  std::string triple;
  std::string libc = "none";
  std::string libm = "none";
  std::string compilerRt = "allow";
  std::vector<std::string> allowed;
};

// Copy policy from FreestandingProfile without changing existing callers.
UndefPolicy undefPolicyOf(const FreestandingProfile &profile);

// Policy overload; runUndefGate(objPath, profile, ...) is a thin wrapper.
bool runUndefGate(llvm::StringRef objPath, const UndefPolicy &policy,
                  std::vector<UndefRow> &rows, std::string *infraError);

// Classify objPath undefined symbols by profile policy; append rows sorted by
// symbol. Return true iff no row is DENY. Unreadable
// or unrecognized object format is infrastructure, not invalid input: set
// infraError and return false; the caller reports Infrastructure, not Rejection.
bool runUndefGate(llvm::StringRef objPath, const FreestandingProfile &profile,
                  std::vector<UndefRow> &rows, std::string *infraError);

// Serialize rows to TSV: header, rows and a final newline.
std::string formatUndefTsv(llvm::ArrayRef<UndefRow> rows);

} // namespace spinel_mlir::freestanding

#endif // SPINEL_MLIR_FREESTANDING_UNDEFGATE_H
