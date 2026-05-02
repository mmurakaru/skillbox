import SwiftUI

struct NewSkillForm: View {
    let rootPath: String
    let onCreate: (URL) -> Void
    let onCancel: () -> Void

    @State private var rawName: String = ""
    @State private var errorText: String?
    @FocusState private var nameFocused: Bool

    private var sanitised: String {
        SkillCreator.sanitize(rawName)
    }

    private var pathPreview: String {
        let name = sanitised.isEmpty ? "<name>" : sanitised
        return "\(rootPath)/\(name)/SKILL.md"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("New skill")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel (Esc)")
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("kebab-case-name", text: $rawName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit { submit() }
                    .onChange(of: rawName) { _, _ in errorText = nil }

                Text(pathPreview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !rawName.isEmpty && sanitised != rawName.lowercased() {
                    Text("Will be saved as: \(sanitised)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let err = errorText {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create") { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(sanitised.isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            nameFocused = true
        }
    }

    private func submit() {
        guard !sanitised.isEmpty else { return }
        let result = SkillCreator.create(name: sanitised, in: rootPath)
        switch result {
        case .success(let url):
            onCreate(url)
        case .failure(let err):
            errorText = err.errorDescription
        }
    }
}
