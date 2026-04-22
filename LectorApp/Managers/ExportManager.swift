import Foundation
import UIKit

enum ExportFormat {
    case txt, rtf, pdf, srt
}

class ExportManager {
    static let shared = ExportManager()
    
    private func getTempURL(for filename: String, extension ext: String) -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let safeFilename = filename.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_")
        return tempDirectory.appendingPathComponent("\(safeFilename).\(ext)")
    }
    
    // Формируем единый текст для экспорта
    private func buildContentString(from lecture: LectureDTO, translatedFullText: String? = nil) -> String {
        var content = "\(lecture.title.uppercased())\n"
        
        let dateLabel = String(localized: "Дата:")
        let summaryVariantLabel = String(localized: "--- КОНСПЕКТ (ВАРИАНТ %d) ---")
        let summaryLabel = String(localized: "--- КОНСПЕКТ ---")
        let fullTextLabel = String(localized: "--- ПОЛНЫЙ ТЕКСТ ---")
        
        if let date = lecture.createdAt {
            content += "\(dateLabel) \(date.formatted(date: .long, time: .shortened))\n\n"
        }
        
        // Экспортируем все варианты конспектов, если они есть
        if let history = lecture.summaryHistory, !history.isEmpty {
            for (index, summary) in history.enumerated() {
                // Подставляем номер варианта
                let localizedHeader = String(format: summaryVariantLabel, index + 1)
                content += "\(localizedHeader)\n\(summary)\n\n"
            }
        } else if let summary = lecture.summary, !summary.isEmpty {
            content += "\(summaryLabel)\n\(summary)\n\n"
        }
        
        // Вставляем переведенный текст или оригинал
        content += "\(fullTextLabel)\n\(translatedFullText ?? lecture.fullText)"
        
        return content
    }
    
    // Экспорт в TXT
    func generateTXT(from lecture: LectureDTO, translatedFullText: String? = nil) -> URL? {
        let content = buildContentString(from: lecture, translatedFullText: translatedFullText)
        let url = getTempURL(for: lecture.title, extension: "txt")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    // Экспорт в RTF
    func generateRTF(from lecture: LectureDTO, translatedFullText: String? = nil) -> URL? {
        let content = buildContentString(from: lecture, translatedFullText: translatedFullText)
        let url = getTempURL(for: lecture.title, extension: "rtf")
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14)]
        let attrString = NSAttributedString(string: content, attributes: attrs)
        
        if let rtfData = try? attrString.data(from: NSRange(location: 0, length: attrString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            try? rtfData.write(to: url)
            return url
        }
        return nil
    }
    
    // Экспорт в PDF
    func generatePDF(from lecture: LectureDTO, translatedFullText: String? = nil) -> URL? {
        let content = buildContentString(from: lecture, translatedFullText: translatedFullText)
        let url = getTempURL(for: lecture.title, extension: "pdf")
        
        let formatter = UIMarkupTextPrintFormatter(markupText: content.replacingOccurrences(of: "\n", with: "<br>"))
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        
        let A4Rect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let printableRect = A4Rect.insetBy(dx: 50, dy: 50)
        
        renderer.setValue(A4Rect, forKey: "paperRect")
        renderer.setValue(printableRect, forKey: "printableRect")
        
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, A4Rect, nil)
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: A4Rect)
        }
        UIGraphicsEndPDFContext()
        
        pdfData.write(to: url, atomically: true)
        return url
    }
    
    // Экспорт субтитров (Без перевода)
    func generateSRT(from segments: [TextSegment], title: String) -> URL? {
        var srtString = ""
        for (index, segment) in segments.enumerated() {
            srtString += "\(index + 1)\n"
            srtString += "\(formatSRTTime(segment.startTime)) --> \(formatSRTTime(segment.endTime))\n"
            srtString += "\(segment.text)\n\n"
        }
        let url = getTempURL(for: title, extension: "srt")
        try? srtString.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    private func formatSRTTime(_ time: Double) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time - floor(time)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}
