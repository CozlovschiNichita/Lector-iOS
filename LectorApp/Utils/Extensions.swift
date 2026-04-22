import Foundation
import SwiftUI

extension URL {
    var fileSizeInMB: Double {
        let attributes = try? FileManager.default.attributesOfItem(atPath: self.path)
        let size = attributes?[.size] as? Int64 ?? 0
        return Double(size) / (1024 * 1024)
    }
    
    func predictedSize(duration: TimeInterval) -> String {
        // Расчет M4A (примерно 1МБ/минута при среднем битрейте)
        let size = (duration / 60) * 1.0
        return String(format: "%.1f МБ", size)
    }
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
