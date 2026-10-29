import PhotosUI
import ShunfengCore
import SwiftUI
import UIKit

/// Photo → a downscaled JPEG small enough to send quickly (the model reads 2000 px fine).
enum PhotoPrep {
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 2000) -> Data? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

/// The camera, for photographing a boarding pass.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// "Is this right?" before anything read from the photo is used. A handwritten change is called out,
/// because it usually means the printed value is no longer true.
struct BoardingPassConfirm: View {
    let pass: BoardingPass
    let use: () -> Void
    let retake: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("班號", pass.flightCode)
                    row("日期", pass.date.map { $0.replacingOccurrences(of: "-", with: "/") })
                    row("航線", "\(pass.from ?? "?") → \(pass.to ?? "?")（\(pass.destinationName ?? "?")）")
                    row("登機門", pass.gate)
                    row("登機時間", pass.boardingTime)
                    row("起飛時間", pass.departureTime)
                    row("座位", pass.seat)
                } footer: {
                    Text("由 Meta 的 Muse Spark 從照片讀出。請確認跟登機證一樣再使用。")
                }
                if !pass.handwrittenChanges.isEmpty {
                    Section {
                        Label("登機證上有手寫修改：\(pass.handwrittenChanges)", systemImage: "pencil.and.scribble")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("手寫的通常是地勤更新過的資訊，以手寫和現場廣播為準。")
                    }
                }
            }
            .navigationTitle("確認登機證")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("重拍", action: retake) }
                ToolbarItem(placement: .confirmationAction) { Button("使用", action: use).bold() }
            }
        }
    }

    private func row(_ title: String, _ value: String?) -> some View {
        LabeledContent(title, value: value ?? "讀不到")
    }
}

extension BoardingPass: Identifiable {
    public var id: String { [flight, date, from, to, seat].map { $0 ?? "" }.joined(separator: "|") }
}
