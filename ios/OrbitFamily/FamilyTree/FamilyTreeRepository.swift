import Foundation
import UIKit
import Supabase

@MainActor
final class FamilyTreeRepository {
    private let client: SupabaseClient
    private let mediaBucket = "family-media"

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchPersons(familyId: UUID) async throws -> [FamilyTreePerson] {
        try await client
            .from("family_tree_persons")
            .select()
            .eq("family_id", value: familyId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func fetchLinks(familyId: UUID) async throws -> [FamilyTreeLink] {
        try await client
            .from("family_tree_links")
            .select()
            .eq("family_id", value: familyId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func fetchMoments(personId: UUID) async throws -> [FamilyTreeMoment] {
        try await client
            .from("family_tree_moments")
            .select()
            .eq("person_id", value: personId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    @discardableResult
    func insertPerson(_ row: FamilyTreePersonInsert) async throws -> FamilyTreePerson {
        try await client
            .from("family_tree_persons")
            .insert(row)
            .select()
            .single()
            .execute()
            .value
    }

    @discardableResult
    func insertLink(_ row: FamilyTreeLinkInsert) async throws -> FamilyTreeLink {
        try await client
            .from("family_tree_links")
            .insert(row)
            .select()
            .single()
            .execute()
            .value
    }

    @discardableResult
    func insertMoment(_ row: FamilyTreeMomentInsert) async throws -> FamilyTreeMoment {
        try await client
            .from("family_tree_moments")
            .insert(row)
            .select()
            .single()
            .execute()
            .value
    }

    func deletePerson(id: UUID) async throws {
        try await client.from("family_tree_persons").delete().eq("id", value: id).execute()
    }

    func deleteLink(id: UUID) async throws {
        try await client.from("family_tree_links").delete().eq("id", value: id).execute()
    }

    /// Seed members into the tree when empty, and fill heuristic parent/partner links when links are missing.
    func seedFromMembersIfEmpty(session: FamilyTreeSession) async throws -> (persons: [FamilyTreePerson], links: [FamilyTreeLink]) {
        var persons = try await fetchPersons(familyId: session.familyId)
        var links = try await fetchLinks(familyId: session.familyId)
        guard session.canEdit else { return (persons, links) }
        guard persons.isEmpty || links.isEmpty else { return (persons, links) }

        var inserted: [UUID: FamilyTreePerson] = [:]
        if persons.isEmpty {
            for member in session.members {
                let photo = member.avatarURL ?? member.avatarPath
                let person = try await insertPerson(
                    FamilyTreePersonInsert(
                        id: UUID(),
                        familyId: session.familyId,
                        memberId: member.id,
                        displayName: member.displayName,
                        birthYear: nil,
                        deathYear: nil,
                        photoURL: photo,
                        isLiving: true,
                        notes: nil,
                        createdBy: session.me.id
                    )
                )
                inserted[member.id] = person
            }
            persons = inserted.values.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        } else {
            for person in persons {
                if let memberId = person.memberId {
                    inserted[memberId] = person
                }
            }
        }

        if links.isEmpty {
            let parents = session.members.filter { $0.role == "owner" || $0.role == "parent" || $0.role == "adult" }
            let children = session.members.filter { $0.role == "child" }

            if parents.count == 2,
               let a = inserted[parents[0].id],
               let b = inserted[parents[1].id] {
                let pair = Self.canonicalPartnerPair(a.id, b.id)
                let link = try await insertLink(
                    FamilyTreeLinkInsert(
                        id: UUID(),
                        familyId: session.familyId,
                        fromPersonId: pair.0,
                        toPersonId: pair.1,
                        linkType: FamilyTreeLinkType.partnerOf.rawValue,
                        createdBy: session.me.id
                    )
                )
                links.append(link)
            }

            for parent in parents {
                guard let from = inserted[parent.id] else { continue }
                for child in children {
                    guard let to = inserted[child.id] else { continue }
                    let link = try await insertLink(
                        FamilyTreeLinkInsert(
                            id: UUID(),
                            familyId: session.familyId,
                            fromPersonId: from.id,
                            toPersonId: to.id,
                            linkType: FamilyTreeLinkType.parentOf.rawValue,
                            createdBy: session.me.id
                        )
                    )
                    links.append(link)
                }
            }
        }

        persons = try await fetchPersons(familyId: session.familyId)
        links = try await fetchLinks(familyId: session.familyId)
        return (persons, links)
    }

    func openDirectChat(memberId: UUID) async throws -> UUID {
        let summary: FamilyTreeDirectChatSummary = try await client
            .rpc("get_or_create_direct_chat", params: FamilyTreeDirectChatParams(pMemberId: memberId))
            .execute()
            .value
        return summary.id
    }

    func addMoment(
        session: FamilyTreeSession,
        personId: UUID,
        caption: String,
        jpegData: Data?
    ) async throws -> FamilyTreeMoment {
        var postId: UUID?
        var mediaURL: String?
        if let jpegData {
            let newPostId = UUID()
            let path = "\(session.familyId.uuidString.lowercased())/feed/\(newPostId.uuidString.lowercased())/0.jpg"
            try await client.storage
                .from(mediaBucket)
                .upload(
                    path,
                    data: jpegData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            _ = try await client
                .rpc(
                    "create_family_post",
                    params: FamilyTreePostCreateParams(
                        pPost: FamilyTreePostCreateBody(id: newPostId, caption: caption, photoPaths: [path])
                    )
                )
                .execute()
            postId = newPostId
            mediaURL = path
        }

        return try await insertMoment(
            FamilyTreeMomentInsert(
                id: UUID(),
                familyId: session.familyId,
                personId: personId,
                postId: postId,
                mediaURL: mediaURL,
                caption: caption.isEmpty ? nil : caption,
                createdBy: session.me.id
            )
        )
    }

    func resolvedMediaURL(_ raw: String?) async -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        return try? await client.storage.from(mediaBucket).createSignedURL(path: raw, expiresIn: 3600)
    }

    func jpegData(from image: UIImage, maxDimension: CGFloat = 1600) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.jpegData(compressionQuality: 0.82)
    }

    nonisolated static func canonicalPartnerPair(_ a: UUID, _ b: UUID) -> (UUID, UUID) {
        a.uuidString < b.uuidString ? (a, b) : (b, a)
    }
}
