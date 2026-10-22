-- AFD Hydrant Intel — run once in the Supabase SQL editor (Fire SMS project).
-- Stores per-hydrant cross-street info, notes and tags entered on the Hydrants page.
-- hydrant_id matches the "id" field in hydrants.json (H-001 … H-435).

create table if not exists hydrant_notes (
  hydrant_id text primary key,               -- e.g. 'H-001'
  cross_street text not null default '',    -- user-editable location label
  notes text not null default '',           -- free-form intel
  tags text not null default '',            -- free-form, comma-separated
  updated_at timestamptz default now()
);

alter table hydrant_notes enable row level security;

-- MVP: the hydrants page is gated by the department passphrase in the page itself,
-- same pattern as the dashboard's and report writer's anon access. Real per-officer
-- auth comes with the multi-tenant rebuild.
drop policy if exists "anon full access" on hydrant_notes;
create policy "anon full access" on hydrant_notes
  for all using (true) with check (true);

create or replace function touch_hydrant_notes_updated()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
drop trigger if exists trg_hydrant_notes_updated on hydrant_notes;
create trigger trg_hydrant_notes_updated before update on hydrant_notes
  for each row execute function touch_hydrant_notes_updated();
