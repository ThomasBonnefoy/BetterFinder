import AppKit
import BetterFinderCore
import SwiftUI

/// Explorer-style address bar: clickable breadcrumbs that turn into an
/// editable path when the empty area is clicked (or with Cmd+L).
struct AddressBar: View {
    let model: BrowserModel

    @State private var text = ""
    @State private var isInvalid = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if model.isEditingAddress {
                editor
            } else {
                breadcrumbs
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 220, idealWidth: 520, maxWidth: 760, minHeight: 28)
    }

    private var editor: some View {
        TextField("Chemin du dossier", text: $text)
            .textFieldStyle(.plain)
            .foregroundStyle(isInvalid ? Color.red : Color.primary)
            .focused($isFocused)
            .onSubmit {
                if !model.submitAddress(text) {
                    isInvalid = true
                    NSSound.beep()
                }
            }
            .onExitCommand { model.endEditingAddress() }
            .onChange(of: text) { isInvalid = false }
            .onChange(of: isFocused) { _, focused in
                if !focused { model.endEditingAddress() }
            }
            .onAppear {
                text = model.addressText
                isInvalid = false
                isFocused = true
            }
    }

    private var breadcrumbs: some View {
        let crumbs = currentCrumbs
        // When the whole path does not fit, drop folders from the left, as
        // Explorer does: the end of the path is the part that matters.
        return ViewThatFits(in: .horizontal) {
            ForEach(0..<max(crumbs.count, 1), id: \.self) { hidden in
                crumbRow(Array(crumbs.dropFirst(hidden)), isTruncated: hidden > 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { model.beginEditingAddress() }
        .help("Cliquez pour saisir un chemin")
    }

    /// Steps shown for the current location. A path on a network drive
    /// starts at the drive, under the name it has in the sidebar.
    private var currentCrumbs: [Crumb] {
        switch model.location {
        case .drive(let id):
            let name = model.driveMonitor?.drive(id)?.name ?? "Lecteur réseau"
            return [Crumb(name: name, action: { model.openDrive(id) })]
        case .folder(let url):
            return Breadcrumbs.make(for: url).map { crumb in
                let name = model.driveMonitor?.driveMounted(at: crumb.url)?.name ?? DisplayName.of(crumb.url)
                return Crumb(name: name, action: { model.navigate(to: crumb.url) })
            }
        }
    }

    private struct Crumb: Identifiable {
        let id = UUID()
        let name: String
        let action: () -> Void
    }

    private func crumbRow(_ crumbs: [Crumb], isTruncated: Bool) -> some View {
        HStack(spacing: 3) {
            if isTruncated {
                Text("…").foregroundStyle(.secondary)
                separator
            }
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                let isLast = index == crumbs.count - 1
                Button(crumb.name, action: crumb.action)
                    .buttonStyle(.plain)
                    .fontWeight(isLast ? .medium : .regular)
                    .lineLimit(1)
                    .fixedSize()

                if !isLast {
                    separator
                }
            }
        }
    }

    private var separator: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}
