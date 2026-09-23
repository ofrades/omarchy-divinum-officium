import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The Divine Office reader: the canonical hour, the liturgical day, and the
// text of the office itself, in one or two languages.
//
// BarWidget.qml owns the bar slot and hands this panel the button to anchor
// against and the settings from shell.json. The fetching lives in
// divinum_officium.py — it speaks HTML to a Divinum Officium server, parses the
// office table, and caches the result, so this file is only layout and wiring.
Panel {
  id: root
  moduleName: "io.github.ofrades.divinum-officium"
  ipcTarget: "io.github.ofrades.divinum-officium"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string helperPath: String(Qt.resolvedUrl("divinum_officium.py")).replace("file://", "")

  // ---- settings, straight out of the widget's shell.json entry
  readonly property string sourceUrl: {
    var value = String(setting("sourceUrl", "https://divinumofficium.hu")).trim()
    return value === "" ? "https://divinumofficium.hu" : value
  }
  readonly property string versionText: String(setting("version", "Rubrics 1960 - 1960"))
  readonly property string language: String(setting("language", "Latin"))
  readonly property string language2Raw: String(setting("language2", "English"))
  // The server prints one column when both languages match, so "None" is just
  // that same request — the parser handles either shape.
  readonly property string language2: (language2Raw === "None" || language2Raw === language) ? "" : language2Raw
  // A Divinum Officium API of one's own — e.g. the stack in the project's own
  // repository, running the engine in a Cloudflare Container behind Access.
  // When set, it replaces the public mirror and needs no crawl delay.
  readonly property string apiUrl: String(setting("apiUrl", "")).trim()
  readonly property string apiClientId: String(setting("apiServiceTokenId", "")).trim()
  readonly property string apiClientSecret: String(setting("apiServiceTokenSecret", ""))
  readonly property string effectiveBaseUrl: apiUrl !== "" ? apiUrl : sourceUrl
  readonly property string hideVerseNumbers: String(setting("hideVerseNumbers", "Off")) === "On"
  readonly property int refreshIntervalSec: numberSetting("refreshIntervalSec", 900, 60, 86400)
  readonly property int cacheTtlSec: numberSetting("cacheTtlMinutes", 360, 0, 10080) * 60
  readonly property var schedule: Model.parseSchedule(setting("hourSchedule", Model.DEFAULT_SCHEDULE))

  // Which book is open: the breviary's hours or the missal's Mass.
  readonly property string riteRaw: String(setting("rite", "Officium"))
  readonly property bool isMass: riteRaw === "Missa"
  readonly property string massFormRaw: String(setting("massForm", "Propers"))
  readonly property bool propersOnly: massFormRaw !== "Full"
  readonly property string massVotive: String(setting("massVotive", "Hodie"))
  readonly property string votiveLabel: {
    for (var i = 0; i < Model.VOTIVES.length; i++) {
      if (Model.VOTIVES[i].value === root.massVotive) return Model.VOTIVES[i].label
    }
    return root.massVotive
  }

  // ---- state
  property string dateKey: Model.dateKey(new Date())
  property int nowMinutes: 0
  // Empty means follow the clock; set means the reader pinned an hour.
  property string pinnedHour: ""
  readonly property string clockHour: Model.hourForMinutes(schedule, nowMinutes).key
  readonly property string hour: pinnedHour !== "" ? pinnedHour : clockHour
  readonly property string hourLabel: Model.hourLabel(hour, "latin")
  property var office: null
  property bool loading: false
  property string fetchError: ""
  property bool stale: false
  property var collapsed: ({})
  property bool pendingRefresh: false
  property bool pendingForce: false

  // The day's Mass is fetched whatever book the panel is reading, because the
  // bar names it: "what Mass is today?" should not need the panel opened.
  property var massPayload: null
  property bool massPending: false
  property bool massPendingForce: false
  property string massLoadedKey: ""
  readonly property string massRequestKey: Model.massKey({
    baseUrl: root.effectiveBaseUrl,
    version: root.versionText,
    lang1: root.language,
    lang2: root.language2 === "" ? root.language : root.language2,
    date: root.dateKey,
    votive: root.massVotive,
    propers: true
  })
  readonly property string massTitle: massPayload && massPayload.title ? String(massPayload.title) : ""
  readonly property string massColourKey: massPayload && massPayload.colorKey ? String(massPayload.colorKey) : ""

  readonly property string dayTitle: office && office.title ? String(office.title) : ""
  readonly property string colorKey: office && office.colorKey ? String(office.colorKey) : ""
  readonly property var colour: Model.colorSpec(colorKey)
  readonly property string commemorations: office && office.commemorations
    ? office.commemorations.join(" · ") : ""
  readonly property var sections: office && office.sections ? office.sections : []
  readonly property string hostLabel: hostOf(effectiveBaseUrl)
  readonly property bool isToday: Model.isToday(dateKey)
  readonly property bool followsClock: pinnedHour === ""

  function numberSetting(name, fallback, min, max) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    if (value < min) value = min
    if (value > max) value = max
    return value
  }

  function hostOf(url) {
    var match = /^[a-z]+:\/\/([^/]+)/i.exec(String(url))
    return match ? match[1] : String(url)
  }

  function updateNow() {
    var now = new Date()
    var previousHour = root.clockHour
    var previousDate = root.dateKey
    root.nowMinutes = now.getHours() * 60 + now.getMinutes()
    if (!root.followsClock) return
    // Midnight rolls the office over to the new day; an hour boundary rolls the
    // unlocked reader to the next hour. A pinned hour holds its ground, and a
    // tick that changes nothing does not refetch.
    var today = Model.dateKey(now)
    if (root.dateKey !== today) root.dateKey = today
    if (root.clockHour !== previousHour || root.dateKey !== previousDate) root.refresh(false)
  }

  // Debounced so clicking through the hours does not launch one request per
  // click — the mirror is a volunteer service and its robots.txt asks for ten
  // seconds between requests. An explicit refresh skips the wait.
  function refresh(force) {
    if (force === true) {
      startFetch(true)
      startMassFetch(true)
      return
    }
    refreshDebounce.restart()
  }

  function startFetch(force) {
    if (officeProcess.running) {
      root.pendingRefresh = true
      if (force === true) root.pendingForce = true
      return
    }
    root.loading = true
    root.fetchError = ""
    officeProcess.command = Model.riteCommand(root.helperPath, {
      rite: root.isMass ? "mass" : "office",
      date: root.dateKey,
      hour: root.hour,
      votive: root.massVotive,
      propersOnly: root.propersOnly,
      baseUrl: root.effectiveBaseUrl,
      apiUrl: root.apiUrl,
      apiClientId: root.apiClientId,
      apiClientSecret: root.apiClientSecret,
      version: root.versionText,
      lang1: root.language,
      lang2: root.language2 === "" ? root.language : root.language2,
      ttl: root.cacheTtlSec,
      refresh: force === true
    })
    officeProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseOffice(raw)
    if (!parsed || parsed.ok !== true) {
      var message = parsed && parsed.error ? parsed.error : ""
      if (message === "") message = "Could not read the office"
      root.fetchError = Model.elide(message, 200)
      root.loading = false
      return
    }
    root.office = parsed
    root.stale = parsed.stale === true
    root.fetchError = parsed.error ? Model.elide(String(parsed.error), 200) : ""
    root.loading = false
    // A propers Mass read in the panel is the same text the bar wants, so it
    // doubles as the day's Mass instead of asking the server twice.
    if (parsed.rite === "mass" && parsed.propers === true) {
      root.massPayload = parsed
      root.massLoadedKey = Model.massKey(parsed)
    }
  }

  function applyMassStatus(raw) {
    var parsed = Model.parseOffice(raw)
    if (!parsed || parsed.ok !== true) return
    root.massPayload = parsed
    root.massLoadedKey = Model.massKey(parsed)
  }

  // Kept out of the panel's own fetch so switching books never blanks the bar's
  // Mass, and so a votive chosen months ago does not ride along silently.
  function refreshMass() {
    massDebounce.restart()
  }

  function startMassFetch(force) {
    if (force !== true && root.massLoadedKey !== "" && root.massLoadedKey === root.massRequestKey) return
    if (massProcess.running) {
      root.massPending = true
      if (force === true) root.massPendingForce = true
      return
    }
    massProcess.command = Model.riteCommand(root.helperPath, {
      rite: "mass",
      date: root.dateKey,
      votive: root.massVotive,
      propersOnly: true,
      baseUrl: root.effectiveBaseUrl,
      apiUrl: root.apiUrl,
      apiClientId: root.apiClientId,
      apiClientSecret: root.apiClientSecret,
      version: root.versionText,
      lang1: root.language,
      lang2: root.language2 === "" ? root.language : root.language2,
      ttl: root.cacheTtlSec,
      refresh: force === true
    })
    massProcess.running = true
  }

  // Changing a setting from the panel writes it back to shell.json, the same
  // way the clock's format cycling does, so the choice survives a restart.
  function applySetting(name, value) {
    var entry = { id: root.moduleName }
    var current = root.settings ? root.settings : ({})
    for (var key in current) {
      if (key !== "id") entry[key] = current[key]
    }
    entry[name] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    root.refresh(false)
  }

  function selectHour(key) {
    root.pinnedHour = key === root.clockHour ? "" : key
    root.refresh(false)
  }

  // Stepping past Compline lands on Matins of the next day, and stepping back
  // from Matins lands on Compline of the previous one — the breviary's own
  // circular day.
  function stepHour(delta) {
    var index = Model.hourIndex(root.hour)
    var next = index + delta
    var date = root.dateKey
    if (next < 0) {
      next = Model.HOURS.length - 1
      date = Model.shiftDateKey(date, -1)
    } else if (next >= Model.HOURS.length) {
      next = 0
      date = Model.shiftDateKey(date, 1)
    }
    root.dateKey = date
    root.pinnedHour = Model.HOURS[next].key
    root.refresh(false)
  }

  function stepDay(delta) {
    root.dateKey = Model.shiftDateKey(root.dateKey, delta)
    root.refresh(false)
  }

  function goNow() {
    root.pinnedHour = ""
    root.dateKey = Model.dateKey(new Date())
    root.updateNow()
    root.refresh(false)
  }

  function isCollapsed(index) {
    return root.collapsed[index] === true
  }

  function toggleSection(index) {
    var next = ({})
    for (var key in root.collapsed) next[key] = root.collapsed[key]
    if (next[index] === true) delete next[index]
    else next[index] = true
    root.collapsed = next
  }

  function setAllCollapsed(value) {
    var next = ({})
    if (value === true) {
      for (var i = 0; i < root.sections.length; i++) next[i] = true
    }
    root.collapsed = next
  }

  readonly property string coverageText: {
    var text = root.isMass
      ? (root.propersOnly ? "Propers" : "Full Mass") + " · " + root.votiveLabel
      : Model.hourLabel(root.hour, "latin")
    if (root.language2 !== "") text += " · " + root.language + " + " + root.language2
    else text += " · " + root.language
    return text
  }

  // The dropdowns and pills below refetch when they change something, but the
  // same settings can also arrive from the plugins settings UI or a hand edit
  // of shell.json. Watch the request itself so every path ends in fresh text.
  readonly property string requestSignature: [
    root.effectiveBaseUrl,
    root.apiClientId,
    root.apiClientSecret,
    root.versionText,
    root.language,
    root.language2,
    root.riteRaw,
    root.massFormRaw,
    root.massVotive
  ].join("|")

  onRequestSignatureChanged: root.refresh(false)

  // The bar names the day's Mass, so the Mass follows the date and the settings
  // the same way the office does — but on its own process, so switching books
  // never blanks it.
  onMassRequestKeyChanged: root.refreshMass()

  function setRite(name) {
    var wanted = String(name).toLowerCase()
    var value = wanted === "mass" || wanted === "missa" ? "Missa" : "Officium"
    if (value !== root.riteRaw) root.applySetting("rite", value)
  }

  function showMass() {
    setRite("mass")
    root.open()
  }

  function showOffice() {
    setRite("office")
    root.open()
  }

  // Any code from the missal's votives list, for keybindings that always want
  // the same votive Mass, e.g. votive C9 for a Requiem.
  function setVotive(code) {
    var value = String(code)
    if (value !== "" && value !== root.massVotive) root.applySetting("massVotive", value)
  }

  onOpenedChanged: if (opened) {
    if (panelFlick) panelFlick.contentY = 0
    if (root.office === null) root.refresh(false)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  SystemClock {
    id: wallClock
    precision: SystemClock.Minutes
    onDateChanged: root.updateNow()
  }

  Component.onCompleted: {
    root.updateNow()
    root.refresh(false)
    root.refreshMass()
  }

  Timer {
    id: refreshDebounce
    interval: 350
    repeat: false
    onTriggered: root.startFetch(false)
  }

  Timer {
    id: massDebounce
    interval: 600
    repeat: false
    onTriggered: root.startMassFetch(false)
  }

  Process {
    id: massProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: massStdout
      waitForEnd: true
      onStreamFinished: root.applyMassStatus(text)
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (root.massPending) {
        var force = root.massPendingForce
        root.massPending = false
        root.massPendingForce = false
        root.startMassFetch(force)
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: root.refresh(false)
  }

  Process {
    id: officeProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: officeStdout
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    stderr: StdioCollector {
      id: officeStderr
      waitForEnd: true
      onStreamFinished: {
        if (officeStderr.text) root.fetchError = Model.elide(String(officeStderr.text).trim(), 200)
      }
    }
    onExited: function(exitCode) {
      root.loading = false
      if (root.pendingRefresh) {
        var force = root.pendingForce
        root.pendingRefresh = false
        root.pendingForce = false
        root.startFetch(force)
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(760))
    contentHeight: panel.fittedContentHeight(bodyColumn.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: versionDropdown.popupOpen || languageDropdown.popupOpen || language2Dropdown.popupOpen || votiveDropdown.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // j/k walk the hours, h/l walk the days — the axis the panel is ordered
      // along, not the axis a scrollbar moves. The Mass has no hours to walk,
      // so there only the days move.
      onMoveRequested: function(dx, dy) {
        if (dy !== 0 && !root.isMass) root.stepHour(dy)
        else if (dx !== 0) root.stepDay(dx)
      }
      onReturnRequested: if (!root.isMass) root.stepHour(1)
      onTextKey: function(t) {
        var key = String(t).toLowerCase()
        if (key === "r") root.refresh(true)
        else if (key === "t") root.goNow()
        else if (key === "[" || key === "]") root.stepDay(key === "[" ? -1 : 1)
        else if (key === "c") root.setAllCollapsed(true)
        else if (key === "e") root.setAllCollapsed(false)
        else if (key === "o") root.setRite("office")
        else if (key === "m") root.setRite("mass")
        else if (!root.isMass && key >= "1" && key <= "8") root.selectHour(Model.HOURS[parseInt(key, 10) - 1].key)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: bodyColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: bodyColumn
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.isMass ? "Sancta Missa" : root.hourLabel
            meta: Model.longDate(root.dateKey) + (root.isToday ? " · Today" : "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.office ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "\u2719"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              Row {
                spacing: Style.space(6)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(9)
                  height: width
                  radius: width / 2
                  color: root.colour.hex
                  visible: root.office !== null
                  border.width: root.colour.outline ? 1 : 0
                  border.color: Util.alpha(root.foreground, 0.45)
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.office !== null ? root.colour.name : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }
          }

          // ---- which book: the breviary's hours, or the missal's Mass.
          RowLayout {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: Model.RITES

              delegate: Button {
                required property var modelData

                text: modelData.label
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                active: (modelData.value === "mass") === root.isMass
                Layout.fillWidth: true
                Layout.preferredWidth: 120
                onClicked: root.setRite(modelData.value)
              }
            }
          }

          // ---- the eight hours. The active one is filled; the hour the clock
          //      is pointing at carries a dot so "now" stays visible even while
          //      another hour is being read.
          RowLayout {
            width: parent.width
            spacing: Style.space(4)
            visible: !root.isMass

            Repeater {
              model: Model.HOURS

              delegate: Button {
                required property var modelData

                text: modelData.latin
                tooltipText: modelData.english + (modelData.key === root.clockHour ? " · now" : "")
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                active: root.hour === modelData.key
                iconText: modelData.key === root.clockHour ? "\u2022" : ""
                iconSize: Style.font.caption
                Layout.fillWidth: true
                Layout.preferredWidth: 60
                onClicked: root.selectHour(modelData.key)
              }
            }
          }

          // ---- the Mass: how much of it, and which one.
          RowLayout {
            width: parent.width
            spacing: Style.space(6)
            visible: root.isMass

            Repeater {
              model: Model.MASS_FORMS

              delegate: Button {
                required property var modelData

                text: modelData.label
                tooltipText: modelData.value === "Propers"
                  ? "The texts that change with the day"
                  : "The propers inside the Ordinary of the Mass"
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                active: (modelData.value === "Full") === !root.propersOnly
                Layout.preferredWidth: 130
                onClicked: root.applySetting("massForm", modelData.value)
              }
            }

            Dropdown {
              id: votiveDropdown
              label: "Mass"
              value: root.massVotive
              options: Model.VOTIVES
              foreground: root.foreground
              fontFamily: root.fontFamily
              Layout.fillWidth: true
              Layout.preferredWidth: 320
              onChanged: function(value) { root.applySetting("massVotive", value) }
            }
          }

          // ---- day and options
          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            Button {
              text: "\u2039"
              tooltipText: "Previous day"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.stepDay(-1)
            }

            Button {
              text: root.isToday ? "Today" : Model.shortDate(root.dateKey)
              tooltipText: "Back to today"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: root.isToday
              onClicked: root.goNow()
            }

            Button {
              text: "\u203a"
              tooltipText: "Next day"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.stepDay(1)
            }

            Item { Layout.fillWidth: true }

            Button {
              text: "Collapse"
              tooltipText: "Collapse every section (c)"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.setAllCollapsed(true)
            }

            Button {
              text: "Expand"
              tooltipText: "Expand every section (e)"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.setAllCollapsed(false)
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(10)

            Dropdown {
              id: versionDropdown
              label: "Rubrics"
              value: root.versionText
              options: Model.VERSIONS
              foreground: root.foreground
              fontFamily: root.fontFamily
              Layout.fillWidth: true
              Layout.preferredWidth: 300
              onChanged: function(value) { root.applySetting("version", value) }
            }

            Dropdown {
              id: languageDropdown
              label: "Text"
              value: root.language
              options: Model.LANGUAGES
              foreground: root.foreground
              fontFamily: root.fontFamily
              Layout.fillWidth: true
              Layout.preferredWidth: 200
              onChanged: function(value) { root.applySetting("language", value) }
            }

            Dropdown {
              id: language2Dropdown
              label: "Second column"
              value: root.language2 === "" ? "None" : root.language2
              options: [{ value: "None", label: "None (single column)" }].concat(Model.LANGUAGES)
              foreground: root.foreground
              fontFamily: root.fontFamily
              Layout.fillWidth: true
              Layout.preferredWidth: 200
              onChanged: function(value) { root.applySetting("language2", value) }
            }
          }

          // ---- the liturgical day itself
          Text {
            width: parent.width
            textFormat: Text.PlainText
            visible: root.dayTitle !== ""
            text: root.dayTitle
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            visible: root.commemorations !== ""
            text: root.commemorations
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            visible: root.fetchError !== "" || root.stale || (root.loading && root.office === null)
            text: root.fetchError !== "" ? root.fetchError
              : root.stale ? "Showing the saved office — " + root.hostLabel + " could not be reached"
              : "Loading the office…"
            color: root.fetchError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(14)

            Repeater {
              model: root.sections

              delegate: OfficeSection {
                required property var modelData
                required property int index

                width: bodyColumn.width
                section: modelData
                collapsed: root.isCollapsed(index)
                foreground: root.foreground
                dim: root.dim
                rubricColor: root.urgent
                verseColor: Qt.darker(root.foreground, 1.7)
                fontFamily: root.fontFamily
                hideVerseNumbers: root.hideVerseNumbers
                onToggled: root.toggleSection(index)
              }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.coverageText + " · " + root.hostLabel + " · " + root.versionText
            color: Qt.darker(root.foreground, 1.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "o/m book · j/k hour · h/l day · 1–8 pick an hour · t today · r refetch · c/e collapse · Esc close"
            color: Qt.darker(root.foreground, 1.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
