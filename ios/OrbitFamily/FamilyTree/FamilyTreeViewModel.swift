import Foundation
import Observation
import UIKit
import CoreGraphics
import Supabase

@Observable
@MainActor
final class FamilyTreeViewModel {
    let session: FamilyTreeSession
    let actions: FamilyTreeHostActions

    private let repository: FamilyTreeRepository

    var persons: [FamilyTreePerson] = []
    var links: [FamilyTreeLink] = []
    var layout = FamilyTreeLayout(nodes: [], edges: [], canvasSize: .init(width: 320, height: 480))
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var selectedPerson: FamilyTreePerson?
    var moments: [FamilyTreeMoment] = []
    var signedPhotoURLs: [UUID: URL] = [:]
    var signedMomentURLs: [UUID: URL] = [:]
    var showAddPerson = false
    var showAddLink = false

    init(
        session: FamilyTreeSession,
        client: SupabaseClient,
        actions: FamilyTreeHostActions = NotificationFamilyTreeActions()
    ) {
        self.session = session
        self.repository = FamilyTreeRepository(client: client)
        self.actions = actions
    }

    var isEmpty: Bool { persons.isEmpty }
    var canEdit: Bool { session.canEdit }

    func person(id: UUID) -> FamilyTreePerson? {
        persons.first { $0.id == id }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var loaded = try await repository.fetchPersons(familyId: session.familyId)
            var loadedLinks = try await repository.fetchLinks(familyId: session.familyId)
            if loaded.isEmpty {
                let seeded = try await repository.seedFromMembersIfEmpty(session: session)
                loaded = seeded.persons
                loadedLinks = seeded.links
            }
            persons = loaded
            links = loadedLinks
            relayout()
            await refreshPhotoURLs()
            FamilyTreeSeenFlag.markSeen()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func select(_ person: FamilyTreePerson) async {
        selectedPerson = person
        await loadMoments(for: person.id)
    }

    func loadMoments(for personId: UUID) async {
        do {
            moments = try await repository.fetchMoments(personId: personId)
            var urls: [UUID: URL] = [:]
            for moment in moments {
                if let url = await repository.resolvedMediaURL(moment.mediaURL) {
                    urls[moment.id] = url
                }
            }
            signedMomentURLs = urls
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addPerson(
        name: String,
        birthYear: Int?,
        deathYear: Int?,
        notes: String?,
        memberId: UUID?,
        relation: FamilyTreeNewRelation,
        relatedPersonId: UUID?
    ) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = FamilyTreeError.emptyName.localizedDescription
            return false
        }
        if let birthYear, let deathYear, deathYear < birthYear {
            errorMessage = FamilyTreeError.invalidYears.localizedDescription
            return false
        }
        guard canEdit else {
            errorMessage = FamilyTreeError.notAllowed.localizedDescription
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let member = memberId.flatMap { session.member(id: $0) }
            let person = try await repository.insertPerson(
                FamilyTreePersonInsert(
                    id: UUID(),
                    familyId: session.familyId,
                    memberId: memberId,
                    displayName: trimmed,
                    birthYear: birthYear,
                    deathYear: deathYear,
                    photoURL: member?.avatarURL ?? member?.avatarPath,
                    isLiving: deathYear == nil,
                    notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    createdBy: session.me.id
                )
            )
            persons.append(person)
            if let relatedPersonId, relation != .none {
                let pair = relationPair(relation, newId: person.id, relatedId: relatedPersonId)
                let ok = await addLink(type: pair.type, from: pair.from, to: pair.to, markBusy: false)
                if !ok { relayout(); return true }
            }
            relayout()
            await refreshPhotoURLs()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addLink(type: FamilyTreeLinkType, from: UUID, to: UUID, markBusy: Bool = true) async -> Bool {
        guard from != to else {
            errorMessage = FamilyTreeError.selfLink.localizedDescription
            return false
        }
        guard canEdit else {
            errorMessage = FamilyTreeError.notAllowed.localizedDescription
            return false
        }
        if type == .parentOf, FamilyTreeLayout.wouldCreateParentCycle(parent: from, child: to, links: links) {
            errorMessage = FamilyTreeError.cycle.localizedDescription
            return false
        }
        let pair = type == .partnerOf ? FamilyTreeRepository.canonicalPartnerPair(from, to) : (from, to)
        if links.contains(where: { $0.linkType == type && $0.fromPersonId == pair.0 && $0.toPersonId == pair.1 })
            || (type == .partnerOf && links.contains(where: {
                $0.linkType == .partnerOf &&
                Set([$0.fromPersonId, $0.toPersonId]) == Set([from, to])
            })) {
            errorMessage = FamilyTreeError.duplicateLink.localizedDescription
            return false
        }
        if markBusy { isSaving = true }
        defer { if markBusy { isSaving = false } }
        do {
            let link = try await repository.insertLink(
                FamilyTreeLinkInsert(
                    id: UUID(),
                    familyId: session.familyId,
                    fromPersonId: pair.0,
                    toPersonId: pair.1,
                    linkType: type.rawValue,
                    createdBy: session.me.id
                )
            )
            links.append(link)
            relayout()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addMoment(caption: String, image: UIImage?) async {
        guard let person = selectedPerson else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let jpeg = image.flatMap { repository.jpegData(from: $0) }
            _ = try await repository.addMoment(
                session: session,
                personId: person.id,
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                jpegData: jpeg
            )
            await loadMoments(for: person.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func messageTapped() async {
        guard let memberId = selectedPerson?.memberId else { return }
        do {
            let chatId = try await repository.openDirectChat(memberId: memberId)
            actions.openDirectChat(memberId: memberId, chatId: chatId)
        } catch {
            errorMessage = FamilyTreeError.missingChat.localizedDescription
        }
    }

    func callTapped(video: Bool) async {
        guard let memberId = selectedPerson?.memberId else { return }
        do {
            let chatId = try await repository.openDirectChat(memberId: memberId)
            actions.startCall(memberId: memberId, chatId: chatId, video: video)
        } catch {
            errorMessage = FamilyTreeError.missingChat.localizedDescription
        }
    }

    func relations(for person: FamilyTreePerson) -> [(title: String, name: String)] {
        var rows: [(String, String)] = []
        for link in links where link.linkType == .parentOf && link.toPersonId == person.id {
            if let parent = self.person(id: link.fromPersonId) {
                rows.append(("Родитель", parent.displayName))
            }
        }
        for link in links where link.linkType == .parentOf && link.fromPersonId == person.id {
            if let child = self.person(id: link.toPersonId) {
                rows.append(("Ребёнок", child.displayName))
            }
        }
        for link in links where link.linkType == .partnerOf && (link.fromPersonId == person.id || link.toPersonId == person.id) {
            let otherId = link.fromPersonId == person.id ? link.toPersonId : link.fromPersonId
            if let other = self.person(id: otherId) {
                rows.append(("Партнёр", other.displayName))
            }
        }
        return rows
    }

    private func relationPair(_ relation: FamilyTreeNewRelation, newId: UUID, relatedId: UUID) -> (type: FamilyTreeLinkType, from: UUID, to: UUID) {
        switch relation {
        case .none:
            return (.partnerOf, relatedId, newId)
        case .childOf:
            return (.parentOf, relatedId, newId)
        case .parentOf:
            return (.parentOf, newId, relatedId)
        case .partnerOf:
            return (.partnerOf, relatedId, newId)
        }
    }

    private func relayout() {
        layout = FamilyTreeLayout.build(persons: persons, links: links)
    }

    private func refreshPhotoURLs() async {
        var urls: [UUID: URL] = [:]
        for person in persons {
            let raw = person.photoURL ?? session.members.first { $0.id == person.memberId }?.avatarPath
            if let url = await repository.resolvedMediaURL(raw) {
                urls[person.id] = url
            }
        }
        signedPhotoURLs = urls
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
