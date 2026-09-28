import SwiftUI
import PromptPinCore

private extension View {
    func fieldBox() -> some View {
        font(.system(size: 13)).padding(11)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }
}
private struct LabeledField: View {
    let label: String
    @Binding var value: String
    var optional = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label + (optional ? " · 可选" : "")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
            TextField(label, text: $value).textFieldStyle(.plain).fieldBox().accessibilityLabel(label)
        }
    }
}
private struct ProtectedField: View {
    let label: String
    @Binding var value: String
    var multiline = false
    @State private var revealed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                Spacer()
                Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye") }
                    .buttonStyle(QuietButton()).accessibilityLabel(revealed ? "隐藏内容" : "显示内容")
            }
            if revealed && multiline {
                TextEditor(text: $value).font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden).frame(height: 130).fieldBox().accessibilityLabel(label)
            } else if revealed {
                TextField(label, text: $value).textFieldStyle(.plain).fieldBox().accessibilityLabel(label)
            } else {
                SecureField(label, text: $value).textFieldStyle(.plain).fieldBox().accessibilityLabel(label)
            }
            if multiline { Text("可直接粘贴完整内容；点击眼睛展开多行编辑。").font(.system(size: 10)).foregroundStyle(Theme.muted) }
        }
    }
}
private struct ContextFields: View {
    @Binding var context: CredentialContext
    @Binding var mainAccount: String
    @Binding var username: String
    private let categories = ["云平台", "对象存储 / 存储桶", "网站 / 应用", "大模型 / AI 服务", "数据库", "服务器 / SSH", "代码托管 / CI", "企业平台", "其他 / 自定义"]
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Picker("用途 · 可选", selection: $context.category) {
                Text("未指定").tag("")
                ForEach(categories, id: \.self) { Text($0).tag($0) }
                if !context.category.isEmpty && !categories.contains(context.category) { Text(context.category).tag(context.category) }
            }.pickerStyle(.menu)
            Picker("账号关系 · 可选", selection: $context.role) {
                Text("未指定").tag(Optional<AccountRole>.none)
                ForEach(AccountRole.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }.pickerStyle(.menu)
            LabeledField(label: context.usernameLabel, value: $username, optional: true)
            if context.role != .primary || mainAccount != username {
            DisclosureGroup("所属主账号 / 租户（可选）") {
                LabeledField(label: "所属主账号 / 租户", value: $mainAccount, optional: true).padding(.top, 7)
            }
            if !mainAccount.isEmpty {
                Text("已保留所属主账号信息，可展开查看和编辑。").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            }
            LabeledField(label: "资源 / Bucket / 项目 / 环境", value: $context.resource, optional: true)
            LabeledField(label: "备注", value: $context.notes, optional: true)
        }.font(.system(size: 12))
    }
}

struct AccountEditor: View {
    @ObservedObject var store: Store
    let original: AccountCredential
    let dismiss: () -> Void
    @State private var account: AccountCredential
    @State private var context: CredentialContext
    @State private var discard = false
    @State private var saveError: String?
    init(store: Store, original: AccountCredential, dismiss: @escaping () -> Void) {
        self.store = store; self.original = original; self.dismiss = dismiss
        _account = State(initialValue: original)
        _context = State(initialValue: original.context ?? CredentialContext())
    }
    private var changed: Bool { account != original || context != (original.context ?? CredentialContext()) }
    private var valid: Bool { !account.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !account.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(original.title.isEmpty ? "新建账号密码" : "编辑账号密码").font(.system(size: 23, weight: .semibold))
            Text("普通账号、主子账号、服务账号都可以，关系可留空。").font(.system(size: 11)).foregroundStyle(Theme.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledField(label: "名称", value: $account.title)
                    ProtectedField(label: "密码", value: $account.password)
                    ContextFields(context: $context, mainAccount: $account.mainAccount, username: Binding(get: { account.loginName }, set: { account.username = $0 }))
                }.padding(2)
            }
            if let saveError { Text(saveError).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Button("取消") { if changed { discard = true } else { dismiss() } }.buttonStyle(SpringButton()).keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存账号", action: save).buttonStyle(SpringButton(filled: true)).keyboardShortcut("s").disabled(!valid)
            }
        }.padding(26).frame(width: 510, height: 510).background(Theme.canvas).foregroundStyle(Theme.ink).tint(Theme.green)
            .interactiveDismissDisabled(changed)
            .alert("放弃未保存的修改？", isPresented: $discard) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃修改", role: .destructive) { dismiss() }
            }
    }
    private func save() {
        guard valid else { return }
        var saved = account
        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.context = context == CredentialContext() && original.context == nil ? nil : context
        saved.updatedAt = Date()
        if store.update({ library in
            if let i = library.accounts.firstIndex(where: { $0.id == saved.id }) { library.accounts[i] = saved }
            else { library.accounts.append(saved) }
        }) { dismiss() } else { saveError = store.error; store.error = nil }
    }
}

struct SecretEditor: View {
    @ObservedObject var store: Store
    let original: SecretRecord
    let dismiss: () -> Void
    @State private var record: SecretRecord
    @State private var context: CredentialContext
    @State private var discard = false
    @State private var saveError: String?
    init(store: Store, original: SecretRecord, dismiss: @escaping () -> Void) {
        self.store = store; self.original = original; self.dismiss = dismiss
        _record = State(initialValue: original)
        _context = State(initialValue: original.context ?? CredentialContext())
    }
    private var changed: Bool { record != original || context != (original.context ?? CredentialContext()) }
    private var valid: Bool {
        let nonempty = { (s: String) in !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return nonempty(record.title) && (record.kind == .accessKeys ? nonempty(record.accessKey) && nonempty(record.secretKey) : nonempty(record.apiKey))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(original.title.isEmpty ? "新建密钥" : "编辑密钥").font(.system(size: 23, weight: .semibold))
            Text("按凭据格式选择类型，账号和用途都可留空。").font(.system(size: 11)).foregroundStyle(Theme.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("凭据类型", selection: $record.kind) {
                        ForEach(SecretKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.menu)
                    LabeledField(label: "名称", value: $record.title)
                    if record.kind == .accessKeys {
                        LabeledField(label: "Access Key ID / AK", value: $record.accessKey)
                        ProtectedField(label: "Secret Access Key / SK", value: $record.secretKey)
                    } else {
                        ProtectedField(label: record.kind.label, value: $record.apiKey, multiline: [.sshKey, .certificate, .custom].contains(record.kind))
                        if record.kind == .apiKey { LabeledField(label: "Model", value: $record.model, optional: true) }
                    }
                    LabeledField(label: "Endpoint / Base URL / 登录地址", value: Binding(get: { record.endpoint }, set: { record.endpointURL = $0 }), optional: true)
                    ContextFields(context: $context, mainAccount: Binding(get: { record.ownerName }, set: { record.ownerAccount = $0 }), username: Binding(get: { record.loginName }, set: { record.username = $0 }))
                    if record.kind != original.kind {
                        Text("切换类型不会删除旧字段；切回原类型仍可查看。").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }.padding(2)
            }
            if let saveError { Text(saveError).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Button("取消") { if changed { discard = true } else { dismiss() } }.buttonStyle(SpringButton()).keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存密钥", action: save).buttonStyle(SpringButton(filled: true)).keyboardShortcut("s").disabled(!valid)
            }
        }.padding(26).frame(width: 510, height: 510).background(Theme.canvas).foregroundStyle(Theme.ink).tint(Theme.green)
            .interactiveDismissDisabled(changed)
            .alert("放弃未保存的修改？", isPresented: $discard) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃修改", role: .destructive) { dismiss() }
            }
    }
    private func save() {
        guard valid else { return }
        var saved = record
        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.context = context == CredentialContext() && original.context == nil ? nil : context
        saved.updatedAt = Date()
        // Preserve all existing values, including whitespace and fields hidden by another type.
        if store.update({ library in
            if let i = library.secrets.firstIndex(where: { $0.id == saved.id }) { library.secrets[i] = saved }
            else { library.secrets.append(saved) }
        }) { dismiss() } else { saveError = store.error; store.error = nil }
    }
}
