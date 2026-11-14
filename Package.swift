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
        .target(name: "MajordomoObjC"),
        .executableTarget(
            name: "Majordomo",
            dependencies: ["MajordomoCore", "MajordomoObjC"],
            resources: [
                .copy("Resources/majordomo.png"),
                .copy("Resources/ThirdPartyNotices.txt")
            ]
        ),
        .executableTarget(
            name: "MajordomoCoreTestRunner",
            dependencies: ["MajordomoCore", "MajordomoObjC"],
            path: "Tests/MajordomoCoreTestRunner"
        )
    ]
)
