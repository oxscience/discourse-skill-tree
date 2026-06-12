# OX Skill Tree

Discourse theme component for campus.outoftheb-ox.de. Renders an
Obsidian-style bubble map of the campus course categories on the user's own
profile summary page (`/u/<username>/summary`), with per-category progress
rings fed by the [discourse-lms](https://github.com/oxscience/discourse-lms)
plugin.

## How it works

- Renders into the `above-user-summary-stats` plugin outlet — pure addition,
  no core DOM is touched. Shown only when a logged-in user views their own
  profile and the `lms_enabled` site setting is on.
- Node lock state is derived from category visibility: categories the user
  cannot read are missing from the client-side category list and render as
  dashed "Pro" bubbles. No permission logic is duplicated here.
- Progress comes from `GET /lms/progress/:category_id` (one request per
  visible LMS node). The SVG renders immediately at fixed size; progress
  arcs are filled in place when responses arrive, so the layout never shifts.
- The graph layout is curated, not computed: the `tree_definition` theme
  setting holds a JSON document with `nodes` (id, category slug, fallback
  label, x/y/r in a 680-wide coordinate space) and `links` (pairs of node
  ids). Invalid JSON falls back to a built-in default.

## Maintenance

When a new course category launches, add a node (and its links) to the
`tree_definition` setting in Admin → Customize → Themes → OX Skill Tree.
All CSS is scoped under `.ox-skill-tree-section`.
