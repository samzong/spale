import Foundation

public struct IconTheme: Sendable {
    private struct Manifest: Decodable {
        struct Definition: Decodable { let iconPath: String }
        let iconDefinitions: [String: Definition]
        let file: String
        let folder: String
        let fileExtensions: [String: String]?
        let fileNames: [String: String]?
        let languageIds: [String: String]?
        let folderNames: [String: String]?
    }

    private static let extensionLanguages = ["mk": "makefile", "mak": "makefile", "php": "php", "vue": "vue", "clj": "clojure", "cljs": "clojure", "cljc": "clojure", "edn": "clojure", "coffee": "coffeescript", "j2": "jinja", "jinja": "jinja", "hpp": "cpp", "hh": "cpp", "hxx": "cpp", "h++": "cpp", "ipp": "cpp", "m": "objective-c", "pl": "perl", "pm": "perl", "markdown": "markdown", "mdown": "markdown", "mkd": "markdown", "mkdn": "markdown", "hbs": "handlebars", "handlebars": "handlebars", "properties": "properties", "cfg": "properties", "conf": "properties", "ini": "properties", "rake": "ruby", "gemspec": "ruby", "ru": "ruby", "podspec": "ruby", "rbi": "ruby", "pyi": "python", "pyw": "python"]
    private static let nameLanguages = ["makefile": "makefile", "gnumakefile": "makefile", "containerfile": "dockerfile", "gemfile": "ruby", "rakefile": "ruby", "podfile": "ruby", "vagrantfile": "ruby", "brewfile": "ruby", "guardfile": "ruby", "capfile": "ruby", "fastfile": "ruby", ".bashrc": "shellscript", ".bash_profile": "shellscript", ".bash_login": "shellscript", ".bash_logout": "shellscript", ".profile": "shellscript", ".zshrc": "shellscript", ".zprofile": "shellscript", ".zlogin": "shellscript", ".zlogout": "shellscript", ".zshenv": "shellscript", "pkgbuild": "shellscript", "apkbuild": "shellscript"]

    private let paths: [String: String]
    private let extensions: [String: String]
    private let fileNames: [String: String]
    private let languages: [String: String]
    private let folderNames: [String: String]
    private let file: String
    private let folder: String

    public init(json: Data) throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: json)
        let lowered = { (map: [String: String]?) in Dictionary((map ?? [:]).map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first }) }
        paths = manifest.iconDefinitions.mapValues { $0.iconPath.hasPrefix("./") ? String($0.iconPath.dropFirst(2)) : $0.iconPath }
        extensions = lowered(manifest.fileExtensions)
        fileNames = lowered(manifest.fileNames)
        languages = manifest.languageIds ?? [:]
        folderNames = lowered(manifest.folderNames)
        file = manifest.file
        folder = manifest.folder
    }

    public func icon(name: String, isDirectory: Bool, isSymbolicLink: Bool) -> String? {
        let name = name.lowercased()
        if isDirectory { return paths[folderNames[name] ?? folder] }
        if isSymbolicLink, let link = paths["link"] { return link }
        if let id = fileNames[name] { return paths[id] }
        let segments = name.split(separator: ".", omittingEmptySubsequences: false).dropFirst()
        for index in segments.indices {
            if let id = extensions[segments[index...].joined(separator: ".")] { return paths[id] }
        }
        let language = Self.nameLanguages[name] ?? segments.last.flatMap { Self.extensionLanguages[String($0)] }
        return paths[language.flatMap { languages[$0] } ?? file]
    }
}
