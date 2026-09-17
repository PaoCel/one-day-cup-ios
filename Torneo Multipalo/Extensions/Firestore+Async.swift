import FirebaseFirestore

protocol FirestoreDocumentBackfillable {
    func withDocumentID(_ documentID: String) -> Self
}

private enum FirestoreDocumentDecoder {
    static func backfilledDocumentID<T>(_ value: T, documentID: String) -> T {
        guard let backfillable = value as? any FirestoreDocumentBackfillable,
              let updatedValue = backfillable.withDocumentID(documentID) as? T else {
            return value
        }

        return updatedValue
    }
}

extension DocumentSnapshot {
    func decodedData<T: Decodable>(as type: T.Type) throws -> T {
        let decoded = try data(as: type)
        return FirestoreDocumentDecoder.backfilledDocumentID(decoded, documentID: documentID)
    }
}

extension Query {
    func getDocumentsAs<T: Decodable>(_ type: T.Type) async throws -> [T] {
        let snapshot = try await getDocuments()
        return snapshot.documents.compactMap { try? $0.decodedData(as: type) }
    }
}

extension DocumentReference {
    func getDocumentAs<T: Decodable>(_ type: T.Type) async throws -> T? {
        let snapshot = try await getDocument()
        guard snapshot.exists else { return nil }
        return try? snapshot.decodedData(as: type)
    }
}
