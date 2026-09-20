# Importing an external source document

The import branch of [`shaping`](SKILL.md): pulling a whole source document — a Google Doc
shape-up pitch, a spec, an exported Word doc — into a shaping project rather than pasting a
paraphrase. Screenshots are usually the most information-dense part of a PM's doc, so **the
images matter as much as the text**.

The import lands as its own `source-requirements.md` plus an `images/` dir. `frame.md` then
links to it and quotes only the lines that drive the frame — that keeps `frame.md`
stakeholder-level instead of screenshot-heavy.

Everything mechanical is handled by the bundled importer, which must be used rather than
hand-rolling the extraction:

```
~/.claude/skills/shaping/scripts/import-source-doc.rb
```

**Step 1 — metadata and markdown.** Two Drive MCP calls:

- `get_file_metadata` → title, owner, created/modified. Provenance goes in the doc.
- `read_file_content` with `includeComments: true` → clean markdown (headings, lists, tables
  preserved) with `[image]` placeholders where images sit. Note whether the doc has comments;
  unresolved PM comments often carry live decisions.

**Step 2 — the images.** `download_file_content` with `exportMimeType: "text/html"`. Google Docs
inlines images as base64 data URIs in that export, so the result is large and the harness spills
it to a file on disk instead of returning it inline.

**That spill is the point, not a failure.** Work from the saved path. Never try to route a base64
export through your context, and never re-emit one into a Bash heredoc to write it out — a 300KB
export is ~100k tokens each way and will blow the output limit mid-write.

**Step 3 — run the importer.** Save the Step 1 markdown to a scratch file, then:

```bash
~/.claude/skills/shaping/scripts/import-source-doc.rb import \
  --project <slug> \
  --export <path-to-spilled-tool-result.txt> \
  --markdown <path-to-scratch.md> \
  --title "..." --url "..." --owner "..." \
  --created YYYY-MM-DD --modified YYYY-MM-DD --comments "no comments"
```

It decodes the export, writes each image to `images/image-NN.png`, splices the refs into the
markdown at their original positions, writes `source-requirements.md` (with `shaping: true`
frontmatter and a provenance block) plus a `source.html` backup with local image paths, and
prints an image manifest with byte sizes, pixel dimensions and the text preceding each image.

`--markdown` is strongly preferred — without it the importer flattens the HTML and loses
headings, lists and tables. If the markdown's placeholder count disagrees with the image count
it aborts rather than misplacing screenshots.

**Step 4 — name the images.** Read each extracted image, then rename in one go. This is the
judgement step the script can't do:

```bash
~/.claude/skills/shaping/scripts/import-source-doc.rb rename --project <slug> \
  01=daily-view-graph 02=predictive-table-empty-state ...
```

Renaming repoints every reference in the markdown and the HTML backup, then re-verifies.
`verify --project <slug>` re-runs that check any time.

**Step 5 — read the doc and report.** Add an image inventory table at the bottom describing what
each screenshot shows, explicitly marked as yours rather than the author's, so the screenshots
are searchable without opening them. Then flag to the user, before shaping starts:

- **Empty sections** — the importer lists these. A blank "What would success look like?" or
  "Risks & Rabbit Holes" is exactly what shaping needs to fill in.
- **Truncated or unfinished sentences** — PMs leave these mid-thought. They usually hide a
  constraint worth asking about.
- **Comments on the doc** — decisions that never made it into the body.

**The Drive MCP is the authenticated path — don't reach for the browser.** The Chrome DevTools
MCP runs an isolated profile with no Google session, so `docs.google.com/.../export?format=zip`
just redirects to a sign-in page.
