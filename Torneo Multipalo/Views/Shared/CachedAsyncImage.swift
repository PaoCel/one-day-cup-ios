import SwiftUI
import UIKit
import PDFKit

// MARK: - Cache

actor ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

actor RemoteImagePipeline {
    static let shared = RemoteImagePipeline()

    private let session: URLSession
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 80 * 1024 * 1024,
            diskCapacity: 250 * 1024 * 1024,
            diskPath: "torneo-multipalo-images"
        )
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        session = URLSession(configuration: configuration)
    }

    func image(for rawURL: String, url: URL) async -> UIImage? {
        if let cached = await ImageCache.shared.image(for: rawURL) {
            return cached
        }

        if let task = inFlight[rawURL] {
            return await task.value
        }

        let task = Task<UIImage?, Never> { [session] in
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad

            do {
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode),
                   httpResponse.statusCode != 304 {
                    return nil
                }

                guard let image = Self.decodedImage(from: data) else {
                    return nil
                }

                await ImageCache.shared.store(image, for: rawURL)
                return image
            } catch {
                return nil
            }
        }

        inFlight[rawURL] = task
        let image = await task.value
        inFlight[rawURL] = nil
        return image
    }

    private static func decodedImage(from data: Data) -> UIImage? {
        if let image = UIImage(data: data) {
            return image
        }

        guard let document = PDFDocument(data: data),
              let page = document.page(at: 0) else {
            return nil
        }

        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return nil
        }

        let maxDimension: CGFloat = 1024
        let scale = min(maxDimension / pageBounds.width, maxDimension / pageBounds.height, 1)
        let renderSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: renderSize)

        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: renderSize))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: renderSize.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }
}

// MARK: - View

/// AsyncImage con cache in memoria. Mostra un placeholder durante il caricamento.
struct CachedAsyncImage: View {
    let urlString: String?
    var placeholderIcon: String = "person.fill"
    var placeholderColor: Color = Color(.systemGray5)
    var contentMode: ContentMode = .fill
    /// Punto di ritaglio quando `contentMode == .fill`. Le miniature dei
    /// giocatori usano `.top`: nelle foto verticali il volto è quasi sempre
    /// sopra il centro geometrico, che altrimenti inquadra soprattutto il busto.
    var contentAlignment: Alignment = .center
    /// Ancora verticale fine del ritaglio `.fill`: 0 = bordo alto, 0.5 = centro.
    /// `contentAlignment` da solo conosce solo questi due estremi, e nessuno dei
    /// due va bene per la figurina del dettaglio giocatore: col centro la testa
    /// finisce fuori dal riquadro, col bordo alto resta un dito d'aria sopra i
    /// capelli e si perde il busto. Un valore intorno a 0.2 tiene il volto
    /// intero e l'inquadratura naturale. Se `nil` vale `contentAlignment`.
    var fillAnchorY: CGFloat?

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            if let img = loadedImage {
                loadedContent(img)
            } else {
                placeholderColor
                Image(systemName: placeholderIcon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: urlString) {
            await load()
        }
    }

    @ViewBuilder
    private func loadedContent(_ image: UIImage) -> some View {
        switch contentMode {
        case .fit:
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        case .fill:
            GeometryReader { geometry in
                let anchor = resolvedAnchorY
                // Riempimento calcolato a mano: `frame(alignment:)` sa ancorare
                // solo in alto o al centro, qui serve una frazione.
                let scale = max(
                    geometry.size.width / max(image.size.width, 1),
                    geometry.size.height / max(image.size.height, 1)
                )
                let scaledWidth = image.size.width * scale
                let scaledHeight = image.size.height * scale

                // Quanto si toglie dall'alto: la frazione chiesta dall'ancora,
                // ma mai piu' del 6% dell'immagine. Senza questo tetto una foto
                // molto verticale (un 9:16 scattato col telefono) perde in alto
                // quasi un quinto dell'inquadratura e la testa sparisce lo
                // stesso: l'eccedenza da ritagliare li' e' enorme.
                let overflowY = max(scaledHeight - geometry.size.height, 0)
                let topCrop = min(overflowY * anchor, scaledHeight * 0.06)

                Image(uiImage: image)
                    .resizable()
                    .frame(width: scaledWidth, height: scaledHeight)
                    .offset(
                        x: (geometry.size.width - scaledWidth) / 2,
                        y: -topCrop
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .clipped()
            }
        @unknown default:
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
    }

    /// `fillAnchorY` esplicita vince; altrimenti si traduce l'allineamento
    /// (top = 0, tutto il resto = centro) così i chiamanti esistenti non cambiano.
    private var resolvedAnchorY: CGFloat {
        if let fillAnchorY { return min(max(fillAnchorY, 0), 1) }
        return contentAlignment == .top ? 0 : 0.5
    }

    private func load() async {
        loadedImage = nil

        guard let raw = urlString, !raw.isEmpty, let url = URL(string: raw) else {
            return
        }

        if let cached = await ImageCache.shared.image(for: raw) {
            loadedImage = cached
            return
        }

        loadedImage = await RemoteImagePipeline.shared.image(for: raw, url: url)
    }
}
