import Foundation

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

public struct BridgeDebugLogPolicy: Sendable, Equatable {
    public static let defaultRetentionDays = 7
    public static let minimumRetentionDays = 1
    public static let maximumRetentionDays = 30
    public static let defaultMaxDirectoryMegabytes = 256
    public static let minimumMaxDirectoryMegabytes = 16
    public static let maximumMaxDirectoryMegabytes = 1024

    public var isEnabled: Bool
    public var retentionDays: Int
    public var maxDirectoryMegabytes: Int

    public init(
        isEnabled: Bool = false,
        retentionDays: Int = Self.defaultRetentionDays,
        maxDirectoryMegabytes: Int = Self.defaultMaxDirectoryMegabytes
    ) {
        self.isEnabled = isEnabled
        self.retentionDays = Self.clampedRetentionDays(retentionDays)
        self.maxDirectoryMegabytes = Self.clampedMaxDirectoryMegabytes(maxDirectoryMegabytes)
    }

    public init(jsonObject: [String: Any]) {
        self.init(
            isEnabled: (jsonObject["debugLoggingEnabled"] as? Bool) ?? false,
            retentionDays: Self.intValue(
                jsonObject["debugLogRetentionDays"],
                default: Self.defaultRetentionDays
            ),
            maxDirectoryMegabytes: Self.intValue(
                jsonObject["debugLogMaxDirectoryMegabytes"],
                default: Self.defaultMaxDirectoryMegabytes
            )
        )
    }

    public static let `default` = BridgeDebugLogPolicy()

    public var maxDirectoryBytes: Int64 {
        Int64(maxDirectoryMegabytes) * 1024 * 1024
    }

    public var jsonObject: [String: Any] {
        [
            "debugLoggingEnabled": isEnabled,
            "debugLogRetentionDays": retentionDays,
            "debugLogMaxDirectoryMegabytes": maxDirectoryMegabytes,
        ]
    }

    public static func clampedRetentionDays(_ value: Int) -> Int {
        min(max(value, minimumRetentionDays), maximumRetentionDays)
    }

    public static func clampedMaxDirectoryMegabytes(_ value: Int) -> Int {
        min(max(value, minimumMaxDirectoryMegabytes), maximumMaxDirectoryMegabytes)
    }

    private static func intValue(_ value: Any?, default defaultValue: Int) -> Int {
        if let intValue = value as? Int {
            return intValue
        }
        if let doubleValue = value as? Double {
            return Int(exactly: doubleValue.rounded()) ?? defaultValue
        }
        if let stringValue = value as? String,
            let intValue = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return intValue
        }
        return defaultValue
    }
}

public enum BridgeDebugLogPruner {
    private static let legacyDirectories = [
        "claude-hooks", "codex-hooks", "gemini-hooks", "codebuddy-cli-hooks", "codebuddy-hooks",
        "hermes-hooks", "pi-hooks", "openclaw-hooks", "qoder-hooks", "qoder-cli-hooks",
        "qoder-cn-hooks", "qoder-cn-cli-hooks", "kimi-hooks", "antigravity-hooks",
    ]

    public static func prune(
        directory: URL, policy: BridgeDebugLogPolicy, now: Date = Date(),
        fileManager: FileManager = .default, excludingFileNames: Set<String> = []
    ) throws {
        _ = fileManager  // Preserve the existing caller contract; deletion is descriptor-relative.
        let rootFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { return }
        var descriptors = [rootFD]
        defer { for fd in descriptors { close(fd) } }
        guard ownedDirectory(rootFD) else { return }
        var entries = logFiles(directoryFD: rootFD, legacy: false, excluding: excludingFileNames)
        for name in legacyDirectories {
            let fd = openat(rootFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { continue }
            descriptors.append(fd)
            guard ownedDirectory(fd) else { continue }
            entries += logFiles(directoryFD: fd, legacy: true, excluding: excludingFileNames)
        }
        let cutoff = now.addingTimeInterval(-Double(policy.retentionDays) * 86_400)
        var retained: [DebugLogFileEntry] = []
        for entry in entries {
            if !policy.isEnabled || entry.modifiedAt < cutoff { remove(entry) } else { retained.append(entry) }
        }
        var total: Int64 = 0
        for entry in retained {
            let sum = total.addingReportingOverflow(entry.sizeBytes)
            total = sum.overflow ? Int64.max : sum.partialValue
        }
        for entry in retained.sorted(by: { $0.modifiedAt < $1.modifiedAt }) where total > policy.maxDirectoryBytes {
            if remove(entry) { total = max(0, total - entry.sizeBytes) }
        }
    }

    private static func ownedDirectory(_ fd: Int32) -> Bool {
        var info = stat()
        return fstat(fd, &info) == 0 && info.st_uid == geteuid() && info.st_mode & S_IFMT == S_IFDIR
    }

    private static func logFiles(directoryFD: Int32, legacy: Bool, excluding: Set<String>) -> [DebugLogFileEntry] {
        let duplicate = dup(directoryFD)
        guard duplicate >= 0 else { return [] }
        guard let directory = fdopendir(duplicate) else {
            close(duplicate)
            return []
        }
        defer { closedir(directory) }
        var results: [DebugLogFileEntry] = []
        var inspected = 0
        while let entry = readdir(directory), inspected < 5_000 {
            inspected += 1
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) {
                    String(cString: $0)
                }
            }
            guard !excluding.contains(name),
                name.range(
                    of: legacy ? #"^[0-9]{8}\.jsonl$"# : #"^bridge-[0-9]{8}\.jsonl$"#,
                    options: .regularExpression) != nil
            else { continue }
            var info = stat()
            guard fstatat(directoryFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_nlink == 1,
                info.st_size >= 0
            else { continue }
            #if canImport(Darwin)
                let seconds = info.st_mtimespec.tv_sec
            #else
                let seconds = info.st_mtim.tv_sec
            #endif
            results.append(
                DebugLogFileEntry(
                    directoryFD: directoryFD, name: name, inode: info.st_ino,
                    sizeBytes: Int64(info.st_size), modifiedAt: Date(timeIntervalSince1970: Double(seconds))))
        }
        return results
    }

    @discardableResult
    private static func remove(_ entry: DebugLogFileEntry) -> Bool {
        var info = stat()
        guard fstatat(entry.directoryFD, entry.name, &info, AT_SYMLINK_NOFOLLOW) == 0,
            info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_ino == entry.inode,
            info.st_nlink == 1
        else { return false }
        return unlinkat(entry.directoryFD, entry.name, 0) == 0
    }
}

private struct DebugLogFileEntry {
    let directoryFD: Int32
    let name: String
    let inode: ino_t
    let sizeBytes: Int64
    let modifiedAt: Date
}
