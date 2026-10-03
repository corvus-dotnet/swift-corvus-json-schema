# swift-corvus-json-schema

A [Bowtie](https://github.com/bowtie-json-schema/bowtie) test harness for
[CorvusJsonSchema](https://github.com/corvus-dotnet/corvus-json-schema-swift), the Swift package of
[Corvus.JsonSchema](https://github.com/corvus-dotnet/Corvus.JsonSchema): a Swift API over the corvus-json-schema C
library.

Its image is published to `ghcr.io/bowtie-json-schema/swift-corvus-json-schema` and run via
`bowtie run -i swift-corvus-json-schema`.

The harness compiles each case's schema with the case's `registry` as the document resolver and validates each
instance. For `annotations` output it evaluates through a verbose collector and reports each annotation with its
instance location and `#…` keyword location. Requests are read with a small JSON scanner that keeps each value's text
as Bowtie wrote it, so schemas and instances reach the library unchanged.

The package's version is pinned in `Package.swift` and `Package.resolved`, which Dependabot keeps at the latest
release. On Linux the package uses the C library from the release its own `Package.swift` names.
