````markdown
# ADR 0004: Swift Package Manager as Primary Build System

## Status

Accepted

## Context

When starting a new macOS application project, we need to choose a build system. The options are:

1. **Xcode Project (.xcodeproj)** — Traditional Apple project format
2. **Swift Package Manager (SPM)** — Swift's native package manager
3. **Hybrid approach** — SPM for build, Xcode for app-specific features

### Considerations

- **Build simplicity**: Ability to build from command line without Xcode
- **Manifest format**: Human-readable and version-control friendly
- **Tool integration**: CI/CD, linting, formatting
- **macOS app features**: Code signing, entitlements, notarization
- **Multi-target support**: Main app, CLI tools, tests

## Decision

We will use **Swift Package Manager** as the primary build system with Xcode as a complementary tool for app-specific features.

### Package Structure

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kuyruk",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Kuyruk", targets: ["Kuyruk"]),
        .executable(name: "api-explorer", targets: ["APIExplorer"])
    ],
    targets: [
        .executableTarget(
            name: "Kuyruk",
            resources: [.process("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(name: "APIExplorer"),
        .testTarget(name: "KuyrukTests", dependencies: ["Kuyruk"])
    ]
)
```

### Build Commands

- **Development**: `swift build`
- **Release**: `swift build -c release`
- **Tests**: `swift test`
- **CLI Tool**: `swift run api-explorer`

### Xcode Integration

When Xcode-specific features are needed:

```bash
# Open Package.swift directly in Xcode
open Package.swift

# Or generate Xcode project (not recommended)
swift package generate-xcodeproj
```

Xcode is still used for:
- App bundle configuration
- Code signing and entitlements
- Notarization
- UI tests (which require app context)
- Asset catalogs and app icons

## Consequences

### Positive

1. **Command-line builds**: CI/CD can build with `swift build` without Xcode
2. **Readable manifest**: `Package.swift` is Swift code, easy to review and version
3. **Modern tooling**: Native support in Swift 6.0 and Xcode 16+
4. **Multi-target clarity**: Clear separation of app, CLI tool, and tests
5. **Dependency management**: If we add dependencies later, SPM handles them natively

### Negative

1. **App bundle complexity**: Creating a full .app bundle requires additional scripting or Xcode
2. **Resource handling**: SPM resource processing is less flexible than Xcode asset catalogs
3. **Code signing**: Must use Xcode or `codesign` commands for production builds

### Mitigations

- Use Xcode for release builds and signing (open `Package.swift` in Xcode)
- Keep `Resources/` folder for SPM-compatible assets
- Document the hybrid workflow in AGENTS.md

## Alternatives Considered

### Pure Xcode Project

**Rejected because:**
- `.xcodeproj` files are not human-readable
- Merge conflicts are common and difficult to resolve
- Requires Xcode for all builds

### Hybrid with xcworkspace

**Rejected because:**
- Adds complexity without significant benefit
- SPM + Xcode opening `Package.swift` achieves the same result

## References

- [Swift Package Manager Documentation](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/)
- [PackageDescription API](https://docs.swift.org/swiftpm/documentation/packagedescription)
- [Creating a Swift Package](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/creatingswiftpackage)

````