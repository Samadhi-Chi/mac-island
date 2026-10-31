import Foundation
import Testing

@Test
func runningProcessRetainsExitAcrossAnAsyncSuspension() async throws {
    let process = try RunningProcess(
        executableURL: URL(fileURLWithPath: "/usr/bin/true"),
        arguments: []
    )
    // Exit can arrive before the caller resumes on another executor thread.
    try await Task.sleep(for: .milliseconds(50))
    let result = process.waitForExit(timeout: 2)
    #expect(result.terminationStatus == 0)
    #expect(result.stdout.isEmpty)
    #expect(result.stderr.isEmpty)
}
