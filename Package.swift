// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Callora",
    platforms: [.macOS(.v14)],
    products: [
        // A droplet is a loadable bundle, so its product is a dynamic library.
        // Do not make it static: the app already carries DroppyKit, and a
        // second copy inside the droplet gives the same type two metadata
        // records, which fails every cast between them.
        .library(name: "Callora", type: .dynamic, targets: ["Callora"])
    ],
    dependencies: [
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", exact: "1.22.0")
    ],
    targets: [
        .target(
            name: "Callora",
            dependencies: [.product(name: "DroppyKit", package: "droppykit")]
        ),
        .testTarget(name: "CalloraTests", dependencies: ["Callora"]),
        .executableTarget(
            name: "CalloraHarness",
            dependencies: [
                "Callora",
                .product(name: "DroppyKitHarness", package: "droppykit")
            ]
        )
    ]
)
