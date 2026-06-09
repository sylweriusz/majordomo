// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Majordomo",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Majordomo", targets: ["Majordomo"]),
        .executable(name: "MajordomoCoreTestRunner", targets: ["MajordomoCoreTestRunner"])
    ],
    targets: [
        .target(name: "MajordomoCore"),
        .executableTarget(
            name: "Majordomo",
            dependencies: ["MajordomoCore"],
            resources: [
                .copy("Resources/majordomo.png"),
                .copy("Resources/ThirdPartyNotices.txt")
            ]
        ),
        .executableTarget(
            name: "MajordomoCoreTestRunner",
            dependencies: ["MajordomoCore"],
            path: "Tests/MajordomoCoreTestRunner"
        )
    ]
)
