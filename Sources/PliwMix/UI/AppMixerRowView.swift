import SwiftUI

public struct AppMixerRowView: View {
    public let app: AudioApp
    @ObservedObject public var viewModel: MixerViewModel

    @State private var isRoutingExpanded = false

    public init(app: AudioApp, viewModel: MixerViewModel) {
        self.app = app
        self.viewModel = viewModel
    }

    private var setting: AppAudioSetting {
        viewModel.setting(for: app.id)
    }

    private var meterLevel: Double {
        viewModel.appLevels[app.id] ?? 0.0
    }

    private var hasCustomOutputDevice: Bool {
        setting.outputDeviceUID != nil
    }

    private var isPinned: Bool {
        viewModel.isPinned(app.id)
    }

    private var speakerSymbol: String {
        if setting.isMuted || setting.volume < 0.01 {
            return "speaker.slash.fill"
        }
        if setting.volume < 0.35 {
            return "speaker.wave.1.fill"
        }
        if setting.volume < 0.7 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row Header: App Icon, Name, Live Status, Output Device Button, Reset / Unpin
            HStack(spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "app.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            )
                    }

                    if app.isRunningOutput && !setting.isMuted {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                            )
                            .offset(x: 2, y: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)

                    Text(app.isRunningOutput ? "Playing" : "Idle")
                        .font(.system(size: 10))
                        .foregroundStyle(app.isRunningOutput ? Color.green : Color.secondary)
                }

                Spacer(minLength: 4)

                // Per-App Output Device Picker Toggle
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        isRoutingExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.deviceSymbol(for: setting.outputDeviceUID))
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(compactOutputLabel)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: 94, alignment: .leading)
                        Image(systemName: isRoutingExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .foregroundStyle(hasCustomOutputDevice ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        (hasCustomOutputDevice ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06)),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .help("Select output device for this app")

                if setting.requiresTap {
                    Button {
                        viewModel.resetApp(app)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset to 100% and default output")
                }

                if isPinned {
                    Button {
                        withAnimation(.snappy(duration: 0.16)) {
                            viewModel.unpinApp(app)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove from mixer")
                }
            }

            // Volume Control Row: Mute Button, 0-100% Slider, Percentage
            HStack(spacing: 10) {
                Button {
                    viewModel.toggleMute(for: app)
                } label: {
                    Image(systemName: speakerSymbol)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(setting.isMuted ? Color.red : Color.primary)
                        .frame(width: 26, height: 26)
                        .background(
                            (setting.isMuted ? Color.red.opacity(0.14) : Color.primary.opacity(0.06)),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(setting.isMuted ? "Unmute app" : "Mute app")

                VolumeSliderView(
                    value: setting.volume,
                    maxValue: 1.0,
                    isMuted: setting.isMuted,
                    isEnabled: true,
                    meterLevel: meterLevel
                ) { newVol in
                    viewModel.setVolume(newVol, for: app)
                }

                Text(setting.isMuted ? "Muted" : setting.percentageText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(setting.isMuted ? Color.red : Color.secondary)
                    .frame(width: 40, alignment: .trailing)
                    .onTapGesture(count: 2) {
                        viewModel.setVolume(1.0, for: app)
                    }
                    .help("Double-click to reset to 100%")
            }

            // Expandable Per-App Output Device Selector
            if isRoutingExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Route Audio To")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 2)

                    outputOptionRow(
                        title: viewModel.deviceName(for: nil),
                        symbol: viewModel.defaultOutputDevice?.symbolName ?? "speaker.wave.2",
                        isSelected: setting.outputDeviceUID == nil
                    ) {
                        viewModel.setOutputDevice(nil, for: app)
                        withAnimation(.snappy(duration: 0.16)) {
                            isRoutingExpanded = false
                        }
                    }

                    ForEach(viewModel.outputDevices) { device in
                        outputOptionRow(
                            title: device.name,
                            symbol: device.symbolName,
                            isSelected: setting.outputDeviceUID == device.uid
                        ) {
                            viewModel.setOutputDevice(device.uid, for: app)
                            withAnimation(.snappy(duration: 0.16)) {
                                isRoutingExpanded = false
                            }
                        }
                    }
                }
                .padding(6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .padding(10)
        .background(
            (setting.requiresTap ? Color.accentColor.opacity(0.05) : Color.primary.opacity(0.03)),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    setting.requiresTap ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
    }

    private var compactOutputLabel: String {
        guard let uid = setting.outputDeviceUID else {
            return "Default"
        }
        return viewModel.outputDevices.first(where: { $0.uid == uid })?.name ?? "Unavailable"
    }

    private func outputOptionRow(
        title: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
