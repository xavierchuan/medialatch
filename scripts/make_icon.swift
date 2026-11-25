import Foundation

guard CommandLine.arguments.count > 1 else {
    fatalError("Output path required")
}

let scriptURL = URL(fileURLWithPath: #filePath)
let projectURL = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let sourceURL = projectURL
    .appendingPathComponent("Resources")
    .appendingPathComponent("MediaLatchIcon.png")
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

let iconData = try Data(contentsOf: sourceURL)
try iconData.write(to: outputURL, options: .atomic)
