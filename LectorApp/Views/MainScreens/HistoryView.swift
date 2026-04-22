import SwiftUI
import SwiftData

struct HistoryView: View {
    let folder: FolderDTO?
    
    init(folder: FolderDTO?) {
        self.folder = folder
    }
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var network: NetworkMonitor
    
    @StateObject private var keyboard = KeyboardObserver()
    
    @State private var isEditing: EditMode = .inactive
    @State private var navigatedLectureID: UUID? = nil
    
    // --- ПОИСК ---
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @State private var currentSearchIndex: Int = 0
    @State private var isFoldersLoading = false
    
    @State private var selection = Set<UUID>()
    @State private var showRenameAlert = false
    @State private var newTitle = ""
    @State private var lectureToRename: LocalLecture?
    @State private var showFolderPicker = false
    @State private var availableFolders: [FolderDTO] = []
    
    @State private var showDeleteConfirmation = false
    @State private var lectureToDelete: LocalLecture?
    @State private var showMassDeleteConfirmation = false
    
    // Настройки
    @State private var showSettings = false
    @State private var settingsRotation: Double = 0.0
    
    @State private var pinUpdateTrigger = UUID()
    
    private var currentUserID: String {
        UserDefaults.standard.string(forKey: "current_user_id") ?? ""
    }
    
    @ObservedObject var globalPlayer = GlobalAudioPlayer.shared
    
    private var isMiniPlayerActive: Bool {
        globalPlayer.currentLectureTitle != nil && globalPlayer.currentLectureTitle?.isEmpty == false
    }
    
    @Query private var allLectures: [LocalLecture]
    
    // --- ФИЛЬТРАЦИЯ И РАЗДЕЛЕНИЕ ---
    private var filteredLectures: [LocalLecture] {
        let ownerID = currentUserID
        let targetFolderID = folder?.id
        
        var result = allLectures.filter { lecture in
            let isOwner = lecture.ownerID == ownerID
            let matchesFolder = (targetFolderID == nil) || (lecture.folderID == targetFolderID)
            return isOwner && matchesFolder
        }
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.fullText.localizedCaseInsensitiveContains(searchText)
            }
        }
        result.sort { $0.createdAt > $1.createdAt }
        return result
    }
    
    private var pinnedLectures: [LocalLecture] {
        filteredLectures.filter { $0.isPinned }
    }
    
    private var unpinnedLectures: [LocalLecture] {
        filteredLectures.filter { !$0.isPinned }
    }

    private let folderService = FolderService()
    private let lectureService = LectureService()

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ScrollViewReader { scrollProxy in
                    Group {
                        if !isSearchPresented || !searchText.isEmpty {
                            List {
                                if !pinnedLectures.isEmpty {
                                    Section(header: Text(String(localized: "Закрепленные"))) {
                                        ForEach(pinnedLectures, id: \.id) { lecture in
                                            lectureRowContainer(lecture)
                                                .id(lecture.id)
                                        }
                                    }
                                }
                                
                                if !unpinnedLectures.isEmpty {
                                    if pinnedLectures.isEmpty {
                                        Section {
                                            ForEach(unpinnedLectures, id: \.id) { lecture in
                                                lectureRowContainer(lecture)
                                                    .id(lecture.id)
                                            }
                                        }
                                    } else {
                                        Section(header: Text(String(localized: "Остальные лекции"))) {
                                            ForEach(unpinnedLectures, id: \.id) { lecture in
                                                lectureRowContainer(lecture)
                                                    .id(lecture.id)
                                            }
                                        }
                                    }
                                }
                            }
                            .listStyle(.insetGrouped)
                            .scrollDismissesKeyboard(.immediately)
                            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: filteredLectures)
                            .id(pinUpdateTrigger)
                            .environment(\.editMode, $isEditing)
                            .onChange(of: searchText) { _ in
                                currentSearchIndex = 0
                            }
                            .refreshable { await syncWithServer() }
                        } else {
                            Color.clear
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        let playerSpace: CGFloat = isMiniPlayerActive ? 80 : 0
                        let overlaySpace: CGFloat = (isEditing == .active || (isSearchPresented && !searchText.isEmpty)) ? 60 : 0
                        Color.clear.frame(height: playerSpace + overlaySpace)
                    }
                    .overlay(alignment: .bottom) {
                        BottomOverlayContainer(
                            keyboard: keyboard,
                            isMiniPlayerVisible: isMiniPlayerActive,
                            miniPlayerPadding: 120,
                            defaultPadding: 20
                        ) {
                            if isEditing == .active {
                                customSelectionActionPanel
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else if isSearchPresented && !searchText.isEmpty && !filteredLectures.isEmpty {
                                searchNavigationPill(proxy: scrollProxy)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .zIndex(10)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            hideKeyboard()
        }
        .navigationTitle(folder?.name ?? String(localized: "История"))
        .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .navigationBarDrawer(displayMode: .automatic), prompt: String(localized: "Поиск лекции или текста"))
        .onChange(of: isSearchPresented) { isPresented in
            if !isPresented {
                searchText = ""
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    withAnimation(.linear(duration: 0.5)) { settingsRotation += 180 }
                    showSettings = true
                }) {
                    Image(systemName: "gearshape.fill").rotationEffect(.degrees(settingsRotation)).foregroundColor(.primary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button(action: {
                        isSearchPresented = true
                    }) {
                        Image(systemName: "magnifyingglass")
                    }
                    
                    OfflineIndicator()
                    
                    Button {
                        withAnimation(.easeInOut) {
                            if isEditing == .active {
                                isEditing = .inactive
                                selection.removeAll()
                            } else {
                                isEditing = .active
                            }
                        }
                    } label: {
                        if isEditing == .active {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .medium))
                        } else {
                            Text(String(localized: "Выбрать"))
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert(String(localized: "Переименовать лекцию"), isPresented: $showRenameAlert) {
            TextField(String(localized: "Название"), text: $newTitle)
            Button(String(localized: "Отмена"), role: .cancel) { lectureToRename = nil }
            Button(String(localized: "Сохранить")) { if let lecture = lectureToRename { renameLecture(lecture, to: newTitle) } }
        }
        .alert(String(localized: "Удалить лекцию?"), isPresented: $showDeleteConfirmation) {
            Button(String(localized: "Отмена"), role: .cancel) { lectureToDelete = nil }
            Button(String(localized: "Удалить"), role: .destructive) { if let lecture = lectureToDelete { performFullDeletion(lecture) } }
        } message: { Text(String(localized: "Это действие нельзя будет отменить. Лекция будет полностью удалена.")) }
        .alert(String(localized: "Удалить выбранные лекции?"), isPresented: $showMassDeleteConfirmation) {
            Button("\(String(localized: "Удалить все")) (\(selection.count))", role: .destructive) { performMassDeletion() }
            Button(String(localized: "Отмена"), role: .cancel) { }
        } message: { Text(String(localized: "Вы уверены, что хотите безвозвратно удалить все выбранные элементы?")) }
        .sheet(isPresented: $showFolderPicker) { folderSelectionSheet }
        .onAppear {
            Task {
                await syncWithServer()
                await loadFoldersSilently()
            }
        }
    }

    // MARK: - плашка навигации поиска
    private func searchNavigationPill(proxy: ScrollViewProxy?) -> some View {
        HStack(spacing: 16) {
            Text("\(currentSearchIndex + 1) \(String(localized: "из")) \(filteredLectures.count)")
                .font(.subheadline.bold())
                .foregroundColor(.primary)
            
            Divider().frame(height: 20)
            
            HStack(spacing: 20) {
                Button(action: {
                    if currentSearchIndex > 0 {
                        currentSearchIndex -= 1
                        if let p = proxy { scrollToCurrentMatch(proxy: p) }
                    }
                }) {
                    Image(systemName: "chevron.up").font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(currentSearchIndex > 0 ? .blue : .gray.opacity(0.5))
                
                Button(action: {
                    if currentSearchIndex < filteredLectures.count - 1 {
                        currentSearchIndex += 1
                        if let p = proxy { scrollToCurrentMatch(proxy: p) }
                    }
                }) {
                    Image(systemName: "chevron.down").font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(currentSearchIndex < filteredLectures.count - 1 ? .blue : .gray.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
    }

    private func scrollToCurrentMatch(proxy: ScrollViewProxy) {
        guard !filteredLectures.isEmpty, currentSearchIndex >= 0, currentSearchIndex < filteredLectures.count else { return }
        let targetID = filteredLectures[currentSearchIndex].id
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
        }
    }

    // MARK: - Контейнер строки
    @ViewBuilder
    private func lectureRowContainer(_ lecture: LocalLecture) -> some View {
        ZStack {
            NavigationLink(destination: LectureDetailView(lecture: mapToDTO(lecture), isModal: false), tag: lecture.id, selection: $navigatedLectureID) {
                EmptyView()
            }
            .opacity(0)
            
            Button {
                if isEditing == .active {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if selection.contains(lecture.id) { selection.remove(lecture.id) }
                        else { selection.insert(lecture.id) }
                    }
                } else {
                    navigatedLectureID = lecture.id
                }
            } label: {
                HStack(spacing: 12) {
                    if isEditing == .active {
                        let isSelected = selection.contains(lecture.id)
                        ZStack {
                            Circle().strokeBorder(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1.5)
                                .background(Circle().fill(isSelected ? Color.blue : Color.clear))
                            if isSelected {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                            }
                        }
                        .frame(width: 22, height: 22)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    lectureRow(lecture)
                    Spacer()
                    
                    if isEditing == .inactive {
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isEditing == .inactive {
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        lectureToDelete = lecture
                        showDeleteConfirmation = true
                    }
                } label: {
                    Label(String(localized: "Удалить"), systemImage: "trash")
                }
                .tint(.red)
                 
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selection = [lecture.id]
                        Task { await prepareFolderPicker() }
                    }
                } label: { Label(String(localized: "В папку"), systemImage: "folder") }.tint(.purple)
                
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        lectureToRename = lecture
                        newTitle = lecture.title
                        showRenameAlert = true
                    }
                } label: { Label(String(localized: "Имя"), systemImage: "pencil") }.tint(.blue)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if isEditing == .inactive {
                Button {
                    lecture.isPinned.toggle()
                    try? modelContext.save()
                    pinUpdateTrigger = UUID()
                } label: {
                    Label(
                        lecture.isPinned ? String(localized: "Открепить") : String(localized: "Закрепить"),
                        systemImage: lecture.isPinned ? "pin.slash" : "pin"
                    )
                    .tint(.orange)
                }
            }
        }
        .contextMenu {
            if isEditing == .inactive {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        lecture.isPinned.toggle()
                        try? modelContext.save()
                    }
                } label: { Label(lecture.isPinned ? String(localized: "Открепить") : String(localized: "Закрепить"), systemImage: lecture.isPinned ? "pin.slash" : "pin") }
                
                Button {
                    lectureToRename = lecture
                    newTitle = lecture.title
                    showRenameAlert = true
                } label: { Label(String(localized: "Переименовать"), systemImage: "pencil") }
                
                Button {
                    selection = [lecture.id]
                    Task { await prepareFolderPicker() }
                } label: { Label(String(localized: "Переместить в папку"), systemImage: "folder") }
                
                Button {
                    lectureToDelete = lecture
                    showDeleteConfirmation = true
                } label: {
                    Label(String(localized: "Удалить"), systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }

    private func lectureRow(_ lecture: LocalLecture) -> some View {
        let isProcessingAudio = (lecture.status == "processing" && lecture.fullText.isEmpty) || lecture.status == "uploading"
        let isGeneratingSummary = lecture.status == "processing" && !lecture.fullText.isEmpty
        
        return VStack(alignment: .leading, spacing: 6) {
            Text(highlightText(lecture.title, searchText: searchText))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            if !searchText.isEmpty, let snippet = extractSnippet(from: lecture.fullText, searchText: searchText) {
                Text(highlightText(snippet, searchText: searchText))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
            
            if isProcessingAudio {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ProgressView(value: lecture.progress ?? 0.0, total: 1.0).tint(lecture.status == "uploading" ? .blue : .orange).scaleEffect(x: 1, y: 1.5)
                        Text("\(Int((lecture.progress ?? 0.0) * 100))%").font(.system(size: 10, weight: .bold)).foregroundColor(lecture.status == "uploading" ? .blue : .orange)
                    }
                    Text(lecture.status == "uploading" ? String(localized: "Загрузка файла...") : String(localized: "Обработка аудио...")).font(.system(size: 10)).foregroundColor(.secondary)
                }
            } else if lecture.status == "error" {
                HStack(spacing: 8) {
                    Text(String(localized: "Ошибка обработки")).font(.system(size: 12)).foregroundColor(.red)
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.caption2)
                }
            } else {
                HStack {
                    Text(lecture.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if isGeneratingSummary {
                        Spacer()
                        ProgressView().controlSize(.mini).tint(.orange)
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Вспомогательные функции для подсветки текста
    private func highlightText(_ text: String, searchText: String) -> AttributedString {
        var attrStr = AttributedString(text)
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return attrStr }
        
        var searchRange = attrStr.startIndex..<attrStr.endIndex
        while let range = attrStr[searchRange].range(of: searchText, options: .caseInsensitive) {
            attrStr[range].backgroundColor = .yellow.opacity(0.8)
            attrStr[range].foregroundColor = .black
            searchRange = range.upperBound..<attrStr.endIndex
        }
        return attrStr
    }

    private func extractSnippet(from text: String, searchText: String) -> String? {
        guard !searchText.isEmpty, !text.isEmpty else { return nil }
        let nsText = text as NSString
        let matchRange = nsText.range(of: searchText, options: .caseInsensitive)
        
        if matchRange.location != NSNotFound {
            let start = max(0, matchRange.location - 20)
            let end = min(nsText.length, matchRange.location + matchRange.length + 20)
            let snippetRange = NSRange(location: start, length: end - start)
            
            var snippet = nsText.substring(with: snippetRange)
            if start > 0 { snippet = "..." + snippet }
            if end < nsText.length { snippet = snippet + "..." }
            
            return snippet.replacingOccurrences(of: "\n", with: " ")
        }
        return nil
    }

    // MARK: - Панель действий
    private var customSelectionActionPanel: some View {
        HStack(spacing: 0) {
            Button(action: {
                Task { await prepareFolderPicker() }
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "folder").font(.system(size: 20))
                    Text(String(localized: "В папку")).font(.caption)
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundColor(selection.isEmpty ? .gray : .blue)
            .disabled(selection.isEmpty)
            
            Divider().frame(height: 30).opacity(0.5)
            
            Button(action: {
                showMassDeleteConfirmation = true
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "trash").font(.system(size: 20))
                    Text(String(localized: "Удалить")).font(.caption)
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundColor(selection.isEmpty ? .gray : .red)
            .disabled(selection.isEmpty)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 40)
    }
    
    // MARK: - Выбор папки
    private var folderSelectionSheet: some View {
        NavigationView {
            ZStack {
                if isFoldersLoading && availableFolders.isEmpty {
                    ProgressView(String(localized: "Загрузка папок..."))
                } else {
                    List {
                        Section {
                            Button(action: {
                                triggerHaptic(.medium)
                                moveSelectedToFolder(nil)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "tray.full").foregroundColor(.blue).font(.title3)
                                    Text(String(localized: "Без папки (все лекции)")).foregroundColor(.primary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        
                        Section(header: Text(String(localized: "Ваши папки"))) {
                            ForEach(availableFolders) { folderDTO in
                                Button(action: {
                                    triggerHaptic(.medium)
                                    moveSelectedToFolder(folderDTO.id)
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(getColor(from: folderDTO.colorHex))
                                            .font(.title3)
                                        Text(folderDTO.name).foregroundColor(.primary)
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            .navigationTitle(String(localized: "Переместить в..."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(String(localized: "Отмена")) { showFolderPicker = false } } }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Логика
    func loadFoldersSilently() async {
        isFoldersLoading = true
        if let folders = try? await folderService.fetchFolders() { await MainActor.run { self.availableFolders = folders } }
        isFoldersLoading = false
    }

    func prepareFolderPicker() async {
        showFolderPicker = true
        if availableFolders.isEmpty { await loadFoldersSilently() }
    }

    func renameLecture(_ lecture: LocalLecture, to title: String) {
        guard !title.isEmpty else { return }
        lecture.title = title
        try? modelContext.save()
        Task { try? await lectureService.updateLecture(id: lecture.id, newTitle: title, folderID: nil) }
    }
    
    func moveSelectedToFolder(_ targetFolderID: UUID?) {
        let ids = Array(selection)
        for id in ids { if let loc = allLectures.first(where: { $0.id == id }) { loc.folderID = targetFolderID } }
        try? modelContext.save()
        Task {
            try? await folderService.updateLecturesBatch(ids: ids, folderID: targetFolderID)
            await MainActor.run {
                selection.removeAll()
                isEditing = .inactive
                showFolderPicker = false
            }
        }
    }
    
    func performMassDeletion() {
        guard network.isConnected else { return }
        let idsToDelete = Array(selection)
        Task {
            for id in idsToDelete {
                if let loc = allLectures.first(where: { $0.id == id }) {
                    try? await lectureService.deleteLecture(id: id)
                    await MainActor.run { modelContext.delete(loc) }
                }
            }
            await MainActor.run {
                try? modelContext.save()
                selection.removeAll()
                isEditing = .inactive
            }
        }
    }
    
    func performFullDeletion(_ lecture: LocalLecture) {
        guard network.isConnected else { return }
        let id = lecture.id
        Task {
            try? await lectureService.deleteLecture(id: id)
            await MainActor.run {
                modelContext.delete(lecture)
                try? modelContext.save()
                lectureToDelete = nil
            }
        }
    }
    
    func syncWithServer() async {
        guard network.isConnected else { return }
        
        SyncManager.shared.triggerSync()
        
        do {
            let remoteLectures = try await lectureService.fetchLectures()
            await MainActor.run {
                for remote in remoteLectures {
                    if let existing = allLectures.first(where: { $0.id == remote.id }) {
                        existing.title = remote.title
                        existing.fullText = remote.fullText
                        existing.summary = remote.summary
                        
                        if existing.folderID != nil && remote.folderID == nil {
                            let localFolderID = existing.folderID
                            Task { try? await lectureService.updateLecture(id: existing.id, folderID: localFolderID) }
                        } else {
                            existing.folderID = remote.folderID
                        }
                        
                        existing.status = remote.status
                        existing.progress = remote.progress
                        if let remoteAudio = remote.localAudioPath, !remoteAudio.isEmpty { existing.localAudioPath = remoteAudio }
                        if let history = remote.summaryHistory {
                            let encoder = JSONEncoder()
                            if let jsonData = try? encoder.encode(history), let jsonString = String(data: jsonData, encoding: .utf8) { existing.summaryHistoryJSON = jsonString }
                        }
                        if let segments = remote.segments {
                            let encoder = JSONEncoder()
                            if let jsonData = try? encoder.encode(segments), let jsonString = String(data: jsonData, encoding: .utf8) { existing.segmentsJSON = jsonString }
                        }
                    } else {
                        let new = LocalLecture(id: remote.id, title: remote.title, fullText: remote.fullText, summary: remote.summary, createdAt: remote.createdAt ?? Date(), ownerID: currentUserID)
                        new.folderID = remote.folderID
                        new.status = remote.status
                        new.progress = remote.progress
                        if let history = remote.summaryHistory {
                            let encoder = JSONEncoder()
                            if let jsonData = try? encoder.encode(history), let jsonString = String(data: jsonData, encoding: .utf8) { new.summaryHistoryJSON = jsonString }
                        }
                        if let segments = remote.segments {
                            let encoder = JSONEncoder()
                            if let jsonData = try? encoder.encode(segments), let jsonString = String(data: jsonData, encoding: .utf8) { new.segmentsJSON = jsonString }
                        }
                        modelContext.insert(new)
                    }
                }
                try? modelContext.save()
            }
        } catch { print("Sync error: \(error)") }
    }
    
    private func mapToDTO(_ local: LocalLecture) -> LectureDTO {
        return LectureDTO(id: local.id, title: local.title, fullText: local.fullText, summary: local.summary, summaryHistory: local.getSummaryHistory(), folderID: local.folderID, createdAt: local.createdAt, localAudioPath: local.localAudioPath, status: local.status, progress: local.progress, segments: local.getSegments())
    }
    
    // MARK: - Вспомогательные функции для UI
    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    private func getColor(from name: String?) -> Color {
        let colors: [(name: String, color: Color)] = [
            ("blue", .blue), ("red", .red), ("orange", .orange),
            ("green", .green), ("purple", .purple),
            ("teal", .teal), ("indigo", .indigo), ("yellow", .yellow),
            ("mint", .mint), ("cyan", .cyan), ("brown", .brown)
        ]
        return colors.first(where: { $0.name == name })?.color ?? .blue
    }
}
