import AppKit
import CoreGraphics
import CoreText
import Foundation

func buildDocument(from markdown: String) -> NSAttributedString {
    let result = NSMutableAttributedString()

    let bodyStyle = NSMutableParagraphStyle()
    bodyStyle.lineHeightMultiple = 1.3
    bodyStyle.paragraphSpacing = 6

    let heading1Style = bodyStyle.mutableCopy() as! NSMutableParagraphStyle
    heading1Style.paragraphSpacing = 10
    heading1Style.paragraphSpacingBefore = 12

    let heading2Style = heading1Style.mutableCopy() as! NSMutableParagraphStyle
    heading2Style.paragraphSpacing = 8
    heading2Style.paragraphSpacingBefore = 10

    let bulletStyle = bodyStyle.mutableCopy() as! NSMutableParagraphStyle
    bulletStyle.firstLineHeadIndent = 0
    bulletStyle.headIndent = 16

    let numberedStyle = bulletStyle.mutableCopy() as! NSMutableParagraphStyle

    let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .paragraphStyle: bodyStyle,
    ]

    let heading1Attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
        .paragraphStyle: heading1Style,
    ]

    let heading2Attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
        .paragraphStyle: heading2Style,
    ]

    let bulletAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .paragraphStyle: bulletStyle,
    ]

    let numberedAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .paragraphStyle: numberedStyle,
    ]

    func appendLine(_ text: String, attributes: [NSAttributedString.Key: Any]) {
        result.append(NSAttributedString(string: text + "\n", attributes: attributes))
    }

    let lines = markdown.components(separatedBy: .newlines)
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            result.append(NSAttributedString(string: "\n", attributes: bodyAttributes))
            continue
        }

        if trimmed.hasPrefix("# ") {
            let text = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            appendLine(String(text), attributes: heading1Attributes)
            continue
        }

        if trimmed.hasPrefix("## ") {
            let text = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
            appendLine(String(text), attributes: heading2Attributes)
            continue
        }

        if trimmed.hasPrefix("- ") {
            let text = "• " + trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            appendLine(String(text), attributes: bulletAttributes)
            continue
        }

        if let range = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            let text = String(trimmed[range.upperBound...])
            appendLine("\(trimmed[..<range.upperBound])\(text)", attributes: numberedAttributes)
            continue
        }

        appendLine(trimmed, attributes: bodyAttributes)
    }

    return result
}

func exportPDF(from attributedString: NSAttributedString, to destination: URL) throws {
    guard let consumer = CGDataConsumer(url: destination as CFURL) else {
        throw NSError(domain: "MakePDF", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create data consumer"])
    }

    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw NSError(domain: "MakePDF", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF context"])
    }

    let printableRect = mediaBox.insetBy(dx: 54, dy: 72)
    let framesetter = CTFramesetterCreateWithAttributedString(attributedString)

    var currentIndex = 0

    repeat {
        context.beginPDFPage(nil)

        let path = CGMutablePath()
        path.addRect(printableRect)

        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: currentIndex, length: 0), path, nil)
        CTFrameDraw(frame, context)

        let visibleRange = CTFrameGetVisibleStringRange(frame)
        currentIndex += visibleRange.length

        context.endPDFPage()
    } while currentIndex < attributedString.length && currentIndex > 0

    context.closePDF()
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: make_pdf.swift <input.md> <output.pdf>\n", stderr)
    exit(1)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

do {
    let markdown = try String(contentsOf: inputURL, encoding: .utf8)
    let attributed = buildDocument(from: markdown)
    try exportPDF(from: attributed, to: outputURL)
    print("Wrote \(outputURL.path)")
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
