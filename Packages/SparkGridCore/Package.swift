// swift-tools-version: 6.2
import PackageDescription

let engineSettings: [SwiftSetting] = [
  .swiftLanguageMode(.v5),
  .defaultIsolation(MainActor.self),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableExperimentalFeature("ApproachableConcurrency"),
]

let testSettings: [SwiftSetting] = [
  .swiftLanguageMode(.v5),
  .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
  name: "SparkGridCore",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "SparkGridCore", targets: ["SparkGridCore"]),
    .executable(name: "spark-grid-cli", targets: ["spark-grid-cli"]),
  ],
  dependencies: [
    .package(url: "https://github.com/CoreOffice/CoreXLSX.git", .upToNextMinor(from: "0.14.2")),
    .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMinor(from: "0.9.20")),
  ],
  targets: [
    .target(name: "GridCore", swiftSettings: engineSettings),
    .target(
      name: "NumberFormat",
      dependencies: ["GridCore"],
      swiftSettings: engineSettings
    ),
    .target(
      name: "Formula",
      dependencies: ["GridCore"],
      swiftSettings: engineSettings
    ),
    .target(
      name: "Functions",
      dependencies: ["Formula"],
      swiftSettings: engineSettings
    ),
    .target(
      name: "Model",
      dependencies: ["GridCore", "NumberFormat", "Formula"],
      swiftSettings: engineSettings
    ),
    .target(
      name: "Calc",
      dependencies: ["GridCore", "NumberFormat", "Formula", "Functions", "Model"],
      swiftSettings: engineSettings
    ),
    .target(
      name: "FileFormats",
      dependencies: [
        "GridCore",
        "NumberFormat",
        "Formula",
        "Model",
        .product(name: "CoreXLSX", package: "CoreXLSX"),
        .product(name: "ZIPFoundation", package: "ZIPFoundation"),
      ],
      swiftSettings: engineSettings
    ),
    .target(
      name: "Engine",
      dependencies: [
        "GridCore",
        "NumberFormat",
        "Formula",
        "Functions",
        "Model",
        "Calc",
        "FileFormats",
      ],
      swiftSettings: engineSettings
    ),
    .target(
      name: "Rendering",
      dependencies: ["GridCore", "NumberFormat", "Formula", "Model", "Calc"],
      swiftSettings: engineSettings
    ),
    .target(
      name: "SparkGridCore",
      dependencies: [
        "GridCore",
        "NumberFormat",
        "Formula",
        "Functions",
        "Model",
        "Calc",
        "FileFormats",
        "Engine",
        "Rendering",
      ],
      swiftSettings: engineSettings
    ),
    .executableTarget(
      name: "spark-grid-cli",
      dependencies: [
        "GridCore",
        "NumberFormat",
        "Formula",
        "Model",
        "Calc",
        "FileFormats",
        "Engine",
      ],
      swiftSettings: engineSettings
    ),
    .testTarget(
      name: "SparkGridCoreTests",
      dependencies: [
        "GridCore",
        "NumberFormat",
        "Formula",
        "Functions",
        "Calc",
        "Model",
        "FileFormats",
        "Engine",
        "Rendering",
      ],
      swiftSettings: testSettings
    ),
    .testTarget(
      name: "AnswerCheck",
      dependencies: [
        "GridCore",
        "Formula",
        "Calc",
        "Model",
        "FileFormats",
        "Engine",
      ],
      swiftSettings: testSettings
    ),
    .testTarget(
      name: "CommandFuzz",
      dependencies: [
        "GridCore",
        "NumberFormat",
        "Formula",
        "Calc",
        "Model",
        "FileFormats",
        "Engine",
      ],
      swiftSettings: testSettings
    ),
  ]
)
