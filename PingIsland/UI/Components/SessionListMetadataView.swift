import SwiftUI

struct SessionListMetadataView: View {
    let record: RecentSessionRecord
    let title: SessionListTitle
    @ObservedObject private var privacy = ScreenPrivacyStore.shared

    var body: some View {
        if !privacy.effectiveMode.showsDetails {
            Text(appLocalized: "screen-privacy.details-hidden").padding(16).frame(width: 280)
        } else {
            detailedBody
        }
    }

    private var detailedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let name = title.nativeName {
                Text(verbatim: String(name.prefix(2_048)))
                    .font(.headline)
                    .textSelection(.enabled)
            } else {
                Text("标题暂不可用").font(.headline)
            }
            LabeledContent("客户端") { Text(verbatim: record.clientName) }
            LabeledContent("来源") {
                Text(appLocalized: record.origin == "unknown" ? "来源待确认" : record.origin)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("完整目录").foregroundStyle(.secondary)
                Text(verbatim: record.workspace).textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("原生会话 ID").foregroundStyle(.secondary)
                Text(verbatim: record.nativeSessionID)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            if title == .unavailable {
                Text("暂时无法读取客户端原始标题，可通过目录和会话 ID 确认。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("session-metadata-details")
    }
}
