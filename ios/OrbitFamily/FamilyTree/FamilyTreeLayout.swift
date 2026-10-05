import Foundation
import CoreGraphics

struct FamilyTreeNodePlacement: Identifiable, Hashable, Sendable {
    let id: UUID
    var x: CGFloat
    var y: CGFloat
    var generation: Int
}

struct FamilyTreeEdgePlacement: Identifiable, Hashable, Sendable {
    let id: UUID
    var from: CGPoint
    var to: CGPoint
    var isPartner: Bool
}

struct FamilyTreeLayout: Hashable, Sendable {
    var nodes: [FamilyTreeNodePlacement]
    var edges: [FamilyTreeEdgePlacement]
    var canvasSize: CGSize

    static let nodeSize: CGFloat = 72
    static let hGap: CGFloat = 108
    static let vGap: CGFloat = 140
    static let padding: CGFloat = 80

    func placement(for id: UUID) -> FamilyTreeNodePlacement? {
        nodes.first { $0.id == id }
    }

    static func build(persons: [FamilyTreePerson], links: [FamilyTreeLink]) -> FamilyTreeLayout {
        guard !persons.isEmpty else {
            return FamilyTreeLayout(nodes: [], edges: [], canvasSize: CGSize(width: 320, height: 480))
        }

        let ids = Set(persons.map(\.id))
        let parentLinks = links.filter { $0.linkType == .parentOf && ids.contains($0.fromPersonId) && ids.contains($0.toPersonId) }
        let partnerLinks = links.filter { $0.linkType == .partnerOf && ids.contains($0.fromPersonId) && ids.contains($0.toPersonId) }

        var children: [UUID: [UUID]] = [:]
        var parents: [UUID: [UUID]] = [:]
        for link in parentLinks {
            children[link.fromPersonId, default: []].append(link.toPersonId)
            parents[link.toPersonId, default: []].append(link.fromPersonId)
        }

        var generation: [UUID: Int] = [:]
        func assignGeneration(_ id: UUID, _ g: Int) {
            if let current = generation[id], current >= g { return }
            generation[id] = g
            for child in children[id] ?? [] {
                assignGeneration(child, g + 1)
            }
        }

        let roots = persons.map(\.id).filter { (parents[$0] ?? []).isEmpty }
        if roots.isEmpty {
            persons.forEach { generation[$0.id] = 0 }
        } else {
            for root in roots { assignGeneration(root, 0) }
            for person in persons where generation[person.id] == nil {
                generation[person.id] = 0
            }
        }

        // Partners share the higher generation so spouses sit on one row.
        for link in partnerLinks {
            let g = max(generation[link.fromPersonId] ?? 0, generation[link.toPersonId] ?? 0)
            generation[link.fromPersonId] = g
            generation[link.toPersonId] = g
        }

        var partnerOf: [UUID: UUID] = [:]
        for link in partnerLinks {
            if partnerOf[link.fromPersonId] == nil { partnerOf[link.fromPersonId] = link.toPersonId }
            if partnerOf[link.toPersonId] == nil { partnerOf[link.toPersonId] = link.fromPersonId }
        }

        let maxGen = generation.values.max() ?? 0
        var columns: [Int: [UUID]] = [:]
        var placed = Set<UUID>()

        for g in 0...maxGen {
            let row = persons.map(\.id).filter { generation[$0] == g }.sorted { a, b in
                let na = persons.first { $0.id == a }?.displayName ?? ""
                let nb = persons.first { $0.id == b }?.displayName ?? ""
                return na.localizedCompare(nb) == .orderedAscending
            }
            var ordered: [UUID] = []
            for id in row where !placed.contains(id) {
                if let partner = partnerOf[id], generation[partner] == g, !placed.contains(partner) {
                    let pair = [id, partner].sorted { a, b in
                        let na = persons.first { $0.id == a }?.displayName ?? ""
                        let nb = persons.first { $0.id == b }?.displayName ?? ""
                        return na.localizedCompare(nb) == .orderedAscending
                    }
                    ordered.append(contentsOf: pair)
                    placed.formUnion(pair)
                } else {
                    ordered.append(id)
                    placed.insert(id)
                }
            }
            columns[g] = ordered
        }

        let widest = columns.values.map(\.count).max() ?? 1
        let width = padding * 2 + CGFloat(max(widest, 1)) * hGap
        let height = padding * 2 + CGFloat(maxGen + 1) * vGap

        var nodes: [FamilyTreeNodePlacement] = []
        for g in 0...maxGen {
            let row = columns[g] ?? []
            let rowWidth = CGFloat(max(row.count - 1, 0)) * hGap
            let startX = (width - rowWidth) / 2
            for (index, id) in row.enumerated() {
                nodes.append(
                    FamilyTreeNodePlacement(
                        id: id,
                        x: startX + CGFloat(index) * hGap,
                        y: padding + CGFloat(g) * vGap,
                        generation: g
                    )
                )
            }
        }

        var byId: [UUID: FamilyTreeNodePlacement] = [:]
        nodes.forEach { byId[$0.id] = $0 }

        var edges: [FamilyTreeEdgePlacement] = []
        for link in parentLinks {
            guard let from = byId[link.fromPersonId], let to = byId[link.toPersonId] else { continue }
            edges.append(
                FamilyTreeEdgePlacement(
                    id: link.id,
                    from: CGPoint(x: from.x, y: from.y + Self.nodeSize / 2),
                    to: CGPoint(x: to.x, y: to.y - Self.nodeSize / 2),
                    isPartner: false
                )
            )
        }
        for link in partnerLinks {
            guard let from = byId[link.fromPersonId], let to = byId[link.toPersonId] else { continue }
            edges.append(
                FamilyTreeEdgePlacement(
                    id: link.id,
                    from: CGPoint(x: from.x, y: from.y),
                    to: CGPoint(x: to.x, y: to.y),
                    isPartner: true
                )
            )
        }

        return FamilyTreeLayout(
            nodes: nodes,
            edges: edges,
            canvasSize: CGSize(width: max(width, 320), height: max(height, 480))
        )
    }

    static func wouldCreateParentCycle(
        parent: UUID,
        child: UUID,
        links: [FamilyTreeLink]
    ) -> Bool {
        if parent == child { return true }
        var children: [UUID: [UUID]] = [:]
        for link in links where link.linkType == .parentOf {
            children[link.fromPersonId, default: []].append(link.toPersonId)
        }
        var stack = [child]
        var seen = Set<UUID>()
        while let current = stack.popLast() {
            if current == parent { return true }
            if seen.contains(current) { continue }
            seen.insert(current)
            stack.append(contentsOf: children[current] ?? [])
        }
        return false
    }
}
