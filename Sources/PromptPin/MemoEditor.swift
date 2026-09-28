import SwiftUI
import PromptPinCore

struct MemoEditor: View {
    @ObservedObject var store: Store
    let original: Memo
    let dismiss: () -> Void
    @State private var title: String
    @State private var content: String
    @State private var discard = false
    @State private var saveError: String?
    @FocusState private var titleFocused: Bool

    init(store: Store, original: Memo, dismiss: @escaping () -> Void) {
        self.store = store; self.original = original; self.dismiss = dismiss
        _title = State(initialValue: original.title)
        _content = State(initialValue: original.body)
    }
    private var changed: Bool { title != original.title || content != original.body }
    private var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(original.title.isEmpty ? "写一条备忘录" : "编辑备忘录").font(.system(size: 23, weight: .semibold))
                    Text("随手记下，随时找回。").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "text.quote").font(.system(size: 26)).foregroundStyle(Theme.green)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("标题").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                TextField("给备忘录起一个好找的名字", text: $title).textFieldStyle(.plain)
                    .font(.system(size: 14)).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                    .focused($titleFocused)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("备忘录内容").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("\(content.count) 字").font(.system(size: 10))
                }.foregroundStyle(Theme.muted)
                TextEditor(text: $content).font(.system(size: 13)).lineSpacing(5)
                    .scrollContentBackground(.hidden).padding(10)
                    .frame(minHeight: 210).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                    .accessibilityLabel("备忘录内容")
            }
            if let saveError { Text(saveError).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Button("取消") { if changed { discard = true } else { dismiss() } }
                    .buttonStyle(SpringButton()).keyboardShortcut(.cancelAction)
                Spacer()
                Text("⌘ S 保存").font(.system(size: 10)).foregroundStyle(Theme.muted)
                Button("保存备忘录", action: save).buttonStyle(SpringButton(filled: true))
                    .keyboardShortcut("s").disabled(!valid)
            }
        }.padding(28).frame(width: 534, height: 510).background(Theme.canvas)
            .foregroundStyle(Theme.ink).tint(Theme.green)
            .onAppear { titleFocused = original.title.isEmpty }
            .interactiveDismissDisabled(changed)
            .alert("放弃未保存的修改？", isPresented: $discard) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃修改", role: .destructive) { dismiss() }
            } message: { Text("尚未保存的内容会丢失。") }
    }
    private func save() {
        guard valid else { return }
        var prompt = original
        prompt.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        prompt.body = content; prompt.updatedAt = Date()
        if store.update({ library in
            if let i = library.memos.firstIndex(where: { $0.id == prompt.id }) { library.memos[i] = prompt }
            else { library.memos.append(prompt) }
        }) { dismiss() }
        else { saveError = store.error; store.error = nil }
    }
}
