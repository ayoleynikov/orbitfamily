import SwiftUI
import PhotosUI
import UIKit

struct FamilyTreePersonCard: View {
    @Bindable var model: FamilyTreeViewModel
    let person: FamilyTreePerson
    @Environment(\.dismiss) private var dismiss
    @State private var tab: CardTab = .about
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var caption = ""
    @State private var showAddMoment = false

    private enum CardTab: String, CaseIterable {
        case about = "О человеке"
        case moments = "Моменты"
    }

    private var hasMember: Bool { person.memberId != nil }
    private var member: FamilyTreeMemberSnapshot? {
        person.memberId.flatMap { model.session.member(id: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if hasMember {
                        actions
                    }
                    Picker("Раздел", selection: $tab) {
                        ForEach(CardTab.allCases, id: \.self) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    switch tab {
                    case .about:
                        aboutBlock
                    case .moments:
                        momentsBlock
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.07, green: 0.09, blue: 0.18).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                if model.canEdit {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Связь") { model.showAddLink = true }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .task {
            await model.select(person)
        }
        .sheet(isPresented: $showAddMoment) {
            addMomentSheet
        }
        .sheet(isPresented: $model.showAddLink) {
            AddLinkSheet(model: model)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            avatar
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.orange.opacity(0.8), lineWidth: 2))
                .shadow(color: .orange.opacity(0.35), radius: 12)
            Text(person.displayName)
                .font(.title.bold())
                .foregroundStyle(.white)
            if !person.yearsLabel.isEmpty {
                Text(person.yearsLabel)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = model.signedPhotoURLs[person.id] {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    initials
                }
            }
        } else {
            initials
        }
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Color(red: 0.2, green: 0.24, blue: 0.45))
            Text(person.initials)
                .font(.title.bold())
                .foregroundStyle(.white)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            actionButton("Сообщение", systemImage: "message.fill") {
                Task { await model.messageTapped() }
            }
            actionButton("Звонок", systemImage: "phone.fill") {
                Task { await model.callTapped(video: false) }
            }
            actionButton("Видео", systemImage: "video.fill") {
                Task { await model.callTapped(video: true) }
            }
        }
        .padding(.horizontal)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var aboutBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            aboutRow(systemImage: "calendar", title: "День рождения", value: person.birthYear.map(String.init) ?? "не указан")
            aboutRow(systemImage: "person.2", title: "Связь", value: member?.roleTitle ?? "Внешний родственник")
            if let notes = person.notes, !notes.isEmpty {
                aboutRow(systemImage: "text.alignleft", title: "О человеке", value: notes)
            }
            let relations = model.relations(for: person)
            if !relations.isEmpty {
                Text("Семья")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                ForEach(Array(relations.enumerated()), id: \.offset) { _, row in
                    aboutRow(systemImage: "leaf", title: row.title, value: row.name)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func aboutRow(systemImage: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                Text(value)
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var momentsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.moments.isEmpty {
                Text("Пока нет моментов. Добавьте фото — так живёт память семьи.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 20)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(model.moments) { moment in
                    momentCell(moment)
                }
                Button {
                    showAddMoment = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                        Image(systemName: "plus")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
                .accessibilityLabel("Добавить момент")
            }
            .padding(.horizontal, 16)
        }
    }

    private func momentCell(_ moment: FamilyTreeMoment) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let url = model.signedMomentURLs[moment.id] {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
            } else {
                Color.white.opacity(0.08)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }
            if let caption = moment.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.35))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .aspectRatio(1, contentMode: .fit)
    }

    private var addMomentSheet: some View {
        NavigationStack {
            Form {
                Section("Фото") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        if let pendingImage {
                            Image(uiImage: pendingImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Label("Выбрать фото", systemImage: "photo")
                        }
                    }
                }
                Section("Подпись") {
                    TextField("Что это за момент?", text: $caption, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Новый момент")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showAddMoment = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Task {
                            await model.addMoment(caption: caption, image: pendingImage)
                            showAddMoment = false
                            caption = ""
                            pendingImage = nil
                        }
                    }
                    .disabled(pendingImage == nil && caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pendingImage = image
                    }
                }
            }
        }
    }
}
