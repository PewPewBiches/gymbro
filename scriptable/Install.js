// gymbro Installer
//
// Paste this into a new Scriptable script called "Install", run it once,
// answer a few questions, and it writes everything else for you.
//
// It creates: GymIn, GymOut, GymManual, GymWidget, and gym_config.json
// in your Scriptable iCloud folder.

// ---- change this to your fork if you are not using the original ----
const REPO = "https://raw.githubusercontent.com/PewPewBiches/gymbro/main/scriptable/"
// --------------------------------------------------------------------

const FILES = ["GymIn.js", "GymOut.js", "GymManual.js", "GymWidget.js"]

const fm = FileManager.iCloud()
const dir = fm.documentsDirectory()
const pad = n => String(n).padStart(2, "0")
const key = d => d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())

async function ask(title, message, fields) {
  const a = new Alert()
  a.title = title
  a.message = message
  for (const f of fields) {
    a.addTextField(f.placeholder, f.value ?? "")
  }
  a.addAction("Next")
  a.addCancelAction("Cancel")
  const r = await a.present()
  if (r === -1) return null
  return fields.map((_, i) => a.textFieldValue(i))
}

async function choose(title, message, options) {
  const a = new Alert()
  a.title = title
  a.message = message
  for (const o of options) a.addAction(o.label)
  a.addCancelAction("Cancel")
  const i = await a.present()
  return i === -1 ? null : options[i].value
}

/// Tap rows to toggle, then Done. Any combination of days works.
async function pickDays(names, preselected) {
  const chosen = new Set(preselected)

  const table = new UITable()
  table.showSeparators = true

  function build() {
    table.removeAllRows()

    const head = new UITableRow()
    head.isHeader = true
    head.addText("Tap the days you train", "Then tap Done, top right")
    table.addRow(head)

    for (let i = 0; i < 7; i++) {
      const row = new UITableRow()
      row.height = 52
      const on = chosen.has(i)
      row.addText(on ? "\u2713" : "\u00B7").widthWeight = 12
      row.addText(names[i], on ? "training day" : "rest day").widthWeight = 88
      row.onSelect = () => {
        if (chosen.has(i)) chosen.delete(i)
        else chosen.add(i)
        build()
        table.reload()
      }
      table.addRow(row)
    }
  }

  build()
  await table.present(false)

  if (chosen.size === 0) {
    const a = new Alert()
    a.title = "No days picked"
    a.message = "You need at least one training day, otherwise nothing can be missed."
    a.addAction("Try again")
    a.addCancelAction("Cancel")
    const r = await a.present()
    if (r === -1) return null
    return pickDays(names, [1, 2, 3, 4, 5])
  }

  return [...chosen].sort()
}

async function main() {
  // 1. Money and dates
  const money = await ask(
    "What did you pay?",
    "The full membership fee, and how many months it covers.",
    [
      { placeholder: "Amount, e.g. 10000" },
      { placeholder: "Months, e.g. 4", value: "4" }
    ]
  )
  if (!money) return
  const fee = Number(money[0].replace(/[^0-9.]/g, "")) || 10000
  const months = Number(money[1]) || 4

  // 2. Start date
  const startChoice = await choose(
    "When did it start?",
    "Pick the day your membership began.",
    [
      { label: "Today", value: "today" },
      { label: "Enter a date", value: "custom" }
    ]
  )
  if (!startChoice) return

  let start = new Date()
  if (startChoice === "custom") {
    const typed = await ask("Start date", "Format: YYYY-MM-DD", [
      { placeholder: "2026-09-01", value: key(new Date()) }
    ])
    if (!typed) return
    const p = typed[0].split("-").map(Number)
    if (p.length === 3 && !isNaN(p[0])) start = new Date(p[0], p[1] - 1, p[2])
  }
  const end = new Date(start)
  end.setMonth(end.getMonth() + months)

  // 3. Schedule
  const dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday",
                    "Thursday", "Friday", "Saturday"]

  let days = await choose(
    "Which days do you go?",
    "Only these days can cost you money. Pick a preset or choose your own.",
    [
      { label: "Monday to Friday", value: [1, 2, 3, 4, 5] },
      { label: "Mon, Wed, Fri", value: [1, 3, 5] },
      { label: "Monday to Saturday", value: [1, 2, 3, 4, 5, 6] },
      { label: "Let me pick", value: "custom" }
    ]
  )
  if (!days) return

  if (days === "custom") {
    days = await pickDays(dayNames, [1, 2, 3, 4, 5])
    if (!days) return
  }

  // 4. Minimum session
  const mins = await choose(
    "Shortest real visit?",
    "Anything briefer is treated as walking past the gym. Pick a little under your usual shortest session.",
    [
      { label: "30 minutes", value: 30 },
      { label: "40 minutes", value: 40 },
      { label: "50 minutes", value: 50 },
      { label: "60 minutes", value: 60 }
    ]
  )
  if (mins === null) return

  // The app stores weekdays as 1 = Sunday ... 7 = Saturday.
  const appDays = days.map(d => d + 1).sort()

  const config = {
    start: key(start),
    end: key(end),
    totalFee: fee,
    days: appDays,
    minMinutes: mins,
    trackFrom: key(new Date()),
    seedMissed: 0,
    skipDates: [],
    restored: []
  }

  // 5. Write config
  fm.writeString(
    fm.joinPath(dir, "gym_config.json"),
    JSON.stringify(config, null, 2)
  )

  // 6. Fetch the scripts
  const done = []
  const failed = []
  for (const f of FILES) {
    try {
      const body = await new Request(REPO + f).loadString()
      if (!body || body.length < 50) throw new Error("empty")
      fm.writeString(fm.joinPath(dir, f), body)
      done.push(f.replace(".js", ""))
    } catch (e) {
      failed.push(f.replace(".js", ""))
    }
  }

  // 7. Report
  const scheduled = countScheduled(start, end, days)
  const rate = scheduled > 0 ? Math.round(fee / scheduled) : 0

  const out = new Alert()
  out.title = failed.length ? "Mostly done" : "Installed"
  out.message =
    "Each missed session will cost you \u20B9" + rate +
    " across " + scheduled + " scheduled days.\n\n" +
    "Installed: " + (done.join(", ") || "nothing") +
    (failed.length ? "\nFailed: " + failed.join(", ") + "\nCheck your connection and run again." : "") +
    "\n\nNext: create the two Shortcuts automations, then add the widget. See the README."
  out.addAction("Done")
  await out.present()
}

function countScheduled(a, b, days) {
  let n = 0
  const d = new Date(a)
  while (d <= b) {
    if (days.includes(d.getDay())) n++
    d.setDate(d.getDate() + 1)
  }
  return n
}

await main()
Script.complete()
