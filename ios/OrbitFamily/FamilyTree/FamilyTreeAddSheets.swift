import SwiftUI

struct AddPersonSheet: View {
    @Bindable var model: FamilyTreeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var birthYearText = ""
    @State private var deathYearText = ""
    @State private var notes = ""
    @State private var memberId: UUID?
    @State private var relation: FamilyTreeNewRelation = .none
    @State private var relatedPersonId: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Кто это") {
                    TextField("Имя", text: $name)
                    TextField("Год рождения", text: $birthYearText)
                        .keyboardType(.numberPad)
                    TextField("Год смерти (если есть)", text: $deathYearText)
                        .keyboardType(.numberPad)
                    TextField("Заметка", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Участник семьи") {
                    Picker("Связать с аккаунтом", selection: $memberId) {
                        Text("Внешний родственник").tag(Optional<UUID>.none)
                        ForEach(unlinkedMembers) { member in
                            Text(member.displayName).tag(Optional(member.id))
                        }
                    }
                }
                if !model.persons.isEmpty {
                    Section("Связь в дереве") {
                        Picker("Родство", selection: $relation) {
                            ForEach(FamilyTreeNewRelation.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        if relation != .none {
                            Picker("С кем", selection: $relatedPersonId) {
                                Text("Выберите").tag(Optional<UUID>.none)
                                ForEach(model.persons) { person in
                                    Text(person.displayName).tag(Optional(person.id))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Новый человек")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        Task {
                            let ok = await model.addPerson(
                                name: name,
                                birthYear: Int(birthYearText.trimmingCharacters(in: .whitespaces)),
                                deathYear: Int(deathYearText.trimmingCharacters(in: .whitespaces)),
                                notes: notes,
                                memberId: memberId,
                                relation: relation,
                                relatedPersonId: relatedPersonId
                            )
                            if ok { dismiss() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSaving)
                }
            }
            .onAppear {
                relatedPersonId = model.selectedPerson?.id
                if relatedPersonId != nil { relation = .childOf }
            }
        }
    }

    private var unlinkedMembers: [FamilyTreeMemberSnapshot] {
        let used = Set(model.persons.compactMap(\.memberId))
        return model.session.members.filter { !used.contains($0.id) }
    }
}

struct AddLinkSheet: View {
    @Bindable var model: FamilyTreeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var fromId: UUID?
    @State private var toId: UUID?
    @State private var type: FamilyTreeLinkType = .parentOf

    var body: some View {
        NavigationStack {
            Form {
                Picker("Тип", selection: $type) {
                    Text("Родитель → ребёнок").tag(FamilyTreeLinkType.parentOf)
                    Text("Партнёры").tag(FamilyTreeLinkType.partnerOf)
                }
                Picker(type == .parentOf ? "Родитель" : "Первый", selection: $fromId) {
                    Text("Выберите").tag(Optional<UUID>.none)
                    ForEach(model.persons) { person in
                        Text(person.displayName).tag(Optional(person.id))
                    }
                }
                Picker(type == .parentOf ? "Ребёнок" : "Второй", selection: $toId) {
                    Text("Выберите").tag(Optional<UUID>.none)
                    ForEach(model.persons) { person in
                        Text(person.displayName).tag(Optional(person.id))
                    }
                }
            }
            .navigationTitle("Новая связь")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard let fromId, let toId else { return }
                        Task {
                            if await model.addLink(type: type, from: fromId, to: toId) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(fromId == nil || toId == nil || fromId == toId || model.isSaving)
                }
            }
            .onAppear {
                fromId = model.selectedPerson?.id
            }
        }
    }
}
