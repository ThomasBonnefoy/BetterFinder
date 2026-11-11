import AppKit
import BetterFinderCore
import SwiftUI

/// How Git states are written and coloured.
enum GitText {
    /// The letter of a state, as `git status` and code editors write it.
    static func letter(_ state: GitFileState) -> String {
        switch state {
        case .untracked: "?"
        case .added: "A"
        case .modified: "M"
        case .renamed: "R"
        case .deleted: "D"
        case .conflicted: "!"
        }
    }

    static func color(_ state: GitFileState) -> NSColor {
        switch state {
        case .untracked: .systemTeal
        case .added: .systemGreen
        case .modified, .renamed: .systemOrange
        case .deleted, .conflicted: .systemRed
        }
    }

    /// What the letter means, for the tooltip.
    static func explanation(_ state: GitFileState, isFolder: Bool) -> String {
        if isFolder {
            switch state {
            case .untracked: return "Git : contient des éléments non suivis"
            case .added: return "Git : contient des fichiers ajoutés"
            case .modified, .renamed, .deleted: return "Git : contient des modifications"
            case .conflicted: return "Git : contient des conflits"
            }
        }
        switch state {
        case .untracked: return "Git : non suivi"
        case .added: return "Git : ajouté"
        case .modified: return "Git : modifié"
        case .renamed: return "Git : renommé"
        case .deleted: return "Git : supprimé"
        case .conflicted: return "Git : en conflit"
        }
    }

    /// Name of where HEAD is: the branch, else the commit.
    static func head(_ status: GitStatus) -> String {
        if let branch = status.branch { return branch }
        if let commit = status.commit { return "détaché à \(commit)" }
        return "aucun commit"
    }

    /// "↑2 ↓1": commits to push and to pull, or `nil` when level.
    static func sync(_ status: GitStatus) -> String? {
        var parts: [String] = []
        if status.ahead > 0 { parts.append("↑\(status.ahead)") }
        if status.behind > 0 { parts.append("↓\(status.behind)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// "2 indexés · 3 modifiés · 1 non suivi", or "aucune modification".
    static func changes(_ status: GitStatus) -> String {
        var parts: [String] = []
        if status.conflicted > 0 {
            parts.append("\(status.conflicted) en conflit")
        }
        if status.staged > 0 {
            parts.append(status.staged > 1 ? "\(status.staged) indexés" : "1 indexé")
        }
        if status.unstaged > 0 {
            parts.append(status.unstaged > 1 ? "\(status.unstaged) modifiés" : "1 modifié")
        }
        if status.untracked > 0 {
            parts.append(status.untracked > 1 ? "\(status.untracked) non suivis" : "1 non suivi")
        }
        return parts.isEmpty ? "aucune modification" : parts.joined(separator: " · ")
    }

    /// The tooltip of the status bar: the repository and its upstream.
    static func details(_ info: GitInfo) -> String {
        var lines = ["Dépôt Git : \(info.root.lastPathComponent)"]
        let status = info.status
        if let upstream = status.upstream {
            var line = "Branche suivie : \(upstream)"
            if status.ahead > 0 {
                line += status.ahead > 1 ? ", \(status.ahead) commits à envoyer" : ", 1 commit à envoyer"
            }
            if status.behind > 0 {
                line += status.behind > 1 ? ", \(status.behind) commits à recevoir" : ", 1 commit à recevoir"
            }
            if status.ahead == 0, status.behind == 0 { line += ", à jour" }
            lines.append(line)
        } else if status.branch != nil {
            lines.append("Aucune branche suivie")
        }
        return lines.joined(separator: "\n")
    }
}

/// The Git part of the status bar: branch, commits to push or pull, changes.
struct GitStatusLabel: View {
    let info: GitInfo

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
            Text(GitText.head(info.status))
                .foregroundStyle(.primary)
            if let sync = GitText.sync(info.status) {
                Text(sync).monospacedDigit()
            }
            Text("·")
            Text(GitText.changes(info.status))
                .foregroundStyle(info.status.conflicted > 0 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
        .help(GitText.details(info))
        .accessibilityElement(children: .combine)
    }
}

/// The small coloured letter that marks a changed file in the lists.
final class GitBadgeView: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        font = .systemFont(ofSize: 11, weight: .bold)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        widthAnchor.constraint(equalToConstant: 14).isActive = true
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ state: GitFileState?, isFolder: Bool) {
        guard let state else {
            isHidden = true
            stringValue = ""
            toolTip = nil
            return
        }
        isHidden = false
        stringValue = GitText.letter(state)
        textColor = GitText.color(state)
        toolTip = GitText.explanation(state, isFolder: isFolder)
    }
}
