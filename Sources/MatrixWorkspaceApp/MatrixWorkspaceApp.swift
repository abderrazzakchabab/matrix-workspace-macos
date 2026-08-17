#if canImport(SwiftUI)
import SwiftUI

@main
struct MatrixWorkspaceApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .frame(minWidth: 900, minHeight: 620)
        }
    }
}
#else
import Foundation

@main
enum MatrixWorkspaceCLIStub {
    static func main() {
        print("matrix-workspace-macos: the GUI requires macOS 14+ (SwiftUI). The cross-platform client is available via `import MatrixWorkspaceCore`.")
    }
}
#endif
