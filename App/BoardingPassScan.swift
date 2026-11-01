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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("從照片讀到的內容，請檢查一次。").font(Theme.body).foregroundStyle(Theme.textSecondary)
                    row("班號", pass.flightCode)
                    row("日期", pass.date.map { $0.replacingOccurrences(of: "-", with: "/") })
                    row("航線", "\(pass.from ?? "?") → \(pass.to ?? "?")（\(pass.destinationName ?? "?")）")
                    row("登機門", pass.gate, keys: ["登機門", "gate", "Gate", "GATE"])
                    row("登機時間", pass.boardingTime, keys: ["登機時間", "boarding", "Boarding", "BOARDING"])
                    row("起飛時間", pass.departureTime, keys: ["起飛", "departure", "Departure"])
                    row("座位", pass.seat, keys: ["座位", "seat", "Seat", "SEAT"])
                    if !pass.handwrittenChanges.isEmpty {
                        Label("登機證上有手寫修改：\(pass.handwrittenChanges)。手寫的通常是地勤更新過的資訊，以手寫和現場廣播為準。",
                              systemImage: "pencil.and.scribble")
                            .sfNote(Theme.possible, Theme.possibleBg)
                    }
                    Text("由 Meta 的 Muse Spark 從照片讀出。").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    Button("資料正確，使用這班", action: use).buttonStyle(.sfPrimary).padding(.top, 8)
                    Button("重拍", action: retake).buttonStyle(.sfSecondary)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
            }
            .background(Theme.page)
            .navigationTitle("確認登機證資料")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Theme.brand)
    }

    /// A field; one the handwritten note mentions gets the orange 2 pt outline and a "手寫修改" tag (M11).
    private func row(_ title: String, _ value: String?, keys: [String] = []) -> some View {
        let edited = keys.contains { pass.handwrittenChanges.contains($0) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                if edited {
                    Label("手寫修改", systemImage: "pencil").font(Theme.caption)
                        .foregroundStyle(Theme.onBrand)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.possible, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
                }
            }
            Text(value ?? "讀不到")
                .font(Theme.heading)
                .foregroundStyle(value == nil ? Theme.textDisabled : Theme.textPrimary)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: Theme.touch, alignment: .leading)
                .background(edited ? Theme.possibleBg : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .strokeBorder(edited ? Theme.possible : Theme.border, lineWidth: edited ? 2 : 1))
        }
        .accessibilityElement(children: .combine)
    }
}

extension BoardingPass: Identifiable {
    public var id: String { [flight, date, from, to, seat].map { $0 ?? "" }.joined(separator: "|") }
}
