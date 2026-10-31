//
//  SessionTextSanitizer.swift
//  PingIsland
//
//  Normalizes session text for display by removing client-injected boilerplate.
//

import Foundation

nonisolated enum SessionTextSanitizer {
    static func sanitizedDisplayText(_ text: String?) -> String? {
        guard var cleaned = removingClientBoilerplate(from: text) else { return nil }
        cleaned =
            cleaned
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }

    /// Cleans display-only conversation content while preserving paragraphs,
    /// bullets, and code-like line breaks for the expanded local detail card.
    static func sanitizedMultilineDisplayText(_ text: String?) -> String? {
        guard var cleaned = removingClientBoilerplate(from: text) else { return nil }
        cleaned =
            cleaned
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(
                of: #"(?m)[ \t]+$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\n{3,}"#,
                with: "\n\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }

    static func boundedMultilineDisplayText(
        _ text: String?,
        maxCharacters: Int,
        truncationNotice: String
    ) -> String? {
        boundedDisplayText(
            sanitizedMultilineDisplayText(text),
            maxCharacters: maxCharacters,
            truncationNotice: truncationNotice
        )
    }

    static func boundedDisplayText(
        _ text: String?,
        maxCharacters: Int,
        truncationNotice: String
    ) -> String? {
        guard let text else { return nil }
        guard !text.isEmpty else { return nil }
        guard maxCharacters > 0 else { return truncationNotice }

        guard
            let cutoff = text.index(
                text.startIndex,
                offsetBy: maxCharacters,
                limitedBy: text.endIndex
            )
        else {
            return text
        }

        guard cutoff < text.endIndex else {
            return text
        }

        let prefix = text[..<cutoff].trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)\n\n\(truncationNotice)"
    }

    private static func removingClientBoilerplate(from text: String?) -> String? {
        guard let text else { return nil }

        var cleaned = text
        cleaned = cleaned.replacingOccurrences(
            of: #"(?is)^Conversation info \(untrusted metadata\):\s*```json.*?```\s*"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?is)^Sender \(untrusted metadata\):\s*```json.*?```\s*"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?is)^System:\s*\[[^\]]+\]\s*Node:.*?(?:\n\s*\n|\z)"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?is)<system-reminder>.*?</system-reminder>"#,
            with: " ",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?is)<system-reminder>.*$"#,
            with: " ",
            options: .regularExpression
        )
        return cleaned
    }
}

nonisolated enum SessionDetailDisplayStrings {
    static let truncationNoticeKey =
        "Showing a shortened preview to keep Mac Island responsive. Open the client to view the full content."
}
