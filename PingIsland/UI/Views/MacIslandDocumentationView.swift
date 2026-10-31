import SwiftUI

struct MacIslandDocumentationView: View {
    let document: MacIslandDocumentation
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(appLocalized: document.titleKey).font(.title3.weight(.semibold))
                Spacer()
                Button(AppLocalization.string("mac-island.action.done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("documentation.close")
            }
            .padding(20)
            Divider()
            ScrollView {
                if let content = document.content(locale: settings.locale) {
                    documentContent(content)
                        .padding(20)
                } else {
                    Text(appLocalized: "无法读取随应用提供的说明，请重新安装完整应用。")
                        .foregroundStyle(.secondary)
                        .padding(24)
                }
            }
            .accessibilityIdentifier("documentation.content.\(document.rawValue)")
        }
        .frame(minWidth: 480, idealWidth: 620, maxWidth: 720, minHeight: 360, idealHeight: 480)
    }

    @ViewBuilder private func documentContent(_ content: String) -> some View {
        if document == .acknowledgements {
            Text(content)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(content.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, block in
                    if block.hasPrefix("# ") {
                        Text(String(block.dropFirst(2))).font(.title2.weight(.semibold))
                    } else if block.hasPrefix("## ") {
                        Text(String(block.dropFirst(3))).font(.headline).padding(.top, 6)
                    } else {
                        Text(
                            (try? AttributedString(
                                markdown: block, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                                ?? AttributedString(block)
                        )
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
