import SwiftUI
import UIKit

struct SelectableText: View {
    let text: String
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(.body)
                .opacity(0)
                .padding(.vertical, 8)
            
            UITextViewRepresentable(text: text)
        }
    }
}

private struct UITextViewRepresentable: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        
        // позволяют тексту тянуться
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }
}
