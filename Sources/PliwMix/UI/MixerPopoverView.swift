import SwiftUI

public struct MixerPopoverView: View {
    @ObservedObject public var viewModel: MixerViewModel
    @ObservedObject public var launchAtLogin: LaunchAtLoginService
    public let onQuit: () -> Void

    @State private var isAddAppPickerOpen = false
    @State private var showOtherProcessesInPicker = false

    public init(viewModel: MixerViewModel, onQuit: @escaping () -> Void) {
        self.viewModel = viewModel
        self.launchAtLogin = viewModel.launchAtLogin
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 14)
                .padding(.top, 13)
                .padding(.bottom, 10)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    MasterVolumeSection(viewModel: viewModel)

                    if viewModel.needsAudioCapturePermission {
                        permissionBanner
                    } else if let error = viewModel.lastError {
                        errorBanner(error)
                    }

                    appsHeaderRow

                    if isAddAppPickerOpen {
                        addAppPickerCard
                    }

                    if viewModel.visibleApps.isEmpty {
                        emptyAppsCard
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.visibleApps) { app in
                                AppMixerRowView(app: app, viewModel: viewModel)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 440)

            Divider()

            footerBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 376)
        .background(.ultraThinMaterial)
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.cyan.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Pliw Mix")
                    .font(.system(size: 14, weight: .bold))

                Text(
                    viewModel.activeTapCount > 0
                        ? "Controlling \(viewModel.activeTapCount) \(viewModel.activeTapCount == 1 ? "app" : "apps")"
                        : "Per-App Audio Mixer"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.hasAnyCustomSetting {
                Button {
                    viewModel.resetAllApps()
                } label: {
                    Text("Reset All")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Reset all apps to 100% volume and default output")
            }

            Button {
                viewModel.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Refresh apps and audio devices")
        }
    }

    private var appsHeaderRow: some View {
        HStack {
            Text("Apps (\(viewModel.visibleApps.count))")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isAddAppPickerOpen.toggle()
                    if !isAddAppPickerOpen {
                        showOtherProcessesInPicker = false
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isAddAppPickerOpen ? "xmark" : "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(isAddAppPickerOpen ? "Done" : "Add App")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(isAddAppPickerOpen ? Color.secondary : Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    (isAddAppPickerOpen ? Color.primary.opacity(0.07) : Color.accentColor.opacity(0.12)),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .help("Manually add an idle app or hidden audio process")
        }
        .padding(.top, 2)
    }

    private var addAppPickerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.addableMainApps.isEmpty && viewModel.addableOtherProcesses.isEmpty {
                Text("All active audio apps are already listed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                if !viewModel.addableMainApps.isEmpty {
                    Text("Available Apps")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(viewModel.addableMainApps) { app in
                        addAppOptionRow(app: app)
                    }
                }

                if !viewModel.addableOtherProcesses.isEmpty {
                    if !viewModel.addableMainApps.isEmpty {
                        Divider()
                            .padding(.vertical, 2)
                    }

                    Button {
                        withAnimation(.snappy(duration: 0.16)) {
                            showOtherProcessesInPicker.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showOtherProcessesInPicker ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                            Text("Other Processes (\(viewModel.addableOtherProcesses.count))")
                                .font(.system(size: 10.5, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showOtherProcessesInPicker {
                        ForEach(viewModel.addableOtherProcesses) { proc in
                            addAppOptionRow(app: proc)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
    }

    private func addAppOptionRow(app: AudioApp) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.16)) {
                viewModel.pinApp(app)
            }
        } label: {
            HStack(spacing: 8) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.secondary)
                }

                Text(app.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyAppsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("No Apps Playing Audio")
                .font(.system(size: 12.5, weight: .semibold))

            Text("Play audio in Chrome, Brave, Safari, or a game and it will appear here — or click + Add App above.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.orange)
                Text("System Audio Permission Required")
                    .font(.system(size: 12, weight: .semibold))
            }

            Text("Go to System Settings → Privacy & Security → Screen & System Audio Recording, then enable Pliw Mix under System Audio Recording Only.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Open Settings") {
                    viewModel.openSystemAudioPermissionSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Retry") {
                    viewModel.retryPermissions()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer()
            Button("Retry") {
                viewModel.retryPermissions()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(9)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            Toggle(
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            ) {
                Text("Launch at Login")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Spacer()

            Button(action: onQuit) {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Quit Pliw Mix and restore all app audio")
        }
    }
}
