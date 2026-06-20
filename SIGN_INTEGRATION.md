# ScaleCloudSign — Integration Reference

> Last updated: reflects full file-by-file diff of every ScaleCloudSign source against its SideStore/AltSign counterpart (`/home/cvt/sidestore/Dependencies/AltSign/`). All functional differences are verified against git history.

## What is ScaleCloudSign?

ScaleCloudSign is a fork of [AltSign](https://github.com/rileytestut/AltSign) — the ObjC/Swift library that handles low-level Apple developer API communication and on-device code signing. It is consumed by **ScaleCloudRenew** (the signing operations framework) via `import ScaleCloudSign`.

The fork's changes fall into three categories:
1. **Module rename**: everything `AltSign` → `ScaleCloudSign` (product name, umbrella header, framework name, error domain string, SPM targets, internal imports).
2. **Proxy integration**: `ALTAppleAPI`'s `NSURLSession` is wired through the ScaleCloudKit Tailscale proxy so all Apple API calls share the same VPN tunnel as the rest of the app.
3. **Build system cleanup**: `Package.swift` restructured to eliminate `unsafeFlags`, explicit OpenSSL header search paths added, `CoreCrypto` Swift wrapper target removed and its source file moved, SPM target names updated.

---

## Repository Structure

```
ScaleCloudSign/
├── Package.swift                   # SPM package definition (4 targets → 1 framework product)
├── ScaleCloudSign.xcconfig         # Xcode build settings (was AltSign.xcconfig)
├── ScaleCloudSign/                 # All ObjC/Swift source (was AltSign/)
│   ├── Apple API/                  # ALTAppleAPI ObjC client + session
│   ├── Capabilities/               # ALTCapabilities entitlement helpers
│   ├── Categories/                 # NSError+ALTErrors, NSFileManager+Zip, NSCharacterSet+ASCII
│   ├── Model/                      # ALTApplication + Apple API model objects
│   ├── Signing/                    # ALTSigner (resign IPA via ldid)
│   ├── Sources/                    # Swift: ALTAppleAPI+Authentication, GSAContext,
│   │                               #        Data+Encryption, CoreCryptoMacros (new)
│   ├── include/                    # Public headers + umbrella (ScaleCloudSign.h)
│   │   └── ScaleCloudSign/         # Per-header copies for framework import path
│   └── ldid/                       # alt_ldid.cpp / alt_ldid.hpp wrapper
├── Dependencies/
│   ├── OpenSSL.xcframework         # Multi-platform OpenSSL (ios-arm64, simulator, macOS, etc.)
│   ├── corecrypto/                 # Apple corecrypto headers + ccsrp.m (+ ccsrp.m.disabled)
│   ├── ldid/                       # Full ldid source tree including libplist
│   └── minizip/                    # minizip C sources
├── prebuilt/
│   └── ScaleCloudSign.framework/   # Last known-good prebuilt binary (arm64 iOS)
└── .github/workflows/
    └── create-release.yml          # GitHub Actions workflow that builds the prebuilt
```

### SPM Targets

| Target | Language | Role |
|--------|----------|------|
| `ScaleCloudSign` | Swift | Public Swift extensions: `ALTAppleAPI+Authentication`, `GSAContext`, `Data+Encryption`, `CoreCryptoMacros` |
| `CScaleCloudSign` | ObjC/ObjC++ | All ObjC sources: `ALTAppleAPI`, `ALTSigner`, all model files, categories |
| `CCoreCrypto` | C | Apple corecrypto headers + `ccsrp.m` |
| `ldid` + `ldid-core` | C++ | Code signing: `alt_ldid.cpp` wrapper + full `ldid` + `libplist` C sources |

The single framework **product** is named `ScaleCloudSign` (dynamic); a `ScaleCloudSign-Static` variant is also declared.

---

## Complete Diff vs SideStore Reference

Reference path: `/home/cvt/sidestore/Dependencies/AltSign/AltSign/`

### Category 1 — Cosmetic Rename Only (file comment line 3)

Every source file has its `//  AltSign` file-comment changed to `//  ScaleCloudSign`. No logic changed. Affected files (all `.h`, `.m`, `.mm`, `.swift` under the source tree):

- All files in `Apple API/`, `Capabilities/`, `Categories/`, `Model/`, `Model/Apple API/`, `Signing/`, `Sources/`

These are pure cosmetic changes from commit `8016191` (`rename AltSign > ScaleCloudSign`).

---

### Category 2 — Module/Import Renames (functional identity changes)

These changes are all from commit `8016191` unless noted.

#### `include/ScaleCloudSign.h` (was `include/AltSign.h`)

The umbrella header was renamed and all framework import paths updated:

```objc
// AltSign (reference)
#import <AltSign/ALTAppleAPI.h>
#import <AltSign/ALTSigner.h>
// ... all <AltSign/ALT*.h>

// ScaleCloudSign (ours)
#import <ScaleCloudSign/ALTAppleAPI.h>
#import <ScaleCloudSign/ALTSigner.h>
// ... all <ScaleCloudSign/ALT*.h>
```

The `include/ScaleCloudSign/` subdirectory (containing per-header copies) replaced `include/AltSign/`. This is required so that `#import <ScaleCloudSign/ALTFoo.h>` resolves correctly when the framework is imported.

#### `Apple API/ALTAppleAPI_Private.h`

```objc
// reference
#import <AltSign/ALTAppleAPI.h>
// ours
#import <ScaleCloudSign/ALTAppleAPI.h>
```

**Note**: commit `ff19013` fixed a double-rename artifact here. The initial rename commit `8016191` had produced `<ScaleCloudSignoudSign/...>` (the string `AltSign` inside `ScaleCloudSign` was itself replaced again). `ff19013` corrected those three occurrences in `ALTAppleAPI_Private.h`, `NSError+ALTErrors.h`, and `ALTModel+Internal.h`.

#### `Model/Apple API/ALTModel+Internal.h`

Eight framework imports changed:
```objc
// reference
#import <AltSign/ALTAccount.h>
#import <AltSign/ALTTeam.h>
// ... (8 total)

// ours
#import <ScaleCloudSign/ALTAccount.h>
#import <ScaleCloudSign/ALTTeam.h>
// ... (8 total)
```

#### `Categories/NSError+ALTErrors.h` and `.m`

Error domain constant renamed:
```objc
// reference
extern NSErrorDomain const AltSignErrorDomain;
typedef NS_ERROR_ENUM(AltSignErrorDomain, ALTError) { ... }
NSErrorDomain const AltSignErrorDomain = @"AltSign.Error";
[NSError setUserInfoValueProviderForDomain:AltSignErrorDomain ...];

// ours
extern NSErrorDomain const ScaleCloudSignErrorDomain;
typedef NS_ERROR_ENUM(ScaleCloudSignErrorDomain, ALTError) { ... }
NSErrorDomain const ScaleCloudSignErrorDomain = @"ScaleCloudSign.Error";
[NSError setUserInfoValueProviderForDomain:ScaleCloudSignErrorDomain ...];
```

**Impact**: Any code that matches on error domain string `"AltSign.Error"` will not match errors from ScaleCloudSign. ScaleCloudRenew's `NSError+ALTServerError.m` uses `@import ScaleCloudSign` and the `ALTError` enum values (not the domain string) so this is handled correctly there.

#### `Categories/NSFileManager+Zip.m` and `Signing/ALTSigner.mm`

All `[NSError errorWithDomain:AltSignErrorDomain ...]` calls updated to `ScaleCloudSignErrorDomain`. Affected error codes: `ALTErrorMissingAppBundle` (Zip.m, ALTSigner.mm), `ALTErrorInvalidApp` (ALTSigner.mm ×2), `ALTErrorMissingProvisioningProfile` (ALTSigner.mm), `ALTErrorUnknown` (ALTSigner.mm).

#### `Model/Apple API/ALTCertificateRequest.m`

CSR subject fields updated:
```objc
// reference
const char *organization = "AltSign";
const char *commonName   = "AltSign";

// ours
const char *organization = "ScaleCloudSign";
const char *commonName   = "ScaleCloudSign";
```

**Impact**: Certificate Signing Requests generated by this code will have `O=ScaleCloudSign, CN=ScaleCloudSign` instead of `O=AltSign, CN=AltSign`. This affects the CSR sent to Apple when requesting a new development certificate. Apple ignores these fields for developer cert issuance, so there is no functional impact on signing.

#### `Sources/ALTAppleAPI+Authentication.swift`

ObjC module import renamed:
```swift
// reference
@_exported import CAltSign
import CAltSign.Private

// ours
@_exported import CScaleCloudSign
import CScaleCloudSign.Private
```

The `@_exported` means consumers of `ScaleCloudSign` automatically get `CScaleCloudSign` re-exported into their namespace.

#### `Sources/Data+Encryption.swift` and `Sources/GSAContext.swift`

CoreCrypto module import renamed:
```swift
// reference
import CoreCrypto

// ours
import CCoreCrypto
```

This matches the SPM target rename in `Package.swift` (see below). The `CoreCrypto` Swift wrapper target was removed; its source file `CoreCryptoMacros.swift` was moved from `Dependencies/corecrypto/Sources/` into `ScaleCloudSign/Sources/` and now imports `CCoreCrypto` directly.

---

### Category 3 — New Functionality: Proxy Integration

#### `Apple API/ALTAppleAPI.m` (commits `7c4c31d` → `137c81b`)

This is the only **behavioural** change in the library. `ALTAppleAPI`'s internal `NSURLSession` is now routed through the ScaleCloudKit Tailscale proxy.

**Reference (`AltSign`):**
```objc
_session = [NSURLSession sessionWithConfiguration:
    [NSURLSessionConfiguration ephemeralSessionConfiguration]];
```

**Ours (`ScaleCloudSign`):**
```objc
// Import ScaleCloudKit for shared proxy lifecycle
#import <ScaleCloudKit/ScaleCloudKit-Swift.h>

// Configure URLSession with Tailscale proxy (shared with ScaleCloudKit)
// SCKSession is a Swift struct and is not visible to ObjC; the same static methods
// are forwarded through the ObjC-visible ScaleCloudKit class instead.
NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
config.connectionProxyDictionary = [ScaleCloudKit applyProxySettings];

_session = [NSURLSession sessionWithConfiguration:config];
[ScaleCloudKit registerSession:_session];
```

**Why two commits**: `7c4c31d` initially called `[SCKSession applyProxySettings]` and `[SCKSession registerSession:]` directly. However `SCKSession` is a Swift `struct` and cannot be exposed to Objective-C. Commit `137c81b` fixed this by calling through the `ScaleCloudKit` ObjC-visible class, which has `@objc public static` forwarder methods (`+applyProxySettings`, `+registerSession:`) that delegate to the same underlying `SCKSession` static methods.

**Effect**: All Apple developer API calls (`/services/v1/...`) go through the same Tailscale VPN tunnel that ScaleCloudKit manages. This ensures consistent network routing when the app is running with a VPN profile active.

**Also changed in `.m`**: The two framework imports at the top were changed from angle-bracket framework form to relative form:
```objc
// reference
#import <AltSign/NSError+ALTErrors.h>
#import <AltSign/NSCharacterSet+ASCII.h>

// ours
#import "NSError+ALTErrors.h"
#import "NSCharacterSet+ASCII.h"
```
This was necessary because `ALTAppleAPI.m` is compiled as part of `CScaleCloudSign`, a target where the public headers subdirectory is `ScaleCloudSign/include/ScaleCloudSign/`, not `AltSign/`. Relative imports avoid the path resolution issue.

---

### Category 4 — Build System Changes (`Package.swift`)

All changes are in commit `8016191` (rename) plus the series of CI-fixing commits before it.

#### Products renamed

```swift
// reference
.library(name: "AltSign-Dynamic", type: .dynamic,
    targets: ["AltSign", "CAltSign", "CoreCrypto", "CCoreCrypto", "ldid", "ldid-core", "OpenSSL"])
.library(name: "AltSign-Static",  type: .static,
    targets: ["AltSign", "CAltSign", "CoreCrypto", "CCoreCrypto", "ldid", "ldid-core"])

// ours
.library(name: "ScaleCloudSign",        type: .dynamic,
    targets: ["ScaleCloudSign", "CScaleCloudSign", "CCoreCrypto", "ldid", "ldid-core"])
.library(name: "ScaleCloudSign-Static", type: .static,
    targets: ["ScaleCloudSign", "CScaleCloudSign", "CCoreCrypto", "ldid", "ldid-core"])
```

Notable: `OpenSSL` is **removed** from the product targets (it was causing build issues with Xcode signature verification); `CoreCrypto` Swift wrapper target is **removed** entirely (see below).

#### `CoreCrypto` Swift target removed; `CoreCryptoMacros.swift` relocated

The reference has a dedicated `CoreCrypto` SPM target:
```swift
// reference
.target(name: "CoreCrypto", dependencies: ["CCoreCrypto"],
    path: "Dependencies/corecrypto/Sources",
    exclude: ["ccsrp.m"],
    sources: ["CoreCryptoMacros.swift"])
```

This was removed. The file `CoreCryptoMacros.swift` is now at `ScaleCloudSign/Sources/CoreCryptoMacros.swift` and is compiled as part of the `ScaleCloudSign` Swift target directly. The content is identical to the reference version. The motivation (from CI history) was eliminating `swiftinterface` cross-module verification errors where `CoreCrypto` references in the emitted `.swiftinterface` couldn't be resolved by downstream consumers of the prebuilt framework.

#### `CAltSign` → `CScaleCloudSign`; explicit OpenSSL header paths added

```swift
// reference
.target(name: "CAltSign", dependencies: ["CoreCrypto", "CCoreCrypto", "ldid-core"],
    path: "AltSign",
    exclude: [...],
    publicHeadersPath: "AltSign/include",
    cSettings: [
        .headerSearchPath("AltSign/include"),
        .headerSearchPath("AltSign/include/AltSign"),
        ...
        .unsafeFlags(["-w"])  // suppress warnings
    ])

// ours
.target(name: "CScaleCloudSign", dependencies: ["CCoreCrypto", "OpenSSL", "ldid-core"],
    path: "ScaleCloudSign",
    exclude: [...],
    publicHeadersPath: "ScaleCloudSign/include",
    cSettings: [
        .headerSearchPath("ScaleCloudSign/include"),
        .headerSearchPath("ScaleCloudSign/include/ScaleCloudSign"),
        ...
        .headerSearchPath("Dependencies/OpenSSL.xcframework/ios-arm64/OpenSSL.framework/Headers"),
        // no unsafeFlags
    ])
```

Key differences:
- `unsafeFlags(["-w"])` replaced with explicit `.headerSearchPath` entries — `unsafeFlags` blocks scheme generation in Xcode and was causing CI failures.
- Explicit `OpenSSL.xcframework/ios-arm64/.../Headers` search path added so `openssl/` headers resolve without relying on inherited paths.
- `OpenSSL` added as an explicit dependency of `CScaleCloudSign`.
- `ldid` and `ldid-core` targets similarly had `unsafeFlags` replaced with explicit OpenSSL and libplist header search paths.

#### `AltSign` Swift target → `ScaleCloudSign`

```swift
// reference
.target(name: "AltSign", dependencies: ["CAltSign"],
    path: "AltSign/Sources")

// ours
.target(name: "ScaleCloudSign", dependencies: ["CScaleCloudSign", "CCoreCrypto"],
    path: "ScaleCloudSign/Sources")
```

`CCoreCrypto` added as explicit dependency (needed since `CoreCryptoMacros.swift` now imports it directly).

---

### New File: `ScaleCloudSign/Sources/CoreCryptoMacros.swift`

Moved from `Dependencies/corecrypto/Sources/CoreCryptoMacros.swift` (reference location). Content unchanged: Swift reimplementations of C macros from Apple's corecrypto headers (`ccdigest_ctx_size`, `ccdigest_di_size`, `ccsrp_gpbuf_size`, `ccsrp_dibuf_size`, `ccsrp_sizeof_srp`, `cchmac_ctx_size`, `cchmac_di_size`). These macros cannot be imported into Swift directly, so they are reimplemented as functions. Now `import CCoreCrypto` (was `import CoreCrypto`).

---

### Files Identical to Reference

| File | Notes |
|------|-------|
| All `Model/Apple API/*.h/.m` | Only cosmetic comment line differs |
| `Signing/ALTSigner.h` | Only cosmetic comment line differs |
| `Signing/ALTSigner.mm` | Comment + `ScaleCloudSignErrorDomain` replacements only |
| `Capabilities/ALTCapabilities.*` | Comment only |
| `Model/ALTApplication.*` | Comment only |
| `Apple API/ALTAppleAPISession.*` | Comment only |
| `Sources/Data+Encryption.swift` | Comment + `CCoreCrypto` import only |
| `Sources/GSAContext.swift` | Comment + `CCoreCrypto` import only |
| `Dependencies/corecrypto/` | Unchanged (original files still present) |
| `Dependencies/ldid/` | Unchanged |
| `Dependencies/minizip/` | Unchanged |

---

## Build Workflow (`create-release.yml`)

Trigger: push to a `v*` tag, or `workflow_dispatch`.

Steps:
1. **Checkout** ScaleCloudSign with `submodules: recursive` (pulls `ldid` nested submodule).
2. **Checkout** `poofygummy/scalecloud-ios` (sparse, `ScaleCloudKit/prebuilt` only) — needed so `FRAMEWORK_SEARCH_PATHS` can find `ScaleCloudKit.framework` for the `#import <ScaleCloudKit/ScaleCloudKit-Swift.h>` in `ALTAppleAPI.m`.
3. **Strip invalid OpenSSL code signatures**: `find Dependencies/OpenSSL.xcframework -name '_CodeSignature' -type d -exec rm -rf {} +` — the bundled OpenSSL xcframework has a signature that Xcode rejects; stripping it lets the build proceed.
4. **`xcodebuild build`** with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`, `-no-verify-emitted-module-interface`, and `FRAMEWORK_SEARCH_PATHS` pointing to `Dependencies/` and `ScaleCloudKit/prebuilt`.
5. **Manually assemble `Modules/`** — SPM does not embed `.swiftmodule` files inside the built `.framework`; they are found in `DerivedData/Build/Intermediates.noindex` and copied in.
6. **Copy public headers** from `ScaleCloudSign/include/ScaleCloudSign/*.h` into `prebuilt/ScaleCloudSign.framework/Headers/`.
7. **Write `module.modulemap`** manually into `Modules/`.
8. **Upload** as a GitHub Actions artifact (name `ScaleCloudSign-prebuilt`, 7-day retention). Not a GitHub Release.

**If building locally**, steps 3 and 4–7 must be done manually. The `ScaleCloudKit.framework` must be available at `../ScaleCloudKit/prebuilt/` (sibling checkout) or the framework search path must be overridden.

---

## Prebuilt Framework (`prebuilt/ScaleCloudSign.framework/`)

- Binary: `ScaleCloudSign` (arm64 iOS dynamic framework)
- `Headers/`: all public ObjC headers (`ALT*.h`, `NSError+ALTErrors.h`, etc.) + umbrella `ScaleCloudSign.h`
- `Modules/module.modulemap`: `framework module ScaleCloudSign { umbrella header "ScaleCloudSign.h"; export *; module * { export * } }`
- `Modules/ScaleCloudSign.swiftmodule/`: Swift interface files (`arm64-apple-ios.swiftinterface`, `.abi.json`, `.swiftdoc`, `.swiftmodule`, `.private.swiftinterface`)

**Consumers of the prebuilt** (i.e. ScaleCloudRenew when not building ScaleCloudSign from source) must have `CCoreCrypto` and `CScaleCloudSign` available separately, or satisfy those imports via `FRAMEWORK_SEARCH_PATHS`. In practice ScaleCloudRenew's `project.yml` points `FRAMEWORK_SEARCH_PATHS` at the sibling submodule source so these resolve.

---

## Commit History Reference

| Commit | What it did |
|--------|-------------|
| `63a7c4c` | Original `Initial Commit` by Riley Testut (AltSign upstream baseline) |
| `b490973` | Last upstream AltSign commit (`Adds ALTSigner to resign apps`) — baseline for all diffs above |
| `7c4c31d` | **Add ScaleCloudKit prebuilt to CI; wire `ALTAppleAPI` session through `SCKSession` proxy** (initial, used wrong ObjC-visible class) |
| `137c81b` | **Fix proxy bridging**: `SCKSession` (Swift struct) not ObjC-visible → switch to `[ScaleCloudKit applyProxySettings]` / `[ScaleCloudKit registerSession:]` forwarders |
| `8016191` | **Rename AltSign → ScaleCloudSign**: product name, module name, umbrella header, all public header paths, SPM target names, xcconfig, `Package.swift` restructure, error domain string, CSR subject |
| `ff19013` | **Fix double-rename artifact**: `8016191`'s sed-style rename had replaced `AltSign` inside `ScaleCloudSign` producing `ScaleCloudSignoudSign` in three private headers (`ALTAppleAPI_Private.h`, `NSError+ALTErrors.h`, `ALTModel+Internal.h`) |
| `211cade` | Track previously untracked files: `AGENTS.md`, disabled corecrypto source, `Package.swift` backups, prebuilt xcframework |
| `bc23927` | Rebuilt prebuilt (`ScaleCloudSign.framework`) |
| `6c66b67` | Attempted to bundle `CCoreCrypto` and `CScaleCloudSign` module descriptors into the prebuilt framework's `Modules/` so downstream consumers wouldn't need them separately |
| `1d271fd` | **Revert** `6c66b67` — current HEAD. The bundled module descriptors caused build errors; reverted to separate targets |

Earlier commits (`803b9f9` through `211cade`) are a series of CI fixes iterating on the `create-release.yml` workflow: switching from `xcodebuild archive` to `xcodebuild build`, manually extracting `.swiftmodule` from `DerivedData/Intermediates`, fixing `unsafeFlags` blocking scheme generation, adding explicit OpenSSL header search paths, stripping invalid code signatures, and switching from xcframework zip artifacts to plain framework folder artifacts.

---

## How This Differs from SideStore's AltSign

| | SideStore / AltSign | ScaleCloudSign |
|---|---|---|
| Module / framework name | `AltSign` | `ScaleCloudSign` |
| ObjC module (SPM target) | `CAltSign` | `CScaleCloudSign` |
| CoreCrypto Swift wrapper | `CoreCrypto` (separate SPM target) | Removed; `CoreCryptoMacros.swift` compiled into `ScaleCloudSign` target |
| Error domain string | `"AltSign.Error"` | `"ScaleCloudSign.Error"` |
| CSR subject O/CN | `"AltSign"` | `"ScaleCloudSign"` |
| Apple API `NSURLSession` | Plain ephemeral session | Routed through ScaleCloudKit Tailscale proxy |
| `unsafeFlags` in `Package.swift` | Present (suppresses warnings) | Replaced with explicit header search paths |
| Umbrella header | `include/AltSign.h` | `include/ScaleCloudSign.h` |
| Public headers import path | `<AltSign/ALT*.h>` | `<ScaleCloudSign/ALT*.h>` |
