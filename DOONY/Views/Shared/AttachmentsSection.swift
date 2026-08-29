import SwiftUI
import SwiftData
import PhotosUI
import Observation
import UniformTypeIdentifiers

/// Any dossier model that can own encrypted attachments.
protocol AttachmentOwning: AnyObject {
    var attachments: [Attachment] { get set }
}

extension Advisor: AttachmentOwning {}
extension Vehicle: AttachmentOwning {}
extension DriverLicense: AttachmentOwning {}
extension VoterRegistration: AttachmentOwning {}
extension RealProperty: AttachmentOwning {}
extension FinancialTie: AttachmentOwning {}
extension NearAndDearItem: AttachmentOwning {}
extension Membership: AttachmentOwning {}
extension EmploymentBusiness: AttachmentOwning {}
extension MailingAddressRecord: AttachmentOwning {}

/// Reusable list of encrypted attachments with add-from-photos and add-from-files.
struct AttachmentsSection<Owner: AttachmentOwning & PersistentModel & Observable>: View {
    @Bindable var owner: Owner
    @Environment(\.modelContext) private var context

    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var keepMetadata = false
    @State private var errorText: String?

    var body: some View {
        Section("Documents & photos (encrypted on-device)") {
            Toggle("Keep photo location/EXIF metadata", isOn: $keepMetadata)
                .font(.footnote)
            Text(keepMetadata
                 ? "Imported photos will retain GPS/EXIF."
                 : "GPS/EXIF is stripped from imported photos (recommended).")
                .font(.caption2).foregroundStyle(.secondary)

            ForEach(owner.attachments) { att in
                HStack {
                    Image(systemName: ExifStripper.isImage(typeIdentifier: att.typeIdentifier) ? "photo" : "doc")
                    VStack(alignment: .leading) {
                        Text(att.displayName).lineLimit(1)
                        Text("\(att.byteCount / 1024) KB\(att.retainedImageMetadata ? " • metadata kept" : "")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .onDelete(perform: deleteAttachments)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Add photo", systemImage: "photo.badge.plus")
            }
            Button {
                showFileImporter = true
            } label: {
                Label("Add document", systemImage: "doc.badge.plus")
            }

            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await importPhoto(newItem) }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .image, .plainText, .item],
                      allowsMultipleSelection: false) { result in
            handleFileImport(result)
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let type = item.supportedContentTypes.first?.identifier ?? UTType.jpeg.identifier
            try addAttachment(data: data, name: "photo-\(shortID()).jpg", type: type)
        } catch {
            errorText = "Could not import photo."
        }
        photoItem = nil
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier)
                    ?? UTType.data.identifier
                try addAttachment(data: data, name: url.lastPathComponent, type: type)
            } catch {
                errorText = "Could not import file."
            }
        case .failure:
            errorText = "File import cancelled or failed."
        }
    }

    private func addAttachment(data: Data, name: String, type: String) throws {
        guard let store = AttachmentStore.shared else {
            errorText = "Secure storage unavailable."; return
        }
        let att = try store.importAttachment(data: data, displayName: name,
                                              typeIdentifier: type, keepImageMetadata: keepMetadata)
        context.insert(att)
        owner.attachments.append(att)
        try? context.save()
    }

    private func deleteAttachments(at offsets: IndexSet) {
        guard let store = AttachmentStore.shared else { return }
        for index in offsets {
            let att = owner.attachments[index]
            store.delete(att, context: context)
        }
        owner.attachments.remove(atOffsets: offsets)
        try? context.save()
    }

    private func shortID() -> String { String(UUID().uuidString.prefix(6)) }
}
