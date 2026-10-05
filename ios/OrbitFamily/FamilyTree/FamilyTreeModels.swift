import Foundation

struct FamilyTreePerson: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var familyId: UUID
    var memberId: UUID?
    var displayName: String
    var birthYear: Int?
    var deathYear: Int?
    var photoURL: String?
    var isLiving: Bool
    var notes: String?
    var createdBy: UUID?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case memberId = "member_id"
        case displayName = "display_name"
        case birthYear = "birth_year"
        case deathYear = "death_year"
        case photoURL = "photo_url"
        case isLiving = "is_living"
        case notes
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var yearsLabel: String {
        if let birthYear, let deathYear {
            return "\(birthYear) – \(deathYear)"
        }
        if let birthYear {
            if isLiving, let age {
                return "\(birthYear) · \(age) \(Self.yearsWord(age))"
            }
            return "\(birthYear)"
        }
        if let deathYear {
            return "† \(deathYear)"
        }
        return ""
    }

    var age: Int? {
        guard isLiving, let birthYear else { return nil }
        return max(0, Calendar.current.component(.year, from: Date()) - birthYear)
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "•" : letters.joined()
    }

    private static func yearsWord(_ n: Int) -> String {
        let n10 = n % 10
        let n100 = n % 100
        if n10 == 1 && n100 != 11 { return "год" }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return "года" }
        return "лет"
    }
}

enum FamilyTreeLinkType: String, Codable, Hashable, Sendable {
    case parentOf = "parent_of"
    case partnerOf = "partner_of"

    var title: String {
        switch self {
        case .parentOf: return "Родитель"
        case .partnerOf: return "Партнёр"
        }
    }
}

struct FamilyTreeLink: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var familyId: UUID
    var fromPersonId: UUID
    var toPersonId: UUID
    var linkType: FamilyTreeLinkType
    var createdBy: UUID?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case fromPersonId = "from_person_id"
        case toPersonId = "to_person_id"
        case linkType = "link_type"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct FamilyTreeMoment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var familyId: UUID
    var personId: UUID
    var postId: UUID?
    var mediaURL: String?
    var caption: String?
    var createdBy: UUID?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case personId = "person_id"
        case postId = "post_id"
        case mediaURL = "media_url"
        case caption
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct FamilyTreePersonInsert: Encodable, Sendable {
    let id: UUID
    let familyId: UUID
    let memberId: UUID?
    let displayName: String
    let birthYear: Int?
    let deathYear: Int?
    let photoURL: String?
    let isLiving: Bool
    let notes: String?
    let createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case memberId = "member_id"
        case displayName = "display_name"
        case birthYear = "birth_year"
        case deathYear = "death_year"
        case photoURL = "photo_url"
        case isLiving = "is_living"
        case notes
        case createdBy = "created_by"
    }
}

struct FamilyTreeLinkInsert: Encodable, Sendable {
    let id: UUID
    let familyId: UUID
    let fromPersonId: UUID
    let toPersonId: UUID
    let linkType: String
    let createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case fromPersonId = "from_person_id"
        case toPersonId = "to_person_id"
        case linkType = "link_type"
        case createdBy = "created_by"
    }
}

struct FamilyTreeMomentInsert: Encodable, Sendable {
    let id: UUID
    let familyId: UUID
    let personId: UUID
    let postId: UUID?
    let mediaURL: String?
    let caption: String?
    let createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case personId = "person_id"
        case postId = "post_id"
        case mediaURL = "media_url"
        case caption
        case createdBy = "created_by"
    }
}

struct DirectChatSummary: Decodable, Sendable {
    let id: UUID
}

struct FamilyPostCreateBody: Encodable, Sendable {
    let id: UUID
    let caption: String
    let photoPaths: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case caption
        case photoPaths = "photo_paths"
    }
}

struct FamilyPostCreateParams: Encodable, Sendable {
    let pPost: FamilyPostCreateBody
    enum CodingKeys: String, CodingKey { case pPost = "p_post" }
}

struct DirectChatParams: Encodable, Sendable {
    let pMemberId: UUID
    enum CodingKeys: String, CodingKey { case pMemberId = "p_member_id" }
}

enum FamilyTreeNewRelation: String, CaseIterable, Identifiable, Sendable {
    case none
    case childOf
    case parentOf
    case partnerOf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Без связи"
        case .childOf: return "Ребёнок выбранного"
        case .parentOf: return "Родитель выбранного"
        case .partnerOf: return "Партнёр выбранного"
        }
    }
}

enum FamilyTreeError: LocalizedError, Equatable {
    case emptyName
    case invalidYears
    case selfLink
    case cycle
    case duplicateLink
    case notAllowed
    case missingChat
    case message(String)

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Введите имя."
        case .invalidYears: return "Проверьте годы жизни."
        case .selfLink: return "Нельзя связать человека с самим собой."
        case .cycle: return "Так получится цикл в дереве. Выберите другую связь."
        case .duplicateLink: return "Такая связь уже есть."
        case .notAllowed: return "Добавлять родственников могут владелец и родители."
        case .missingChat: return "Не удалось открыть чат."
        case .message(let text): return text
        }
    }
}
