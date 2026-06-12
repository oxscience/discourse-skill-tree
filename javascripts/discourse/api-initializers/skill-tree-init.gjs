import Component from "@glimmer/component";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";

const SVG_NS = "http://www.w3.org/2000/svg";

// Fallback when the theme setting is missing or contains invalid JSON.
// Layout logic: one linear learning path rising from bottom-left (free entry)
// to top-right (Pro specialization), Tech & KI branching off Science,
// Symposien as an unlinked satellite (format, not a skill).
const DEFAULT_TREE = {
  height: 420,
  nodes: [
    { id: "training", category: "training", label: "Training", x: 80, y: 280, r: 40 },
    { id: "ernaehrung", category: "ernaehrung", label: "Ernährung", x: 190, y: 200, r: 30 },
    { id: "rehab", category: "klinik", label: "Rehab", x: 300, y: 270, r: 36 },
    { id: "science", category: "forschung-evidenz", label: "Science", x: 410, y: 180, r: 34 },
    { id: "tech-ki", category: "webinare", label: "Tech & KI", x: 350, y: 80, r: 28 },
    { id: "neuro", category: "neurowissenschaften", label: ["Neuro-", "wissenschaften"], x: 520, y: 250, r: 36 },
    { id: "pain-performance", category: "pain-performance", label: "Pain & Performance", x: 615, y: 200, r: 40 },
    { id: "symposien", category: "ox-symposien-pro", label: "Symposien", x: 600, y: 350, r: 26 },
  ],
  links: [
    ["training", "ernaehrung"],
    ["ernaehrung", "rehab"],
    ["rehab", "science"],
    ["science", "tech-ki"],
    ["science", "neuro"],
    ["neuro", "pain-performance"],
  ],
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

  // Edges first so the bubbles paint on top of the line ends.
  (def.links || []).forEach((pair) => {
    const a = nodesById[pair[0]];
    const b = nodesById[pair[1]];
    if (!a || !b) {
      return;
    }
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len = Math.sqrt(dx * dx + dy * dy);
    const padA = a.r + 8;
    const padB = b.r + 8;
    if (!len || len <= padA + padB) {
      return;
    }
    const ux = dx / len;
    const uy = dy / len;
    svg.appendChild(
      svgEl("line", {
        class: "ost-edge",
        x1: (a.x + ux * padA).toFixed(1),
        y1: (a.y + uy * padA).toFixed(1),
        x2: (b.x - ux * padB).toFixed(1),
        y2: (b.y - uy * padB).toFixed(1),
      })
    );
  });

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

  const legend = document.createElement("div");
  legend.className = "ost-legend";
  legend.innerHTML =
    '<span><span class="ost-dot -ring"></span>Ring = dein Fortschritt</span>' +
    '<span><span class="ost-dot -locked"></span>Pro-Bereich</span>';
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
