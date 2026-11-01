open Testing

let doc = "# Title\n\n**A lead** -- the rest of `code` here.\n\n- **Item lead**: more\n\n```sh\nmise run x\n```\n"

describe("a doc against its original", () => {
  test("is the same where only the prose between has changed", () => {
    let edited = doc->String.replace("the rest of", "what remains of")
    expect(Doc_compare.compare(doc, edited))->toEqual([])
  })

  test("names a heading, a bold lead and a code span lost or added", () => {
    let edited = doc->String.replace("# Title", "## Title")->String.replace("**A lead**", "A lead")
    expect(Doc_compare.compare(doc, edited))->toEqual([
      "lost heading: # Title",
      "added heading: ## Title",
      "lost bold lead: **A lead**",
    ])
    expect(Doc_compare.compare(doc, doc->String.replace("`code`", "`other`")))->toEqual([
      "lost code span: `code`",
      "added code span: `other`",
    ])
  })

  test("reads a fenced block as one span and a heading inside it as none", () => {
    let fenced = "```md\n# not a heading\n```\n"
    expect(Doc_compare.read(fenced).headings)->toEqual([])
    expect(Doc_compare.compare(fenced, "```md\n# changed\n```\n"))->toEqual([
      "lost code span: # not a heading",
      "added code span: # changed",
    ])
  })

  test("reads a bold lead past a list marker and across a wrapped line", () => {
    expect(Doc_compare.read("1. **Wrapped\nlead** and more\n").leads)->toEqual(["**Wrapped lead**"])
  })
})
