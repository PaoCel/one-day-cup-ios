import Foundation
import FirebaseStorage

class StorageService {
    private var storage: Storage { Storage.storage() }

    func uploadImage(_ data: Data, path: String) async throws -> URL {
        try RuntimeSafety.shared.assertAllowsMutation("caricare immagini su Storage")
        let ref = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType(for: path)

        _ = try await ref.putDataAsync(data, metadata: metadata)
        return try await ref.downloadURL()
    }

    func deleteImage(path: String) async throws {
        try RuntimeSafety.shared.assertAllowsMutation("eliminare immagini da Storage")
        try await storage.reference().child(path).delete()
    }

    private func contentType(for path: String) -> String {
        let lowercasedPath = path.lowercased()

        if lowercasedPath.hasSuffix(".png") {
            return "image/png"
        }
        if lowercasedPath.hasSuffix(".webp") {
            return "image/webp"
        }
        if lowercasedPath.hasSuffix(".heic") || lowercasedPath.hasSuffix(".heif") {
            return "image/heic"
        }

        return "image/jpeg"
    }
}
