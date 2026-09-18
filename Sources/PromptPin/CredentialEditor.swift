import SwiftUI
import PromptPinCore

private struct FieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: 13)).padding(11)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }
}
private extension View {
    func fieldBox() -> some View { modifier(FieldBox()) }
}

private struct FieldLabel: View {
    let text: String
    var optional = false
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            if optional { Text("可选").font(.system(size: 9)).foregroundStyle(Theme.muted.opacity(0.8)) }
        }.font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
    }
}

struct AccountEditor: View {
    @ObservedObject var store: Store
    let original: AccountCredential
    let dismiss: () -> Void
    @State private var title: String
    @State private var mainAccount: String
    @State private var subAccount: String
    @State private var password: String
    @State private var showPassword = false
    @State private var discard = false
    @State private var saveError: String?

    init(store: Store, original: AccountCredential, dismiss: @escaping () -> Void) {
        self.store = store; self.original = original; self.dismiss = dismiss
        _title = State(initialValue: original.title)
        _mainAccount = State(initialValue: original.mainAccount)
        _subAccount = State(initialValue: original.subAccount)
        _password = State(initialValue: original.password)
    }
    private var changed: Bool {
        title != original.title || mainAccount != original.mainAccount
            || subAccount != original.subAccount || password != original.password
    }
    private var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !subAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(original.title.isEmpty ? "收好一个账号" : "编辑账号").font(.system(size: 23, weight: .semibold))
                    Text("保存在本机，随用随取。").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "person.text.rectangle").font(.system(size: 26)).foregroundStyle(Theme.green)
            }
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: "备注名")
                TextField("例如：阿里云主控台", text: $title).textFieldStyle(.plain).fieldBox()
            }
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: "主账号", optional: true)
                TextField("有则填写，没有可留空", text: $mainAccount).textFieldStyle(.plain).fieldBox()
            }
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: "子账号（用户）")
                TextField("登录用户名", text: $subAccount).textFieldStyle(.plain).fieldBox()
            }
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: "密码")
                HStack {
                    if showPassword {
                        TextField("密码", text: $password).textFieldStyle(.plain)
                    } else {
                        SecureField("密码", text: $password).textFieldStyle(.plain)
                    }
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye").font(.system(size: 12))
                    }.buttonStyle(QuietButton()).foregroundStyle(Theme.muted)
                        .accessibilityLabel(showPassword ? "隐藏密码" : "显示密码")
                }.fieldBox()
            }
            if let saveError { Text(saveError).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Button("取消") { if changed { discard = true } else { dismiss() } }
                    .buttonStyle(SpringButton()).keyboardShortcut(.cancelAction)
                Spacer()
                Text("⌘ S 保存").font(.system(size: 10)).foregroundStyle(Theme.muted)
                Button("保存账号", action: save).buttonStyle(SpringButton(filled: true))
                    .keyboardShortcut("s").disabled(!valid)
            }
        }.padding(28).frame(width: 480).background(Theme.canvas)
            .foregroundStyle(Theme.ink).tint(Theme.green)
            .interactiveDismissDisabled(changed)
            .alert("放弃未保存的修改？", isPresented: $discard) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃修改", role: .destructive) { dismiss() }
            } message: { Text("尚未保存的内容会丢失。") }
    }
    private func save() {
        guard valid else { return }
        var account = original
        account.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        account.mainAccount = mainAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        account.subAccount = subAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        account.password = password; account.updatedAt = Date()
        if store.update({ library in
            if let i = library.accounts.firstIndex(where: { $0.id == account.id }) { library.accounts[i] = account }
            else { library.accounts.append(account) }
        }) { dismiss() }
        else { saveError = store.error; store.error = nil }
    }
}

struct SecretEditor: View {
    @ObservedObject var store: Store
    let original: SecretRecord
    let kindLocked: Bool
    let dismiss: () -> Void
    @State private var kind: SecretKind
    @State private var title: String
    @State private var mainAccount: String
    @State private var subAccount: String
    @State private var accessKey: String
    @State private var secretKey: String
    @State private var model: String
    @State private var apiKey: String
    @State private var baseURL: String
    @State private var showSecret = false
    @State private var discard = false
    @State private var saveError: String?

    init(store: Store, original: SecretRecord, kindLocked: Bool, dismiss: @escaping () -> Void) {
        self.store = store; self.original = original; self.kindLocked = kindLocked; self.dismiss = dismiss
        _kind = State(initialValue: original.kind)
        _title = State(initialValue: original.title)
        _mainAccount = State(initialValue: original.mainAccount)
        _subAccount = State(initialValue: original.subAccount)
        _accessKey = State(initialValue: original.accessKey)
        _secretKey = State(initialValue: original.secretKey)
        _model = State(initialValue: original.model)
        _apiKey = State(initialValue: original.apiKey)
        _baseURL = State(initialValue: original.baseURL)
    }
    private var changed: Bool {
        kind != original.kind || title != original.title || mainAccount != original.mainAccount
            || subAccount != original.subAccount || accessKey != original.accessKey || secretKey != original.secretKey
            || model != original.model || apiKey != original.apiKey || baseURL != original.baseURL
    }
    private var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && {
            switch kind {
            case .accessKeys:
                return !subAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .apiKey:
                return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(original.title.isEmpty ? "收好一个密钥" : "编辑密钥").font(.system(size: 23, weight: .semibold))
                    Text("保存在本机，随用随取。").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "key.fill").font(.system(size: 26)).foregroundStyle(Theme.green)
            }
            Picker("类型", selection: $kind) {
                Text("AK / SK").tag(SecretKind.accessKeys)
                Text("API Key（大模型服务等）").tag(SecretKind.apiKey)
            }.font(.system(size: 12)).pickerStyle(.segmented).disabled(kindLocked)
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: "备注名")
                TextField("例如：OpenAI 生产环境", text: $title).textFieldStyle(.plain).fieldBox()
            }
            if kind == .accessKeys {
                VStack(alignment: .leading, spacing: 7) {
                    FieldLabel(text: "主账号", optional: true)
                    TextField("有则填写，没有可留空", text: $mainAccount).textFieldStyle(.plain).fieldBox()
                }
                VStack(alignment: .leading, spacing: 7) {
                    FieldLabel(text: "子账号（用户）")
                    TextField("访问所用的用户名", text: $subAccount).textFieldStyle(.plain).fieldBox()
                }
                VStack(alignment: .leading, spacing: 7) {
                    FieldLabel(text: "AK")
                    TextField("Access Key ID", text: $accessKey).textFieldStyle(.plain).fieldBox()
                }
                secretField(title: "SK", placeholder: "Access Key Secret", text: $secretKey)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    FieldLabel(text: "Model", optional: true)
                    TextField("例如：gpt-4o，可留空", text: $model).textFieldStyle(.plain).fieldBox()
                }
                secretField(title: "API Key", placeholder: "sk-…", text: $apiKey)
                VStack(alignment: .leading, spacing: 7) {
                    FieldLabel(text: "Base URL", optional: true)
                    TextField("例如：https://api.openai.com/v1，可留空", text: $baseURL).textFieldStyle(.plain).fieldBox()
                }
            }
            if let saveError { Text(saveError).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Button("取消") { if changed { discard = true } else { dismiss() } }
                    .buttonStyle(SpringButton()).keyboardShortcut(.cancelAction)
                Spacer()
                Text("⌘ S 保存").font(.system(size: 10)).foregroundStyle(Theme.muted)
                Button("保存密钥", action: save).buttonStyle(SpringButton(filled: true))
                    .keyboardShortcut("s").disabled(!valid)
            }
        }.padding(28).frame(width: 480).background(Theme.canvas)
            .foregroundStyle(Theme.ink).tint(Theme.green)
            .interactiveDismissDisabled(changed)
            .alert("放弃未保存的修改？", isPresented: $discard) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃修改", role: .destructive) { dismiss() }
            } message: { Text("尚未保存的内容会丢失。") }
    }
    private func secretField(title label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: label)
            HStack {
                if showSecret { TextField(placeholder, text: text).textFieldStyle(.plain) }
                else { SecureField(placeholder, text: text).textFieldStyle(.plain) }
                Button { showSecret.toggle() } label: {
                    Image(systemName: showSecret ? "eye.slash" : "eye").font(.system(size: 12))
                }.buttonStyle(QuietButton()).foregroundStyle(Theme.muted)
                    .accessibilityLabel(showSecret ? "隐藏内容" : "显示内容")
            }.fieldBox()
        }
    }
    private func save() {
        guard valid else { return }
        var record = original
        record.kind = kind
        record.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        record.mainAccount = mainAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        record.subAccount = subAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        record.accessKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        record.secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        record.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        record.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        record.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updatedAt = Date()
        if store.update({ library in
            if let i = library.secrets.firstIndex(where: { $0.id == record.id }) { library.secrets[i] = record }
            else { library.secrets.append(record) }
        }) { dismiss() }
        else { saveError = store.error; store.error = nil }
    }
}
