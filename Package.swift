// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MatrixWorkspace",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MatrixWorkspaceCore", targets: ["MatrixWorkspaceCore"]),
        .executable(name: "matrix-workspace-macos", targets: ["MatrixWorkspaceApp"])
    ],
    targets: [
        .target(name: "MatrixWorkspaceCore"),
        .testTarget(
            name: "MatrixWorkspaceCoreTests",
            dependencies: ["MatrixWorkspaceCore"]
        ),
        .executableTarget(
            name: "MatrixWorkspaceApp",
            dependencies: ["MatrixWorkspaceCore"]
        )
    ]
)
