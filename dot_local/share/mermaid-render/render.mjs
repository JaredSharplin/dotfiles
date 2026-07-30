// Reads Mermaid source on stdin, writes SVG on stdout. Exits non-zero with the
// parser's message on stderr when the source has an unrenderable header.
//
// Colours match the study page's gruvbox palette. The SVG carries them as CSS
// custom properties, so it only looks right in a browser — librsvg and other
// rasterisers resolve neither var() nor color-mix() and render the nodes black.
import { readFileSync } from "node:fs";
import { renderMermaidSVG } from "beautiful-mermaid";

const COLORS = {
  bg: "#262626",
  fg: "#ebdbb2",
  line: "#504945",
  accent: "#b8bb26",
  muted: "#928374",
  surface: "#32302f",
  border: "#504945",
  font: "-apple-system, sans-serif",
  transparent: true,
};

// The renderer templates the font name into a Google Fonts @import. The page is
// offline and the font is a system one, so drop the fetch.
const withoutWebfont = (svg) => svg.replace(/\s*@import url\([^)]*\);/, "");

const source = readFileSync(0, "utf8");

try {
  process.stdout.write(withoutWebfont(renderMermaidSVG(source, COLORS)));
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
}
