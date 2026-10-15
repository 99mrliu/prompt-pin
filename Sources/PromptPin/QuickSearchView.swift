import SwiftUI
import PromptPinCore

@MainActor
final class QuickSearchModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var hits: [QuickSearchHit] = []
    @Published private(set) var selected = 0
    @Published private(set) var copiedTitle: String?
    @Published private(set) var inlineError: String?
    @Published private(set) var focusTick = UUID()
    @Published private(set) var panelHeight: CGFloat = 144

    static let barHeight: CGFloat = 56
    static let rowHeight: CGFloat = 46
    static let emptyHeight: CGFloat = 88
    static let maxVisible = 8

    private let store: Store
    /// Fired after a successful copy; the window controller shows the confirmation briefly then closes.
    var onCopied: (() -> Void)?

    init(store: Store) {
        self.store = store
        rebuild()
        panelHeight = computeHeight()
    }

    func reset() {
        query = ""
        copiedTitle = nil
        inlineError = nil
        selected = 0
        rebuild()
        panelHeight = computeHeight()
        focusTick = UUID()
    }

    func move(by delta: Int) {
        guard !hits.isEmpty else { return }
        selected = (selected + delta + hits.count) % hits.count
    }

    func select(_ index: Int) {
        guard hits.indices.contains(index) else { return }
        selected = index
    }

    func commit() {
        guard hits.indices.contains(selected) else { return }
        let hit = hits[selected]
        if store.copyText(hit.copyText) {
            copiedTitle = hit.title
            panelHeight = computeHeight()
            onCopied?()
        } else {
            inlineError = "无法写入剪贴板，请重试。"
        }
    }

    private func rebuild() {
        hits = QuickSearchIndex.hits(in: store.library, query: query, limit: Self.maxVisible)
        selected = min(selected, max(0, hits.count - 1))
    }

    private func computeHeight() -> CGFloat {
        if copiedTitle != nil { return Self.barHeight }
        let listHeight = hits.isEmpty ? Self.emptyHeight : CGFloat(hits.count) * Self.rowHeight
        return Self.barHeight + listHeight
    }

    func queryChanged(to newValue: String) {
        query = newValue
        inlineError = nil
        copiedTitle = nil
        selected = 0
        rebuild()
        panelHeight = computeHeight()
    }
}

struct QuickSearchView: View {
    @ObservedObject var model: QuickSearchModel
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar.frame(height: QuickSearchModel.barHeight)
            if model.copiedTitle == nil {
                Rectangle().fill(Theme.line).frame(height: 1)
                results.frame(height: model.panelHeight - QuickSearchModel.barHeight)
            }
        }
        .frame(width: 640)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        .onAppear { queryFocused = true }
        .onChange(of: model.focusTick) { _ in queryFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 11) {
            if let copiedTitle = model.copiedTitle {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17)).foregroundStyle(Theme.green)
                Text("已复制").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(copiedTitle).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
            } else {
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(Theme.green)
                TextField("搜索提示词、账号、密钥、备忘录，回车复制", text: Binding(
                    get: { model.query },
                    set: { model.queryChanged(to: $0) }))
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .focused($queryFocused)
                if let inlineError = model.inlineError {
                    Text(inlineError).font(.system(size: 11)).foregroundStyle(.red).lineLimit(1)
                }
                Spacer()
                Text("esc").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.line))
            }
        }
        .padding(.horizontal, 16)
    }

    private var results: some View {
        Group {
            if model.hits.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .light)).foregroundStyle(Theme.muted)
                    Text(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "最近编辑的内容会显示在这里"
                         : "没有找到匹配的内容")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.hits.enumerated()), id: \.element.id) { index, hit in
                        row(hit, index: index)
                    }
                }
            }
        }
    }

    private func row(_ hit: QuickSearchHit, index: Int) -> some View {
        let selected = index == model.selected
        return HStack(spacing: 10) {
            Text(hit.kind.label).font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.green).padding(.horizontal, 7).padding(.vertical, 3)
                .background(Theme.mint.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                if !hit.subtitle.isEmpty {
                    Text(hit.subtitle).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if selected {
                HStack(spacing: 4) {
                    Image(systemName: "return").font(.system(size: 10))
                    Text(hit.actionLabel).font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Theme.green)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: QuickSearchModel.rowHeight)
        .background(selected ? Theme.mint.opacity(0.5) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            model.select(index)
            model.commit()
        }
    }
}
