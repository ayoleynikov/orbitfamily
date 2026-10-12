import Foundation
import Supabase

/// Snapshot of a family member as returned by `my_family` / `private.member_json`.
struct FamilyTreeMemberSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    let role: String
    let avatarURL: String?
    let avatarPath: String?

    var canEditTree: Bool {
        role == "owner" || role == "parent"
    }

    var roleTitle: String {
        switch role {
        case "owner": return "Владелец"
        case "parent": return "Родитель"
        case "adult": return "Взрослый"
        case "child": return "Ребёнок"
        case "guest": return "Гость"
        default: return "Участник"
        }
    }
}

struct FamilyTreeSession: Hashable, Sendable {
    let familyId: UUID
    let familyName: String
    let me: FamilyTreeMemberSnapshot
    let members: [FamilyTreeMemberSnapshot]

    var canEdit: Bool { me.canEditTree }

    func member(id: UUID) -> FamilyTreeMemberSnapshot? {
        members.first { $0.id == id }
    }
}

/// Host-app hooks so the tree can reuse existing chat / CallKit / LiveKit flows.
protocol FamilyTreeHostActions {
    func openDirectChat(memberId: UUID, chatId: UUID)
    func startCall(memberId: UUID, chatId: UUID, video: Bool)
}

enum FamilyTreeDeepLink {
    static let url = URL(string: "orbitfamily://tree")!

    static func isTree(_ url: URL) -> Bool {
        let host = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return url.scheme == "orbitfamily" && (host == "tree" || url.path == "/tree")
    }
}

extension Notification.Name {
    /// userInfo: `memberId` (UUID), `chatId` (UUID)
    static let orbitOpenDirectChat = Notification.Name("orbit.Orbit-Family.openDirectChat")
    /// userInfo: `memberId` (UUID), `chatId` (UUID), `video` (Bool)
    static let orbitStartCall = Notification.Name("orbit.Orbit-Family.startCall")
}

/// Default actions: posts notifications the existing chat / call stack should handle.
struct NotificationFamilyTreeActions: FamilyTreeHostActions {
    func openDirectChat(memberId: UUID, chatId: UUID) {
        NotificationCenter.default.post(
            name: .orbitOpenDirectChat,
            object: nil,
            userInfo: ["memberId": memberId, "chatId": chatId]
        )
    }

    func startCall(memberId: UUID, chatId: UUID, video: Bool) {
        NotificationCenter.default.post(
            name: .orbitStartCall,
            object: nil,
            userInfo: ["memberId": memberId, "chatId": chatId, "video": video]
        )
    }
}

enum FamilyTreeSeenFlag {
    static let defaultsKey = "orbit.familyTree.seen"

    static var isNew: Bool {
        !UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }
}
