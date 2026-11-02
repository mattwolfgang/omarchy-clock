import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Time.js" as Time

// The Stopwatch tab: the elapsed time as the hero, like the date on the calendar
// tab, with laps scrolling underneath it.
Item {
  id: view

  property var service: null
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  property double now: 0
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property real innerWidth: width

  readonly property var watch: service ? service.stopwatch : Time.newStopwatch()
  readonly property bool running: watch.running
  readonly property double elapsed: Time.stopwatchElapsed(watch, now)
  readonly property var laps: Time.lapRows(watch.laps)

  function num(text) { return Time.localizeNumber(text, Commons.I18n.zeroDigit, Commons.I18n.decimal) }

  Column {
    id: top
    anchors.horizontalCenter: parent.horizontalCenter
    width: view.innerWidth
    spacing: Style.space(12)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: view.num(Time.formatStopwatch(view.elapsed))
      textFormat: Text.PlainText
      color: view.foreground
      font.family: view.fontFamily
      font.pixelSize: 52
      font.bold: true
      font.features: { "tnum": 1 }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(8)

      Button {
        iconText: view.running ? Time.ICONS.pause : Time.ICONS.play
        text: strings.t(view.running ? "action.pause" : (view.elapsed > 0 ? "action.resume" : "stopwatch.start"))
        bordered: true
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.service.toggleStopwatch()
      }

      Button {
        iconText: Time.ICONS.lap
        text: strings.t("stopwatch.lap")
        bordered: true
        enabled: view.running
        opacity: enabled ? 1 : 0.4
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.service.lapStopwatch()
      }

      Button {
        iconText: Time.ICONS.restart
        text: strings.t("stopwatch.reset")
        bordered: true
        enabled: view.elapsed > 0
        opacity: enabled ? 1 : 0.4
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.service.resetStopwatch()
      }
    }
  }

  Flickable {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: top.bottom
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.space(14)
    width: view.innerWidth
    contentHeight: rows.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: rows
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: view.laps

        Item {
          id: lapRow
          required property var modelData
          width: rows.width
          height: lapNumber.implicitHeight

          Text {
            id: lapNumber
            anchors.left: parent.left
            text: strings.t("stopwatch.lapNumber").arg(Commons.I18n.formatNumber(lapRow.modelData.number))
            textFormat: Text.PlainText
            color: Qt.darker(view.foreground, 1.5)
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.num(Time.formatStopwatch(lapRow.modelData.split))
            textFormat: Text.PlainText
            color: view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.right: parent.right
            text: view.num(Time.formatStopwatch(lapRow.modelData.total))
            textFormat: Text.PlainText
            color: Qt.darker(view.foreground, 1.5)
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
