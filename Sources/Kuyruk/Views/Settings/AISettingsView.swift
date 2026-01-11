import SwiftUI

/// Settings view for AI-powered features using GitHub Models.
struct AISettingsView: View {
    @Environment(GitHubModelsService.self) private var modelsService
    @Environment(AuthService.self) private var authService

    @AppStorage("aiSummariesEnabled") private var summariesEnabled: Bool = true

    var body: some View {
        Form {
            self.accountSection
            self.aiSummariesSection
            self.modelPickerSection
            self.usageSection
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await self.modelsService.fetchAvailableModels()
        }
    }

    // MARK: - Account Section

    @ViewBuilder
    private var accountSection: some View {
        Section("GitHub Account") {
            if self.authService.state.isAuthenticated {
                if let user = authService.currentUser {
                    HStack(spacing: 12) {
                        AvatarView(url: user.avatarUrl, size: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name ?? user.login)
                                .font(.headline)

                            Text("Connected for AI features")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Label("Authenticated", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                HStack {
                    Label("Sign in to use AI features", systemImage: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Sign In") {
                        Task {
                            await self.authService.login()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - AI Summaries Section

    @ViewBuilder
    private var aiSummariesSection: some View {
        Section {
            Toggle("Enable TL;DR Summaries", isOn: self.$summariesEnabled)

            if self.summariesEnabled {
                Text("AI will generate concise summaries of your notifications on demand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("AI Summaries", systemImage: "sparkles")
        }
    }

    // MARK: - Model Picker Section

    @ViewBuilder
    private var modelPickerSection: some View {
        Section("Model") {
            if self.modelsService.isLoadingModels {
                HStack {
                    ProgressView()
                        .controlSize(.small)

                    Text("Loading models...")
                        .foregroundStyle(.secondary)
                }
            } else if let error = modelsService.modelsError {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Failed to load models", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Retry") {
                        Task {
                            await self.modelsService.fetchAvailableModels()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if self.modelsService.availableModels.isEmpty {
                Text("No models available")
                    .foregroundStyle(.secondary)
            } else {
                self.modelPicker
            }
        }
        .disabled(!self.summariesEnabled || !self.authService.state.isAuthenticated)
    }

    @ViewBuilder
    private var modelPicker: some View {
        @Bindable var service = self.modelsService

        Picker("Select Model", selection: self.modelIdBinding) {
            Text("Select a model").tag(nil as String?)

            ForEach(self.modelsService.availableModels) { model in
                HStack {
                    Text(model.displayName)

                    if model.isLowTier {
                        Text("(Low tier)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(model.id as String?)
            }
        }
        .pickerStyle(.menu)

        if let selectedId = modelsService.selectedModelId,
           let model = modelsService.availableModels.first(where: { $0.id == selectedId }) {
            if let summary = model.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Binding for the selected model ID.
    private var modelIdBinding: Binding<String?> {
        Binding(
            get: { self.modelsService.selectedModelId },
            set: { self.modelsService.selectedModelId = $0 })
    }

    // MARK: - Usage Section

    @ViewBuilder
    private var usageSection: some View {
        Section("Usage") {
            if let remaining = modelsService.rateLimitRemaining {
                HStack {
                    Label {
                        Text("\(remaining) requests remaining")
                    } icon: {
                        Image(systemName: self.rateLimitIcon(for: remaining))
                            .foregroundStyle(self.rateLimitColor(for: remaining))
                    }

                    Spacer()

                    if self.modelsService.isRateLimited {
                        Text("Rate limited")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.red.opacity(0.1), in: Capsule())
                    }
                }

                if let reset = modelsService.rateLimitReset {
                    Text("Resets at \(reset.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Rate limit information will appear after first use")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func rateLimitIcon(for remaining: Int) -> String {
        switch remaining {
        case 0:
            "exclamationmark.triangle.fill"
        case 1...5:
            "chart.bar.fill"
        default:
            "chart.bar"
        }
    }

    private func rateLimitColor(for remaining: Int) -> Color {
        switch remaining {
        case 0:
            .red
        case 1...5:
            .orange
        default:
            .secondary
        }
    }
}

#Preview {
    Text("AISettingsView Preview - requires GitHubModelsService and AuthService environments")
        .frame(width: 500, height: 400)
}
