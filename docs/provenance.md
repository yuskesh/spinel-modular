# Provenance

What in this repository comes from somewhere else, and under which terms.
Everything not named here was written for this project.

## Spinel

`vendor/spinel` is a git submodule of https://github.com/yuskesh/spinel, a
fork of [Spinel](https://github.com/matz/spinel) (MIT License, Copyright (c)
2024- Yukihiro Matsumoto), pinned at
`4e0a59bd999e614bd8b2ece72ec2b8d0cbbc5522`. The fork carries a stack of
patches above upstream: the linkage seam for a selected root, the input
ledger, the fact reader's outputs and fixes.

`tools/contract/spinel_contract.h` reproduces two Spinel functions; Spinel's
licence text is beside it.

## Notices

[NOTICE](../NOTICE) and [THIRD_PARTY.md](../THIRD_PARTY.md) list the licences.
