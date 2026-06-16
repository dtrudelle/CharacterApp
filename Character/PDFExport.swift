import SwiftUI
import PDFKit
import AppKit
import UniformTypeIdentifiers

// =====================================================================
//  PDFExport.swift
//  Rendu de la fiche en PDF AU FORMAT FIXE (ratio Lettre), imprimable.
//  Chaque page logique (hauteur naturelle) est découpée en pages physiques
//  de hauteur Lettre : on décale le contenu vers le haut puis on le fenêtre
//  à la taille d'une page. Le rendu passe par ImageRenderer -> PDFPage(image:)
//  (orientation correcte), sans manipulation de pixels.
// =====================================================================

@MainActor
enum PDFExport {

    static func makePDF(character: Character,
                        references: SheetBuilder.References,
                        scale: CGFloat = 2) -> Data? {
        let view = CharacterSheetView(character: character, references: references)
        let pageWidth = view.printablePageWidth
        let pageHeight = view.printablePageHeight
        let document = PDFDocument()
        var pageIndex = 0

        for logical in view.pdfLogicalPages() {
            // 1) Mesure de la hauteur naturelle du contenu (sans rasteriser).
            var contentHeight = pageHeight
            let measurer = ImageRenderer(content: logical)
            measurer.render { size, _ in contentHeight = size.height }
            let count = max(1, Int((contentHeight / pageHeight).rounded(.up)))

            // 2) Une page physique par tranche de hauteur Lettre.
            for k in 0..<count {
                let physical = logical
                    .offset(y: -CGFloat(k) * pageHeight)
                    .frame(width: pageWidth, height: pageHeight, alignment: .topLeading)
                    .clipped()
                    .background(Color.white)

                let renderer = ImageRenderer(content: physical)
                renderer.scale = scale
                guard let image = renderer.nsImage,
                      let pdfPage = PDFPage(image: image) else { continue }
                document.insert(pdfPage, at: pageIndex)
                pageIndex += 1
            }
        }

        return document.pageCount > 0 ? document.dataRepresentation() : nil
    }

    static func exportWithSavePanel(character: Character,
                                    references: SheetBuilder.References) {
        guard let data = makePDF(character: character, references: references) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(sanitized(character.name)).pdf"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    private static func sanitized(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.replacingOccurrences(of: "/", with: "-")
                             .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "personnage" : cleaned
    }
}
