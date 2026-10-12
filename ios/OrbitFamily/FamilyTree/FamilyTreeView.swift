import SwiftUI
import Supabase

/// Home grid tile: «Дерево» → `FamilyTreeView`.
struct FamilyTreeHomeTileLabel: View {
    var isNew: Bool = FamilyTreeSeenFlag.isNew

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.82, blue: 0.38), Color(red: 0.95, green: 0.55, blue: 0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if isNew {
                    Text("новое")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange, in: Capsule())
                        .offset(x: 8, y: -8)
                }
            }
            Text("Дерево")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Семья")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.16, blue: 0.38), Color(red: 0.07, green: 0.09, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .accessibilityLabel("Дерево семьи")
    }
}

struct FamilyTreeHomeTile: View {
    var isNew: Bool = FamilyTreeSeenFlag.isNew
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            FamilyTreeHomeTileLabel(isNew: isNew)
        }
        .buttonStyle(.plain)
    }
}

/// Root tree screen: zoom/pan canvas, avatar nodes, empty state, FAB.
struct FamilyTreeView: View {
    @State private var model: FamilyTreeViewModel
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var magnify: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    init(
        session: FamilyTreeSession,
        client: SupabaseClient,
        actions: FamilyTreeHostActions = NotificationFamilyTreeActions()
    ) {
        _model = State(initialValue: FamilyTreeViewModel(session: session, client: client, actions: actions))
    }

    init(model: FamilyTreeViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        ZStack {
            FamilyTreeSkyBackground()
            if model.isLoading && model.persons.isEmpty {
                ProgressView("Загрузка дерева…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if model.isEmpty {
                FamilyTreeEmptyState(canEdit: model.canEdit) {
                    if model.canEdit { model.showAddPerson = true }
                }
            } else {
                canvas
            }
        }
        .navigationTitle("Наша семья")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.canEdit {
                    Button {
                        model.showAddPerson = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Добавить человека")
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if model.canEdit && !model.isEmpty {
                Button {
                    model.showAddPerson = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color.orange, Color(red: 0.95, green: 0.45, blue: 0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: Circle()
                        )
                        .shadow(color: .orange.opacity(0.45), radius: 12, y: 4)
                }
                .padding(20)
                .accessibilityLabel("Добавить человека")
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(item: $model.selectedPerson) { person in
            FamilyTreePersonCard(model: model, person: person)
        }
        .sheet(isPresented: $model.showAddPerson) {
            AddPersonSheet(model: model)
        }
        .alert("Дерево", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let layout = model.layout
            let fitted = min(
                geo.size.width / max(layout.canvasSize.width, 1),
                geo.size.height / max(layout.canvasSize.height, 1)
            )
            let liveScale = max(0.4, min(2.8, scale * magnify))
            ZStack {
                FamilyTreeGlow()
                ZStack {
                    FamilyTreeEdgesView(edges: layout.edges)
                    ForEach(layout.nodes) { node in
                        if let person = model.person(id: node.id) {
                            FamilyTreeNodeView(
                                person: person,
                                photoURL: model.signedPhotoURLs[person.id]
                            )
                            .position(x: node.x, y: node.y)
                            .onTapGesture {
                                Task { await model.select(person) }
                            }
                        }
                    }
                }
                .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                .scaleEffect(fitted * liveScale)
                .offset(
                    x: offset.width + drag.width,
                    y: offset.height + drag.height
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .updating($magnify) { value, state, _ in state = value }
                    .onEnded { value in
                        scale = max(0.4, min(2.8, scale * value))
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring) {
                    scale = 1
                    offset = .zero
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            zoomChrome
        }
    }

    private var zoomChrome: some View {
        VStack(spacing: 8) {
            Button {
                scale = min(2.8, scale + 0.2)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 36, height: 36)
            }
            Button {
                scale = max(0.4, scale - 0.2)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 36, height: 36)
            }
        }
        .foregroundStyle(.white)
        .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(16)
    }
}

private struct FamilyTreeNodeView: View {
    let person: FamilyTreePerson
    let photoURL: URL?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.orange.opacity(0.55), Color.orange.opacity(0.05)],
                            center: .center,
                            startRadius: 18,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)
                    .blur(radius: 1)
                personAvatar
                    .frame(width: 58, height: 58)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.orange.opacity(0.9), lineWidth: 2))
                    .shadow(color: .orange.opacity(0.45), radius: 8)
            }
            Text(person.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 88)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(person.displayName)
    }

    @ViewBuilder
    private var personAvatar: some View {
        if let photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    initials
                }
            }
        } else {
            initials
        }
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Color(red: 0.18, green: 0.22, blue: 0.42))
            Text(person.initials)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
        }
    }
}

private struct FamilyTreeEdgesView: View {
    let edges: [FamilyTreeEdgePlacement]

    var body: some View {
        Canvas { context, _ in
            for edge in edges {
                var path = Path()
                if edge.isPartner {
                    path.move(to: edge.from)
                    path.addLine(to: edge.to)
                    context.stroke(
                        path,
                        with: .color(Color.orange.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                } else {
                    let midY = (edge.from.y + edge.to.y) / 2
                    path.move(to: edge.from)
                    path.addCurve(
                        to: edge.to,
                        control1: CGPoint(x: edge.from.x, y: midY),
                        control2: CGPoint(x: edge.to.x, y: midY)
                    )
                    context.stroke(
                        path,
                        with: .color(Color.orange.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FamilyTreeEmptyState: View {
    let canEdit: Bool
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.orange)
                .shadow(color: .orange.opacity(0.5), radius: 16)
            Text("Соберите дерево семьи")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Добавьте родных — живых и тех, кого помните. Можно начать с участников семьи.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if canEdit {
                Button("Собрать дерево", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            } else {
                Text("Попросите родителя добавить родственников.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

private struct FamilyTreeSkyBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.08, blue: 0.22),
                Color(red: 0.02, green: 0.04, blue: 0.12)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay {
            Canvas { context, size in
                for i in 0..<40 {
                    let x = CGFloat((i * 47) % 97) / 97 * size.width
                    let y = CGFloat((i * 31) % 89) / 89 * size.height
                    let r = CGFloat((i % 3) + 1)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                        with: .color(.white.opacity(0.35))
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private struct FamilyTreeGlow: View {
    var body: some View {
        Canvas { context, size in
            let trunk = Path { path in
                path.move(to: CGPoint(x: size.width / 2, y: size.height * 0.88))
                path.addQuadCurve(
                    to: CGPoint(x: size.width / 2, y: size.height * 0.28),
                    control: CGPoint(x: size.width / 2 + 8, y: size.height * 0.58)
                )
            }
            context.stroke(
                trunk,
                with: .linearGradient(
                    Gradient(colors: [Color.orange.opacity(0.15), Color.yellow.opacity(0.55)]),
                    startPoint: CGPoint(x: size.width / 2, y: size.height),
                    endPoint: CGPoint(x: size.width / 2, y: 0)
                ),
                lineWidth: 8
            )
            let crown = Path(ellipseIn: CGRect(
                x: size.width * 0.22,
                y: size.height * 0.12,
                width: size.width * 0.56,
                height: size.height * 0.42
            ))
            context.fill(crown, with: .color(Color.orange.opacity(0.07)))
        }
        .allowsHitTesting(false)
        .blur(radius: 0.4)
    }
}
