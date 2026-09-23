import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar label for the Divine Office: the canonical hour being prayed now, with
// the liturgical colour of the day beside it.
//
// The popup lives in Panel.qml and is loaded here the same way the built-in
// clock loads its calendar: this widget owns the bar slot, the panel owns the
// UI and the fetching. The panel is loaded eagerly (though hidden) so the bar
// can show the colour of the day without the user opening anything.
BarWidget {
  id: root
  moduleName: "io.github.ofrades.divinum-officium"

  readonly property var panelItem: panelLoader.item
  readonly property string hourKey: panelItem ? panelItem.hour : ""
  readonly property string dayTitle: panelItem ? panelItem.dayTitle : ""
  readonly property string colorKey: panelItem ? panelItem.colorKey : ""
  readonly property bool hasOffice: dayTitle !== ""
  readonly property var colour: Model.colorSpec(colorKey)
  readonly property var settingsHour: panelItem ? panelItem.hourLabel : ""

  // Latin is the breviary's own language, so the bar keeps the hour's Latin
  // name even when the panel is set to read in translation.
  readonly property string displayText: settingsHour !== "" ? settingsHour : "Officium"
  readonly property string shortText: {
    var index = Model.hourIndex(hourKey)
    return index < 0 ? "—" : Model.HOURS[index].abbrev
  }
  readonly property bool showDot: String(setting("showColourDot", "On")) !== "Off"

  readonly property string tooltipText: hasOffice
    ? (dayTitle + "\n" + displayText + " · " + colour.name + "\nRight-click to refresh")
    : "Divinum Officium"

  function refresh() {
    if (panelItem && panelItem.refresh) panelItem.refresh(true)
  }

  // ---- Popup. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function stepHour(delta) {
    if (panelLoader.item) panelLoader.item.stepHour(delta)
  }

  function stepDay(delta) {
    if (panelLoader.item) panelLoader.item.stepDay(delta)
  }

  function goNow() {
    if (panelLoader.item) panelLoader.item.goNow()
  }

  // The day occupies more slot than it paints a mark for, so the bar's
  // open-panel dot takes the width of the label instead of the whole slot.
  readonly property real openPanelIndicatorWidth: root.vertical ? 0 : contentRow.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.ofrades.divinum-officium"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function next(): void { root.stepHour(1) }
    function previous(): void { root.stepHour(-1) }
    function today(): void { root.goNow() }
    function nextDay(): void { root.stepDay(1) }
    function previousDay(): void { root.stepDay(-1) }
    function rite(name: string): void {
      if (panelLoader.item) panelLoader.item.setRite(name)
    }
    function mass(): void {
      if (panelLoader.item) panelLoader.item.showMass()
    }
    function office(): void {
      if (panelLoader.item) panelLoader.item.showOffice()
    }
    function votive(code: string): void {
      if (panelLoader.item) panelLoader.item.setVotive(code)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical
      ? root.barSize
      : contentRow.implicitWidth + Math.round(button.scaledHorizontalMargin * 2)
    fixedHeight: root.vertical
      ? contentColumn.implicitHeight + Math.round(button.scaledVerticalPadding * 2)
      : -1
    tooltipText: root.tooltipText

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) root.goNow()
      else root.togglePanel()
    }

    Row {
      id: contentRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(5)

      Rectangle {
        id: dot
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showDot
        width: Style.space(7)
        height: width
        radius: width / 2
        color: root.colour.hex
        opacity: root.hasOffice ? 1.0 : 0.35
        border.width: root.colour.outline || !root.hasOffice ? 1 : 0
        border.color: Util.alpha(button.foreground, 0.45)

        Behavior on opacity {
          NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
      }

      Text {
        id: contentText
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.displayText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }
    }

    Column {
      id: contentColumn
      visible: root.vertical
      anchors.centerIn: parent
      spacing: Style.space(2)

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.showDot
        width: Style.space(7)
        height: width
        radius: width / 2
        color: root.colour.hex
        opacity: root.hasOffice ? 1.0 : 0.35
        border.width: root.colour.outline || !root.hasOffice ? 1 : 0
        border.color: Util.alpha(button.foreground, 0.45)
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: root.shortText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }
    }
  }
}
