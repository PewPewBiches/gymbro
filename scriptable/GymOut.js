// GymOut
// Add to a Shortcuts automation with: Scriptable > Run Script > GymOut
// Turn on "Run in App". Nothing to type, nothing to configure.

const EVENT = "OUT"

const fm = FileManager.iCloud()
const path = fm.joinPath(fm.documentsDirectory(), "gym_log.txt")

const pad = n => String(n).padStart(2, "0")
const d = new Date()
const stamp =
  d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) +
  " " + pad(d.getHours()) + ":" + pad(d.getMinutes())

let existing = ""
if (fm.fileExists(path)) {
  if (!fm.isFileDownloaded(path)) await fm.downloadFileFromiCloud(path)
  existing = fm.readString(path)
}

fm.writeString(path, existing + EVENT + "," + stamp + "\n")

Script.setShortcutOutput(EVENT + " " + stamp)
Script.complete()
