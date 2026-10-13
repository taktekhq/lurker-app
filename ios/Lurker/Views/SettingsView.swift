import LurkerKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = ""
    @State private var token = ""
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("https://your-worker.workers.dev", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Token", text: $token)
                }

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        if isTesting {
                            ProgressView()
                        } else {
                            Text("Test")
                        }
                    }
                    .disabled(isTesting)

                    if let testResult {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(testResult == "OK" ? .green : .red)
                    }
                } header: {
                    Text("Check your connection")
                } footer: {
                    Text("Calls GET /v1/shares with the server and token above, without saving them yet.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                serverURL = appState.settings.serverURL()?.absoluteString ?? ""
                token = appState.settings.token() ?? ""
            }
        }
    }

    private var trimmedURL: String {
        serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        appState.settings.set(serverURL: URL(string: trimmedURL), token: trimmedToken)
        dismiss()
        Task { await appState.refresh() }
    }

    private func test() async {
        guard let url = URL(string: trimmedURL), !trimmedToken.isEmpty else {
            testResult = "Add a server URL and a token first."
            return
        }

        isTesting = true
        defer { isTesting = false }

        let client = Client(base: url, token: trimmedToken)
        do {
            _ = try await client.shares()
            testResult = "OK"
        } catch let error as APIError {
            testResult = error.message
        } catch {
            testResult = error.localizedDescription
        }
    }
}
