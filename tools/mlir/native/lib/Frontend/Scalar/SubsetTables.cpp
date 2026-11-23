//===- SubsetTables.cpp - freestanding subset: the inherited refusals -----===//
//
// Hand-maintained. fsInheritedNodes() lists the Prism node kinds the
// freestanding subset refuses although no input reaches them
// (tests/subset/coverage.tsv marks each unverified-inherited, with the
// reason). They stay in force, named, not removed. Every other refusal, and
// every call name, is in lib/Core/SubsetRefusals.cpp;
// fsSubsetCheck (FreestandingSubset.cpp) reads that table first, then this one.
//
// tests/subset-tables/check.rb pins the key sets and a digest of the reasons
// of both files in tests/subset-tables/pin.tsv: change the pin in the same
// commit.
//
//===----------------------------------------------------------------------===//

#include "FreestandingSubset.h"

namespace spinel_mlir::scalar {
const std::map<std::string, std::string> &fsInheritedNodes() {
  static const std::map<std::string, std::string> t = {
      {"ClassNode",
       "a `class` definition"},
      {"ModuleNode",
       "a `module` definition"},
      {"IndexNode",
       "an index expression (`a[i]`) -- indexable objects are heap objects"},
      {"ConstantWriteNode",
       "a constant assignment"},
      {"RescueNode",
       "a `rescue`"},
      {"EnsureNode",
       "an `ensure`"},
  };
  return t;
}

} // namespace spinel_mlir::scalar
