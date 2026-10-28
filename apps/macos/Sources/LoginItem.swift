// Dokey for macOS - start at login.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa
import ServiceManagement

/// macOS 13+ uses SMAppService; older systems get a per-user LaunchAgent.
enum LoginItem {
    private static let agentLabel = "com.dhtoan.dokey.mac.launcher"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    /// Returns an error message, or nil on success.
    static func setEnabled(_ enabled: Bool) -> String? {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        do {
            if enabled {
                guard let executable = Bundle.main.executablePath else { return "Không tìm thấy tệp chạy của Dokey." }
                let plist: [String: Any] = [
                    "Label": agentLabel,
                    "ProgramArguments": [executable],
                    "RunAtLoad": true,
                    "ProcessType": "Interactive",
                ]
                try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: agentURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: agentURL.path) {
                try FileManager.default.removeItem(at: agentURL)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
