import SwiftUI

public struct MasterVolumeSection: View {
    @ObservedObject public var viewModel: MixerViewModel
    @State private var isDeviceListExpanded = false

    public init(viewModel: MixerViewModel) {
        self.viewModel = viewModel
    }

    private var masterPercentText: String {
        "\(Int((viewModel.masterVolume * 100).rounded()))%"
    }

    private var masterSpeakerSymbol: String {
        if viewModel.isMasterMuted || viewModel.masterVolume < 0.01 {
            return "speaker.slash.fill"
        }
        if viewModel.masterVolume < 0.35 {
            return "speaker.wave.1.fill"
        }
        if viewModel.masterVolume < 0.7 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label {
                    Text("Master Volume")
                        .font(.system(size: 12, weight: .semibold))
                } icon: {
                    Image(systemName: viewModel.defaultOutputDevice?.symbolName ?? "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        isDeviceListExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.defaultOutputDevice?.name ?? "No Device")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 145, alignment: .trailing)

                        Image(systemName: isDeviceListExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Select macOS default output device")
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.toggleMasterMute()
                } label: {
                    Image(systemName: masterSpeakerSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(viewModel.isMasterMuted ? Color.red : Color.primary)
                        .frame(width: 26, height: 26)
                        .background(
                            (viewModel.isMasterMuted ? Color.red.opacity(0.14) : Color.primary.opacity(0.06)),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(viewModel.isMasterMuted ? "Unmute master volume" : "Mute master volume")

                VolumeSliderView(
                    value: viewModel.masterVolume,
                    maxValue: 1.0,
                    isMuted: viewModel.isMasterMuted,
                    isEnabled: viewModel.masterVolumeSupported
                ) { newVol in
                    viewModel.setMasterVolume(newVol)
                }

                Text(viewModel.isMasterMuted ? "Muted" : masterPercentText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(viewModel.isMasterMuted ? Color.red : Color.secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            if isDeviceListExpanded && !viewModel.outputDevices.isEmpty {
                VStack(spacing: 4) {
                    ForEach(viewModel.outputDevices) { device in
                        Button {
                            viewModel.setSystemDefaultOutput(device)
                            withAnimation(.snappy(duration: 0.16)) {
                                isDeviceListExpanded = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: device.symbolName)
                                    .font(.system(size: 11))
                                    .frame(width: 16)
                                    .foregroundStyle(device.isDefault ? Color.accentColor : Color.secondary)

                                Text(device.name)
                                    .font(.system(size: 11.5, weight: device.isDefault ? .semibold : .regular))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if device.isDefault {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                device.isDefault ? Color.accentColor.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}
