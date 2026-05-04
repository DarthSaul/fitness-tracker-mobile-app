import SwiftUI
import PhotosUI

/// Feedback screen reachable from Settings → Feedback. Mirrors the Vue page:
/// submit form on top (text + optional screenshot via PhotosPicker), filter
/// pills (Unaddressed → Addressed → All), then the list.
struct FeedbackView: View {
    @State private var viewModel: FeedbackViewModel
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var screenshotPreview: Image?

    init(viewModel: FeedbackViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            submitSection
            filterSection
            listSection
        }
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onChange(of: photosPickerItem) { _, newItem in
            Task { await loadPickedPhoto(newItem) }
        }
    }

    // MARK: - Submit

    private var submitSection: some View {
        Section {
            TextField(
                "What's on your mind?",
                text: Binding(
                    get: { viewModel.draftContent },
                    set: { viewModel.draftContent = $0 }
                ),
                axis: .vertical
            )
            .lineLimit(3...8)
            .font(.body)

            attachmentRow

            Button {
                Task { await viewModel.submit() }
            } label: {
                HStack {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }
                    Text(viewModel.isSubmitting ? "Saving…" : "Submit")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSubmit)

            if viewModel.didSubmit {
                Label("Feedback saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.footnote)
            }
            if let err = viewModel.submitError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        } header: {
            Text("New feedback")
        } footer: {
            Text("Jot down thoughts while you're using the app. Optional screenshot helps with bug reports.")
        }
    }

    @ViewBuilder
    private var attachmentRow: some View {
        if let preview = screenshotPreview, let attached = viewModel.draftScreenshot {
            HStack(alignment: .top, spacing: 12) {
                preview
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(attached.filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(formatBytes(attached.data.count))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(role: .destructive) {
                    photosPickerItem = nil
                    screenshotPreview = nil
                    viewModel.clearScreenshot()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } else {
            PhotosPicker(
                selection: $photosPickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Attach screenshot", systemImage: "paperclip")
            }
        }
    }

    // MARK: - Filter pills

    private var filterSection: some View {
        Section {
            Picker("Filter", selection: Binding(
                get: { viewModel.filter },
                set: { viewModel.filter = $0 }
            )) {
                ForEach(FeedbackViewModel.Filter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    // MARK: - List

    @ViewBuilder
    private var listSection: some View {
        Section {
            if viewModel.isLoading && viewModel.allFeedback.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    HStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 40)
                    }
                }
            } else if viewModel.filteredFeedback.isEmpty {
                Text(viewModel.allFeedback.isEmpty ? "No feedback yet." : "Nothing in this filter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(viewModel.filteredFeedback) { item in
                    FeedbackRow(item: item) {
                        Task { await viewModel.toggleAddressed(item) }
                    }
                }
            }

            if let err = viewModel.loadError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            HStack {
                Text("Submitted")
                Spacer()
                if !viewModel.allFeedback.isEmpty {
                    Text("\(viewModel.filteredFeedback.count) of \(viewModel.allFeedback.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - PhotosPicker glue

    /// Loads bytes + a SwiftUI Image preview from the picker selection.
    /// Detects MIME type via the picked item's UTType so the multipart part
    /// header matches what the server validates against (image/*).
    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else {
            screenshotPreview = nil
            viewModel.clearScreenshot()
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let mime = inferMimeType(item: item)
            let filename = "screenshot-\(Int(Date.now.timeIntervalSince1970))\(extensionFor(mime))"
            viewModel.draftScreenshot = .init(data: data, filename: filename, mimeType: mime)

            if let uiImage = UIImage(data: data) {
                screenshotPreview = Image(uiImage: uiImage)
            }
        } catch {
            viewModel.submitError = "Couldn't load screenshot: \(error.localizedDescription)"
        }
    }

    /// PhotosPicker exposes the picked asset's content type via
    /// `supportedContentTypes`. The first entry is the canonical UTType for
    /// the asset; we map it to a MIME string the multipart encoder needs.
    private func inferMimeType(item: PhotosPickerItem) -> String {
        if let preferred = item.supportedContentTypes.first?.preferredMIMEType {
            return preferred
        }
        return "image/jpeg"
    }

    private func extensionFor(_ mime: String) -> String {
        switch mime {
        case "image/png":  return ".png"
        case "image/heic": return ".heic"
        case "image/gif":  return ".gif"
        default:           return ".jpg"
        }
    }

    private func formatBytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

// MARK: - Row

private struct FeedbackRow: View {
    let item: FeedbackDTO
    let onToggleAddressed: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                Text(item.content)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                if let urlString = item.screenshotUrl, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("View screenshot", systemImage: "photo")
                            .font(.caption)
                    }
                }

                Text(formatDate(item.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onToggleAddressed) {
                Image(systemName: item.addressed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.addressed ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.addressed ? "Mark unaddressed" : "Mark addressed")
        }
        .padding(.vertical, 4)
    }

    /// Mirrors the Vue page's "first name; default to You" rule.
    private var displayName: String {
        guard let raw = item.user.name?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty else {
            return "You"
        }
        return raw.split(separator: " ").first.map(String.init) ?? "You"
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }
}
