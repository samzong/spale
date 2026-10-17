import AppKit
import SpaleCore

let invocation = CommandLine.arguments[0]
let isCLI = !invocation.contains(".app/Contents/MacOS/")
if isCLI {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.count > 1 {
        FileHandle.standardError.write(Data("Usage: spale [path]\n".utf8)); exit(1)
    }
    let path = arguments.first ?? FileManager.default.currentDirectoryPath
    let expanded = (path as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL.resolvingSymlinksInPath()
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else {
        FileHandle.standardError.write(Data("spale: the path does not exist.\n".utf8)); exit(1)
    }
    if directory.boolValue && Git.root(containing: url) == nil {
        FileHandle.standardError.write(Data("spale: the folder is not in a Git repository.\n".utf8)); exit(1)
    }
    var components = URLComponents(); components.scheme = "spale"; components.host = "open"
    components.queryItems = [URLQueryItem(name: "path", value: url.path)]
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-b", "us.samzong.spale", components.url!.absoluteString]
    try process.run(); process.waitUntilExit(); exit(process.terminationStatus)
}
_ = DocumentController()
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
