import Darwin
import Foundation

nonisolated enum BoundedLocalFileReader {
    /// Opens first, validates the descriptor, then reads a bounded head/tail.
    /// O_NONBLOCK keeps special files from blocking before fstat can reject them.
    static func jsonl(at url: URL, under root: URL, maximumBytes: Int = 4 * 1024 * 1024) -> String? {
        // Foundation can re-abbreviate /private/var as /var. Compare two kernel
        // descriptor paths so legitimate temporary-directory aliases stay valid.
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NONBLOCK | O_CLOEXEC)
        guard rootFD >= 0 else { return nil }
        defer { close(rootFD) }
        var rootPath = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(rootFD, F_GETPATH, &rootPath) == 0 else { return nil }
        let allowed = String(cString: rootPath) + "/"
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_uid == geteuid(), info.st_size >= 0,
            fcntl(fd, F_GETPATH, &path) == 0,
            String(cString: path).hasPrefix(allowed)
        else { return nil }
        func readRange(offset: off_t, count: Int) -> Data? {
            var bytes = [UInt8](repeating: 0, count: count)
            let length = pread(fd, &bytes, count, offset)
            guard length >= 0 else { return nil }
            return Data(bytes.prefix(length))
        }
        guard maximumBytes >= 65_536 else { return nil }
        let bytes: Data
        if info.st_size <= maximumBytes {
            guard let whole = readRange(offset: 0, count: Int(info.st_size)) else { return nil }
            bytes = whole
        } else {
            guard let head = readRange(offset: 0, count: 65_536),
                let firstNewline = head.firstIndex(of: 10),
                let tail = readRange(offset: info.st_size - off_t(maximumBytes - 65_536), count: maximumBytes - 65_536),
                let tailNewline = tail.firstIndex(of: 10)
            else { return nil }
            bytes = Data(head[...firstNewline]) + Data(tail.dropFirst(tailNewline + 1))
        }
        guard bytes.split(separator: 10).allSatisfy({ $0.count <= 1_048_576 }) else { return nil }
        return String(data: bytes, encoding: .utf8)
    }
}
