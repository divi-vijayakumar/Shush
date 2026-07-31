import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingAddSecret = false
    @State private var showingImporter = false
    @State private var showingSweep = false
    @State private var showingCLIAccess = false
    @State private var showingProfile = false
    @State private var showingProfiles = false
    @State private var confirmingBulkDelete = false
    @State private var confirmingBulkRetire = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } content: {
            itemList
                .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 430)
        } detail: {
            if let item = model.selectedItem {
                ItemDetailView(item: item)
                    .id(item.id)
            } else if !model.selection.isEmpty {
                BulkSelectionView(count: model.selection.count)
            } else {
                EmptyDetailView()
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search Shush")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import Files", systemImage: "square.and.arrow.down")
                }
                Button {
                    showingSweep = true
                } label: {
                    Label("Secret Sweep", systemImage: "sparkle.magnifyingglass")
                }
                if !model.selection.isEmpty {
                    Button {
                        confirmingBulkRetire = true
                    } label: {
                        Label("Retire Selected", systemImage: "archivebox")
                    }
                    .disabled(!selectionContainsActiveItems)
                    Button(role: .destructive) {
                        confirmingBulkDelete = true
                    } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                }
                Button {
                    showingAddSecret = true
                } label: {
                    Label("Add Secret", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $showingAddSecret) {
            AddSecretView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showingSweep) {
            SecretSweepView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showingCLIAccess) {
            CLIAccessView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showingProfiles) {
            ProfilesView()
                .environmentObject(model)
        }
        .alert("Retire \(model.selection.count) selected item\(model.selection.count == 1 ? "" : "s")?", isPresented: $confirmingBulkRetire) {
            Button("Cancel", role: .cancel) {}
            Button("Retire") {
                Task { await model.retireSelected() }
            }
        } message: {
            Text("This marks the selected items as retired in Shush. It does not revoke credentials at their providers.")
        }
        .alert("Permanently delete \(model.selection.count) selected item\(model.selection.count == 1 ? "" : "s")?", isPresented: $confirmingBulkDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive) {
                Task { await model.deleteSelected() }
            }
        } message: {
            Text("Every encrypted value for the selected items will be removed. This cannot be undone.")
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await model.importFiles(urls) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddSecret)) { _ in
            showingAddSecret = true
        }
        .overlay(alignment: .bottom) {
            if let notice = model.clipboardNotice {
                Toast(text: notice)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation { model.clipboardNotice = nil }
                    }
                    .padding(.bottom, 22)
            }
        }
    }

    private var selectionContainsActiveItems: Bool {
        model.items.contains { model.selection.contains($0.id) && !$0.isRetired }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ShushMark(size: 38)
                Menu {
                    ForEach(model.profiles) { profile in
                        Button {
                            Task { await model.switchProfile(to: profile.id) }
                        } label: {
                            if profile.id == model.activeProfileID {
                                Label(profile.label, systemImage: "checkmark")
                            } else {
                                Text(profile.label)
                            }
                        }
                    }
                    Divider()
                    Button {
                        showingProfiles = true
                    } label: {
                        Label(
                            model.pendingProfileRequests.isEmpty
                                ? "Manage Profiles…"
                                : "Manage Profiles… (\(model.pendingProfileRequests.count) request\(model.pendingProfileRequests.count == 1 ? "" : "s"))",
                            systemImage: "person.2"
                        )
                    }
                    Button {
                        showingProfile = true
                    } label: {
                        Label("Account Settings…", systemImage: "person.crop.circle")
                    }
                    Button {
                        showingCLIAccess = true
                    } label: {
                        Label("CLI Access…", systemImage: "terminal")
                    }
                    Divider()
                    Button {
                        model.signOut()
                    } label: {
                        Label("Lock Shush", systemImage: "lock")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(model.activeProfile?.label ?? "Shush")
                                .font(.headline)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        Text(model.activeProfile?.email ?? "Local vault")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .menuStyle(.borderlessButton)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)

            List(ItemFilter.allCases, selection: $model.filter) { itemFilter in
                Label(itemFilter.label, systemImage: itemFilter.symbol)
                    .tag(itemFilter)
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(.mint)
                        .frame(width: 8, height: 8)
                    Text("Agent Vault running")
                        .font(.caption.weight(.medium))
                }
                Text("\(model.items.count) encrypted item\(model.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var itemList: some View {
        Group {
            if model.filteredItems.isEmpty {
                DropZone(
                    hasItems: !model.items.isEmpty,
                    onBrowse: { showingImporter = true },
                    onURLs: { urls in Task { await model.importFiles(urls) } }
                )
            } else {
                List(selection: $model.selection) {
                    Section {
                        ForEach(model.filteredItems) { item in
                            ItemRow(item: item)
                                .tag(item.id)
                        }
                    } header: {
                        HStack {
                            Text(model.filter.label)
                            Spacer()
                            Text("\(model.filteredItems.count)")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .listStyle(.inset)
                .safeAreaInset(edge: .bottom) {
                    DropStrip { urls in
                        Task { await model.importFiles(urls) }
                    }
                }
            }
        }
        .navigationTitle(model.filter.label)
    }
}

private struct ItemRow: View {
    @EnvironmentObject private var model: AppModel
    let item: ShushItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.indigo.opacity(0.11))
                Image(systemName: item.kind.symbol)
                    .foregroundStyle(.indigo)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if item.isRetired {
                        Text("RETIRED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }
                }
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.duplicateCount(for: item) > 0 {
                Image(systemName: "square.on.square")
                    .foregroundStyle(.orange)
                    .help("Possible duplicate")
            }
            Text(item.savedAt, format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }
}

private struct DropZone: View {
    let hasItems: Bool
    let onBrowse: () -> Void
    let onURLs: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(targeted ? 0.18 : 0.09))
                    .frame(width: 86, height: 86)
                Image(systemName: targeted ? "arrow.down.doc.fill" : "lock.doc.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.indigo)
            }
            Text(hasItems ? "Nothing matches your search" : "Drop secrets here")
                .font(.title2.bold())
            Text(
                hasItems
                    ? "Try another filter or import a new file."
                    : "JSON, TFVars, .env, YAML, certificates,\nand other files stay encrypted in Agent Vault."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            Button("Choose Files…", action: onBrowse)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            onURLs(urls)
            return true
        } isTargeted: { targeted = $0 }
    }
}

private struct DropStrip: View {
    let onURLs: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        HStack {
            Image(systemName: "arrow.down.doc")
            Text(targeted ? "Release to encrypt" : "Drop more files")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(targeted ? .indigo : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.bar)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            onURLs(urls)
            return true
        } isTargeted: { targeted = $0 }
    }
}

private struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("Select an item")
                .font(.title3.bold())
            Text("Values stay hidden until you explicitly reveal them.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

private struct BulkSelectionView: View {
    let count: Int

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 42))
                .foregroundStyle(.indigo)
            Text("\(count) item\(count == 1 ? "" : "s") selected")
                .font(.title3.bold())
            Text("Use the toolbar to retire or permanently delete the selection.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

private struct Toast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThickMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}
