import SwiftUI
import SwiftData
import AVFoundation
import Combine

// MARK: - Главный экран
struct LectureDetailView: View {
    @StateObject private var viewModel: LectureDetailViewModel
    @State private var currentSummaryIndex = 0
    var isModal: Bool
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @AppStorage("aiLanguage") private var aiLanguage: String = "en"
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    
    @StateObject private var keyboard = KeyboardObserver()
    
    // Алерты
    @State private var showWaitAlert = false
    @State private var showDeleteAudioAlert = false
    
    // --- переменные для перевода (iOS 18+) ---
    @StateObject private var translationHelper = TranslationHelper()
    @State private var targetLanguage: Locale.Language?
    @State private var pendingFormat: ExportFormat?
    
    // --- переменные для нативного поиска ---
    @State private var isSearchPresented = false
    @State private var searchResults: [UUID] = []
    @State private var currentSearchIndex: Int = 0
    
    init(lecture: LectureDTO, isModal: Bool = false) {
        _viewModel = StateObject(wrappedValue: LectureDetailViewModel(lecture: lecture))
        self.isModal = isModal
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        headerSection
                        
                        if viewModel.hasLocalAudio, let audioPath = viewModel.lecture.localAudioPath {
                            // Аудио уже на борту
                            storageInfoSection(fileName: audioPath)
                            MainAudioPlayerView(lecture: viewModel.lecture, isDownloadingAudio: false)
                            
                        } else if viewModel.isDownloadingAudio {
                            // Файл найден на сервере и сейчас качается в память iPhone
                            MainAudioPlayerView(lecture: viewModel.lecture, isDownloadingAudio: true)
                            
                        } else if ["processing", "waiting_in_queue", "uploading"].contains(viewModel.lecture.status) {
                            // Сервер еще работает над файлом
                            HStack(spacing: 16) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                    .scaleEffect(1.2)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.lecture.status == "waiting_in_queue" ? String(localized: "В очереди на обработку...") : String(localized: "Извлечение аудио..."))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(String(localized: "Плеер появится автоматически"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 16)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(16)
                        }
                        
                        summarySection
                        
                        if let error = viewModel.errorMessage {
                            Text(error).font(.caption).foregroundColor(.red).padding(.horizontal)
                        }
                        
                        Divider().padding(.vertical, 10)
                        transcriptSection(proxy: scrollProxy)
                        
                        Color.clear.frame(height: 120)
                    }
                    .padding()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                .overlay(alignment: .bottom) {
                    BottomOverlayContainer(
                        keyboard: keyboard,
                        isMiniPlayerVisible: GlobalAudioPlayer.shared.playingLecture != nil && !isModal,
                        miniPlayerPadding: 120,
                        defaultPadding: 20
                    ) {
                        if isSearchPresented && !viewModel.searchText.isEmpty && !searchResults.isEmpty {
                            searchNavigationPill(proxy: scrollProxy)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .zIndex(10)
                }
            }
            
            if viewModel.converter.isExporting {
                conversionOverlay
            }
        }
        .searchable(text: $viewModel.searchText, isPresented: $isSearchPresented, placement: .navigationBarDrawer(displayMode: .automatic), prompt: String(localized: "Поиск по лекции"))
        .onChange(of: viewModel.searchText) { _ in
            executeSearch(proxy: nil)
        }
        .onChange(of: isSearchPresented) { isPresented in
            if !isPresented {
                viewModel.searchText = ""
                searchResults = []
            }
        }
        .onAppear {
            viewModel.fetchTemporaryAudioIfNeeded(context: modelContext)
            if viewModel.lecture.status == "processing" || viewModel.lecture.status == "uploading" {
                viewModel.startPolling(context: modelContext)
            }
            
            translationHelper.checkRomanian(text: viewModel.lecture.fullText)
            
            if #available(iOS 18.0, *) {
                Task { await translationHelper.fetchSupportedLanguages() }
            }
        }
        .onDisappear {
            viewModel.cleanUp()
        }
        .refreshable {
            await viewModel.syncThisLecture(context: modelContext)
        }
        .toast(isShowing: $viewModel.showCopyToast, message: String(localized: "Текст скопирован в буфер!"))
        .alert(String(localized: "Текст еще не готов"), isPresented: $showWaitAlert) {
            Button(String(localized: "ОК"), role: .cancel) { }
        } message: {
            Text(String(localized: "Дождитесь окончания расшифровки аудио, чтобы экспортировать документ."))
        }
        .alert(String(localized: "Удалить аудиофайл?"), isPresented: $showDeleteAudioAlert) {
            Button(String(localized: "Отмена"), role: .cancel) { }
            Button(String(localized: "Удалить"), role: .destructive) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.deleteAudioFile(context: modelContext)
                }
            }
        } message: {
            Text(String(localized: "Это освободит память на устройстве, но вы потеряете возможность перематывать аудио по клику на текст лекции. Текст и конспекты останутся."))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                OfflineIndicator()
            }
            
            if isModal {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Закрыть")) { dismiss() }
                }
            } else {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: {
                            isSearchPresented = true
                        }) {
                            Image(systemName: "magnifyingglass")
                        }
                        
                        LectureFileActionsMenu(
                            viewModel: viewModel,
                            translationHelper: translationHelper,
                            hasLocalAudio: viewModel.hasLocalAudio,
                            isRealTextEmpty: viewModel.isRealTextEmpty,
                            onShowWaitAlert: { showWaitAlert = true },
                            onShowDeleteAlert: { showDeleteAudioAlert = true },
                            onTranslate: { format, lang in
                                pendingFormat = format
                                targetLanguage = lang
                            },
                            presentShareSheet: presentShareSheet
                        )
                    }
                }
            }
        }
        .withTranslation(fullText: viewModel.lecture.fullText, targetLanguage: $targetLanguage) { translatedText in
            if let format = pendingFormat {
                viewModel.exportDocument(format: format, translatedFullText: translatedText, presentAction: presentShareSheet)
                pendingFormat = nil
            }
        }
    }
    
    // MARK: - Логика точного поиска и навигация
    private func executeSearch(proxy: ScrollViewProxy?) {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let segments = viewModel.lecture.segments else {
            searchResults = []
            return
        }

        searchResults = segments.filter { $0.text.localizedCaseInsensitiveContains(query) }.map { $0.id }
        
        if !searchResults.isEmpty {
            currentSearchIndex = 0
            if let proxy = proxy {
                scrollToCurrentMatch(proxy: proxy)
            }
        }
    }

    private func scrollToCurrentMatch(proxy: ScrollViewProxy) {
        guard !searchResults.isEmpty, currentSearchIndex >= 0, currentSearchIndex < searchResults.count else { return }
        let targetID = searchResults[currentSearchIndex]
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
        }
    }
    
    // MARK: - плашка навигации поиска
    private func searchNavigationPill(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 16) {
            Text("\(currentSearchIndex + 1) \(String(localized: "из")) \(searchResults.count)")
                .font(.subheadline.bold())
                .foregroundColor(.primary)
            
            Divider().frame(height: 20)
            
            HStack(spacing: 20) {
                Button(action: {
                    if currentSearchIndex > 0 {
                        currentSearchIndex -= 1
                        scrollToCurrentMatch(proxy: proxy)
                    }
                }) {
                    Image(systemName: "chevron.up").font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(currentSearchIndex > 0 ? .blue : .gray.opacity(0.5))
                
                Button(action: {
                    if currentSearchIndex < searchResults.count - 1 {
                        currentSearchIndex += 1
                        scrollToCurrentMatch(proxy: proxy)
                    }
                }) {
                    Image(systemName: "chevron.down").font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(currentSearchIndex < searchResults.count - 1 ? .blue : .gray.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - UI Секции
    private func languageName(for code: String) -> String {
        switch code {
        case "ru": return String(localized: "Русский")
        case "en": return String(localized: "English")
        case "ro": return String(localized: "Română")
        case "fr": return String(localized: "Français")
        default: return code
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.lecture.title).font(.title2).bold()
            if let date = viewModel.lecture.createdAt {
                Text(date.formatted(date: .long, time: .shortened)).font(.subheadline).foregroundColor(.secondary)
            }
        }
    }
    
    private func storageInfoSection(fileName: String) -> some View {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        let isCaf = url.pathExtension.lowercased() == "caf"
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Управление памятью")).font(.headline)
                    Text("\(String(localized: "Формат:")) \(url.pathExtension.uppercased())").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f МБ", url.fileSizeInMB)).font(.title3).bold().foregroundColor(.blue)
            }
            if isCaf {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Файл в формате CAF. Рекомендуется сжать в M4A.")).font(.caption).foregroundColor(.orange)
                    Button(action: { viewModel.handleManualConversion(to: .m4a, context: modelContext) }) {
                        Label(String(localized: "Сжать сейчас"), systemImage: "arrow.down.doc.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                }
            }
        }
        .padding().background(Color(UIColor.tertiarySystemBackground)).cornerRadius(16)
    }
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "Конспект ИИ"), systemImage: "sparkles").font(.headline).foregroundColor(.purple)
                Spacer()
                if let history = viewModel.lecture.summaryHistory, !history.isEmpty {
                    Button(action: {
                        let textToCopy = history[currentSummaryIndex]
                        viewModel.copyToClipboard(textToCopy)
                    }) { Image(systemName: "doc.on.doc").font(.caption).padding(8).background(Color.purple.opacity(0.1)).clipShape(Circle()) }
                    
                    Button(action: {
                        viewModel.deleteSummary(at: currentSummaryIndex, context: modelContext)
                        if currentSummaryIndex >= (viewModel.lecture.summaryHistory?.count ?? 0) {
                            currentSummaryIndex = max(0, (viewModel.lecture.summaryHistory?.count ?? 1) - 1)
                        }
                    }) { Image(systemName: "trash").font(.caption).padding(8).background(Color.red.opacity(0.1)).clipShape(Circle()).foregroundColor(.red) }
                }
            }

            let isGenerating = viewModel.isGeneratingSummary

            if isGenerating {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { ProgressView().tint(.purple); Text(String(localized: "Генерация конспекта...")).font(.subheadline).foregroundColor(.secondary) }
                }
                .padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
            } else {
                generationControlsCard(isRealTextEmpty: viewModel.isRealTextEmpty)
            }

            if let history = viewModel.lecture.summaryHistory, !history.isEmpty {
                TabView(selection: $currentSummaryIndex) {
                    ForEach(history.indices, id: \.self) { index in
                        ScrollView {
                            SelectableText(text: history[index])
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 40)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(minHeight: 350)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }
    
    @ViewBuilder
    private func generationControlsCard(isRealTextEmpty: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRealTextEmpty {
                HStack {
                    Image(systemName: "text.badge.xmark")
                    Text(String(localized: "Конспект недоступен. Дождитесь появления текста лекции."))
                }.font(.caption).foregroundColor(.orange).padding(.bottom, 4)
            }
            
            if !networkMonitor.isConnected {
                HStack { Image(systemName: "wifi.slash"); Text(String(localized: "Для ИИ нужен интернет")) }.font(.caption2).foregroundColor(.red)
            }
            
            HStack(spacing: 12) {
                Menu {
                    Picker(String(localized: "Язык"), selection: $aiLanguage) {
                        Text(String(localized: "English")).tag("en")
                        Text(String(localized: "Русский")).tag("ru")
                        Text(String(localized: "Română")).tag("ro")
                        Text(String(localized: "Français")).tag("fr")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe"); Text(languageName(for: aiLanguage)); Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.subheadline).padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color(UIColor.tertiarySystemBackground)).cornerRadius(8).foregroundColor(.primary)
                }
                .disabled(isRealTextEmpty || !networkMonitor.isConnected)
                
                Button(action: { viewModel.generateSummary(language: aiLanguage, context: modelContext) }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text(viewModel.lecture.summaryHistory?.isEmpty == false ? String(localized: "Еще вариант") : String(localized: "Сгенерировать"))
                    }
                    .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background((isRealTextEmpty || !networkMonitor.isConnected) ? Color.gray.opacity(0.3) : Color.purple)
                    .foregroundColor((isRealTextEmpty || !networkMonitor.isConnected) ? .secondary : .white)
                    .cornerRadius(8)
                }
                .disabled(isRealTextEmpty || !networkMonitor.isConnected)
            }
        }
        .padding(12).background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
    }
    
    private func transcriptSection(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Полный текст")).font(.title3).bold().foregroundColor(.primary).fontWeight(.light)
                Spacer()
                if !viewModel.isRealTextEmpty {
                    Button(action: {
                        UIPasteboard.general.string = viewModel.lecture.fullText
                        withAnimation { viewModel.showCopyToast = true }
                    }) { Image(systemName: "doc.on.doc").font(.caption).padding(8).background(Color.blue.opacity(0.1)).clipShape(Circle()) }
                }
            }
            
            if !viewModel.isRealTextEmpty, let segments = viewModel.lecture.segments, !segments.isEmpty {
                Text(String(localized: "Удерживайте сегмент для быстрого исправления"))
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .bold()
                    .padding(.bottom, 4)
            }
            
            if viewModel.isRealTextEmpty {
                Text(viewModel.lecture.fullText.isEmpty ? String(localized: "Ожидает расшифровки...") : viewModel.lecture.fullText)
                    .font(.subheadline).foregroundColor(.secondary).padding(.top, 4)
            } else {
                let isThisLecturePlaying = GlobalAudioPlayer.shared.currentLectureTitle == viewModel.lecture.title
                if let segments = viewModel.lecture.segments, !segments.isEmpty {
                    SegmentedTextView(
                        segments: segments,
                        viewModel: viewModel,
                        onSeek: { timestamp in
                            let duration = GlobalAudioPlayer.shared.duration
                            let targetProgress = duration > 0 ? timestamp / duration : 0
                            if !isThisLecturePlaying {
                                GlobalAudioPlayer.shared.play(lecture: viewModel.lecture)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    let newDuration = GlobalAudioPlayer.shared.duration
                                    if newDuration > 0 { GlobalAudioPlayer.shared.seek(to: timestamp / newDuration) }
                                }
                            } else {
                                if !GlobalAudioPlayer.shared.isPlaying { GlobalAudioPlayer.shared.resume() }
                                if duration > 0 { GlobalAudioPlayer.shared.seek(to: targetProgress) }
                            }
                        },
                        onEdit: { segmentID, newText in viewModel.updateSegment(id: segmentID, newText: newText, context: modelContext) }
                    )
                } else {
                    SelectableText(text: viewModel.lecture.fullText).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private var conversionOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView(value: viewModel.converter.exportProgress).progressViewStyle(.circular).tint(.white).scaleEffect(1.5)
                Text("\(String(localized: "Обработка аудио...")) \(Int(viewModel.converter.exportProgress * 100))%").foregroundColor(.white).bold()
            }
            .padding(40).background(RoundedRectangle(cornerRadius: 20).fill(Color(UIColor.systemGray6)))
        }
    }
    
    private func presentShareSheet(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, let rootVC = scene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Изолированное меню действий
struct LectureFileActionsMenu: View {
    let viewModel: LectureDetailViewModel
    @ObservedObject var translationHelper: TranslationHelper
    
    let hasLocalAudio: Bool
    let isRealTextEmpty: Bool
    
    let onShowWaitAlert: () -> Void
    let onShowDeleteAlert: () -> Void
    let onTranslate: (ExportFormat, Locale.Language) -> Void
    
    var presentShareSheet: (URL) -> Void
    
    var body: some View {
        Menu {
            Section(String(localized: "Оригинал")) {
                Button(action: {
                    if isRealTextEmpty { onShowWaitAlert() }
                    else { viewModel.exportDocument(format: .pdf, presentAction: presentShareSheet) }
                }) { Label(String(localized: "PDF Документ"), systemImage: "doc.richtext") }
                
                Button(action: {
                    if isRealTextEmpty { onShowWaitAlert() }
                    else { viewModel.exportDocument(format: .rtf, presentAction: presentShareSheet) }
                }) { Label(String(localized: "Word (.rtf)"), systemImage: "doc.text") }
                
                Button(action: {
                    if isRealTextEmpty { onShowWaitAlert() }
                    else { viewModel.exportDocument(format: .txt, presentAction: presentShareSheet) }
                }) { Label(String(localized: "Обычный текст (.txt)"), systemImage: "doc.plaintext") }
                
                Button(action: {
                    if isRealTextEmpty { onShowWaitAlert() }
                    else { viewModel.exportDocument(format: .srt, presentAction: presentShareSheet) }
                }) { Label(String(localized: "Субтитры (.srt)"), systemImage: "captions.bubble") }
            }
            
            if #available(iOS 18.0, *) {
                Section(String(localized: "Перевод (только текст)")) {
                    if translationHelper.isRomanian {
                        Text(String(localized: "Румынский язык пока не поддерживается системой для перевода")).font(.caption)
                    } else {
                        Menu {
                            Text(String(localized: "Внимание: Заголовки и конспекты останутся в оригинале")).font(.caption)
                            ForEach(translationHelper.supportedLanguages, id: \.self) { lang in
                                Menu(translationHelper.localizedName(for: lang)) {
                                    Button(String(localized: "В PDF")) { onTranslate(.pdf, lang) }
                                    Button(String(localized: "В Word (.rtf)")) { onTranslate(.rtf, lang) }
                                    Button(String(localized: "В текст (.txt)")) { onTranslate(.txt, lang) }
                                }
                            }
                        } label: {
                            Label(String(localized: "Перевести и экспортировать"), systemImage: "translate")
                        }
                        .disabled(isRealTextEmpty)
                    }
                }
            }
            
            if hasLocalAudio {
                Section(String(localized: "Скачать аудио")) {
                    Button(action: { viewModel.shareAudio(as: .m4a, presentAction: presentShareSheet) }) { Label(String(localized: "Аудио: M4A"), systemImage: "music.note") }
                    Button(action: { viewModel.shareAudio(as: .wav, presentAction: presentShareSheet) }) { Label(String(localized: "Аудио: WAV"), systemImage: "waveform") }
                }
                Section(String(localized: "Управление")) {
                    Button(role: .destructive, action: onShowDeleteAlert) { Label(String(localized: "Удалить аудио"), systemImage: "trash") }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}
