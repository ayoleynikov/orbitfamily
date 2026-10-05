import SwiftUI
import Supabase

/// Home → «Дерево» navigation helper. Drop next to Кухня / Карта.
struct FamilyTreeHomeNavigationLink: View {
    let session: FamilyTreeSession
    let client: SupabaseClient
    var actions: FamilyTreeHostActions = NotificationFamilyTreeActions()

    var body: some View {
        NavigationLink {
            FamilyTreeView(session: session, client: client, actions: actions)
        } label: {
            FamilyTreeHomeTileLabel()
        }
        .buttonStyle(.plain)
    }
}

struct FamilyTreeHomeDestination: View {
    let session: FamilyTreeSession
    let client: SupabaseClient
    var actions: FamilyTreeHostActions = NotificationFamilyTreeActions()

    var body: some View {
        FamilyTreeView(session: session, client: client, actions: actions)
    }
}

extension View {
    /// Handles `orbitfamily://tree`.
    func familyTreeDeepLink(isPresented: Binding<Bool>) -> some View {
        onOpenURL { url in
            if FamilyTreeDeepLink.isTree(url) {
                isPresented.wrappedValue = true
            }
        }
    }
}
