import UIKit
import UserNotifications

/// Attacca alla notifica lo stemma della squadra che ha segnato.
///
/// Il server lo sceglie già — `functions/index.js`, `buildMatchNotificationPayload`:
/// il logo di chi ha segnato, e sull'autogol quello dell'altra squadra — e lo
/// spedisce come `image` di FCM. Su iOS però quell'immagine non compare da
/// sola: senza un'estensione che la scarichi e la attacchi, il campo viene
/// ignorato e la notifica resta di solo testo. È tutto qui il mestiere di
/// questo file.
///
/// ⚠️ **L'icona tonda a sinistra resta quella dell'app.** Non è una scelta:
/// iOS non la lascia cambiare per notifica. Lo stemma compare come miniatura a
/// destra, e grande quando la notifica si espande.
///
/// Niente Firebase qui dentro: l'helper di FirebaseMessaging farebbe la stessa
/// cosa, ma legare un'estensione a un pacchetto per venti righe di download
/// significa portarsi dietro tutto il peso di Firebase in un processo che iOS
/// uccide dopo pochi secondi.
final class NotificationService: UNNotificationServiceExtension {
    private var completa: ((UNNotificationContent) -> Void)?
    private var contenuto: UNMutableNotificationContent?
    private var scarico: URLSessionDataTask?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        completa = contentHandler
        let mutabile = request.content.mutableCopy() as? UNMutableNotificationContent
        contenuto = mutabile
        guard let mutabile else { return contentHandler(request.content) }

        guard let url = Self.immagine(in: request.content.userInfo) else {
            return contentHandler(mutabile)
        }

        // `dataTask` e non `download`: il file temporaneo di `downloadTask`
        // sparisce quando il task finisce, e l'allegato va invece spostato in
        // un posto che sopravviva alla chiamata.
        scarico = URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { contentHandler(mutabile) }
            guard let data, let allegato = Self.allegato(data: data, nome: url.lastPathComponent) else { return }
            mutabile.attachments = [allegato]
        }
        scarico?.resume()
    }

    /// iOS concede pochi secondi: scaduti, la notifica parte com'è. Meglio
    /// senza stemma che in ritardo o persa.
    override func serviceExtensionTimeWillExpire() {
        scarico?.cancel()
        if let contenuto { completa?(contenuto) }
    }

    /// L'url dell'immagine, da dove FCM la mette.
    private static func immagine(in info: [AnyHashable: Any]) -> URL? {
        let candidati = [
            (info["fcm_options"] as? [String: Any])?["image"] as? String,
            info["image"] as? String,
        ]
        guard let raw = candidati.compactMap({ $0 }).first(where: { !$0.isEmpty }) else { return nil }
        return URL(string: raw)
    }

    /// Che immagine e', letta dai primi byte.
    private static func tipo(data: Data) -> String? {
        let b = [UInt8](data.prefix(12))
        guard b.count >= 12 else { return nil }
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if b.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        // WEBP: "RIFF" …4 byte di lunghezza… "WEBP". iOS lo accetta come
        // allegato solo dalla 14, e sotto lo scarta: meglio saperlo qui.
        if b.starts(with: [0x52, 0x49, 0x46, 0x46]), Array(b[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return "webp" }
        return nil
    }

    private static func allegato(data: Data, nome: String) -> UNNotificationAttachment? {
        // L'estensione del file conta: senza, iOS non sa che tipo di allegato
        // sia e lo scarta in silenzio. E non basta leggerla dall'url: gli
        // stemmi stanno su Firebase Storage, dove il nome finisce con
        // `?alt=media&token=…` e di estensione non ce n'e'. Si guardano i primi
        // byte, che non mentono.
        let estensione = tipo(data: data) ?? {
            let dallUrl = (nome as NSString).pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "gif"].contains(dallUrl) ? dallUrl : "png"
        }()
        let cartella = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
            let file = cartella.appendingPathComponent("stemma.\(estensione)")
            try data.write(to: file)
            return try UNNotificationAttachment(identifier: "stemma", url: file, options: nil)
        } catch {
            return nil
        }
    }
}
