# Upstream Sync

How `codev-workshops` repos are kept current with their `Cognition-Partner-Workshops`
originals: [`sync-map.yaml`](sync-map.yaml) says what is paired with what, and
[`../scripts/sync_from_source.py`](../scripts/sync_from_source.py) does the work.

Not to be confused with [`upstream-map.yaml`](upstream-map.yaml), which records the
*third-party* upstreams (Spring PetClinic, NodeGoat, …) that workshop repos were forked
from, and the clusters of lab repos that intentionally diverge from each other.

## Rules

The source default branch is the only reference for "is a sync needed", and the target is
never force-pushed, so lab work committed in `codev-workshops` cannot be destroyed.

| Target vs. source default branch | `ff-only` (default) | `pr-on-diverge` |
| --- | --- | --- |
| identical | nothing | nothing |
| target strictly behind | fast-forward push | fast-forward push |
| target has its own commits too | skipped, reported | branch + PR in the target |
| target ahead only | skipped, reported | skipped, reported |

`sync: off` on a pair excludes it entirely.

## Why the map is by history, not by name

The two orgs name repos differently (`ts-`/`uc-`/`app_` prefixes were introduced after the
copies were made), and three repos exist in both orgs under the *same* name with completely
unrelated history — syncing those by name would overwrite live work. Every pair was
established by a shared root commit and is listed explicitly; `collisions:` documents the
same-name traps.

## Running it

```bash
pip install pyyaml

scripts/sync_from_source.py status               # read-only classification of every pair
scripts/sync_from_source.py apply --dry-run      # what a run would change
scripts/sync_from_source.py apply                # fast-forward what is safe
scripts/sync_from_source.py apply --create-missing   # also mirror repos under new_repos:
scripts/sync_from_source.py discover             # find upstream renames / unmapped repos
```

Credentials: reading the source org and pushing to existing targets works with any token
that has contents access to both orgs (`gh auth login` is enough). Creating the repos under
`new_repos:` additionally needs `GITHUB_MIRROR_PAT` — a fine-grained PAT on
`codev-workshops` with **Administration: write** and **Contents: write**, plus
**Workflows: write** if the mirrored history touches `.github/workflows/`.

Set `SYNC_GITHUB_BASE=https://github.com` if your environment does not rewrite github.com
through a credential proxy.

## Maintenance

`discover` reports source repos that are absent from the map and, for each, whether some
unpaired `codev-workshops` repo shares its root commit — that is how upstream renames and
newly added workshops surface. Move the resolved ones from `new_repos:` into `pairs:` after
they have been mirrored.

This repo (`codev-workshops/workshop-metadata`) is itself paired with
`Cognition-Partner-Workshops/workshop-content` and holds the tooling, so it is set to
`pr-on-diverge`: upstream changes arrive as a reviewable PR instead of a push that would
drop the sync map.
