import SwiftUI
import UIKit

/// Bridge UIKit → SwiftUI per selezionare un'immagine dalla libreria o fotocamera.
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    /// Il ritaglio quadrato di sistema. Acceso quasi ovunque (foto profilo,
    /// logo squadra: li' il quadrato e' proprio la forma giusta), ma **spento
    /// sulla figurina**, dove l'inquadratura la decide il generatore e
    /// all'utente si promette per iscritto che non deve ritagliare niente.
    var allowsEditing: Bool = true

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = allowsEditing
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let key: UIImagePickerController.InfoKey = info[.editedImage] != nil ? .editedImage : .originalImage
            parent.image = info[key] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
