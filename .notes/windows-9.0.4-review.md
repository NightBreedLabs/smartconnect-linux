# Windows 9.0.4.003.000 artifact review

## What

Added a [Windows artifact review and Linux comparison](../docs/research/windows-9.0.4.003.000.md)
against Linux commit `8f2b190`. No implementation or feature-verification labels changed.

## How

REA inspected PE imports, resources, certificates and Go build metadata. Focused JavaScript
analysis covered three shipped feature bundles and 18 provenance-mapped entry-bundle declarations.
Broad entry-bundle analysis hit its source deadline; coverage remains explicitly incomplete.
Supplemental read-only parsing inventoried Go function names and selected native entry points.
Existing Wine logs were summarized without copying nonce/signature fields.

The report compares these observations with the Rust daemon, helpers and frontends. It keeps
plugin capabilities, internal UI command numbers and phone handshake versions distinct, and
records stale image-clipboard and FUSE-cache documentation instead of assuming TODOs describe
the current implementation.

## Why

The installed Windows app reveals useful component boundaries even when its UI fails under Wine.
Artifact and source evidence can guide Linux work without copying vendor implementation or
claiming untested compatibility. A single Ghidra pass reconstructed the Windows WebSocket handler,
but incomplete Go type recovery leaves paired-key possession checks unresolved; the report does
not turn those branches into a guessed authentication fix. Raw artifacts, logs and paths remain outside
Git; hashes, REA Evidence IDs, uncertainty and a local evidence-location convention remain in
the authored report.
