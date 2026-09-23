// Hour logic, liturgical colours, and text rendering for the Divinum Officium
// plugin. Pure functions with no shell access, testable with plain node.

// The eight canonical hours, in the order the breviary prays them.
var HOURS = [
  { key: "Matutinum", latin: "Matutinum", english: "Matins", abbrev: "Mat" },
  { key: "Laudes", latin: "Laudes", english: "Lauds", abbrev: "Laud" },
  { key: "Prima", latin: "Prima", english: "Prime", abbrev: "Prim" },
  { key: "Tertia", latin: "Tertia", english: "Terce", abbrev: "Ter" },
  { key: "Sexta", latin: "Sexta", english: "Sext", abbrev: "Sext" },
  { key: "Nona", latin: "Nona", english: "None", abbrev: "Non" },
  { key: "Vesperae", latin: "Vesperae", english: "Vespers", abbrev: "Vesp" },
  { key: "Completorium", latin: "Completorium", english: "Compline", abbrev: "Compl" }
]

// The hours are prayed at roughly the times their names say: Lauds at dawn,
// Prime after sunrise, Terce/Sext/None at the third, sixth and ninth hour,
// Vespers in the evening, Compline before bed. Matins owns the night, so it
// takes everything from midnight until Lauds.
var DEFAULT_SCHEDULE = "00:00,06:00,07:30,09:00,12:00,15:00,18:00,21:00"

// Every rubrical edition and language the office server knows, as published in
// the server's own horas.dialog. Values are what Pofficium.pl expects.
var VERSIONS = [  "Rubrics 1960 - 1960",
  "Rubrics 1960 - 2020 USA",
  "Reduced - 1955",
  "Divino Afflatu - 1954",
  "Divino Afflatu - 1939",
  "Tridentine - 1906",
  "Tridentine - 1888",
  "Tridentine - 1570",
  "Monastic - 1963",
  "Monastic - 1963 - Barroux",
  "Monastic Divino 1930",
  "Monastic Tridentinum 1617",
  "Monastic Tridentinum Cisterciensis 1951",
  "Monastic Tridentinum Cisterciensis Altovadensis",
  "Ordo Praedicatorum - 1962"
]

var LANGUAGES = [
  { value: "Latin", label: "Latin" },
  { value: "English", label: "English" },
  { value: "Deutsch", label: "Deutsch" },
  { value: "Francais", label: "Français" },
  { value: "Italiano", label: "Italiano" },
  { value: "Espanol", label: "Español" },
  { value: "Portugues", label: "Português" },
  { value: "Polski", label: "Polski" },
  { value: "Magyar", label: "Magyar" },
  { value: "Magyar-Kaldi", label: "Magyar (Káldi)" },
  { value: "Nederlands", label: "Nederlands" },
  { value: "Dansk", label: "Dansk" },
  { value: "Bohemice", label: "Čeština" },
  { value: "Cesky-Schaller", label: "Čeština (Schaller)" },
  { value: "Vietnamice", label: "Tiếng Việt" },
  { value: "Hebrew", label: "עברית" },
  { value: "Latin-Bea", label: "Latin (Pius XII psalter)" },
  { value: "Latin-gabc", label: "Latin (gabc)" },
  { value: "Polski-Newer", label: "Polski (newer)" }
]

// The two books the server renders: the breviary's hours and the missal's
// Mass. Both come back as the same table, so the reader draws them alike.
var RITES = [
  { value: "office", label: "Officium" },
  { value: "mass", label: "Missa" }
]

// How much of the Mass to read: the propers that change with the day, or the
// propers inside the Ordinary, which is what the website shows by default.
var MASS_FORMS = [
  { value: "Propers", label: "Propers" },
  { value: "Full", label: "Full Mass" }
]

// Votive and communal Masses from the missal's own votives list, values are the
// codes missa.pl takes. "Hodie" is the Mass of the day.
var VOTIVES = [
  { value: "Hodie", label: "Mass of the day" },
  { value: "C9", label: "Requiem (Defunctorum)" },
  { value: "C11", label: "Beatae Mariae Virginis" },
  { value: "C2", label: "Unius Martyris Pontificis (Statuit)" },
  { value: "C4", label: "Confessoris Pontificis (Statuit)" },
  { value: "C5", label: "Confessoris non Pontificis (Os justi)" },
  { value: "C6", label: "Unius Virginis Martyris (Loquebar)" },
  { value: "C8", label: "Dedicationis Ecclesiae (Terribilis)" },
  { value: "V4", label: "De S. Joseph Sponso (Feria IV)" },
  { value: "V6", label: "De Passione DNJC (Feria VI)" },
  { value: "Coronatio", label: "Pro Papa" },
  { value: "Propaganda", label: "Pro Propagatione Fidei" }
]

// Divinum Officium names the colour of the day in the page it serves. Its
// "black" is the Roman white/ferial class (the server omits the colour
// attribute entirely for it) and its "grey" is a real black, used for
// requiems, so the two are not what their names suggest.
var COLORS = {
  black: { name: "White", hex: "#e9e6df", outline: true },
  white: { name: "White", hex: "#e9e6df", outline: true },
  red: { name: "Red", hex: "#c4483c", outline: false },
  green: { name: "Green", hex: "#5c9a52", outline: false },
  purple: { name: "Violet", hex: "#8a6bbf", outline: false },
  blue: { name: "Marian Blue", hex: "#5c85c4", outline: false },
  grey: { name: "Black", hex: "#3a3a3f", outline: true },
  gold: { name: "Gold", hex: "#c9a227", outline: false }
}

// ---------------------------------------------------------------------------
// schedule
// ---------------------------------------------------------------------------

function parseSchedule(text) {
  var parts = String(text === undefined || text === null ? "" : text).split(",")
  var minutes = []
  for (var i = 0; i < parts.length; i++) {
    var match = /^\s*(\d{1,2}):(\d{2})\s*$/.exec(parts[i])
    if (!match) return parseSchedule(DEFAULT_SCHEDULE)
    var hours = parseInt(match[1], 10)
    var mins = parseInt(match[2], 10)
    if (hours > 23 || mins > 59 || (minutes.length > 0 && hours * 60 + mins <= minutes[minutes.length - 1]))
      return parseSchedule(DEFAULT_SCHEDULE)
    minutes.push(hours * 60 + mins)
  }
  if (minutes.length !== HOURS.length) return parseSchedule(DEFAULT_SCHEDULE)
  if (minutes[0] !== 0) return parseSchedule(DEFAULT_SCHEDULE)
  return minutes
}

function hourIndexForMinutes(schedule, minutes) {
  var index = 0
  for (var i = 0; i < schedule.length; i++) {
    if (minutes >= schedule[i]) index = i
  }
  return index
}

function hourForMinutes(schedule, minutes) {
  return HOURS[hourIndexForMinutes(schedule, minutes)]
}

// Minutes until the next hour begins. After Compline the next hour is Matins,
// which starts at midnight the following day.
function minutesToNextHour(schedule, minutes) {
  var index = hourIndexForMinutes(schedule, minutes)
  var next = index + 1 < schedule.length ? schedule[index + 1] : schedule[0] + 1440
  return next - minutes
}

function nextHourForMinutes(schedule, minutes) {
  return HOURS[(hourIndexForMinutes(schedule, minutes) + 1) % HOURS.length]
}

function formatDuration(minutes) {
  var total = Math.max(0, Math.round(minutes))
  var hours = Math.floor(total / 60)
  var rest = total % 60
  if (hours === 0) return rest + "m"
  if (rest === 0) return hours + "h"
  return hours + "h " + rest + "m"
}

function hourIndex(key) {
  for (var i = 0; i < HOURS.length; i++) {
    if (HOURS[i].key === key) return i
  }
  return -1
}

function hourLabel(key, language) {
  var index = hourIndex(key)
  if (index < 0) return String(key === undefined || key === null ? "" : key)
  return language === "english" ? HOURS[index].english : HOURS[index].latin
}

// ---------------------------------------------------------------------------
// dates
// ---------------------------------------------------------------------------

function pad2(value) {
  return value < 10 ? "0" + value : String(value)
}

function dateKey(date) {
  return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function parseDateKey(key) {
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key === undefined ? "" : key))
  if (!match) return new Date()
  return new Date(parseInt(match[1], 10), parseInt(match[2], 10) - 1, parseInt(match[3], 10))
}

function shiftDateKey(key, days) {
  var date = parseDateKey(key)
  date.setDate(date.getDate() + days)
  return dateKey(date)
}

function isToday(key) {
  return key === dateKey(new Date())
}

// English day names, deliberately not the system locale: the office itself is
// being read in a fixed language and the site's own labels are English.
var DAY_NAMES = [
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
]
var MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"
]

function longDate(key) {
  var date = parseDateKey(key)
  return DAY_NAMES[date.getDay()] + ", " + date.getDate() + " " + MONTH_NAMES[date.getMonth()] + " " + date.getFullYear()
}

function shortDate(key) {
  var date = parseDateKey(key)
  return date.getDate() + " " + MONTH_NAMES[date.getMonth()].slice(0, 3) + " " + date.getFullYear()
}

// ---------------------------------------------------------------------------
// liturgical colour
// ---------------------------------------------------------------------------

function colorSpec(key) {
  var spec = COLORS[String(key === undefined || key === null ? "" : key).toLowerCase()]
  return spec === undefined ? COLORS.black : spec
}

// ---------------------------------------------------------------------------
// office text
// ---------------------------------------------------------------------------

function escapeHtml(text) {
  return String(text === undefined || text === null ? "" : text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}

// One RichText string per column keeps psalm-length offices to a couple of
// Text items per section instead of one per line.
function richText(lines, palette) {
  if (!lines || lines.length === 0) return ""
  var parts = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var kind = line.k
    if (kind === "rubric") {
      var marker = escapeHtml(line.marker)
      var rest = escapeHtml(line.text)
      parts.push('<font color="' + palette.rubric + '">' + marker + "</font>" + (rest === "" ? "" : " " + rest))
    } else if (kind === "verse") {
      if (palette.hideVerseNumbers === true) parts.push(escapeHtml(line.text))
      else parts.push('<font color="' + palette.verse + '">' + escapeHtml(line.marker) + "</font> " + escapeHtml(line.text))
    } else if (kind === "title") {
      var after = line.after === undefined || line.after === "" ? "" : ' <font color="' + palette.verse + '">' + escapeHtml(line.after) + "</font>"
      parts.push("<b>" + escapeHtml(line.text) + "</b>" + after)
    } else {
      parts.push(escapeHtml(line.text))
    }
  }
  return parts.join("<br/>")
}

function sectionLabel(section) {
  if (!section || !section.columns) return ""
  for (var i = 0; i < section.columns.length; i++) {
    var label = String(section.columns[i].label === undefined ? "" : section.columns[i].label)
    if (label !== "") return label
  }
  return ""
}

function sectionNote(section) {
  if (!section || !section.columns) return ""
  for (var i = 0; i < section.columns.length; i++) {
    var note = String(section.columns[i].note === undefined ? "" : section.columns[i].note)
    if (note !== "") return note
  }
  return ""
}

function lineCount(section) {
  if (!section || !section.columns || section.columns.length === 0) return 0
  return section.columns[0].lines ? section.columns[0].lines.length : 0
}

function parseOffice(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  if (text === "") return null
  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (error) {
    return { ok: false, error: "could not read the office helper output" }
  }
  if (!parsed || typeof parsed !== "object") return null
  if (parsed.ok === true && !parsed.sections) return null
  return parsed
}

function elide(text, limit) {
  var value = String(text === undefined || text === null ? "" : text)
  var max = limit === undefined ? 120 : limit
  if (value.length <= max) return value
  return value.slice(0, Math.max(0, max - 1)) + "…"
}

// The argv for the helper, kept here so the shell wiring and the tests agree on
// one command shape. The office asks for an hour; the Mass asks for a votive
// form and whether to leave the Ordinary out.
function riteCommand(helperPath, options) {
  var rite = options.rite === "mass" ? "mass" : "office"
  var args = [
    "python3", helperPath, rite,
    "--date", String(options.date),
    "--base-url", String(options.baseUrl),
    "--version", String(options.version),
    "--lang1", String(options.lang1),
    "--lang2", String(options.lang2),
    "--ttl", String(options.ttl)
  ]
  if (rite === "mass") {
    args.push("--votive", String(options.votive ? options.votive : "Hodie"))
    if (options.propersOnly === true) args.push("--propers")
  } else {
    args.push("--hour", String(options.hour))
  }
  if (options.refresh === true) args.push("--refresh")
  return args
}

if (typeof module !== "undefined") {
  module.exports = {
    HOURS: HOURS,
    VERSIONS: VERSIONS,
    LANGUAGES: LANGUAGES,
    RITES: RITES,
    MASS_FORMS: MASS_FORMS,
    VOTIVES: VOTIVES,
    COLORS: COLORS,
    DEFAULT_SCHEDULE: DEFAULT_SCHEDULE,
    parseSchedule: parseSchedule,
    hourIndexForMinutes: hourIndexForMinutes,
    hourForMinutes: hourForMinutes,
    minutesToNextHour: minutesToNextHour,
    nextHourForMinutes: nextHourForMinutes,
    formatDuration: formatDuration,
    hourIndex: hourIndex,
    hourLabel: hourLabel,
    dateKey: dateKey,
    parseDateKey: parseDateKey,
    shiftDateKey: shiftDateKey,
    isToday: isToday,
    longDate: longDate,
    shortDate: shortDate,
    colorSpec: colorSpec,
    escapeHtml: escapeHtml,
    richText: richText,
    sectionLabel: sectionLabel,
    sectionNote: sectionNote,
    lineCount: lineCount,
    parseOffice: parseOffice,
    elide: elide,
    riteCommand: riteCommand
  }
}
