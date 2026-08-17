#if canImport(SwiftUI)
import Foundation
import Observation
import MatrixWorkspaceCore

/// Observable app-wide state, bridging the cross-platform `MatrixWorkspaceCore`
/// client to the SwiftUI layer.
@MainActor
@Observable
final class AppState {
    var baseURLString: String
    var session: MatrixSessionResponse?
    var workspaces: [WorkspaceSelection]
    var rooms: [RoomSummary]
    var runEvents: [RunEvent]
    var repositories: [GithubRepositorySummary]
    var auditRecords: [AuditRecordItem]
    var activeRun: RunResponse?
    var errorMessage: String?
    var isLoading: Bool = false

    @ObservationIgnored private let sessionStore: SessionStore = KeychainSessionStore()
    @ObservationIgnored private var client: ControlPlaneClient?
    @ObservationIgnored private var stream: RunEventStream?
    @ObservationIgnored private var streamConnection: RunEventConnection?

    private static let baseURLDefaultsKey = "controlPlaneBaseURL"
    private static let workspacesDefaultsKey = "createdWorkspaces"

    init() {
        let defaults = UserDefaults.standard
        self.baseURLString = defaults.string(forKey: Self.baseURLDefaultsKey) ?? ""

        if let data = defaults.data(forKey: Self.workspacesDefaultsKey),
           let decoded = try? JSONDecoder().decode([WorkspaceSelection].self, from: data) {
            self.workspaces = decoded
        } else {
            self.workspaces = []
        }

        self.session = nil
        self.rooms = []
        self.runEvents = []
        self.repositories = []
        self.auditRecords = []
        self.activeRun = nil
    }

    var isAuthenticated: Bool { session != nil && client != nil }

    // MARK: Auth

    func login(homeserverUrl: String, accessToken: String) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let baseURL = URL(string: trimmed), trimmed.hasPrefix("http") else {
                errorMessage = "Enter a valid control plane URL (https://…)"
                return
            }

            let client = ControlPlaneClient(
                baseURL: baseURL,
                sessionStore: sessionStore,
                onUnauthorized: { Task { @MainActor [weak self] in self?.handleUnauthorized() } }
            )
            let response = try await client.createMatrixSession(
                homeserverUrl: homeserverUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                accessToken: accessToken
            )

            self.client = client
            self.stream = RunEventStream(baseURL: baseURL, sessionStore: sessionStore)
            self.session = response
            UserDefaults.standard.set(baseURLString, forKey: Self.baseURLDefaultsKey)
            await loadRooms()
        } catch {
            errorMessage = (error as? ControlPlaneError)?.message ?? error.localizedDescription
        }
    }

    func logout() {
        Task { try? await sessionStore.clear() }
        handleUnauthorized()
    }

    private func handleUnauthorized() {
        session = nil
        client = nil
        stream = nil
        streamConnection?.cancel()
        streamConnection = nil
        activeRun = nil
    }

    // MARK: Rooms & workspaces

    func loadRooms() async {
        guard let client else { return }
        do {
            rooms = try await client.getRooms()
        } catch {
            errorMessage = (error as? ControlPlaneError)?.message ?? error.localizedDescription
        }
    }

    func createWorkspace(name: String) async {
        guard let client else { return }
        errorMessage = nil
        do {
            let workspace = try await client.createWorkspace(name: name)
            workspaces.append(workspace)
            persistWorkspaces()
        } catch {
            errorMessage = (error as? ControlPlaneError)?.message ?? error.localizedDescription
        }
    }

    func bindRoom(_ room: RoomSummary, to workspace: WorkspaceSelection) async {
        guard let client else { return }
        do {
            _ = try await client.bindRoom(roomId: room.roomId, workspaceId: workspace.workspaceId)
            await loadRooms()
        } catch {
            errorMessage = (error as? ControlPlaneError)?.message ?? error.localizedDescription
        }
    }

    private func persistWorkspaces() {
        if let data = try? JSONEncoder().encode(workspaces) {
            UserDefaults.standard.set(data, forKey: Self.workspacesDefaultsKey)
        }
    }

    // MARK: Runs

    func launchRun(workspaceId: String, prompt: String, mode: RunMode, specialistIds: [String]) async {
        guard let client else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let request = RunRequest(prompt: prompt, mode: mode, specialistIds: specialistIds)
            let run = try await client.launchRun(
                workspaceId: workspaceId,
                request: request,
                idempotencyKey: UUID().uuidString
            )
            activeRun = run
            runEvents = []
            startStream(runId: run.runId)
        } catch {
            errorMessage = (error as? ControlPlaneError)?.message ?? error.localizedDescription
        }
    }

    func cancelActiveRun() {
        guard let client, let runId = activeRun?.runId else { return }
        Task {
            do { _ = try await client.cancelRun(runId: runId) }
            catch { errorMessage = (error as? ControlPlaneError)?.message ?? error.localizedDescription }
        }
    }

    private func startStream(runId: String) {
        guard let stream else { return }
        streamConnection?.cancel()
        let connection = stream.connect(runId: runId, from: 0)
        streamConnection = connection

        Task { @MainActor [weak self] in
            do {
                for try await event in connection.stream {
                    self?.runEvents.append(event)
                }
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func stopStream() {
        streamConnection?.cancel()
        streamConnection = nil
    }

    // MARK: GitHub read

    func loadRepositories(workspaceId: String, installationId: String) async {
        guard let client else { return }
        errorMessage = nil
        do {
            let page = try await client.listGithubRepositories(
                workspaceId: workspaceId,
                installationId: installationId
            )
            repositories = page.items
        } catch {
            errorMessage = (error as? ControlPlaneError)?.message ?? error.localizedDescription
        }
    }

    // MARK: Audit

    func loadAudit(workspaceId: String) async {
        guard let client else { return }
        errorMessage = nil
        do {
            let page = try await client.listAuditRecords(workspaceId: workspaceId)
            auditRecords = page.items
        } catch {
            errorMessage = (error as? ControlPlaneError)?.message ?? error.localizedDescription
        }
    }
}
#endif
