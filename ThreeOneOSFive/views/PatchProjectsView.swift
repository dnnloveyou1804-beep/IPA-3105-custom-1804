import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum PatchPackagePickerPolicy {
    static let packageType3105 = UTType(filenameExtension: "3105") ?? .data
    static let allowedContentTypes: [UTType] = [packageType3105, .data]
    static let copiesSelectedDocument = true
}

struct PatchProjectsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var draftCoordinator: PatchDraftCoordinator
    @StateObject private var store = PatchProjectStore()
    @State private var showCreate = false
    @State private var showImporter = false
    @State private var searchText = ""

    private var filteredItems: [PatchLibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.items }
        return store.items.filter { item in
            if item.packageURL.lastPathComponent.localizedCaseInsensitiveContains(query) {
                return true
            }
            guard let project = item.project else { return false }
            return project.name.localizedCaseInsensitiveContains(query)
                || project.allBundleIdentifiers.contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
                || project.directories.contains {
                    $0.relativePath.localizedCaseInsensitiveContains(query)
                }
                || project.rules.contains {
                    $0.relativePath.localizedCaseInsensitiveContains(query)
                        || $0.replacementFilename.localizedCaseInsensitiveContains(query)
                }
        }
    }

    init() {
#if targetEnvironment(simulator)
        _showCreate = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--simulate-patch-editor")
        )
#endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppSearchField(
                    text: $searchText,
                    prompt: language.text("patch.search"),
                    clearLabel: language.text("common.clear")
                )
                Divider()
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if store.items.isEmpty && !store.isBusy {
                            emptyState
                        } else if filteredItems.isEmpty && !searchText.isEmpty {
                            searchEmptyState
                        } else {
                            ForEach(filteredItems) { item in
                                itemRow(item)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color.black.ignoresSafeArea())
                .refreshable {
                    store.reload()
                }
            }
            .navigationTitle(language.text("patch.title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if store.isBusy {
                        ProgressView()
                    } else {
                        Menu {
                            Button {
                                showImporter = true
                            } label: {
                                Label(language.text("patch.import"), systemImage: "square.and.arrow.down")
                            }
                            Button {
                                showCreate = true
                            } label: {
                                Label(language.text("patch.new"), systemImage: "plus")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
                FileDocumentPicker(
                    allowedContentTypes: PatchPackagePickerPolicy.allowedContentTypes,
                    copiesSelectedDocument: PatchPackagePickerPolicy.copiesSelectedDocument,
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        showImporter = false
                        if case .success(let urls) = result, let url = urls.first {
                            store.importPackage(at: url)
                        }
                    },
                    onCancel: {
                        showImporter = false
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showCreate) {
                PatchProjectEditorView(
                    existingProject: nil,
                    passwordIsProtected: false
                ) { project, password in
                    store.create(project: project, password: password)
                }
            }
            .sheet(item: $draftCoordinator.request) { request in
                PatchProjectEditorView(
                    existingProject: nil,
                    passwordIsProtected: false,
                    initialDraft: request.draft
                ) { project, password in
                    store.create(project: project, password: password)
                    draftCoordinator.clear()
                }
            }
            .sheet(item: $store.passwordRequest, onDismiss: store.cancelUnlock) { _ in
                PatchUnlockView(store: store)
            }
            .alert(item: $store.alert) { alert in
                Alert(
                    title: Text(language.text(alert.titleKey)),
                    message: Text(alert.message(language: language)),
                    dismissButton: .default(Text(language.text("common.ok")))
                )
            }
            .onAppear(perform: consumeExternalImport)
            .onChange(of: draftCoordinator.importRequest?.id) { _ in
                consumeExternalImport()
            }
        }
    }

    private func consumeExternalImport() {
        guard let request = draftCoordinator.importRequest else { return }
        draftCoordinator.clearImport()
        store.importPackage(from: request.source)
    }

    @ViewBuilder
    private func itemRow(_ item: PatchLibraryItem) -> some View {
        if item.isLocked {
            Button { store.requestUnlock(for: item) } label: {
                PatchProjectRow(item: item, language: language, store: store)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                PatchProjectDetailView(store: store, projectID: item.id)
            } label: {
                PatchProjectRow(item: item, language: language, store: store)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text(language.text("patch.empty_title"))
                .font(.headline)
            Text(language.text("patch.empty_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(language.text("patch.new")) { showCreate = true }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(AppTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(.secondary)
            Text(language.text("patch.search_empty"))
                .font(.headline)
            Text(language.text("patch.search_empty_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}

private struct PatchProjectRow: View {
    let item: PatchLibraryItem
    let language: AppLanguage
    @ObservedObject var store: PatchProjectStore
    @State private var isWorking = false
    @State private var actionAlert: PatchStoreAlert?

    private var isApplied: Bool {
        DevicePatchService.latestReceipt(projectID: item.id) != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            AppRowIcon(systemName: item.isLocked ? "lock.doc.fill" : "shippingbox.fill")
                .shadow(color: isApplied ? AppTheme.accent.opacity(0.8) : Color.clear, radius: 5)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(item.project?.name ?? language.text("patch.locked_project"))
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                Text(item.isLocked
                     ? language.text("patch.tap_to_unlock")
                     : language.text(
                        item.summary.schemaVersion >= 2 ? "patch.workspace_items_count" : "patch.rules_count",
                        Int64((item.project?.rules.count ?? 0) + (item.project?.directories.count ?? 0))
                     ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            if item.summary.isPasswordProtected {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(language.text("patch.password_protected"))
            }
            
            if !item.isLocked {
                Toggle("", isOn: Binding(
                    get: { isApplied },
                    set: { newValue in
                        if newValue && !isApplied {
                            apply()
                        } else if !newValue && isApplied {
                            restore()
                        }
                    }
                ))
                .labelsHidden()
                .tint(AppTheme.accent)
                .disabled(isWorking)
                // Prevent toggle tap from triggering the NavigationLink
                .onTapGesture {}
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: isApplied ? AppTheme.accent.opacity(0.4) : Color.black.opacity(0.2), radius: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isApplied ? AppTheme.accent.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(language.text(alert.titleKey)),
                message: Text(alert.message(language: language)),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
    }

    private func apply() {
        guard let baseProject = item.project else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                let project = item.summary.schemaVersion >= 2
                    ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
                    : baseProject
                _ = try DevicePatchService.apply(project: project)
                await MainActor.run {
                    store.reload()
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.applied_message")
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: error.localizationKey, messageArgument: error.localizationArgument)
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.apply")
                }
            }
        }
    }

    private func restore() {
        guard let receipt = DevicePatchService.latestReceipt(projectID: item.id) else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.restore(receipt: receipt)
                await MainActor.run {
                    store.reload()
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.restored_message")
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: error.localizationKey, messageArgument: error.localizationArgument)
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.restore")
                }
            }
        }
    }
}

private struct PatchUnlockView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                SecureField(language.text("patch.password"), text: $password)
            }
            .navigationTitle(language.text("patch.unlock_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("patch.unlock")) {
                        store.unlock(password: password)
                        dismiss()
                    }
                    .disabled(password.isEmpty)
                }
            }
        }
    }
}

private struct PatchProjectDetailView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var store: PatchProjectStore
    let projectID: UUID
    @State private var showEditor = false
    @State private var editingRule: PatchRule?
    @State private var isWorking = false
    @State private var actionAlert: PatchStoreAlert?
    @State private var shareRequest: PatchShareRequest?

    private var item: PatchLibraryItem? {
        store.items.first(where: { $0.id == projectID })
    }

    private var receipt: PatchTransactionReceipt? {
        DevicePatchService.latestReceipt(projectID: projectID)
    }

    private var isWorkspaceProject: Bool {
        (item?.summary.schemaVersion ?? 1) >= 2
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let item, let project = item.project {
                    if isWorkspaceProject {
                        VStack(spacing: 16) {
                            Text(language.text("patch.workspace"))
                                .font(.headline)
                                .foregroundStyle(AppTheme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            ForEach(project.allBundleIdentifiers, id: \.self) { bundleID in
                                Label {
                                    Text(bundleID)
                                        .font(.subheadline.monospaced())
                                } icon: {
                                    Image(systemName: "app.dashed")
                                        .foregroundStyle(AppTheme.accent)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            HStack {
                                Text(language.text("patch.files"))
                                Spacer()
                                Text("\(project.rules.count)")
                            }
                            HStack {
                                Text(language.text("patch.folders"))
                                Spacer()
                                Text("\(project.directories.count)")
                            }
                            
                            if let workspaceURL = item.workspaceURL {
                                NavigationLink {
                                    FileBrowserView(
                                        containerPath: workspaceURL.path,
                                        title: project.name,
                                        bundleID: nil
                                    )
                                } label: {
                                    Label(
                                        language.text("patch.open_workspace"),
                                        systemImage: "folder"
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                    } else {
                        VStack(spacing: 16) {
                            Text(language.text("patch.rules"))
                                .font(.headline)
                                .foregroundStyle(AppTheme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                            ForEach(project.rules) { rule in
                                Button {
                                    editingRule = rule
                                } label: {
                                    HStack(spacing: 10) {
                                        ruleSummary(rule)
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(language.text("patch.edit_rule_hint"))
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                    }

                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: item.summary.isPasswordProtected ? "lock.fill" : "lock.open")
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 24)
                            Text(language.text(item.summary.isPasswordProtected
                                ? "patch.password_locked"
                                : "patch.no_password"))
                                .font(.subheadline)
                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(16)

                    Button(action: prepareExport) {
                        Label(language.text("patch.export"), systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .foregroundStyle(AppTheme.accent)
                            .cornerRadius(16)
                            .shadow(color: AppTheme.accent.opacity(0.3), radius: 5)
                    }
                    .disabled(isWorking)
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(item?.project?.name ?? language.text("patch.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isWorking {
                    ProgressView()
                } else if !isWorkspaceProject {
                    Button(language.text("patch.edit")) { showEditor = true }
                        .disabled(item?.project == nil)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let item, let project = item.project {
                PatchProjectEditorView(
                    existingProject: project,
                    passwordIsProtected: item.summary.isPasswordProtected
                ) { updatedProject, _ in
                    store.update(project: updatedProject)
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            PatchRuleEditorView(rule: rule) { updatedRule in
                updateRule(updatedRule)
            }
        }
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(language.text(alert.titleKey)),
                message: Text(alert.message(language: language)),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
        .sheet(item: $shareRequest) { request in
            PatchActivityView(items: [request.url])
                .ignoresSafeArea()
        }
    }

    private func ruleSummary(_ rule: PatchRule) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(rule.bundleID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(rule.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Label(rule.replacementFilename, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.vertical, 3)
    }

    private func updateRule(_ updatedRule: PatchRule) {
        guard var project = item?.project,
              let index = project.rules.firstIndex(where: { $0.id == updatedRule.id }) else {
            return
        }
        project.rules[index] = updatedRule
        project.updatedAt = Date()
        do {
            try PatchPackageCodec.validate(project)
            store.update(project: project)
        } catch let error as PatchPackageError {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: error.localizationKey,
                messageArgument: error.localizationArgument
            )
        } catch {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: "patch.error.invalid_project"
            )
        }
    }

    private func prepareExport() {
        guard let item else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                if item.summary.schemaVersion >= 2 {
                    _ = try PatchProjectLibrary.synchronizeWorkspace(item: item)
                }
                await MainActor.run {
                    store.reload()
                    isWorking = false
                    shareRequest = PatchShareRequest(url: item.packageURL)
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: error.localizationKey,
                        messageArgument: error.localizationArgument
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: "patch.error.invalid_project"
                    )
                }
            }
        }
    }
}

private struct PatchShareRequest: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct PatchActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
