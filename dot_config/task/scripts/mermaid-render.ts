import { renderMermaidASCII } from "beautiful-mermaid"

// Gruvbox dark theme — force truecolor since output is piped (not a TTY)
const theme = {
  fg:       "#ebdbb2", // gruvbox fg     — node labels
  border:   "#83a598", // gruvbox aqua   — node borders
  line:     "#a89984", // gruvbox gray4  — edge lines
  arrow:    "#fabd2f", // gruvbox yellow — arrowheads
  corner:   "#a89984", // same as line
  junction: "#83a598", // same as border
}

const chunks: Buffer[] = []
for await (const chunk of process.stdin as AsyncIterable<Buffer>) chunks.push(chunk)
const input = Buffer.concat(chunks).toString().trim()
process.stdout.write(renderMermaidASCII(input, { colorMode: "truecolor", theme }) + "\n")
