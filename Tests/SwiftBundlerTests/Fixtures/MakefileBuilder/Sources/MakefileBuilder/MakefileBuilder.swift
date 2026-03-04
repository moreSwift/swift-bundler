import SwiftBundlerBuilders
import Foundation

@main
struct MakefileBuilder: Builder {
    static func build(_ context: some BuilderContext) async throws -> BuilderResult {
        try await context.run("make", [])

        let destination = context.buildDirectory.appendingPathComponent("libclib.a")
        try? FileManager.default.removeItem(
            at: destination
        )
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "libclib.a"),
            to: destination
        )

        return BuilderResult()
    }
}
