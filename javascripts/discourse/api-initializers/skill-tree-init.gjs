import Component from "@glimmer/component";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";

const SVG_NS = "http://www.w3.org/2000/svg";

// Fallback when the theme setting is missing or contains invalid JSON.
// Layout logic: a clean game-style talent tree, top→down, solid edges only.
// Symposien sits at the apex, overarching the whole tree (the cross-cutting
// talk series). Below it Science is the root and fans into the four domains.
// Third tier converges: Ernährung is fed by Training + Rehab; Pain &
// Performance — the big capstone — is fed by Training + Rehab + Neuro.
// Kommunikation (MI/CFT series) mirrors Ernährung on the right, fed by
// Rehab + Neuro (one mirrored edge crossing, same as on the left side).
// No dashed "overlap" web: a tree, not a net.
const DEFAULT_TREE = {
  height: 525,
  nodes: [
    { id: "symposien", category: "ox-symposien-pro", label: "Symposien", x: 335, y: 56, r: 26 },
    { id: "science", category: "forschung-evidenz", label: "Science", x: 335, y: 165, r: 32 },
    { id: "tech-ki", category: "webinare", label: "Tech & KI", x: 125, y: 300, r: 24 },
    { id: "training", category: "training", label: "Training", x: 265, y: 300, r: 30 },
    { id: "rehab", category: "klinik", label: "Rehab", x: 405, y: 300, r: 32 },
    { id: "neuro", category: "neurowissenschaften", label: ["Neuro-", "wissenschaften"], x: 545, y: 300, r: 28 },
    { id: "ernaehrung", category: "ernaehrung", label: "Ernährung", x: 220, y: 440, r: 26 },
    { id: "pain-performance", category: "pain-performance", label: "Pain & Performance", x: 335, y: 448, r: 42 },
    { id: "kommunikation", category: "kommunikation", label: "Kommunikation", x: 450, y: 440, r: 26 },
  ],
  // Solid tree edges only — the learning progression.
  links: [
    ["symposien", "science"],
    ["science", "tech-ki"],
    ["science", "training"],
    ["science", "rehab"],
    ["science", "neuro"],
    ["training", "ernaehrung"],
    ["rehab", "ernaehrung"],
    ["training", "pain-performance"],
    ["rehab", "pain-performance"],
    ["neuro", "pain-performance"],
    ["rehab", "kommunikation"],
    ["neuro", "kommunikation"],
  ],
  // Intentionally empty: the dashed thematic web was the main source of
  // clutter. Kept as a capability — re-add pairs here if ever wanted.
  overlaps: [],
};

function treeDefinition() {
  try {
    if (typeof settings !== "undefined" && settings.tree_definition) {
      const parsed = JSON.parse(settings.tree_definition);
      if (parsed && Array.isArray(parsed.nodes)) {
        return parsed;
      }
    }
  } catch {
    // invalid JSON in the setting — use the built-in default
  }
  return JSON.parse(JSON.stringify(DEFAULT_TREE));
}

function svgEl(tag, attrs = {}) {
  const el = document.createElementNS(SVG_NS, tag);
  Object.keys(attrs).forEach((k) => el.setAttribute(k, attrs[k]));
  return el;
}

function findCategory(site, slug) {
  return (site.categories || []).find((c) => c.slug === slug) || null;
}

function isLmsCategory(cat) {
  return !!cat && (cat.lms_enabled === true || cat.lms_enabled === "true");
}

function buildGraph(api, container) {
  const def = treeDefinition();
  const site = api.container.lookup("service:site");
  const height = def.height || 420;

  const svg = svgEl("svg", {
    viewBox: `0 0 680 ${height}`,
    role: "img",
    "aria-label": "Lernpfad-Übersicht",
  });

  const nodesById = {};
  def.nodes.forEach((n) => (nodesById[n.id] = n));

  // Edges first so the bubbles paint on top of the line ends. Overlap edges
  // (thematic closeness, not a learning step) get extra padding so they also
  // clear the node labels, and render dashed via .ost-overlap. For nodes that
  // sit close together the full label-clearance pad would consume the whole
  // segment — in that case shrink the pad so the edge still draws (just
  // clearing the bubbles), so "docks to all" never silently loses an edge.
  function drawEdge(pair, cls, pad) {
    const a = nodesById[pair[0]];
    const b = nodesById[pair[1]];
    if (!a || !b) {
      return;
    }
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (!len) {
      return;
    }
    let padA = a.r + pad;
    let padB = b.r + pad;
    if (len <= padA + padB) {
      const slack = Math.max(0, (len - a.r - b.r - 12) / 2);
      padA = a.r + slack;
      padB = b.r + slack;
      if (len <= padA + padB) {
        return;
      }
    }
    const ux = dx / len;
    const uy = dy / len;
    svg.appendChild(
      svgEl("line", {
        class: cls,
        x1: (a.x + ux * padA).toFixed(1),
        y1: (a.y + uy * padA).toFixed(1),
        x2: (b.x - ux * padB).toFixed(1),
        y2: (b.y - uy * padB).toFixed(1),
      })
    );
  }

  (def.overlaps || []).forEach((pair) => drawEdge(pair, "ost-edge ost-overlap", 30));
  (def.links || []).forEach((pair) => drawEdge(pair, "ost-edge", 8));

  const pricingUrl =
    (typeof settings !== "undefined" && settings.pricing_url) ||
    "https://outoftheb-ox.de/pages/oxcampus#ox-pricing";

  def.nodes.forEach((n) => {
    const cat = findCategory(site, n.category);
    const locked = !cat;
    const lms = isLmsCategory(cat);

    const g = cat
      ? svgEl("a", { href: `/c/${cat.slug}/${cat.id}` })
      : svgEl("a", { href: pricingUrl });
    g.setAttribute("class", "ost-node" + (locked ? " -locked" : ""));

    if (locked) {
      const tooltip = svgEl("title");
      tooltip.textContent = "Pro-Bereich — mehr zum Campus-Zugang";
      g.appendChild(tooltip);
    }

    if (lms) {
      const ringR = n.r + 5;
      const circ = 2 * Math.PI * ringR;
      g.appendChild(
        svgEl("circle", { class: "ost-ring-track", cx: n.x, cy: n.y, r: ringR })
      );
      const ring = svgEl("circle", {
        class: "ost-ring",
        cx: n.x,
        cy: n.y,
        r: ringR,
        "stroke-dasharray": `0 ${circ.toFixed(1)}`,
        transform: `rotate(-90 ${n.x} ${n.y})`,
      });
      g.appendChild(ring);
      n._ring = ring;
      n._circ = circ;
    }

    g.appendChild(
      svgEl("circle", { class: "ost-bubble", cx: n.x, cy: n.y, r: n.r })
    );

    const center = svgEl("text", {
      class: "ost-pct",
      x: n.x,
      y: n.y + 5,
      "text-anchor": "middle",
    });
    center.textContent = locked ? "Pro" : "";
    g.appendChild(center);
    n._center = center;

    const label = svgEl("text", {
      class: "ost-label",
      x: n.x,
      y: n.y + n.r + 24,
      "text-anchor": "middle",
    });
    // Curated label wins (allows short forms and manual line breaks via
    // arrays); category name is the fallback.
    const raw = n.label || (cat ? cat.name : n.id);
    const lines = Array.isArray(raw) ? raw : [raw];
    lines.forEach((line, i) => {
      const tspan = svgEl("tspan", { x: n.x, dy: i === 0 ? 0 : "1.2em" });
      tspan.textContent = line;
      label.appendChild(tspan);
    });
    g.appendChild(label);

    svg.appendChild(g);
  });

  container.appendChild(svg);

  // Fit the viewBox to the actual rendered content (bubbles + labels) so
  // there is no asymmetric dead space around the graph. The curated layout
  // leaves more empty room on one side; on a narrow (mobile) viewport that
  // reads as the whole tree being shoved sideways. Cropping to the real
  // bounding box keeps it centered on every screen width. Wrapped in a
  // guard so a failed/empty getBBox just leaves the static viewBox in place.
  try {
    const bb = svg.getBBox();
    if (bb && bb.width > 0 && bb.height > 0) {
      const pad = 18;
      svg.setAttribute(
        "viewBox",
        `${(bb.x - pad).toFixed(1)} ${(bb.y - pad).toFixed(1)} ` +
          `${(bb.width + pad * 2).toFixed(1)} ${(bb.height + pad * 2).toFixed(1)}`
      );
    }
  } catch {
    // keep the static viewBox
  }

  const legend = document.createElement("div");
  legend.className = "ost-legend";
  let legendHtml =
    '<span><span class="ost-dot -ring"></span>Ring = dein Fortschritt</span>' +
    '<span><span class="ost-dot -locked"></span>Pro-Bereich</span>';
  if ((def.overlaps || []).length) {
    legendHtml += '<span><span class="ost-dash"></span>inhaltliche Nähe</span>';
  }
  legend.innerHTML = legendHtml;
  container.appendChild(legend);

  // Async progress fill — updates existing SVG attributes in place, so the
  // layout never shifts while the requests are in flight.
  def.nodes.forEach((n) => {
    const cat = findCategory(site, n.category);
    if (!isLmsCategory(cat)) {
      return;
    }
    ajax(`/lms/progress/${cat.id}.json`)
      .then((p) => {
        const pct = p && typeof p.percent === "number" ? p.percent : 0;
        n._ring.setAttribute(
          "stroke-dasharray",
          `${((pct / 100) * n._circ).toFixed(1)} ${n._circ.toFixed(1)}`
        );
        n._center.textContent = `${pct}%`;
      })
      .catch(() => {
        n._center.textContent = "";
      });
  });
}

export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");
  if (!siteSettings.lms_enabled) {
    return;
  }

  class OxSkillTree extends Component {
    get shouldShow() {
      const currentUser = api.getCurrentUser();
      const profileUser = this.args.outletArgs?.user;
      return !!currentUser && !!profileUser && currentUser.id === profileUser.id;
    }

    setup = (element) => {
      try {
        buildGraph(api, element);
      } catch (e) {
        // Never let the visualization break the profile page.
        // eslint-disable-next-line no-console
        console.warn("[ox-skill-tree]", e);
      }
    };

    <template>
      {{#if this.shouldShow}}
        <div class="top-section ox-skill-tree-section">
          <h3 class="stats-title">Dein Lernpfad</h3>
          <div class="ox-skill-tree-graph" {{didInsert this.setup}}></div>
        </div>
      {{/if}}
    </template>
  }

  api.renderInOutlet("above-user-summary-stats", OxSkillTree);
});
