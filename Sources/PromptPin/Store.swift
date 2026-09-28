import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PromptPinCore

@MainActor final class Store: ObservableObject {
    @Published private(set) var library = Library(projects: [], prompts: [])
    @Published var error: String?
    @Published var isLocked = false
    @Published var notice: String?
    let disk: LibraryDisk
    // An explicit alternate directory is used for isolated UI checks, never for live migrations.
    static var configuredDisk: LibraryDisk {
        if let path = ProcessInfo.processInfo.environment["PROMPT_PIN_DATA_DIR"], !path.isEmpty {
            return LibraryDisk(directory: URL(fileURLWithPath: path, isDirectory: true))
        }
        return .standard
    }
    var holdOpen: ((Bool) -> Void)?

    init() {
        disk = Self.configuredDisk
        do {
            if let existing = try disk.load() { library = existing }
            else { let initial = Library.starter; try disk.save(initial); library = initial }
        } catch { isLocked = true; self.error = "读取本地数据失败，已停止写入以保护原文件。\n\(error.localizedDescription)" }
    }
    @discardableResult func update(_ edit: (inout Library) -> Void) -> Bool {
        guard !isLocked else { error = "请先恢复备份或检查数据文件，再进行编辑。"; return false }
        var next = library
        edit(&next)
        do {
            guard try disk.load() == library else { throw LibraryError.invalid("磁盘资料已在其他地方变更。请保留当前编辑内容并重新打开应用，避免覆盖新资料。") }
            try disk.save(next); library = next; return true
        }
        catch { self.error = "保存失败，修改尚未保存：\(error.localizedDescription)"; return false }
    }
    @discardableResult func copyText(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            error = "无法写入剪贴板，请重试。"; return false
        }
        return true
    }
    @discardableResult func copy(_ prompt: Prompt) -> Bool { copyText(prompt.body) }
    func exportLibrary() {
        holdOpen?(true); defer { holdOpen?(false) }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PromptPin-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try disk.encode(library).write(to: url, options: .atomic); notice = "备份已导出" }
        catch { self.error = error.localizedDescription }
    }
    func importLibrary() {
        holdOpen?(true); defer { holdOpen?(false) }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try disk.decode(Data(contentsOf: url))
            let merged = library.merging(incoming)
            let added = merged.prompts.count + merged.accounts.count + merged.secrets.count + merged.memos.count
                - library.prompts.count - library.accounts.count - library.secrets.count - library.memos.count
            if update({ $0 = merged }) { notice = "已导入 \(added) 条资料，现有内容保留" }
        } catch { self.error = "导入失败：\(error.localizedDescription)" }
    }
    func restore() {
        do { library = try disk.restoreBackup(); isLocked = false; notice = "已恢复上一版，原文件已保留" }
        catch { self.error = "恢复失败：\(error.localizedDescription)" }
    }
    func revealData() { NSWorkspace.shared.open(disk.directory) }
}
