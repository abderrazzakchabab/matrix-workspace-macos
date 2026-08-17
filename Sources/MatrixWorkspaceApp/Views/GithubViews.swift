#if canImport(SwiftUI)
import SwiftUI
import MatrixWorkspaceCore

struct GitHubView: View {
    @Environment(AppState.self) private var state
    @State private var workspaceId = ""
    @State private var installationId = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GitHub").font(.title2).bold()

            HStack {
                Picker("Workspace", selection: $workspaceId) {
                    Text("Select a workspace").tag("")
                    ForEach(state.workspaces, id: \.workspaceId) { workspace in
                        Text(workspace.name).tag(workspace.workspaceId)
                    }
                }
                .frame(maxWidth: 260)

                TextField("GitHub App installation ID", text: $installationId)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)

                Button("Load repositories") {
                    Task { await state.loadRepositories(workspaceId: workspaceId, installationId: installationId) }
                }
                .disabled(workspaceId.isEmpty || installationId.isEmpty)
            }

            if let error = state.errorMessage {
                Text(error).foregroundStyle(.red)
            }

            Table(state.repositories) {
                TableColumn("Name") { repo in
                    Text(repo.name)
                }
                TableColumn("Owner") { repo in
                    Text(repo.owner)
                }
                TableColumn("Default branch") { repo in
                    Text(repo.defaultBranch)
                }
                TableColumn("Visibility") { repo in
                    Text(repo.isPrivate ? "private" : "public")
                }
            }
        }
        .padding(24)
        .navigationTitle("GitHub")
    }
}

struct AuditView: View {
    @Environment(AppState.self) private var state
    @State private var workspaceId = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audit trail").font(.title2).bold()

            HStack {
                Picker("Workspace", selection: $workspaceId) {
                    Text("Select a workspace").tag("")
                    ForEach(state.workspaces, id: \.workspaceId) { workspace in
                        Text(workspace.name).tag(workspace.workspaceId)
                    }
                }
                .frame(maxWidth: 260)

                Button("Load audit") {
                    Task { await state.loadAudit(workspaceId: workspaceId) }
                }
                .disabled(workspaceId.isEmpty)
            }

            if let error = state.errorMessage {
                Text(error).foregroundStyle(.red)
            }

            Table(state.auditRecords) {
                TableColumn("Outcome") { record in
                    Text(record.outcome)
                }
                TableColumn("Operation") { record in
                    Text(record.operation ?? "—")
                }
                TableColumn("Repository") { record in
                    Text(record.repository ?? "—")
                }
                TableColumn("Created") { record in
                    Text(record.createdAt)
                }
            }
        }
        .padding(24)
        .navigationTitle("Audit")
    }
}
#endif
