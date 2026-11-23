// Freestanding refusal-category spellings.
#include <cstdlib>
#include "spinel-mlir/Freestanding/Diagnostics.h"

#include "llvm/Support/raw_ostream.h"

namespace spinel_mlir::freestanding {

llvm::StringRef stageName(Stage stage) {
  // Closed switch: adding a stage exposes this missing branch.
  switch (stage) {
  case Stage::P0: return "P0";
  case Stage::P1: return "P1";
  case Stage::P2: return "P2";
  case Stage::D1: return "D1";
  case Stage::D2: return "D2";
  case Stage::B:  return "B";
  case Stage::C:  return "C";
  case Stage::G:  return "G";
  }
  return "?";
}

llvm::StringRef categoryName(Category category) {
  switch (category) {
  case Category::UnknownProfileKey:        return "unknown-profile-key";
  case Category::AbiWidthMismatch:         return "abi-width-mismatch";
  case Category::BadBoundaryType:          return "bad-boundary-type";
  case Category::BadExternType:            return "bad-extern-type";
  case Category::BufferDirectionViolation: return "buffer-direction-violation";
  case Category::BufferLenGovernance:      return "buffer-len-governance";
  case Category::BufferElemMismatch:       return "buffer-elem-mismatch";
  case Category::ExternSignatureMismatch:  return "extern-signature-mismatch";
  case Category::UndeclaredPlatformExtern: return "undeclared-platform-extern";
  case Category::UndefAllowlistViolation:  return "undef-allowlist-violation";
  case Category::BadExportSymbol:          return "bad-export-symbol";
  case Category::OverflowPolicyConflict:    return "overflow-policy-conflict";
  case Category::ProfileError:             return "profile-error";
  case Category::ReopenedBuiltin:          return "reopened-builtin";
  case Category::SplitAcrossFiles:         return "split-across-files";
  case Category::ConflictingIntrinsic:     return "conflicting-intrinsic";
  case Category::UnsupportedIntrinsicCall: return "unsupported-intrinsic-call";
  }
  return "?";
}

std::string formatRejection(const Rejection &rejection) {
  std::string out;
  llvm::raw_string_ostream os(out);
  // Keep the profile-validation prefix: the platform gate matches REJECT
  // profile-error. Omit the subject. Keep
  // P0/ProfileError internally, changing only output.
  if (rejection.category == Category::ProfileError) {
    os << "spinel-mlirgen: REJECT profile-error: " << rejection.detail;
    return os.str();
  }
  os << "spinel-fs:" << stageName(rejection.stage) << ": "
     << categoryName(rejection.category) << ": "
     << (rejection.subject.empty() ? "-" : rejection.subject) << ": ";
  if (rejection.argPos > 0)
    os << "arg=" << rejection.argPos << " ";
  os << rejection.detail;
  return os.str();
}

// Include the structured stage and category only when requested.
static bool wantDiagClass() {
  const char *v = ::getenv("SPINEL_FS_DIAG_CLASS");
  return v && llvm::StringRef(v) == "1";
}

std::string formatRejectionMlirgen(const Rejection &rejection) {
  std::string out;
  llvm::raw_string_ostream os(out);
  // Profile-validation failures use formatRejection spelling.
  if (rejection.category == Category::ProfileError) {
    os << "spinel-mlirgen: REJECT profile-error: " << rejection.detail;
  } else if (rejection.stage == Stage::P0 || rejection.stage == Stage::P1 ||
             rejection.stage == Stage::P2) {
    // Profile-stage failures omit the unsupported category prefix.
    // Only ProfileError retains the REJECT profile-error category.
    // for the platform gate.
    os << "spinel-mlirgen: " << rejection.detail;
  } else {
    os << "spinel-mlirgen: unsupported: " << rejection.detail;
  }
  if (wantDiagClass())
    os << "\nspinel-fs:" << stageName(rejection.stage) << ": "
       << categoryName(rejection.category) << ": "
       << (rejection.subject.empty() ? "-" : rejection.subject);
  return os.str();
}

} // namespace spinel_mlir::freestanding
