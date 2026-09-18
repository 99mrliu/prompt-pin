import SwiftUI
import ServiceManagement
import PromptPinCore

struct LibraryView: View {
    @ObservedObject var store: Store
    @State private var selectedProject: UUID?
    @State private var pinnedOnly = false
    @State private var query = ""
    @State private var draft: Prompt?
    @State private var projectEditor = false
    @State private var projectToRename: Project?
    @State private var projectName = ""
    @State private var projectError: String?
    @State private var deletePrompt: Prompt?
    @State private var deleteProject: Project?
    @State private var copiedID: UUID?
    @State private var copyGeneration = UUID()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @FocusState private var searchFocused: Bool

    private var title: String {
        if pinnedOnly { return "常用置顶" }
        return store.library.projects.first { $0.id == selectedProject }?.name ?? "全部提示词"
    }
    private var visiblePrompts: [Prompt] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.library.prompts.filter { prompt in
            (selectedProject == nil || prompt.projectID == selectedProject) &&
            (!pinnedOnly || prompt.isPinned) &&
            (keyword.isEmpty || prompt.title.localizedStandardContains(keyword) || prompt.body.localizedStandardContains(keyword) || projectLabel(prompt.projectID).localizedStandardContains(keyword))
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 192)
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                header
                search.padding(.horizontal, 26).padding(.bottom, 18)
                if store.isLocked { recovery }
                else if visiblePrompts.isEmpty { emptyState }
                else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(visiblePrompts) { prompt in promptCard(prompt) }
                        }.padding(.horizontal, 26).padding(.top, 2).padding(.bottom, 20)
                    }
                }
                footer
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 780, height: 580)
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .tint(Theme.green)
        .preferredColorScheme(.light)
        .sheet(item: $draft) { prompt in
            PromptEditor(store: store, original: prompt) { draft = nil }
        }
        .sheet(isPresented: $projectEditor) { projectForm }
        .alert("无法完成操作", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .alert("删除这条提示词？", isPresented: Binding(get: { deletePrompt != nil }, set: { if !$0 { deletePrompt = nil } })) {
            Button("取消", role: .cancel) { deletePrompt = nil }
            Button("删除", role: .destructive) {
                if let prompt = deletePrompt { store.update { $0.prompts.removeAll { $0.id == prompt.id } } }
                deletePrompt = nil
            }
        } message: { Text("“\(deletePrompt?.title ?? "")”将从提示词库中移除。") }
        .alert("删除项目及其中的提示词？", isPresented: Binding(get: { deleteProject != nil }, set: { if !$0 { deleteProject = nil } })) {
            Button("取消", role: .cancel) { deleteProject = nil }
            Button("删除项目", role: .destructive) {
                if let project = deleteProject {
                    if store.update({ library in
                        library.prompts.removeAll { $0.projectID == project.id }
                        library.projects.removeAll { $0.id == project.id }
                    }), selectedProject == project.id { selectedProject = nil }
                }
                deleteProject = nil
            }
        } message: {
            Text("将删除“\(deleteProject?.name ?? "")”及其中 \(store.library.prompts.filter { $0.projectID == deleteProject?.id }.count) 条提示词。建议先导出备份。")
        }
        .onChange(of: draft != nil || projectEditor) { store.holdOpen?($0) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "pin.fill").font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(Theme.green, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prompt Pin").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("好用的话，随手可得").font(.system(size: 9)).foregroundStyle(Theme.muted)
                }
            }.padding(.top, 28).padding(.bottom, 31).padding(.horizontal, 18)
            VStack(spacing: 5) {
                navigationRow("全部提示词", icon: "square.grid.2x2", count: store.library.prompts.count, active: selectedProject == nil && !pinnedOnly) {
                    selectedProject = nil; pinnedOnly = false
                }
                navigationRow("常用置顶", icon: "pin", count: store.library.prompts.filter(\.isPinned).count, active: pinnedOnly) {
                    selectedProject = nil; pinnedOnly = true
                }
            }.padding(.horizontal, 12)
            HStack {
                Text("我的项目").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                Spacer()
                Button { openProjectEditor(nil) } label: { Image(systemName: "plus").font(.system(size: 11)) }
                    .buttonStyle(QuietButton()).help("新建项目").accessibilityLabel("新建项目")
                    .disabled(store.isLocked)
            }.padding(.horizontal, 21).padding(.top, 25).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(store.library.projects) { project in
                        navigationRow(project.name, icon: "folder", count: store.library.prompts.filter { $0.projectID == project.id }.count, active: selectedProject == project.id) {
                            selectedProject = project.id; pinnedOnly = false
                        }.contextMenu {
                            Button("重命名项目") { openProjectEditor(project) }
                            Button("删除项目…", role: .destructive) { deleteProject = project }
                        }
                    }
                }.padding(.horizontal, 12)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "internaldrive").font(.system(size: 12))
                    Text("只在你的 Mac 上").font(.system(size: 11, weight: .medium))
                }.foregroundStyle(Theme.green)
                Text("保存灵感，也省下每一次重复。")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.mint.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                .padding(14)
            HStack {
                Menu {
                    Button("导出备份…") { store.exportLibrary() }.disabled(store.isLocked)
                    Button("导入备份（合并）…") { store.importLibrary() }.disabled(store.isLocked)
                    Button("打开数据文件夹") { store.revealData() }
                    Divider()
                    Toggle("登录时自动启动", isOn: Binding(get: { launchAtLogin }, set: setLogin))
                    if SMAppService.mainApp.status == .requiresApproval {
                        Button("前往系统设置允许启动") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    Divider()
                    Button("退出 Prompt Pin") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "gearshape").font(.system(size: 14)) }
                    .menuStyle(.borderlessButton).fixedSize().help("设置与备份").accessibilityLabel("设置与备份")
                Spacer()
                Text("随用随取").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }.padding(.horizontal, 23).padding(.bottom, 20)
        }.background(Color.white.opacity(0.64))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                Text("把重复留给收藏，把时间留给创造。")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            Button(action: newPrompt) { Label("新建提示词", systemImage: "plus") }
                .buttonStyle(SpringButton(filled: true)).keyboardShortcut("n")
                .disabled(store.isLocked)
        }.padding(.horizontal, 26).padding(.top, 28).padding(.bottom, 24)
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("搜索标题、内容或项目…", text: $query)
                .textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).accessibilityLabel("清除搜索")
            }
            Button { searchFocused = true } label: { Text("⌘ F").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                .buttonStyle(.plain).keyboardShortcut("f").accessibilityLabel("搜索提示词")
        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line, lineWidth: 1))
    }

    private func promptCard(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text(projectLabel(prompt.projectID)).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.green).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.mint.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                Spacer()
                Button {
                    store.update { library in
                        if let i = library.prompts.firstIndex(where: { $0.id == prompt.id }) { library.prompts[i].isPinned.toggle() }
                    }
                } label: {
                    Image(systemName: prompt.isPinned ? "pin.fill" : "pin").font(.system(size: 11))
                        .foregroundStyle(prompt.isPinned ? Theme.green : Theme.muted.opacity(0.75))
                }.buttonStyle(QuietButton()).help(prompt.isPinned ? "取消置顶" : "置顶提示词")
                    .accessibilityLabel(prompt.isPinned ? "取消置顶" : "置顶提示词")
                Menu {
                    Button("编辑提示词") { draft = prompt }
                    Button("复制一份") {
                        draft = Prompt(projectID: prompt.projectID, title: prompt.title + " · 副本", body: prompt.body)
                    }
                    Divider()
                    Button("删除…", role: .destructive) { deletePrompt = prompt }
                } label: { Image(systemName: "ellipsis").font(.system(size: 13)) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("提示词操作")
            }
            Button { draft = prompt } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(prompt.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(prompt.body.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("查看与编辑完整提示词")
            HStack {
                Text("\(prompt.body.count) 字").font(.system(size: 10)).foregroundStyle(Theme.muted)
                Spacer()
                Button { copy(prompt) } label: {
                    Label(copiedID == prompt.id ? "已复制" : "复制提示词", systemImage: copiedID == prompt.id ? "checkmark" : "doc.on.doc")
                        .frame(minWidth: 86)
                }.buttonStyle(SpringButton())
            }.padding(.top, 1)
        }.padding(17).background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.line.opacity(0.75), lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: store.isLocked ? "exclamationmark.triangle" : "checkmark.shield")
            Text(store.isLocked ? "数据需要修复" : "已保存到本机")
            Spacer()
            Text(store.notice ?? "\(visiblePrompts.count) 条提示词 · 点击卡片编辑")
                .lineLimit(1)
        }.font(.system(size: 10)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 26).padding(.vertical, 14)
            .background(Theme.canvas)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: query.isEmpty ? "text.badge.plus" : "magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(Theme.green)
            Text(query.isEmpty ? "留住下一句好提示" : "没有找到相关提示词").font(.system(size: 17, weight: .semibold))
            Text(query.isEmpty ? (pinnedOnly ? "点击提示词上的图钉，常用内容就会出现在这里。" : "把经常输入的内容存下来，下次一键复制。") : "试试更短的关键词，或切换到全部提示词。")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if !query.isEmpty {
                Button("清除筛选") { query = ""; selectedProject = nil; pinnedOnly = false }.buttonStyle(SpringButton())
            } else if !pinnedOnly {
                Button("创建第一条提示词", action: newPrompt).buttonStyle(SpringButton(filled: true))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(26)
    }
    private var recovery: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle).foregroundStyle(Theme.green)
            Text("本地数据暂时无法读取").font(.headline)
            Text("原文件不会被覆盖。可以查看数据文件夹，或恢复上一版备份。")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button("恢复上一版备份") { store.restore() }.buttonStyle(SpringButton(filled: true))
            Button("打开数据文件夹") { store.revealData() }.buttonStyle(SpringButton())
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func navigationRow(_ name: String, icon: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 17)
                Text(name).font(.system(size: 12, weight: active ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 3)
                Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit().opacity(0.65)
            }.foregroundStyle(active ? Theme.green : Theme.muted)
                .padding(.horizontal, 11).padding(.vertical, 11)
                .background(active ? Theme.mint : .clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).help(name)
    }

    private var projectForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(projectToRename == nil ? "新建项目" : "重命名项目").font(.system(size: 21, weight: .semibold))
            TextField("例如：我的研究项目", text: $projectName).textFieldStyle(.roundedBorder)
                .onSubmit(saveProject)
            if let projectError { Text(projectError).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Button("取消") { projectEditor = false }.buttonStyle(SpringButton()).keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存", action: saveProject).buttonStyle(SpringButton(filled: true)).keyboardShortcut(.defaultAction)
                    .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 350).background(Theme.canvas)
    }
    private func saveProject() {
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let id = projectToRename?.id ?? UUID()
        if store.update({ library in
            if let i = library.projects.firstIndex(where: { $0.id == id }) { library.projects[i].name = name }
            else { library.projects.append(Project(id: id, name: name)) }
        }) { selectedProject = id; pinnedOnly = false; projectEditor = false }
        else { projectError = store.error; store.error = nil }
    }
    private func openProjectEditor(_ project: Project?) {
        projectToRename = project; projectName = project?.name ?? ""; projectError = nil; projectEditor = true
    }
    private func newPrompt() {
        guard let id = selectedProject ?? store.library.projects.first?.id else { openProjectEditor(nil); return }
        draft = Prompt(projectID: id, title: "", body: "")
    }
    private func projectLabel(_ id: UUID) -> String { store.library.projects.first { $0.id == id }?.name ?? "" }
    private func copy(_ prompt: Prompt) {
        guard store.copy(prompt) else { return }
        copiedID = prompt.id
        let generation = UUID(); copyGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if copyGeneration == generation { copiedID = nil }
        }
    }
    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { store.error = "设置自动启动失败：\(error.localizedDescription)" }
    }
}
