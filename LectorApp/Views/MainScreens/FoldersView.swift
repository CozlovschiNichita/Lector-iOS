import SwiftUI
import SwiftData

struct FoldersView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedTab: Int
    @State private var isEditing: EditMode = .inactive
    @State private var navigatedFolderID: UUID? = nil
    
    @Query private var localFolders: [LocalFolder]
    @Query private var allLectures: [LocalLecture]
    
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    
    @StateObject private var keyboard = KeyboardObserver()
    
    // --- ПОИСК ---
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @State private var currentSearchIndex: Int = 0
    
    // --- СОСТОЯНИЕ UI (Создание и Удаление) ---
    @State private var showAddFolderAlert = false
    @State private var newFolderName = ""
    @State private var selectedFolderColor = "blue"
    
    @State private var folderToDelete: LocalFolder?
    @State private var showDeleteAlert = false
    @State private var selection = Set<UUID>()
    @State private var showMassDeleteAlert = false
    
    // --- СОСТОЯНИЕ UI (Редактирование) ---
    @State private var folderToEdit: LocalFolder?
    @State private var showEditFolderSheet = false
    @State private var editFolderName = ""
    @State private var editFolderColor = "blue"
    
    // Настройки
    @State private var showSettings = false
    @State private var settingsRotation: Double = 0.0
    
    @State private var pinUpdateTrigger = UUID()
    
    private let service = FolderService()
    @ObservedObject var globalPlayer = GlobalAudioPlayer.shared
    
    private var isMiniPlayerActive: Bool {
        globalPlayer.currentLectureTitle != nil && globalPlayer.currentLectureTitle?.isEmpty == false
    }
    
    let folderColors: [(name: String, color: Color)] = [
        ("blue", .blue), ("red", .red), ("orange", .orange),
        ("green", .green), ("purple", .purple),
        ("teal", .teal), ("indigo", .indigo), ("yellow", .yellow),
        ("mint", .mint), ("cyan", .cyan), ("brown", .brown)
    ]
    
    private var currentUserID: String { UserDefaults.standard.string(forKey: "current_user_id") ?? "" }

    // ЛОГИКА ФИЛЬТРАЦИИ (ПОИСК ВНУТРИ ПАПОК)
    private var filteredFolders: [LocalFolder] {
        var result = localFolders.filter { $0.ownerID == currentUserID }
        
        if !searchText.isEmpty {
            result = result.filter { folder in
                let matchesFolderName = folder.name.localizedCaseInsensitiveContains(searchText)
                
                let folderLectures = allLectures.filter { $0.folderID == folder.id && $0.ownerID == currentUserID }
                let matchesLectures = folderLectures.contains { lec in
                    lec.title.localizedCaseInsensitiveContains(searchText) ||
                    lec.fullText.localizedCaseInsensitiveContains(searchText)
                }
                
                return matchesFolderName || matchesLectures
            }
        }
        
        result.sort { $0.createdAt > $1.createdAt }
        return result
    }
    
    private var pinnedFolders: [LocalFolder] { filteredFolders.filter { $0.isPinned } }
    private var unpinnedFolders: [LocalFolder] { filteredFolders.filter { !$0.isPinned } }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    ScrollViewReader { scrollProxy in
                        Group {
                            if !isSearchPresented || !searchText.isEmpty {
                                List {
                                    if isEditing == .inactive && searchText.isEmpty {
                                        Section {
                                            Button(action: { selectedTab = 0 }) {
                                                HStack(spacing: 12) {
                                                    Image(systemName: "tray.full")
                                                        .foregroundColor(.blue)
                                                        .font(.title3)
                                                    Text(String(localized: "Все лекции"))
                                                        .font(.headline)
                                                        .foregroundColor(.primary)
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(Color(UIColor.tertiaryLabel))
                                                }
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }

                                    if !pinnedFolders.isEmpty {
                                        Section(header: Text(String(localized: "Закрепленные")) ) {
                                            ForEach(pinnedFolders) { folder in
                                                folderRowContainer(folder).id(folder.id)
                                            }
                                        }
                                    }
                                    
                                    if !unpinnedFolders.isEmpty {
                                        Section(header: Text(pinnedFolders.isEmpty ? String(localized: "Мои папки") : String(localized: "Остальные папки"))) {
                                            ForEach(unpinnedFolders) { folder in
                                                folderRowContainer(folder).id(folder.id)
                                            }
                                        }
                                    }
                                }
                                .listStyle(.insetGrouped)
                                .scrollDismissesKeyboard(.immediately)
                                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: localFolders)
                                .id(pinUpdateTrigger)
                                .environment(\.editMode, $isEditing)
                                .onChange(of: searchText) { _ in currentSearchIndex = 0 }
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
                                } else if isSearchPresented && !searchText.isEmpty && !filteredFolders.isEmpty {
                                    // ТЕПЕРЬ PROXY ВИДЕН!
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
            .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .navigationBarDrawer(displayMode: .automatic), prompt: String(localized: "Поиск папок и лекций внутри"))
            .onChange(of: isSearchPresented) { isPresented in if !isPresented { searchText = "" } }
            .navigationTitle(String(localized: "Библиотека"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        Button(action: {
                            withAnimation(.linear(duration: 0.5)) { settingsRotation += 180 }
                            showSettings = true
                        }) {
                            Image(systemName: "gearshape.fill").rotationEffect(.degrees(settingsRotation)).foregroundColor(.primary)
                        }
                        OfflineIndicator()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { isSearchPresented = true }) { Image(systemName: "magnifyingglass") }
                        
                        if isEditing == .inactive {
                            Button(action: { showAddFolderAlert = true }) { Image(systemName: "folder.badge.plus") }
                        }
                        
                        Button {
                            withAnimation(.easeInOut) {
                                isEditing = (isEditing == .active) ? .inactive : .active
                                if isEditing == .inactive { selection.removeAll() }
                            }
                        } label: {
                            if isEditing == .active { Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .medium)) }
                            else { Text(String(localized: "Выбрать")) }
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showAddFolderAlert) { addFolderSheet }
            .sheet(isPresented: $showEditFolderSheet) { editFolderSheet }
            .alert(String(localized: "Удалить папку?"), isPresented: $showDeleteAlert) {
                Button(String(localized: "Отмена"), role: .cancel) { folderToDelete = nil }
                Button(String(localized: "Удалить"), role: .destructive) { if let f = folderToDelete { deleteFolder(id: f.id) } }
            } message: { Text(String(localized: "Лекции внутри переместятся в 'Все лекции'.")) }
            .alert(String(localized: "Удалить выбранные?"), isPresented: $showMassDeleteAlert) {
                Button(String(localized: "Отмена"), role: .cancel) { }
                Button(String(localized: "Удалить все"), role: .destructive) { performMassDeletion() }
            }
            .onChange(of: networkMonitor.isConnected) { connected in if connected { Task { await syncFolders() } } }
        }
    }

    // MARK: - плашка навигации поиска
    private func searchNavigationPill(proxy: ScrollViewProxy?) -> some View {
        HStack(spacing: 16) {
            Text("\(currentSearchIndex + 1) \(String(localized: "из")) \(filteredFolders.count)").font(.subheadline.bold()).foregroundColor(.primary)
            Divider().frame(height: 20)
            HStack(spacing: 20) {
                Button(action: {
                    if currentSearchIndex > 0 { currentSearchIndex -= 1; if let p = proxy { scrollToCurrentMatch(proxy: p) } }
                }) { Image(systemName: "chevron.up").font(.system(size: 16, weight: .bold)) }
                .foregroundColor(currentSearchIndex > 0 ? .blue : .gray.opacity(0.5))
                
                Button(action: {
                    if currentSearchIndex < filteredFolders.count - 1 { currentSearchIndex += 1; if let p = proxy { scrollToCurrentMatch(proxy: p) } }
                }) { Image(systemName: "chevron.down").font(.system(size: 16, weight: .bold)) }
                .foregroundColor(currentSearchIndex < filteredFolders.count - 1 ? .blue : .gray.opacity(0.5))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12).background(.ultraThinMaterial).clipShape(Capsule()).shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
    }

    private func scrollToCurrentMatch(proxy: ScrollViewProxy) {
        guard !filteredFolders.isEmpty, currentSearchIndex >= 0, currentSearchIndex < filteredFolders.count else { return }
        let targetID = filteredFolders[currentSearchIndex].id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(targetID, anchor: .center) } }
    }

    // MARK: - Ячейка папки
    @ViewBuilder
    private func folderRowContainer(_ folder: LocalFolder) -> some View {
        let folderDTO = FolderDTO(id: folder.id, name: folder.name, createdAt: folder.createdAt, colorHex: folder.colorHex)
        
        Button {
            if isEditing == .active {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if selection.contains(folder.id) { selection.remove(folder.id) }
                    else { selection.insert(folder.id) }
                }
            } else { navigatedFolderID = folder.id }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if isEditing == .active {
                    let isSelected = selection.contains(folder.id)
                    ZStack {
                        Circle().strokeBorder(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1.5).background(Circle().fill(isSelected ? Color.blue : Color.clear))
                        if isSelected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(.white) }
                    }
                    .frame(width: 22, height: 22).transition(.scale.combined(with: .opacity)).padding(.top, 2)
                }

                Image(systemName: "folder.fill").foregroundColor(getColor(from: folder.colorHex)).font(.title3).padding(.top, 0)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(highlightText(folder.name, searchText: searchText))
                        .font(.headline)
                    
                    if !searchText.isEmpty {
                        let matchingLectures = allLectures.filter {
                            $0.folderID == folder.id && $0.ownerID == currentUserID &&
                            ($0.title.localizedCaseInsensitiveContains(searchText) || $0.fullText.localizedCaseInsensitiveContains(searchText))
                        }
                        
                        if !matchingLectures.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(matchingLectures.prefix(3)) { lec in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "doc.text.fill").font(.system(size: 10)).foregroundColor(getColor(from: folder.colorHex)).opacity(0.8).padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(highlightText(lec.title, searchText: searchText))
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            
                                            if let snippet = extractSnippet(from: lec.fullText, searchText: searchText) {
                                                Text(highlightText(snippet, searchText: searchText))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                if matchingLectures.count > 3 {
                                    Text("\(String(localized: "И ещё")) \(matchingLectures.count - 3) \(String(localized: "лекций..."))").font(.caption2).foregroundColor(.blue).padding(.top, 2)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    if !folder.isSynced {
                        HStack(spacing: 4) {
                            Image(systemName: "icloud.and.arrow.up")
                            Text(String(localized: "Ожидание синхронизации"))
                        }.font(.caption2).foregroundColor(.secondary).padding(.top, 2)
                    }
                }
                Spacer()
                
                if isEditing == .inactive { Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundColor(Color(UIColor.tertiaryLabel)).padding(.top, 4) }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(NavigationLink(destination: HistoryView(folder: folderDTO), tag: folder.id, selection: $navigatedFolderID) { EmptyView() }.hidden())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isEditing == .inactive {
                Button { folderToDelete = folder; showDeleteAlert = true } label: { Label(String(localized: "Удалить"), systemImage: "trash") }.tint(.red)
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        folderToEdit = folder; editFolderName = folder.name; editFolderColor = folder.colorHex ?? "blue"; showEditFolderSheet = true
                    }
                } label: { Label(String(localized: "Изменить"), systemImage: "pencil") }.tint(.blue)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if isEditing == .inactive {
                Button { folder.isPinned.toggle(); try? modelContext.save(); pinUpdateTrigger = UUID() } label: { Label(folder.isPinned ? String(localized: "Открепить") : String(localized: "Закрепить"), systemImage: folder.isPinned ? "pin.slash" : "pin") }.tint(.orange)
            }
        }
        .contextMenu {
            if isEditing == .inactive {
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { folder.isPinned.toggle(); try? modelContext.save() } } label: { Label(folder.isPinned ? String(localized: "Открепить") : String(localized: "Закрепить"), systemImage: folder.isPinned ? "pin.slash" : "pin") }
                Button { folderToEdit = folder; editFolderName = folder.name; editFolderColor = folder.colorHex ?? "blue"; showEditFolderSheet = true } label: { Label(String(localized: "Редактировать"), systemImage: "pencil") }
                Button { folderToDelete = folder; showDeleteAlert = true } label: { Label(String(localized: "Удалить"), systemImage: "trash") }.tint(.red)
            }
        }
    }

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

    private var customSelectionActionPanel: some View {
        HStack(spacing: 0) {
            Button(action: { showMassDeleteAlert = true }) {
                VStack(spacing: 4) { Image(systemName: "trash").font(.system(size: 20)); Text(String(localized: "Удалить")).font(.caption) }.frame(maxWidth: .infinity)
            }.foregroundColor(selection.isEmpty ? .gray : .red).disabled(selection.isEmpty)
        }
        .padding(.vertical, 12).background(.ultraThinMaterial).clipShape(Capsule()).shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5).padding(.horizontal, 100)
    }

    private func colorPickerView(selection: Binding<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(folderColors, id: \.name) { colorItem in
                    Circle().fill(colorItem.color).frame(width: 34, height: 34)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(.white).opacity(selection.wrappedValue == colorItem.name ? 1 : 0).scaleEffect(selection.wrappedValue == colorItem.name ? 1 : 0.5))
                        .shadow(color: colorItem.color.opacity(0.3), radius: 4, x: 0, y: 2)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                let generator = UIImpactFeedbackGenerator(style: .light); generator.impactOccurred(); selection.wrappedValue = colorItem.name
                            }
                        }
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 4)
        }
    }

    private var addFolderSheet: some View {
        NavigationView {
            Form {
                Section(String(localized: "Название папки")) { TextField(String(localized: "Название"), text: $newFolderName) }
                Section(String(localized: "Цвет")) { colorPickerView(selection: $selectedFolderColor) }
            }
            .navigationTitle(String(localized: "Новая папка")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button(String(localized: "Отмена")) { showAddFolderAlert = false } }
                ToolbarItem(placement: .navigationBarTrailing) { Button(String(localized: "Создать")) { createFolder() }.disabled(newFolderName.isEmpty) }
            }
        }.presentationDetents([.height(340)])
    }

    private var editFolderSheet: some View {
        NavigationView {
            Form {
                Section(String(localized: "Название папки")) { TextField(String(localized: "Название"), text: $editFolderName) }
                Section(String(localized: "Цвет")) { colorPickerView(selection: $editFolderColor) }
            }
            .navigationTitle(String(localized: "Редактировать")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button(String(localized: "Отмена")) { showEditFolderSheet = false } }
                ToolbarItem(placement: .navigationBarTrailing) { Button(String(localized: "Сохранить")) { if let f = folderToEdit { updateFolderDetails(f) } }.disabled(editFolderName.isEmpty) }
            }
        }.presentationDetents([.height(340)])
    }

    private func createFolder() {
        let currentID = UserDefaults.standard.string(forKey: "current_user_id") ?? ""
        let newFolder = LocalFolder(name: newFolderName, ownerID: currentID)
        newFolder.colorHex = selectedFolderColor
        modelContext.insert(newFolder)
        try? modelContext.save()
        newFolderName = ""
        showAddFolderAlert = false
        if networkMonitor.isConnected { Task { await syncFolders() } }
    }
    
    private func updateFolderDetails(_ folder: LocalFolder) {
        folder.name = editFolderName
        folder.colorHex = editFolderColor
        try? modelContext.save()
        showEditFolderSheet = false
        
        if networkMonitor.isConnected {
            let id = folder.id
            let name = editFolderName
            let color = editFolderColor
            Task { try? await service.updateFolder(id: id, name: name, colorHex: color); await syncFolders() }
        } else {
            folder.isSynced = false
        }
    }
    
    private func deleteFolder(id: UUID) {
        if let folder = localFolders.first(where: { $0.id == id }) {
            modelContext.delete(folder)
            updateLocalDb(id: id)
            if networkMonitor.isConnected { Task { try? await service.deleteFolder(id: id) } }
        }
    }
    
    private func performMassDeletion() { for id in selection { deleteFolder(id: id) }; selection.removeAll(); isEditing = .inactive }
    private func updateLocalDb(id: UUID) { let desc = FetchDescriptor<LocalLecture>(predicate: #Predicate { $0.folderID == id }); if let lecs = try? modelContext.fetch(desc) { for lec in lecs { lec.folderID = nil } }; try? modelContext.save() }
    
    private func syncFolders() async {
        guard networkMonitor.isConnected else { return }
        
        SyncManager.shared.triggerSync()
        
        let unsyncedFolders = localFolders.filter { !$0.isSynced }
        for folder in unsyncedFolders {
            if let serverFolder = try? await service.createFolder(name: folder.name, colorHex: folder.colorHex) {
                let oldID = folder.id; let newID = serverFolder.id
                let desc = FetchDescriptor<LocalLecture>(predicate: #Predicate { $0.folderID == oldID })
                if let lecs = try? modelContext.fetch(desc) { for lec in lecs { lec.folderID = newID } }
                
                let newLocal = LocalFolder(id: newID, name: serverFolder.name, createdAt: serverFolder.createdAt ?? Date(), ownerID: folder.ownerID, isSynced: true, colorHex: serverFolder.colorHex)
                modelContext.insert(newLocal); modelContext.delete(folder)
            }
        }
        try? modelContext.save()
        
        if let serverFolders = try? await service.fetchFolders() {
            let currentID = UserDefaults.standard.string(forKey: "current_user_id") ?? ""
            for serverFolder in serverFolders {
                if let existing = localFolders.first(where: { $0.id == serverFolder.id }) {
                    existing.name = serverFolder.name
                    if let newColor = serverFolder.colorHex { existing.colorHex = newColor }
                    existing.isSynced = true
                } else {
                    let newLocal = LocalFolder(id: serverFolder.id, name: serverFolder.name, createdAt: serverFolder.createdAt ?? Date(), ownerID: currentID, isSynced: true, colorHex: serverFolder.colorHex)
                    modelContext.insert(newLocal)
                }
            }
            try? modelContext.save()
        }
    }
    
    private func getColor(from name: String?) -> Color { return folderColors.first(where: { $0.name == name })?.color ?? .blue }
}
