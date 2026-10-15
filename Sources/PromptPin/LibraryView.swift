import SwiftUI
import ServiceManagement
import PromptPinCore

struct LibraryView: View {
    enum Pane: Equatable {
        case allPrompts, pinned, accounts, secrets, memos, project(UUID)
    }
    @ObservedObject var store: Store
    @State private var pane: Pane = .allPrompts
    @State private var query = ""
    @State private var draft: Prompt?
    @State private var accountDraft: AccountCredential?
    @State private var secretDraft: SecretRecord?
    @State private var memoDraft: Memo?
    @State private var deleteMemo: Memo?
    @State private var categoryFilter = ""
    @State private var roleFilter = ""
    @State private var kindFilter: SecretKind?
    @State private var projectEditor = false
    @State private var projectToRename: Project?
    @State private var projectName = ""
    @State private var projectError: String?
    @State private var deletePrompt: Prompt?
    @State private var deleteProject: Project?
    @State private var deleteAccount: AccountCredential?
    @State private var deleteSecret: SecretRecord?
    @State private var copiedID: UUID?
    @State private var copiedKey: String?
    @State private var copyGeneration = UUID()
    @State private var revealed: Set<UUID> = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @FocusState private var searchFocused: Bool

    private var title: String {
        switch pane {
        case .allPrompts: return "全部提示词"
        case .pinned: return "常用置顶"
        case .accounts: return "账号密码"
        case .secrets: return "密钥"
        case .memos: return "备忘录"
        case .project(let id): return store.library.projects.first { $0.id == id }?.name ?? "提示词"
        }
    }
    private var subtitle: String {
        switch pane {
        case .accounts: return "账号关系与用途可选，按自己的习惯整理。"
        case .secrets: return "按类型和用途整理，不必强行填写主子账号。"
        case .memos: return "临时想法、操作步骤和日常记录，随手存好。"
        default: return "把重复留给收藏，把时间留给创造。"
        }
    }
    private var visiblePrompts: [Prompt] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.library.prompts.filter { prompt in
            (pane == .allPrompts || pane == .pinned || pane == .project(prompt.projectID)) &&
            (pane != .pinned || prompt.isPinned) &&
            (keyword.isEmpty || prompt.title.localizedStandardContains(keyword) || prompt.body.localizedStandardContains(keyword) || projectLabel(prompt.projectID).localizedStandardContains(keyword))
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }
    private var visibleAccounts: [AccountCredential] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.library.accounts.filter { account in
            matches(account.context) && (keyword.isEmpty || contextMatches(account.context, keyword) || account.title.localizedStandardContains(keyword)
                || account.mainAccount.localizedStandardContains(keyword)
                || account.loginName.localizedStandardContains(keyword))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var visibleSecrets: [SecretRecord] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.library.secrets.filter { record in
            matches(record.context) && (kindFilter == nil || record.kind == kindFilter) && (keyword.isEmpty || contextMatches(record.context, keyword) || record.title.localizedStandardContains(keyword)
                || record.ownerName.localizedStandardContains(keyword)
                || record.loginName.localizedStandardContains(keyword)
                || record.accessKey.localizedStandardContains(keyword)
                || record.apiKey.localizedStandardContains(keyword))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var visibleMemos: [Memo] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.library.memos.filter { keyword.isEmpty || $0.title.localizedStandardContains(keyword) || $0.body.localizedStandardContains(keyword) }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private func matches(_ context: CredentialContext?) -> Bool {
        (categoryFilter.isEmpty || context?.category == categoryFilter) &&
        (roleFilter.isEmpty || (context?.role?.rawValue ?? "unspecified") == roleFilter)
    }
    private func contextMatches(_ context: CredentialContext?, _ keyword: String) -> Bool {
        guard let context else { return false }
        return [context.category, context.resource, context.notes, context.role?.label ?? ""].contains { $0.localizedStandardContains(keyword) }
    }
    private var credentialFilters: some View {
        HStack(spacing: 10) {
            Picker("用途", selection: $categoryFilter) {
                Text("全部用途").tag("")
                ForEach(Array(Set((store.library.accounts.compactMap { $0.context?.category } + store.library.secrets.compactMap { $0.context?.category }).filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0).tag($0) }
            }
            Picker("关系", selection: $roleFilter) {
                Text("全部关系").tag("")
                Text("未指定").tag("unspecified")
                ForEach(AccountRole.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
            }
            if pane == .secrets {
                Picker("类型", selection: $kindFilter) {
                    Text("全部类型").tag(Optional<SecretKind>.none)
                    ForEach(SecretKind.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
            }
        }.labelsHidden().font(.system(size: 11)).padding(.horizontal, 26).padding(.bottom, 12)
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 192)
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                header
                search.padding(.horizontal, 26).padding(.bottom, 18)
                if pane == .accounts || pane == .secrets { credentialFilters }
                if store.isLocked { recovery }
                else if mainList.isEmpty { emptyState }
                else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(mainList) { item in card(for: item) }
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
        .sheet(item: $accountDraft) { account in
            AccountEditor(store: store, original: account) { accountDraft = nil }
        }
        .sheet(item: $secretDraft) { secret in
            SecretEditor(store: store, original: secret) { secretDraft = nil }
        }
        .sheet(item: $memoDraft) { memo in MemoEditor(store: store, original: memo) { memoDraft = nil } }
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
                    }), pane == .project(project.id) { pane = .allPrompts }
                }
                deleteProject = nil
            }
        } message: {
            Text("将删除“\(deleteProject?.name ?? "")”及其中 \(store.library.prompts.filter { $0.projectID == deleteProject?.id }.count) 条提示词。建议先导出备份。")
        }
        .alert("删除这个账号？", isPresented: Binding(get: { deleteAccount != nil }, set: { if !$0 { deleteAccount = nil } })) {
            Button("取消", role: .cancel) { deleteAccount = nil }
            Button("删除", role: .destructive) {
                if let account = deleteAccount { store.update { $0.accounts.removeAll { $0.id == account.id } } }
                deleteAccount = nil
            }
        } message: { Text("“\(deleteAccount?.title ?? "")”将从账号库中移除。建议确认已有其他地方留存。") }
        .alert("删除这个密钥？", isPresented: Binding(get: { deleteSecret != nil }, set: { if !$0 { deleteSecret = nil } })) {
            Button("取消", role: .cancel) { deleteSecret = nil }
            Button("删除", role: .destructive) {
                if let secret = deleteSecret { store.update { $0.secrets.removeAll { $0.id == secret.id } } }
                deleteSecret = nil
            }
        } message: { Text("“\(deleteSecret?.title ?? "")”将从密钥库中移除。建议确认已有其他地方留存。") }
        .alert("删除这条备忘录？", isPresented: Binding(get: { deleteMemo != nil }, set: { if !$0 { deleteMemo = nil } })) {
            Button("取消", role: .cancel) { deleteMemo = nil }
            Button("删除", role: .destructive) {
                if let memo = deleteMemo { store.update { $0.memos.removeAll { $0.id == memo.id } } }
                deleteMemo = nil
            }
        } message: { Text("这条备忘录将从本机资料库中移除。") }
        .onChange(of: pane) { _ in query = ""; categoryFilter = ""; roleFilter = ""; kindFilter = nil; revealed.removeAll() }
        .onChange(of: draft != nil || projectEditor || accountDraft != nil || secretDraft != nil || memoDraft != nil) { store.holdOpen?($0) }
    }

    private var mainList: [CardItem] {
        switch pane {
        case .memos: return visibleMemos.map { CardItem(id: $0.id, kind: .memo($0)) }
        case .accounts: return visibleAccounts.map { CardItem(id: $0.id, kind: .account($0)) }
        case .secrets: return visibleSecrets.map { CardItem(id: $0.id, kind: .secret($0)) }
        default: return visiblePrompts.map { CardItem(id: $0.id, kind: .prompt($0)) }
        }
    }
    private struct CardItem: Identifiable {
        enum Content {
            case prompt(Prompt)
            case account(AccountCredential)
            case secret(SecretRecord)
            case memo(Memo)
        }
        let id: UUID
        let kind: Content
    }
    @ViewBuilder private func card(for item: CardItem) -> some View {
        switch item.kind {
        case .prompt(let prompt): promptCard(prompt)
        case .account(let account): accountCard(account)
        case .secret(let secret): secretCard(secret)
        case .memo(let memo): memoCard(memo)
        }
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
            }.padding(.top, 28).padding(.bottom, 24).padding(.horizontal, 18)
            VStack(spacing: 5) {
                navigationRow("全部提示词", icon: "square.grid.2x2", count: store.library.prompts.count, active: pane == .allPrompts) {
                    pane = .allPrompts
                }
                navigationRow("常用置顶", icon: "pin", count: store.library.prompts.filter(\.isPinned).count, active: pane == .pinned) {
                    pane = .pinned
                }
            }.padding(.horizontal, 12)
            HStack {
                Text("我的项目").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                Spacer()
                Button { openProjectEditor(nil) } label: { Image(systemName: "plus").font(.system(size: 11)) }
                    .buttonStyle(QuietButton()).help("新建项目").accessibilityLabel("新建项目")
                    .disabled(store.isLocked)
            }.padding(.horizontal, 21).padding(.top, 18).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(store.library.projects) { project in
                        navigationRow(project.name, icon: "folder", count: store.library.prompts.filter { $0.projectID == project.id }.count, active: pane == .project(project.id)) {
                            pane = .project(project.id)
                        }.contextMenu {
                            Button("重命名项目") { openProjectEditor(project) }
                            Button("删除项目…", role: .destructive) { deleteProject = project }
                        }
                    }
                    HStack {
                        Text("随身资料").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                        Spacer()
                    }.padding(.top, 18).padding(.bottom, 4)
                    navigationRow("账号密码", icon: "person.crop.circle", count: store.library.accounts.count, active: pane == .accounts) {
                        pane = .accounts
                    }
                    navigationRow("密钥", icon: "key", count: store.library.secrets.count, active: pane == .secrets) {
                        pane = .secrets
                    }
                    navigationRow("备忘录", icon: "note.text", count: store.library.memos.count, active: pane == .memos) { pane = .memos }
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
                    Button("快速搜索  ⌥⌘P / ⌃⌘P") {
                        NotificationCenter.default.post(name: .promptPinPresentQuickSearch, object: nil)
                    }
                    Divider()
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
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            Button(action: newItem) { Label(newItemLabel, systemImage: "plus") }
                .buttonStyle(SpringButton(filled: true)).keyboardShortcut("n")
                .disabled(store.isLocked)
        }.padding(.horizontal, 26).padding(.top, 28).padding(.bottom, 24)
    }

    private var newItemLabel: String {
        switch pane {
        case .accounts: return "新建账号"
        case .secrets: return "新建密钥"
        case .memos: return "新建备忘录"
        default: return "新建提示词"
        }
    }
    private func newItem() {
        switch pane {
        case .memos: memoDraft = Memo()
        case .accounts:
            accountDraft = AccountCredential(title: "", subAccount: "", password: "")
        case .secrets:
            secretDraft = SecretRecord(kind: .accessKeys, title: "")
        default:
            let projectID: UUID?
            if case .project(let id) = pane { projectID = id } else { projectID = nil }
            guard let id = projectID ?? store.library.projects.first?.id else { openProjectEditor(nil); return }
            draft = Prompt(projectID: id, title: "", body: "")
        }
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField(searchPlaceholder, text: $query)
                .textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).accessibilityLabel("清除搜索")
            }
            Button { searchFocused = true } label: { Text("⌘ F").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                .buttonStyle(.plain).keyboardShortcut("f").accessibilityLabel("搜索")
        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line, lineWidth: 1))
    }
    private var searchPlaceholder: String {
        switch pane {
        case .accounts: return "搜索备注名或账号…"
        case .secrets: return "搜索名称、用途、资源或账号…"
        case .memos: return "搜索备忘录标题或正文…"
        default: return "搜索标题、内容或项目…"
        }
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

    private func accountCard(_ account: AccountCredential) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text("账号").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.green).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.mint.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                Spacer()
                Menu {
                    Button("编辑账号") { accountDraft = account }
                    Button("复制一份") {
                        var duplicate = account; duplicate.id = UUID(); duplicate.title += " · 副本"; accountDraft = duplicate
                    }
                    Divider()
                    Button("删除…", role: .destructive) { deleteAccount = account }
                } label: { Image(systemName: "ellipsis").font(.system(size: 13)) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("账号操作")
            }
            contextSummary(account.context)
            Button { accountDraft = account } label: {
                Text(account.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("查看与编辑账号")
            VStack(alignment: .leading, spacing: 7) {
                if let resource = account.context?.resource, !resource.isEmpty {
                    credentialRow("资源 / 项目", value: resource, recordID: account.id, field: "account-\(account.id)-resource")
                }
                if !account.mainAccount.isEmpty && !(account.context?.role == .primary && account.mainAccount == account.loginName) {
                    credentialRow("主账号", value: account.mainAccount, recordID: account.id, field: "account-\(account.id)-main")
                }
                if !account.loginName.isEmpty { credentialRow((account.context ?? CredentialContext()).usernameLabel, value: account.loginName, recordID: account.id, field: "account-\(account.id)-sub") }
                credentialRow("密码", value: account.password, isSecret: true, recordID: account.id, field: "account-\(account.id)-password")
            }
        }.padding(17).background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.line.opacity(0.75), lineWidth: 1))
    }

    private func secretCard(_ secret: SecretRecord) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text(secret.kind.label).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.green).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.mint.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                Spacer()
                Menu {
                    Button("编辑密钥") { secretDraft = secret }
                    Button("复制一份") {
                        var duplicate = secret
                        duplicate.id = UUID()
                        duplicate.title = secret.title + " · 副本"
                        secretDraft = duplicate
                    }
                    Divider()
                    Button("删除…", role: .destructive) { deleteSecret = secret }
                } label: { Image(systemName: "ellipsis").font(.system(size: 13)) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("密钥操作")
            }
            contextSummary(secret.context)
            Button { secretDraft = secret } label: {
                Text(secret.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("查看与编辑密钥")
            VStack(alignment: .leading, spacing: 7) {
                if let resource = secret.context?.resource, !resource.isEmpty {
                    credentialRow("资源 / Bucket", value: resource, recordID: secret.id, field: "secret-\(secret.id)-resource")
                }
                if !secret.ownerName.isEmpty {
                    credentialRow("所属主账号", value: secret.ownerName, recordID: secret.id, field: "secret-\(secret.id)-main")
                }
                if !secret.loginName.isEmpty {
                    credentialRow((secret.context ?? CredentialContext()).usernameLabel, value: secret.loginName, recordID: secret.id, field: "secret-\(secret.id)-sub")
                }
                if secret.kind == .accessKeys {
                    credentialRow("AK", value: secret.accessKey, recordID: secret.id, field: "secret-\(secret.id)-ak")
                    credentialRow("SK", value: secret.secretKey, isSecret: true, recordID: secret.id, field: "secret-\(secret.id)-sk")
                    if !secret.endpoint.isEmpty { credentialRow("Endpoint", value: secret.endpoint, recordID: secret.id, field: "secret-\(secret.id)-baseurl") }
                } else {
                    if !secret.model.isEmpty {
                        credentialRow("Model", value: secret.model, recordID: secret.id, field: "secret-\(secret.id)-model")
                    }
                    credentialRow(secret.kind.label, value: secret.apiKey, isSecret: true, recordID: secret.id, field: "secret-\(secret.id)-apikey")
                    if !secret.endpoint.isEmpty {
                        credentialRow("Base URL", value: secret.endpoint, recordID: secret.id, field: "secret-\(secret.id)-baseurl")
                    }
                }
            }
        }.padding(17).background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.line.opacity(0.75), lineWidth: 1))
    }

    @ViewBuilder private func contextSummary(_ context: CredentialContext?) -> some View {
        if let context {
            let summary = [context.category, context.role?.label ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
            if !summary.isEmpty { Text(summary).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(2) }
        }
    }
    private func memoCard(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { memoDraft = memo } label: { Text(memo.title).font(.system(size: 15, weight: .semibold)) }.buttonStyle(.plain)
                Spacer()
                Menu {
                    Button("编辑备忘录") { memoDraft = memo }
                    Button("删除…", role: .destructive) { deleteMemo = memo }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("备忘录操作")
            }
            Button { memoDraft = memo } label: {
                Text(memo.body).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack {
                Text(memo.updatedAt, style: .date).font(.system(size: 10)).foregroundStyle(Theme.muted)
                Spacer()
                Button { copyValue(memo.body, key: "memo-\(memo.id)") } label: {
                    Label(copiedKey == "memo-\(memo.id)" ? "已复制" : "复制内容", systemImage: "doc.on.doc")
                }.buttonStyle(SpringButton())
            }
        }.padding(17).background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.line))
    }

    private func credentialRow(_ label: String, value: String, isSecret: Bool = false, recordID: UUID, field: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(width: 84, alignment: .leading)
            Text(isSecret && !revealed.contains(recordID) ? mask(value) : value)
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.ink)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if isSecret {
                Button {
                    if revealed.contains(recordID) { revealed.remove(recordID) } else { revealed.insert(recordID) }
                } label: {
                    Image(systemName: revealed.contains(recordID) ? "eye.slash" : "eye").font(.system(size: 12))
                }.buttonStyle(QuietButton()).foregroundStyle(Theme.muted)
                    .help(revealed.contains(recordID) ? "隐藏" : "临时显示")
                    .accessibilityLabel(revealed.contains(recordID) ? "隐藏内容" : "显示内容")
            }
            Button { copyValue(value, key: field) } label: {
                Label(copiedKey == field ? "已复制" : "复制", systemImage: copiedKey == field ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
            }.buttonStyle(QuietButton()).foregroundStyle(Theme.green).help("复制\(label)")
        }
    }
    private func mask(_ value: String) -> String { String(repeating: "•", count: max(8, min(value.count, 14))) }
    private func copyValue(_ text: String, key: String) {
        guard store.copyText(text) else { return }
        copiedKey = key
        let generation = UUID(); copyGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if copyGeneration == generation { copiedKey = nil }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: store.isLocked ? "exclamationmark.triangle" : "checkmark.shield")
            Text(store.isLocked ? "数据需要修复" : "已保存到本机")
            Spacer()
            Text(store.notice ?? footerCount)
                .lineLimit(1)
        }.font(.system(size: 10)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 26).padding(.vertical, 14)
            .background(Theme.canvas)
    }
    private var footerCount: String {
        switch pane {
        case .accounts: return "\(visibleAccounts.count) 个账号"
        case .secrets: return "\(visibleSecrets.count) 个密钥"
        case .memos: return "\(visibleMemos.count) 条备忘录"
        default: return "\(visiblePrompts.count) 条提示词 · 点击卡片编辑"
        }
    }

    private var emptyState: some View {
        switch pane {
        case .memos: return AnyView(VStack(spacing: 16) {
            Image(systemName: "note.text").font(.largeTitle).foregroundStyle(Theme.green)
            Text(query.isEmpty ? "记下此刻想到的" : "没有找到相关备忘录").font(.headline)
            Button(query.isEmpty ? "新建备忘录" : "清除搜索") { if query.isEmpty { newItem() } else { query = "" } }.buttonStyle(SpringButton())
        }.frame(maxWidth: .infinity, maxHeight: .infinity))
        case .accounts: return AnyView(accountEmptyState)
        case .secrets: return AnyView(secretEmptyState)
        default: return AnyView(promptEmptyState)
        }
    }
    private var promptEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: query.isEmpty ? "text.badge.plus" : "magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(Theme.green)
            Text(query.isEmpty ? "留住下一句好提示" : "没有找到相关提示词").font(.system(size: 17, weight: .semibold))
            Text(query.isEmpty ? (pane == .pinned ? "点击提示词上的图钉，常用内容就会出现在这里。" : "把经常输入的内容存下来，下次一键复制。") : "试试更短的关键词，或切换到全部提示词。")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if !query.isEmpty {
                Button("清除筛选") { query = ""; pane = .allPrompts }.buttonStyle(SpringButton())
            } else if pane != .pinned {
                Button("创建第一条提示词", action: newItem).buttonStyle(SpringButton(filled: true))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(26)
    }
    private var accountEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: query.isEmpty ? "person.crop.circle.badge.plus" : "magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(Theme.green)
            Text(store.library.accounts.isEmpty ? "收好第一个账号" : "没有找到相关账号").font(.system(size: 17, weight: .semibold))
            Text(query.isEmpty ? "名称和密码必填，账号关系、用户名与用途均可选。" : "试试更短的关键词。")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if !query.isEmpty || !categoryFilter.isEmpty || !roleFilter.isEmpty || kindFilter != nil {
                Button("清除筛选") { query = ""; categoryFilter = ""; roleFilter = ""; kindFilter = nil }.buttonStyle(SpringButton())
            } else {
                Button("新建账号", action: newItem).buttonStyle(SpringButton(filled: true))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(26)
    }
    private var secretEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: query.isEmpty ? "key.fill" : "magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(Theme.green)
            Text(store.library.secrets.isEmpty ? "收好第一个密钥" : "没有找到相关密钥").font(.system(size: 17, weight: .semibold))
            Text(query.isEmpty ? "支持 AK/SK、API Key、Token、SSH、证书及自定义凭据。" : "试试更短的关键词。")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if !query.isEmpty || !categoryFilter.isEmpty || !roleFilter.isEmpty || kindFilter != nil {
                Button("清除筛选") { query = ""; categoryFilter = ""; roleFilter = ""; kindFilter = nil }.buttonStyle(SpringButton())
            } else {
                Button("新建密钥", action: newItem).buttonStyle(SpringButton(filled: true))
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
        }) { pane = .project(id); projectEditor = false }
        else { projectError = store.error; store.error = nil }
    }
    private func openProjectEditor(_ project: Project?) {
        projectToRename = project; projectName = project?.name ?? ""; projectError = nil; projectEditor = true
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
