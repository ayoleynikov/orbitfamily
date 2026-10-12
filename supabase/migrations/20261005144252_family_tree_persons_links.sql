-- Family tree MVP (already applied on dheajrhjadxvdzmtnqan).
-- Idempotent history copy of live tables + RLS + can_edit_family_tree.

create table if not exists public.family_tree_persons (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  member_id uuid references public.members(id) on delete set null,
  display_name text not null,
  birth_year int,
  death_year int,
  photo_url text,
  is_living boolean not null default true,
  notes text,
  created_by uuid references public.members(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint family_tree_persons_years_chk check (
    birth_year is null or death_year is null or death_year >= birth_year
  )
);

create index if not exists family_tree_persons_family_idx on public.family_tree_persons(family_id);
create index if not exists family_tree_persons_member_idx on public.family_tree_persons(member_id);

create table if not exists public.family_tree_links (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  from_person_id uuid not null references public.family_tree_persons(id) on delete cascade,
  to_person_id uuid not null references public.family_tree_persons(id) on delete cascade,
  link_type text not null check (link_type in ('parent_of', 'partner_of')),
  created_by uuid references public.members(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint family_tree_links_no_self check (from_person_id <> to_person_id),
  constraint family_tree_links_unique unique (family_id, from_person_id, to_person_id, link_type)
);

create index if not exists family_tree_links_family_idx on public.family_tree_links(family_id);

create table if not exists public.family_tree_moments (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  person_id uuid not null references public.family_tree_persons(id) on delete cascade,
  post_id uuid references public.family_posts(id) on delete set null,
  media_url text,
  caption text,
  created_by uuid references public.members(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists family_tree_moments_person_idx on public.family_tree_moments(person_id);

alter table public.family_tree_persons enable row level security;
alter table public.family_tree_links enable row level security;
alter table public.family_tree_moments enable row level security;

create or replace function public.can_edit_family_tree(p_family uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists(
    select 1 from members m
    join families f on f.id = m.family_id
    where m.family_id = p_family
      and m.user_id = auth.uid()
      and m.left_at is null
      and (m.role in ('owner', 'parent') or f.owner_id = m.id)
  );
$$;

drop policy if exists family_tree_persons_select on public.family_tree_persons;
create policy family_tree_persons_select on public.family_tree_persons
  for select to authenticated
  using (is_family_member(family_id));

drop policy if exists family_tree_persons_insert on public.family_tree_persons;
create policy family_tree_persons_insert on public.family_tree_persons
  for insert to authenticated
  with check (is_family_member(family_id) and can_edit_family_tree(family_id));

drop policy if exists family_tree_persons_update on public.family_tree_persons;
create policy family_tree_persons_update on public.family_tree_persons
  for update to authenticated
  using (is_family_member(family_id) and can_edit_family_tree(family_id))
  with check (is_family_member(family_id) and can_edit_family_tree(family_id));

drop policy if exists family_tree_persons_delete on public.family_tree_persons;
create policy family_tree_persons_delete on public.family_tree_persons
  for delete to authenticated
  using (is_family_member(family_id) and can_edit_family_tree(family_id));

drop policy if exists family_tree_links_select on public.family_tree_links;
create policy family_tree_links_select on public.family_tree_links
  for select to authenticated
  using (is_family_member(family_id));

drop policy if exists family_tree_links_insert on public.family_tree_links;
create policy family_tree_links_insert on public.family_tree_links
  for insert to authenticated
  with check (is_family_member(family_id) and can_edit_family_tree(family_id));

drop policy if exists family_tree_links_update on public.family_tree_links;
create policy family_tree_links_update on public.family_tree_links
  for update to authenticated
  using (is_family_member(family_id) and can_edit_family_tree(family_id))
  with check (is_family_member(family_id) and can_edit_family_tree(family_id));

drop policy if exists family_tree_links_delete on public.family_tree_links;
create policy family_tree_links_delete on public.family_tree_links
  for delete to authenticated
  using (is_family_member(family_id) and can_edit_family_tree(family_id));

drop policy if exists family_tree_moments_select on public.family_tree_moments;
create policy family_tree_moments_select on public.family_tree_moments
  for select to authenticated
  using (is_family_member(family_id));

drop policy if exists family_tree_moments_insert on public.family_tree_moments;
create policy family_tree_moments_insert on public.family_tree_moments
  for insert to authenticated
  with check (is_family_member(family_id));

drop policy if exists family_tree_moments_update on public.family_tree_moments;
create policy family_tree_moments_update on public.family_tree_moments
  for update to authenticated
  using (is_family_member(family_id) and can_edit_family_tree(family_id))
  with check (is_family_member(family_id) and can_edit_family_tree(family_id));

drop policy if exists family_tree_moments_delete on public.family_tree_moments;
create policy family_tree_moments_delete on public.family_tree_moments
  for delete to authenticated
  using (can_delete_family_item(family_id, created_by));

grant select, insert, update, delete on public.family_tree_persons to authenticated;
grant select, insert, update, delete on public.family_tree_links to authenticated;
grant select, insert, update, delete on public.family_tree_moments to authenticated;
