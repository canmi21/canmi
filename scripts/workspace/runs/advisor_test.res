open Testing

let holder: Advisor.holder = {name: "a", pid: 7, since: "t", handingTo: None}
let standing = (record, ~pid=1, ~alive=_ => true) => Advisor.standingOf(record, ~pid, ~alive)

describe("the advisor's seat", () => {
  test("tells the three cases and its own", () => {
    expect(standing(None))->toEqual(First)
    expect(standing(Some(holder)))->toEqual(Candidate(holder))
    expect(standing(Some(holder), ~alive=_ => false))->toEqual(Orphan(holder))
    expect(standing(Some(holder), ~pid=7))->toEqual(Holding(holder))
  })

  test("acts on the holder's order alone", () => {
    expect(Advisor.orderFrom(Some(holder), ~sender="a"))->toEqual(Ok())
    expect(Advisor.orderFrom(Some(holder), ~sender="b")->Result.isError)->toEqual(true)
    expect(Advisor.orderFrom(None, ~sender="b")->Result.isError)->toEqual(true)
  })

  test("parses a valid record and rejects broken text", () => {
    let text = Ledger.line([("name", JSON.String("a")), ("pid", JSON.Number(7.))])
    expect(Advisor.parse(text)->Option.map(one => one.pid))->toEqual(Some(7))
    expect(Advisor.parse("broken"))->toEqual(None)
  })
})

@val external processPid: int = "process.pid"

describe("advisor commands", () => {
  let root = temporaryRoot("advisor-")
  let saved = ref([])
  beforeEach(() => {
    saved :=
      ["ADVISOR_HOME", "RUNS_HOME", "CLAUDE_PID"]->Array.map(key => (key, Node.env->Dict.get(key)))
    Node.env->Dict.set("ADVISOR_HOME", root.contents)
    Node.env->Dict.set("RUNS_HOME", Node.join([root.contents, "runs"]))
    Node.env->Dict.set("CLAUDE_PID", Int.toString(processPid))
  })
  afterEach(() =>
    saved.contents->Array.forEach(
      ((key, value)) =>
        switch value {
        | Some(value) => Node.env->Dict.set(key, value)
        | None => Node.env->Dict.delete(key)
        },
    )
  )
  let record = () => Node.readFileSync(Advisor.currentFile())
  let claim = () => Advisor.claim("old", ~pid=processPid, ~authorSaid=false)
  let run = source =>
    Node.spawnSync(
      "node",
      ["--input-type=module", "-e", source],
      {
        encoding: "utf8",
        timeout: 8000,
      },
    )
  let modulePath = Node.pathToFileURL(
    Node.join([Node.cwd(), "scripts/workspace/runs/advisor.res.mjs"]),
  )["href"]

  test("refuses unknown caller pids for every mutation and says it cannot tell", () => {
    [None, Some("garbage"), Some("0"), Some("-1"), Some("12junk")]->Array.forEach(
      value => {
        switch value {
        | None => Node.env->Dict.delete("CLAUDE_PID")
        | Some(value) => Node.env->Dict.set("CLAUDE_PID", value)
        }
        expect(Advisor.main(["claim", "unknown", "--author-said"]))->toEqual(1)
        expect(Node.existsSync(Advisor.currentFile()))->toEqual(false)
        Advisor.write({...holder, pid: 0})
        let before = record()
        expect(Advisor.main(["handing", "new"]))->toEqual(1)
        expect(Advisor.main(["pass", "new", Int.toString(processPid)]))->toEqual(1)
        expect(record())->toEqual(before)
        Node.rmSync(Advisor.currentFile(), {recursive: false, force: true})
      },
    )
    let result = run(
      `import * as a from '${modulePath}'; delete process.env.CLAUDE_PID; a.main(['case']);`,
    )
    expect(result.stdout->Nullable.getOr("")->String.includes("cannot tell"))->toEqual(true)
  })

  test("claims first, preserves a live holder, and needs the author's word for an orphan", () => {
    expect(claim())->toEqual(0)
    let before = record()
    expect(Advisor.claim("other", ~pid=processPid + 1, ~authorSaid=true))->toEqual(1)
    expect(record())->toEqual(before)
    Advisor.write({...holder, pid: 2147483647})
    expect(claim())->toEqual(1)
    expect(Advisor.claim("old", ~pid=processPid, ~authorSaid=true))->toEqual(0)
  })

  test("refuses handing and passing with a missing caller pid", () => {
    Advisor.write({...holder, pid: 0})
    Node.env->Dict.delete("CLAUDE_PID")
    let before = record()
    let handing = Advisor.main(["handing", "new"])
    let passing = Advisor.main(["pass", "new", Int.toString(processPid)])
    expect((handing, passing, record()))->toEqual((1, 1, before))
  })

  test("refuses a live successor other than the one named by handing", () => {
    expect(claim())->toEqual(0)
    expect(Advisor.handing("new", ~pid=processPid))->toEqual(0)
    let before = record()
    expect(Advisor.pass("different", ~to=processPid, ~pid=processPid))->toEqual(1)
    expect(record())->toEqual(before)
  })

  test("refuses a dead positive successor pid", () => {
    expect(claim())->toEqual(0)
    let before = record()
    expect(Advisor.pass("new", ~to=2147483647, ~pid=processPid))->toEqual(1)
    expect(record())->toEqual(before)
  })

  test("refuses a truncated record even while its previous holder lives", () => {
    expect(claim())->toEqual(0)
    Node.writeFileSync(Advisor.currentFile(), "{\"name\":\"old\",")
    let before = record()
    expect(Advisor.claim("new", ~pid=processPid + 1, ~authorSaid=false))->toEqual(1)
    expect(record())->toEqual(before)
  })

  test(
    "refuses dead targets and a different named successor without changing either record",
    () => {
      expect(claim())->toEqual(0)
      Ledger.registerSession(~role="advisor", ~name="old", ~transcript=None)
      expect(Advisor.handing("new", ~pid=processPid))->toEqual(0)
      let before = record()
      let registered = Node.readFileSync(Node.join([Ledger.sessions(), "old.json"]))
      [0, -1, 2147483647]->Array.forEach(
        to => {
          expect(Advisor.pass("new", ~to, ~pid=processPid))->toEqual(1)
          expect(record())->toEqual(before)
        },
      )
      expect(Advisor.pass("different", ~to=processPid, ~pid=processPid))->toEqual(1)
      expect(record())->toEqual(before)
      expect(Node.readFileSync(Node.join([Ledger.sessions(), "old.json"])))->toEqual(registered)
    },
  )

  test("passes to a live successor and unregisters only the old holder", () => {
    expect(claim())->toEqual(0)
    Ledger.registerSession(~role="advisor", ~name="old", ~transcript=None)
    Ledger.registerSession(~role="advisor", ~name="new", ~transcript=None)
    expect(Advisor.handing("new", ~pid=processPid))->toEqual(0)
    expect(Advisor.pass("new", ~to=processPid, ~pid=processPid))->toEqual(0)
    expect(Advisor.read()->Option.map(one => one.name))->toEqual(Some("new"))
    expect(Node.readdir(Ledger.sessions()))->toEqual(["new.json"])
  })

  test("refuses handing and passing by another session", () => {
    expect(claim())->toEqual(0)
    let before = record()
    expect(Advisor.handing("new", ~pid=processPid + 1))->toEqual(1)
    expect(Advisor.pass("new", ~to=processPid, ~pid=processPid + 1))->toEqual(1)
    expect(record())->toEqual(before)
  })

  test("requires the author's word for every present broken record", () => {
    ["", "broken", "{\"name\":\"old\",", "{}", "{\"name\":\"old\",\"pid\":0}"]->Array.forEach(
      text => {
        Node.writeFileSync(Advisor.currentFile(), text)
        expect(claim())->toEqual(1)
        expect(record())->toEqual(text)
        expect(Advisor.claim("old", ~pid=processPid, ~authorSaid=true))->toEqual(0)
      },
    )
  })

  test("keeps the seat and registration when publishing a pass fails", () => {
    expect(claim())->toEqual(0)
    Ledger.registerSession(~role="advisor", ~name="old", ~transcript=None)
    let before = record()
    let result = run(
      `
      import fs from 'node:fs';
      import {syncBuiltinESMExports} from 'node:module';
      const write = fs.writeFileSync;
      fs.writeFileSync = (path, ...args) => {
        if (path.endsWith('/${Delegation.advisorCurrent}')) {
          write(path, ''); throw Error('interrupted write');
        }
        return write(path, ...args);
      };
      const rename = fs.renameSync;
      fs.renameSync = (from, to) => {
        if (to.endsWith('/${Delegation.advisorCurrent}')) throw Error('interrupted rename');
        return rename(from, to);
      };
      syncBuiltinESMExports();
      const a = await import('${modulePath}');
      try { process.exitCode = a.pass('new', process.pid, Number(process.env.CLAUDE_PID)); }
      catch { process.exitCode = 2; }
    `,
    )
    expect(record())->toEqual(before)
    expect(result.status->Nullable.toOption)->toEqual(Some(1))
    expect(Node.readdir(Ledger.sessions()))->toEqual(["old.json"])
  })

  test("allows only one of two racing first claims", () => {
    let result = run(
      `
      import {Worker} from 'node:worker_threads';
      const shared = new SharedArrayBuffer(4);
      const source = \`
        const {workerData, parentPort, threadId} = require('node:worker_threads');
        const fs = require('node:fs');
        const {syncBuiltinESMExports} = require('node:module');
        const gate = new Int32Array(workerData);
        const write = fs.writeFileSync;
        fs.writeFileSync = (path, ...args) => {
          if (path.endsWith('/${Delegation.advisorCurrent}')) {
            Atomics.add(gate, 0, 1); Atomics.notify(gate, 0);
            if (Atomics.load(gate, 0) < 2) Atomics.wait(gate, 0, 1, 1000);
          }
          return write(path, ...args);
        };
        syncBuiltinESMExports();
        import('${modulePath}').then(a => {
          parentPort.postMessage(a.claim('racer' + threadId, process.pid + threadId, false));
        });
      \`;
      const results = await Promise.all([1, 2].map(() => new Promise((resolve, reject) => {
        const worker = new Worker(source, {eval: true, workerData: shared, execArgv: []});
        worker.on('message', resolve); worker.on('error', reject);
      })));
      console.log('winners=' + results.filter(code => code === 0).length);
    `,
    )
    expectAs(result.status->Nullable.toOption, result.stderr->Nullable.getOr(""))->toEqual(Some(0))
    expect(result.stdout->Nullable.getOr("")->String.includes("winners=1"))->toEqual(true)
  })
})
