import Foundation

let helper = Bundle.main.executableURL!.deletingLastPathComponent()
    .appendingPathComponent("LibraryHelper")

if !FileManager.default.fileExists(atPath: helper.path) {
    fatalError("Missing LibraryHelper")
}
