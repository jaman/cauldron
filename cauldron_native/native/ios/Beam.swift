import AVFoundation
import Foundation

enum Beam {
    static func start() {
        guard let resources = Bundle.main.resourcePath else { fatalError("no resource path") }
        let root = resources + "/otp"
        let data = dataDirectory()
        prepareEnvironment(root: root, data: data)
        releaseEnvironment(root: root, data: data)
        prepareAudio()

        let arguments = startArguments(root: root, data: data)
        let thread = Thread {
            var cArguments = arguments.map { strdup($0) }
            cArguments.append(nil)
            erl_start(Int32(arguments.count), &cArguments)
        }
        thread.stackSize = 16 * 1024 * 1024
        thread.name = "beam"
        thread.start()
    }

    private static func dataDirectory() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if os(macOS)
        let path = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "cauldron").path
        #else
        let path = base.appendingPathComponent("cauldron").path
        #endif
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private static func prepareEnvironment(root: String, data: String) {
        let folders = ["XDG_CONFIG_HOME": "config", "XDG_DATA_HOME": "data", "XDG_STATE_HOME": "state", "XDG_CACHE_HOME": "cache"]
        for (name, folder) in folders {
            let path = data + "/" + folder
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            setenv(name, path, 1)
        }
        setenv("HOME", data, 1)
        setenv("CAULDRON_NATIVE_DATA", data, 1)
        setenv("BINDIR", root + "/bin", 1)
        setenv("ROOTDIR", root, 1)
        setenv("EMU", "beam", 1)
        setenv("PROGNAME", "erl", 1)
        setenv("LANG", "en_US.UTF-8", 1)
        #if !os(macOS)
        Resolver.prepare(data: data)
        #endif
        setenv("ERL_CRASH_DUMP_SECONDS", "0", 1)
    }

    private static func releaseEnvironment(root: String, data: String) {
        guard let text = try? String(contentsOfFile: root + "/releases/env", encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = String(line[..<equals])
            let value = String(line[line.index(after: equals)...])
                .replacingOccurrences(of: "$ROOT", with: root)
                .replacingOccurrences(of: "$HOME", with: data)
            setenv(name, value, 1)
        }
    }

    private static func prepareAudio() {
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private static func startArguments(root: String, data: String) -> [String] {
        guard let text = try? String(contentsOfFile: root + "/releases/start_args", encoding: .utf8) else {
            fatalError("no start_args in the release")
        }
        let lines = text.split(separator: "\n").map {
            $0.replacingOccurrences(of: "$ROOT", with: root).replacingOccurrences(of: "$HOME", with: data)
        }
        return ["beam"] + lines
    }
}
