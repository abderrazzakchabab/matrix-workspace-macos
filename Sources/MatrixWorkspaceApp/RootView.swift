#if canImport(SwiftUI)
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.isAuthenticated {
            MainView()
        } else {
            LoginView()
        }
    }
}

// MARK: - Login

struct LoginView: View {
    @Environment(AppState.self) private var state
    @State private var homeserverUrl = ""
    @State private var accessToken = ""

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 24) {
            Text("Matrix Agent Workspace")
                .font(.largeTitle)
                .bold()

            Form {
                TextField("Control plane URL (https://…)", text: $state.baseURLString)
                TextField("Homeserver URL (https://matrix…)", text: $homeserverUrl)
                SecureField("Matrix access token", text: $accessToken)
            }
            .formStyle(.grouped)
            .frame(maxWidth: 520)

            if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Button {
                Task { await state.login(homeserverUrl: homeserverUrl, accessToken: accessToken) }
            } label: {
                if state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Sign in")
                        .frame(minWidth: 140)
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(state.isLoading || accessToken.isEmpty)
        }
        .padding(44)
    }
}

// MARK: - Main split view

struct MainView: View {
    @Environment(AppState.self) private var state
    @State private var selection: SidebarItem? = .workspaces

    enum SidebarItem: String, CaseIterable, Identifiable {
        case workspaces
        case github
        case audit

        var id: String { rawValue }

        var title: String {
            switch self {
            case .workspaces: "Workspaces"
            case .github: "GitHub"
            case .audit: "Audit"
            }
        }

        var icon: String {
            switch self {
            case .workspaces: "square.stack.3d.up"
            case .github: "chevron.left.forwardslash.chevron.right"
            case .audit: "list.bullet.rectangle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .navigationTitle("Matrix Workspace")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        state.logout()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        } detail: {
            switch selection {
            case .workspaces: WorkspacesView()
            case .github: GitHubView()
            case .audit: AuditView()
            case nil: ContentUnavailableView("Select a section", systemImage: "sidebar.left")
            }
        }
    }
}
#endif
