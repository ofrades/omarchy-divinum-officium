import QtQuick
import qs.Commons
import "Model.js" as Model

// One row of the office: a section label (Incipit, Hymnus, Psalmi, Capitulum,
// Oratio, ...) and the text beneath it, one column per language — the same
// shape as the table a Divinum Officium server prints.
//
// Sections are collapsible because Matins alone carries a dozen readings and
// three nocturnes of psalms; collapsing is what makes it navigable.
Item {
  id: root

  property var section: null
  property bool collapsed: false

  property color foreground: Color.foreground
  property color dim: Color.foreground
  property color rubricColor: Color.urgent
  property color verseColor: Color.muted
  property string fontFamily: Style.font.family
  property bool hideVerseNumbers: false

  signal toggled()

  readonly property var columns: section && section.columns ? section.columns : []
  readonly property string label: Model.sectionLabel(section)
  readonly property string note: Model.sectionNote(section)
  readonly property var palette: ({
    rubric: root.rubricColor,
    verse: root.verseColor,
    hideVerseNumbers: root.hideVerseNumbers
  })

  width: parent ? parent.width : 0
  height: content.implicitHeight

  function columnLabel(index) {
    if (index < 0 || index >= columns.length) return ""
    var label = String(columns[index].label === undefined ? "" : columns[index].label)
    return label === root.label ? "" : label
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(6)

    // ---- header. The whole strip is the collapse target, so the chevron
    //      itself does not have to be hit.
    Item {
      width: parent.width
      height: headerRow.implicitHeight
      visible: root.label !== "" || root.note !== ""

      Row {
        id: headerRow
        width: parent.width
        spacing: Style.space(6)

        Text {
          id: headerText
          textFormat: Text.PlainText
          text: root.label
          visible: root.label !== ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.0
        }

        Text {
          textFormat: Text.PlainText
          text: root.note
          visible: root.note !== ""
          width: Math.max(0, parent.width - headerText.width - headerChevron.width - parent.spacing * 2)
          color: Qt.darker(root.foreground, 1.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          anchors.top: headerText.top
        }

        Text {
          id: headerChevron
          textFormat: Text.PlainText
          text: root.collapsed ? "\u25b8" : "\u25be"
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
      }
    }

    // ---- text. Two languages sit side by side, as on the website; one
    //      language takes the full width.
    Row {
      id: columnsRow
      width: parent.width
      spacing: Style.space(18)
      visible: !root.collapsed

      Repeater {
        model: root.columns

        delegate: Column {
          required property var modelData
          required property int index

          readonly property string own: root.columnLabel(index)

          width: (columnsRow.width - (root.columns.length - 1) * columnsRow.spacing) / Math.max(1, root.columns.length)
          spacing: Style.space(4)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            visible: parent.own !== ""
            text: parent.own
            color: Qt.darker(root.foreground, 1.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.RichText
            text: Model.richText(modelData.lines, root.palette)
            color: root.foreground
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.15
            renderType: Text.NativeRendering
          }
        }
      }
    }
  }
}
