# Family Tree MVP (Orbit Family)

Drop-in SwiftUI + supabase-swift feature. Backend tables already exist on project `dheajrhjadxvdzmtnqan`.

This GitHub repo is the public site; the iOS app lives in the local Xcode project. Add the `ios/OrbitFamily/FamilyTree/` folder to the **Orbit Family** app target.

## Wire into Home

Next to Кухня / Карта:

```swift
NavigationLink {
    FamilyTreeView(session: treeSession, client: supabase)
} label: {
    FamilyTreeHomeTileLabel()
}
```

Build `treeSession` from the members you already have, or:

```swift
let treeSession = try await FamilyTreeSession.load(from: supabase)
```

Deep link: `orbitfamily://tree` via `.familyTreeDeepLink(isPresented:)`.

## Chat / Call / Video

Person card shows **Сообщение / Звонок / Видео** only when `member_id` is set.

The tree calls `get_or_create_direct_chat(p_member_id:)` then posts:

- `Notification.Name.orbitOpenDirectChat` — `userInfo`: `memberId`, `chatId`
- `Notification.Name.orbitStartCall` — `userInfo`: `memberId`, `chatId`, `video`

Handle those the same way as an existing 1:1 chat / CallKit / LiveKit start. Or pass a custom `FamilyTreeHostActions`.

## Add files to the Xcode target

1. File → Add Files to “Orbit Family” → `ios/OrbitFamily/FamilyTree/`
2. Check **Copy items if needed** (or add a folder reference / group), target membership on.
3. `import` is not needed — types are in the app module.

Requires iOS 17+ (Observation, `@Bindable`) and the existing `Supabase` package.

## Rights

- Read: any family member (`is_family_member`)
- Add person / link: owner or parent (`can_edit_family_tree`)
- Moments insert: any member; delete uses `can_delete_family_item`

## Out of scope (v1)

Generations / Branches / Map overview, life Timeline, GEDCOM.

---

## Test notes — Demo Family

Family: **Demo Family** (`ZFSS-4272`). Members: Review (owner), Мама (демо) (parent, no account), Миша (демо) (child, no account).

1. Sign in as **Review** (owner). From Home tap **Дерево**.
2. First open seeds the tree from members: Review + Мама + Миша, partner link between the two parents, both `parent_of` Миша.
3. Pinch / drag the canvas; double-tap resets zoom. Tap a node → person card.
4. On **Review** (has `member_id`): **Сообщение / Звонок / Видео** visible. Message should open/create a direct chat. Demo relatives without a user still have `member_id` after seed — buttons show; VoIP may have no tokens.
5. Card tabs **О человеке** and **Моменты**. `+` on Moments uploads to `family-media` (`{familyId}/feed/{postId}/0.jpg`) and inserts `family_tree_moments`.
6. Owner/parent: `+` FAB / toolbar → add person (external or linked member) and optional parent/child/partner link. From the card, **Связь** adds `parent_of` or `partner_of`. Parent cycles are rejected.
7. Sign in as a **child** on a family whose tree is already seeded: tree is read-only (no FAB). If the tree was never seeded, the child sees the empty state (RLS blocks seed insert).
8. Reload the screen: seed must **not** duplicate persons.
9. Big Bang Family: same flow with Papa / Я / Mama.

SQL history: `supabase/migrations/20261005144252_family_tree_persons_links.sql` (already applied live; idempotent).
