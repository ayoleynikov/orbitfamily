import Foundation
import Supabase

/// `my_family` JSON (`private.family_bundle` / `private.member_json`).
struct FamilyTreeMyFamilyBundle: Decodable, Sendable {
    struct Family: Decodable, Sendable {
        let id: UUID
        let name: String
    }

    struct Member: Decodable, Sendable {
        let id: UUID
        let role: String
        let displayName: String
        let avatarURL: String?
        let avatarPath: String?

        enum CodingKeys: String, CodingKey {
            case id, role
            case displayName = "display_name"
            case avatarURL = "avatar_url"
            case avatarPath = "avatar_path"
        }

        var snapshot: FamilyTreeMemberSnapshot {
            FamilyTreeMemberSnapshot(
                id: id,
                displayName: displayName,
                role: role,
                avatarURL: avatarURL,
                avatarPath: avatarPath
            )
        }
    }

    let family: Family
    let me: Member
    let members: [Member]

    var session: FamilyTreeSession {
        FamilyTreeSession(
            familyId: family.id,
            familyName: family.name,
            me: me.snapshot,
            members: members.map(\.snapshot)
        )
    }
}

extension FamilyTreeSession {
    /// Preferred: map from the in-memory Member models the app already has.
    static func make(
        familyId: UUID,
        familyName: String,
        meId: UUID,
        members: [(id: UUID, displayName: String, role: String, avatarURL: String?, avatarPath: String?)]
    ) -> FamilyTreeSession {
        let snaps = members.map {
            FamilyTreeMemberSnapshot(
                id: $0.id,
                displayName: $0.displayName,
                role: $0.role,
                avatarURL: $0.avatarURL,
                avatarPath: $0.avatarPath
            )
        }
        let me = snaps.first { $0.id == meId } ?? snaps[0]
        return FamilyTreeSession(familyId: familyId, familyName: familyName, me: me, members: snaps)
    }

    static func load(from client: SupabaseClient) async throws -> FamilyTreeSession {
        let bundle: FamilyTreeMyFamilyBundle = try await client
            .rpc("my_family")
            .execute()
            .value
        return bundle.session
    }
}
