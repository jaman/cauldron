#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

struct CauldronLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CauldronActivityAttributes.self) { context in
            LockScreenActivity(state: context.state)
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(context.state.url.flatMap(URL.init(string:)))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityPicture(state: state, compact: false)
                }
                DynamicIslandExpandedRegion(.trailing, priority: 1) {
                    HStack(alignment: .lastTextBaseline) {
                        ActivityInfo(state: state)
                        Spacer()
                        ActivityTimer(state: state)
                    }
                    .tint(colour(state.tint) ?? .accentColor)
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
            } compactLeading: {
                CompactPicture(state: state)
            } compactTrailing: {
                if let ends = state.ends {
                    Text(timerInterval: Date.now...max(ends, .now), countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(colour(state.tint) ?? .accentColor)
                        .frame(width: 40)
                } else if let progress = state.progress {
                    ProgressView(value: progress).progressViewStyle(.circular).frame(width: 18, height: 18)
                } else {
                    Text(state.title).font(.caption2).lineLimit(1)
                }
            } minimal: {
                CompactPicture(state: state)
            }
            .contentMargins(.trailing, 32, for: .expanded)
            .contentMargins([.leading, .top, .bottom], 6, for: .compactLeading)
            .contentMargins(.all, 6, for: .minimal)
            .widgetURL(state.url.flatMap(URL.init(string:)))
        }
    }
}

private func colour(_ name: String?) -> Color? { name.map { Color($0) } }

struct LockScreenActivity: View {
    let state: CauldronActivityAttributes.ContentState
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        HStack(spacing: 12) {
            ActivityPicture(state: state, compact: false)
                .opacity(isLuminanceReduced ? 0.5 : 1)
            ActivityInfo(state: state)
            Spacer()
            ActivityTimer(state: state)
        }
        .tint(.primary)
        .padding([.leading, .top, .bottom])
        .padding(.trailing, state.ends == nil ? 16 : 32)
        .activityBackgroundTint(colour(state.background))
    }
}

struct ActivityPicture: View {
    let state: CauldronActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        if let image = compact ? (state.compactImage ?? state.image) : state.image {
            Image(image).clipShape(ContainerRelativeShape())
        } else {
            Image(systemName: state.icon).font(.title).foregroundStyle(.tint)
        }
    }
}

struct CompactPicture: View {
    let state: CauldronActivityAttributes.ContentState

    var body: some View {
        if state.compactImage ?? state.image != nil {
            ActivityPicture(state: state, compact: true)
                .padding(4)
                .background((colour(state.badge) ?? .accentColor).gradient, in: ContainerRelativeShape())
        } else {
            Image(systemName: state.icon).foregroundStyle(.tint)
        }
    }
}

struct ActivityInfo: View {
    let state: CauldronActivityAttributes.ContentState
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
            Text(state.detail)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .opacity(isLuminanceReduced ? 0.5 : 1)
            if state.ends == nil, let progress = state.progress {
                ProgressView(value: progress)
            }
        }
    }
}

struct ActivityTimer: View {
    let state: CauldronActivityAttributes.ContentState
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if let ends = state.ends {
            VStack(alignment: .trailing) {
                Text(timerInterval: Date.now...max(ends, .now), countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                Text(state.endsLabel ?? "")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .opacity(isLuminanceReduced ? 0.5 : 1)
            }
        }
    }
}
#endif
