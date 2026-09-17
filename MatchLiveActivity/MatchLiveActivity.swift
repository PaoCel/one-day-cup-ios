import ActivityKit
import SwiftUI
import WidgetKit

struct MatchLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    teamColumn(
                        name: context.attributes.team1Name,
                        logoFile: context.attributes.team1LogoFile,
                        goals: context.state.team1Goals
                    )
                }

                DynamicIslandExpandedRegion(.trailing) {
                    teamColumn(
                        name: context.attributes.team2Name,
                        logoFile: context.attributes.team2LogoFile,
                        goals: context.state.team2Goals
                    )
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.isFinished ? "Fine" : "\(context.state.elapsedMinutes)'")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)

                        if let event = context.state.lastEvent {
                            Text(event)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if let campo = context.attributes.campo {
                        Text("Campo \(campo)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    teamLogoMini(file: context.attributes.team1LogoFile, name: context.attributes.team1Name, size: 18)
                    Text("\(context.state.team1Goals)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.cyan)
                }
            } compactTrailing: {
                HStack(spacing: 3) {
                    Text("\(context.state.team2Goals)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.cyan)
                    teamLogoMini(file: context.attributes.team2LogoFile, name: context.attributes.team2Name, size: 18)
                }
            } minimal: {
                Text("\(context.state.team1Goals)-\(context.state.team2Goals)")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.cyan)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<MatchActivityAttributes>) -> some View {
        VStack(spacing: 8) {
            HStack {
                if context.state.isFinished {
                    Text("TERMINATA")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.orange)
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("LIVE \(context.state.elapsedMinutes)'")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                if let campo = context.attributes.campo {
                    Text("Campo \(campo)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    teamLogo(file: context.attributes.team1LogoFile, name: context.attributes.team1Name, size: 36)
                    Text(context.attributes.team1Name)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    Text("\(context.state.team1Goals)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text("-")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("\(context.state.team2Goals)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                }

                VStack(spacing: 4) {
                    teamLogo(file: context.attributes.team2LogoFile, name: context.attributes.team2Name, size: 36)
                    Text(context.attributes.team2Name)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
            }

            if let event = context.state.lastEvent {
                Text(event)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .activityBackgroundTint(.black.opacity(0.85))
        .activitySystemActionForegroundColor(.white)
    }

    // MARK: - Logo Views

    @ViewBuilder
    private func teamLogo(file: String?, name: String, size: CGFloat) -> some View {
        if let imageData = SharedLogoStorage.loadImage(filename: file),
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            initialsView(name: name, size: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        }
    }

    @ViewBuilder
    private func teamLogoMini(file: String?, name: String, size: CGFloat) -> some View {
        if let imageData = SharedLogoStorage.loadImage(filename: file),
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            initialsView(name: name, size: size)
                .clipShape(Circle())
        }
    }

    private func initialsView(name: String, size: CGFloat) -> some View {
        LinearGradient(
            colors: [.blue.opacity(0.7), .cyan.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: size, height: size)
        .overlay(
            Text(abbreviate(name))
                .font(.system(size: size * 0.38, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        )
    }

    // MARK: - Dynamic Island Helpers

    private func teamColumn(name: String, logoFile: String?, goals: Int) -> some View {
        VStack(spacing: 4) {
            teamLogo(file: logoFile, name: name, size: 28)
            Text("\(goals)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    private func abbreviate(_ name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return words.prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
        }
        return String(name.prefix(3)).uppercased()
    }
}
