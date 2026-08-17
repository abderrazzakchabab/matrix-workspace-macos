#if canImport(SwiftUI)
import SwiftUI
import MatrixWorkspaceCore

struct WorkspacesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                WorkspacesSection()
                Divider()
                RunComposerSection()
                Divider()
                RunTimelineSection()
            }
            .padding(24)
        }
        .navigationTitle("Workspaces")
    }
}

// MARK: - Workspaces

struct WorkspacesSection: View {
    @Environment(AppState.self) private var state
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workspaces").font(.title2).bold()

            if state.workspaces.isEmpty {
                Text("No workspaces yet. Create one to launch runs.")
                    .foregroundStyle(.secondary)
            }

            ForEach(state.workspaces, id: \.workspaceId) { workspace in
                HStack {
                    VStack(alignment: .leading) {
                        Text(workspace.name).font(.headline)
                        Text(workspace.workspaceId).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(workspace.status).foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                TextField("Workspace name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                Button("Create") {
                    Task { await state.createWorkspace(name: newName) }
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: 520)
        }
    }
}

// MARK: - Run composer

struct RunComposerSection: View {
    @Environment(AppState.self) private var state
    @State private var workspaceId = ""
    @State private var prompt = ""
    @State private var mode: RunMode = .parallel
    @State private var specialists = "reader"

    private var specialistIds: [String] {
        specialists
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Launch run").font(.title2).bold()

            Picker("Workspace", selection: $workspaceId) {
                Text("Select a workspace").tag("")
                ForEach(state.workspaces, id: \.workspaceId) { workspace in
                    Text(workspace.name).tag(workspace.workspaceId)
                }
            }
            .frame(maxWidth: 360)

            TextEditor(text: $prompt)
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack {
                Picker("Mode", selection: $mode) {
                    Text("Parallel").tag(RunMode.parallel)
                    Text("Sequential").tag(RunMode.sequential)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                TextField("Specialists (comma-separated)", text: $specialists)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = state.errorMessage {
                Text(error).foregroundStyle(.red)
            }

            Button {
                Task {
                    await state.launchRun(
                        workspaceId: workspaceId,
                        prompt: prompt,
                        mode: mode,
                        specialistIds: specialistIds
                    )
                }
            } label: {
                if state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Launch")
                }
            }
            .disabled(
                workspaceId.isEmpty
                || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || specialistIds.isEmpty
            )
        }
    }
}

// MARK: - Run timeline

struct RunTimelineSection: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Run timeline").font(.title2).bold()
                Spacer()
                if let run = state.activeRun {
                    Text(run.status.rawValue)
                        .foregroundStyle(.secondary)
                    if !state.runEvents.isEmpty {
                        Button("Stop") { state.stopStream() }
                    }
                }
            }

            if let run = state.activeRun {
                Text(run.runId).font(.caption).foregroundStyle(.secondary)
            }

            if state.runEvents.isEmpty {
                Text(state.activeRun == nil
                     ? "No active run."
                     : "Waiting for events…")
                    .foregroundStyle(.secondary)
            }

            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(state.runEvents, id: \.id) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Text("#\(event.sequence)").monospacedDigit().foregroundStyle(.secondary)
                        Text(event.type).font(.callout).bold()
                        Spacer()
                        Text(event.occurredAt).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
#endif
