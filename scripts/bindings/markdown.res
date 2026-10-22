/** CommonMark and GFM as remark reads them, the same reading web's RFC pages are drawn with. */
type plugin
type processor
type rec node = {@as("type") kind: string, value?: string, children?: array<node>}

@module("unified") external unified: unit => processor = "unified"
@module("remark-parse") external remarkParse: plugin = "default"
@module("remark-gfm") external remarkGfm: plugin = "default"
@send external use: (processor, plugin) => processor = "use"
@send external parseWith: (processor, string) => node = "parse"

/** The syntax tree of `markdown`. */
let tree = markdown => unified()->use(remarkParse)->use(remarkGfm)->parseWith(markdown)
