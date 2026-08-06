// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "AgenTM5N",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .executable(
      name: "AgenTM5N",
      targets: ["AgenTM5N"]
    )
  ],
  dependencies: [
    .package(
      url: "https://github.com/migueldeicaza/SwiftTerm.git",
      exact: "1.15.0"
    )
  ],
  targets: [
    .systemLibrary(
      name: "CCommonCrypto",
      path: "Sources/CCommonCrypto"
    ),
    .executableTarget(
      name: "AgenTM5N",
      dependencies: [
        "CCommonCrypto",
        .product(name: "SwiftTerm", package: "SwiftTerm"),
      ],
      path: "Sources/AgenTM5N",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("CoreML"),
        .linkedFramework("CryptoKit"),
        .linkedFramework("FoundationModels"),
        .linkedFramework("OSLog"),
        .linkedFramework("Security"),
      ]
    ),
  ]
)
