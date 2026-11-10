import SwiftUI
import ActivityKit
import WidgetKit
import AlarmKit

@main
struct RFAlarmWidgetBundle: WidgetBundle {
    var body: some Widget { RFAlarmLiveActivity() }
}
struct RFAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<RFAlarmMetadata>.self) { context in
            HStack {
                Image(systemName: "bell.badge.fill").foregroundStyle(.cyan)
                VStack(alignment: .leading) {
                    Text(context.attributes.metadata?.title ?? "Напоминание").font(.headline)
                    Text("RemindFlow").font(.caption)
                }
            }.padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.metadata?.title ?? "Напоминание")
                }
            } compactLeading: {
                Image(systemName: "bell.fill")
            } compactTrailing: {
                Image(systemName: "clock")
            } minimal: {
                Image(systemName: "bell.fill")
            }
        }
    }
}
