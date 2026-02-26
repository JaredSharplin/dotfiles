import { renderMermaidASCII } from "beautiful-mermaid"

const chunks: Buffer[] = []
for await (const chunk of process.stdin as AsyncIterable<Buffer>) chunks.push(chunk)
const input = Buffer.concat(chunks).toString().trim()
process.stdout.write(renderMermaidASCII(input) + "\n")
