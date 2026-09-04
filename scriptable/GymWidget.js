// GymWidget
// Homescreen widget showing rupees burnt on missed gym sessions.
// Reads gym_log.txt written by GymLog.js

// ---------- CONFIG ----------
// These are only fallbacks. The Install script writes gym_config.json,
// and if that file exists its values win. You should not need to edit
// anything here.
let START       = "2026-01-01"   // first day of the commitment
let END         = "2026-05-01"   // last day of the commitment
let TOTAL_FEE   = 10000          // what you paid
let DAYS        = [1, 2, 3, 4, 5] // 0 = Sunday ... 6 = Saturday
let MIN_MINUTES = 45             // shortest visit that counts
let TRACK_FROM  = "2026-01-01"   // start counting misses from here
let SEED_MISSED = 0              // misses before TRACK_FROM you want to own
let SKIP_DATES  = []             // ["2026-10-20"] travel, illness, gym closed
let RESTORED    = []             // days repaired with a weekend session
// ----------------------------

const pad = n => String(n).padStart(2, "0")
const key = d => d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())

function parseDay(s) {
  const p = s.split("-").map(Number)
  return new Date(p[0], p[1] - 1, p[2])
}

function parseStamp(s) {
  // "2026-01-01 18:30"
  const parts = s.trim().split(" ")
  const d = parts[0].split("-").map(Number)
  const t = (parts[1] || "00:00").split(":").map(Number)
  return new Date(d[0], d[1] - 1, d[2], t[0], t[1])
}

// --- read the log ---
const fm = FileManager.iCloud()
const path = fm.joinPath(fm.documentsDirectory(), "gym_log.txt")

let lines = []
if (fm.fileExists(path)) {
  if (!fm.isFileDownloaded(path)) await fm.downloadFileFromiCloud(path)
  lines = fm.readString(path).split("\n").filter(l => l.trim().length > 0)
}

// --- overlay settings from the app, if present ---
const cfgPath = fm.joinPath(fm.documentsDirectory(), "gym_config.json")
if (fm.fileExists(cfgPath)) {
  try {
    if (!fm.isFileDownloaded(cfgPath)) await fm.downloadFileFromiCloud(cfgPath)
    const c = JSON.parse(fm.readString(cfgPath))
    if (c.start) START = c.start
    if (c.end) END = c.end
    if (typeof c.totalFee === "number") TOTAL_FEE = c.totalFee
    // The app stores weekdays as 1=Sunday..7=Saturday. Shift to 0..6.
    if (Array.isArray(c.days)) DAYS = c.days.map(d => d - 1)
    if (typeof c.minMinutes === "number") MIN_MINUTES = c.minMinutes
    if (c.trackFrom) TRACK_FROM = c.trackFrom
    if (typeof c.seedMissed === "number") SEED_MISSED = c.seedMissed
    if (Array.isArray(c.skipDates)) SKIP_DATES = c.skipDates
    if (Array.isArray(c.restored)) RESTORED = c.restored
  } catch (e) {
    // Bad or half written file. Keep the fallbacks above.
  }
}

// --- build the set of days a session happened ---
const autoDays = new Set()
const manualDays = new Set()
let pendingIn = null

for (const line of lines) {
  const comma = line.indexOf(",")
  if (comma < 0) continue
  const tag = line.slice(0, comma).trim().toUpperCase()
  const when = parseStamp(line.slice(comma + 1))
  if (isNaN(when.getTime())) continue

  if (tag === "IN") {
    // Duplicate arrivals can fire on GPS drift. Keep the earliest one
    // from the same day so the session is never shortened.
    if (!pendingIn || key(pendingIn) !== key(when)) pendingIn = when
  } else if (tag === "OUT" && pendingIn) {
    const mins = (when - pendingIn) / 60000
    if (mins >= MIN_MINUTES) autoDays.add(key(pendingIn))
    pendingIn = null
  } else if (tag === "MANUAL") {
    manualDays.add(key(when))
  }
}

// --- money per session ---
const startDate = parseDay(START)
const endDate = parseDay(END)
let scheduledTotal = 0
for (let d = new Date(startDate); d <= endDate; d.setDate(d.getDate() + 1)) {
  if (DAYS.includes(d.getDay())) scheduledTotal++
}
const rate = TOTAL_FEE / scheduledTotal

// --- count misses from TRACK_FROM up to yesterday ---
const today = new Date()
today.setHours(0, 0, 0, 0)
const yesterday = new Date(today)
yesterday.setDate(yesterday.getDate() - 1)

let missed = 0
let done = 0
const from = parseDay(TRACK_FROM)
for (let d = new Date(from); d <= yesterday && d <= endDate; d.setDate(d.getDate() + 1)) {
  if (!DAYS.includes(d.getDay())) continue
  const k = key(d)
  if (autoDays.has(k) || manualDays.has(k) || RESTORED.includes(k)) done++
  else if (!SKIP_DATES.includes(k)) missed++
}

// today counts as done if already logged, but never as missed yet
const todayKey = key(today)
const todayIsScheduled = DAYS.includes(today.getDay())
const todayDone = autoDays.has(todayKey) || manualDays.has(todayKey)
if (todayDone) done++

const burnt = Math.round((missed + SEED_MISSED) * rate)

// --- next scheduled day ---
function nextDayLabel() {
  const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  for (let i = 1; i <= 7; i++) {
    const d = new Date(today)
    d.setDate(d.getDate() + i)
    if (d > endDate) return "done"
    if (DAYS.includes(d.getDay()) && !SKIP_DATES.includes(key(d))) return names[d.getDay()]
  }
  return "done"
}

// --- status line ---
let status, accent
if (todayIsScheduled && !todayDone) {
  status = "you owe today"
  accent = new Color("#E5484D")
} else if (todayIsScheduled && todayDone) {
  status = "logged today"
  accent = new Color("#30A46C")
} else {
  status = "next " + nextDayLabel().toLowerCase()
  accent = new Color("#8B8B8B")
}

// --- widget ---
const family = config.widgetFamily || "small"
const rupees = "\u20B9" + burnt.toLocaleString("en-IN")

let w

if (family === "accessoryRectangular") {
  // Lock screen. iOS renders this monochrome, so no colour.
  w = new ListWidget()
  w.addAccessoryWidgetBackground = true

  const amount = w.addText(rupees)
  amount.font = Font.boldSystemFont(22)

  const sub = w.addText(burnt > 0 ? "money lost" : "nothing lost yet")
  sub.font = Font.mediumSystemFont(12)

  const line = w.addText(
    done + " went \u00B7 " + (missed + SEED_MISSED) + " missed"
  )
  line.font = Font.systemFont(11)

} else if (family === "accessoryInline") {
  w = new ListWidget()
  w.addText(rupees + " lost")

} else if (family === "accessoryCircular") {
  w = new ListWidget()
  w.addAccessoryWidgetBackground = true
  const a = w.addText(rupees)
  a.font = Font.boldSystemFont(14)
  a.minimumScaleFactor = 0.5
  const b = w.addText("lost")
  b.font = Font.systemFont(9)

} else {
  // Homescreen
  w = new ListWidget()
  w.backgroundColor = new Color("#000000")
  w.setPadding(16, 16, 16, 16)

  w.addSpacer()

  const amount = w.addText(rupees)
  amount.font = Font.blackSystemFont(46)
  amount.textColor = new Color("#FFFFFF")
  amount.minimumScaleFactor = 0.4
  amount.lineLimit = 1

  const sub = w.addText(burnt > 0 ? "gone" : "still intact")
  sub.font = Font.mediumSystemFont(13)
  sub.textColor = new Color("#737373")

  w.addSpacer()

  const detail = w.addText(done + " went, " + (missed + SEED_MISSED) + " missed")
  detail.font = Font.mediumSystemFont(12)
  detail.textColor = new Color("#737373")

  const st = w.addText(status)
  st.font = Font.mediumSystemFont(12)
  st.textColor = new Color("#737373")
}

w.refreshAfterDate = new Date(Date.now() + 30 * 60 * 1000)

if (config.runsInWidget) {
  Script.setWidget(w)
} else if (family === "accessoryRectangular") {
  w.presentSmall()
} else {
  w.presentSmall()
}
Script.complete()
