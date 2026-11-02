import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Time.js" as Time

// The Timers tab: type a duration or press a preset, and each running timer gets
// a row. Space is fixed by the calendar tab, so a long list scrolls in place.
Item {
  id: view

  property var service: null
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  property double now: 0
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property real innerWidth: width

  readonly property bool editing: durationField.activeFocus || labelField.activeFocus
  readonly property var timers: service ? service.timers : []
  property bool invalid: false

  signal finished()

  function num(text) { return Time.localizeNumber(text, Commons.I18n.zeroDigit, Commons.I18n.decimal) }

  function focusEntry() {
    durationField.selectAll()
    durationField.forceActiveFocus()
  }

  function submit() {
    var ms = Time.parseDuration(Time.normalizeInput(durationField.text, Commons.I18n.zeroDigit, Commons.I18n.decimal))
    view.invalid = ms <= 0
    if (view.invalid || !service || !service.addTimer(labelField.text.trim(), ms)) return
    durationField.text = ""
    labelField.text = ""
    view.finished()
  }

  function fieldKey(event) {
    if (event.key === Qt.Key_Escape) {
      view.invalid = false
      view.finished()
      event.accepted = true
    }
  }

  Column {
    id: entry
    anchors.horizontalCenter: parent.horizontalCenter
    width: view.innerWidth
    spacing: Style.space(8)

    Row {
      width: parent.width
      spacing: Style.space(8)

      TextField {
        id: durationField
        width: Style.space(110)
        anchors.verticalCenter: parent.verticalCenter
        // Accepted forms rather than prose: the parser reads these in every language.
        placeholderText: view.num("5m, 1:30") + "…"
        foreground: view.foreground
        font.family: view.fontFamily
        onTextChanged: view.invalid = false
        onAccepted: view.submit()
        Keys.onPressed: function(event) { view.fieldKey(event) }
      }

      TextField {
        id: labelField
        width: parent.width - durationField.width - startButton.width - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        placeholderText: strings.t("field.name")
        maximumLength: 40
        foreground: view.foreground
        font.family: view.fontFamily
        onAccepted: view.submit()
        Keys.onPressed: function(event) { view.fieldKey(event) }
      }

      Button {
        id: startButton
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t("timer.start")
        bordered: true
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.submit()
      }
    }

    Row {
      spacing: Style.space(6)

      Repeater {
        model: [
          { key: "preset.minutes", amount: 1, ms: 60000 },
          { key: "preset.minutes", amount: 5, ms: 300000 },
          { key: "preset.minutes", amount: 10, ms: 600000 },
          { key: "preset.minutes", amount: 15, ms: 900000 },
          { key: "preset.minutes", amount: 30, ms: 1800000 },
          { key: "preset.hours", amount: 1, ms: 3600000 }
        ]

        Button {
          required property var modelData
          text: strings.t(modelData.key).arg(Commons.I18n.formatNumber(modelData.amount))
          bordered: true
          foreground: view.foreground
          fontFamily: view.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: if (view.service) view.service.addTimer(labelField.text.trim(), modelData.ms)
        }
      }
    }

    Text {
      visible: view.invalid
      text: strings.t("timer.hint")
      textFormat: Text.PlainText
      color: Commons.Color.accent
      font.family: view.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Text {
    visible: view.timers.length === 0 && !view.invalid
    anchors.centerIn: list
    text: strings.t("timer.empty")
    textFormat: Text.PlainText
    color: Qt.darker(view.foreground, 1.6)
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
  }

  Flickable {
    id: list
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: entry.bottom
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.space(12)
    width: view.innerWidth
    contentHeight: rows.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: rows
      width: parent.width
      spacing: Style.space(12)

      Repeater {
        model: view.timers

        Item {
          id: row
          required property var modelData
          readonly property bool running: modelData.state === "running"
          readonly property bool done: modelData.state === "done"
          width: rows.width
          height: Style.space(42)

          Text {
            id: remaining
            anchors.left: parent.left
            anchors.top: parent.top
            text: view.num(Time.formatCountdown(row.done ? row.modelData.durationMs : Time.timerRemaining(row.modelData, view.now)))
            textFormat: Text.PlainText
            color: row.running ? view.foreground : Qt.darker(view.foreground, 1.5)
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            anchors.left: remaining.right
            anchors.right: actions.left
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            anchors.baseline: remaining.baseline
            text: row.modelData.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Qt.darker(view.foreground, 1.4)
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            id: actions
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.space(2)

            PanelActionButton {
              visible: !row.done
              iconText: row.running ? Time.ICONS.pause : Time.ICONS.play
              tooltipText: strings.t(row.running ? "action.pause" : "action.resume")
              foreground: view.foreground
              fontFamily: view.fontFamily
              onClicked: {
                if (row.running) view.service.pauseTimer(row.modelData.id)
                else view.service.resumeTimer(row.modelData.id)
              }
            }

            PanelActionButton {
              iconText: Time.ICONS.restart
              tooltipText: strings.t("action.restart")
              foreground: view.foreground
              fontFamily: view.fontFamily
              onClicked: view.service.restartTimer(row.modelData.id)
            }

            PanelActionButton {
              iconText: Time.ICONS.remove
              tooltipText: strings.t("action.remove")
              foreground: view.foreground
              fontFamily: view.fontFamily
              onClicked: view.service.removeTimer(row.modelData.id)
            }
          }

          // The same rail as the calendar's year bar.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Style.space(6)
            radius: Style.cornerRadius > 0 ? height / 2 : 0
            color: Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.12)

            Rectangle {
              width: Math.round(parent.width * Time.timerProgress(row.modelData, view.now))
              height: parent.height
              radius: parent.radius
              color: Style.selectedStateColor(view.foreground, Commons.Color.accent)
            }
          }
        }
      }
    }
  }
}
