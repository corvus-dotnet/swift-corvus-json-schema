# The C library for the target platform, fetched on the build platform: the release its Package.swift names (on Linux
# the Swift package uses the C library installed on the system). This stage runs natively even when the image is
# built for another architecture under emulation, where tar cannot unpack.
FROM --platform=$BUILDPLATFORM swift:6.4 AS capi
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /harness
COPY Package.swift Package.resolved ./
RUN swift package resolve \
 && capi=$(sed -n 's|.*/releases/download/capi-v\([0-9.]*\)/.*|\1|p' .build/checkouts/corvus-json-schema-swift/Package.swift) \
 && arch=$(case "$TARGETARCH" in arm64) echo aarch64 ;; *) echo x86_64 ;; esac) \
 && name="corvus-json-schema-$capi-$arch-unknown-linux-gnu" \
 && curl -sSfL "https://github.com/corvus-dotnet/Corvus.JsonSchema/releases/download/capi-v$capi/$name.tar.gz" | tar -xz -C /opt \
 && mv "/opt/$name" /opt/corvus-json-schema

FROM swift:6.4 AS build
RUN apt-get update && apt-get install -y --no-install-recommends jq pkg-config \
 && rm -rf /var/lib/apt/lists/*
COPY --from=capi /opt/corvus-json-schema /opt/corvus-json-schema
ENV PKG_CONFIG_PATH=/opt/corvus-json-schema/lib/pkgconfig LD_LIBRARY_PATH=/opt/corvus-json-schema/lib
WORKDIR /harness
COPY Package.swift Package.resolved ./
COPY Sources ./Sources
RUN version=$(jq -r '.pins[] | select(.identity == "corvus-json-schema-swift") | .state.version' Package.resolved) \
 && swift_version=$(swift --version 2>/dev/null | sed -n 's/.*Swift version \([^ ]*\).*/\1/p' | head -n 1) \
 && printf 'let packageVersion = "%s"\nlet swiftVersion = "%s"\n' "$version" "$swift_version" > Sources/BowtieCorvusJsonSchema/Version.swift \
 && swift build -c release

FROM swift:6.4-slim
COPY --from=build /opt/corvus-json-schema/lib/libcorvus_json_schema.so /usr/local/lib/
RUN ldconfig
COPY --from=build /harness/.build/release/BowtieCorvusJsonSchema /usr/local/bin/
CMD ["BowtieCorvusJsonSchema"]
