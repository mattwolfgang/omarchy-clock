import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Time.js" as Time

// The Alarms tab: a time, an optional name, and the days it repeats on. No days
// means once. Alarms only ring while the shell is running.
Item {
  id: view

  property var service: null
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  property var labelLocale: Qt.locale()
  property var weekdays: [1, 2, 3, 4, 5, 6, 0]
  property bool use12h: false
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property real innerWidth: width

  readonly property bool editing: timeField.activeFocus || labelField.activeFocus
  readonly property var alarms: service ? service.alarms : []
  property var selectedDays: []
  property bool invalid: false

  signal finished()

  function focusEntry() {
    timeField.selectAll()
    timeField.forceActiveFocus()
  }

  function submit() {
    var time = Time.parseAlarmTime(Time.normalizeInput(timeField.text, Commons.I18n.zeroDigit, Commons.I18n.decimal))
    view.invalid = time === null
    if (view.invalid || !service) return
    if (!service.addAlarm(labelField.text.trim(), time.hour, time.minute, view.selectedDays)) return
    timeField.text = ""
    labelField.text = ""
    view.selectedDays = []
    view.finished()
  }

  function fieldKey(event) {
    if (event.key === Qt.Key_Escape) {
      view.invalid = false
      view.finished()
      event.accepted = true
    }
  }

  function toggleDay(day) {
    var days = view.selectedDays.slice()
    var index = days.indexOf(day)
    if (index === -1) days.push(day)
    else days.splice(index, 1)
    view.selectedDays = days
  }

  function timeLabel(hour, minute) {
    return new Date(2000, 0, 1, hour, minute).toLocaleTimeString(view.labelLocale, view.use12h ? "h:mm AP" : "HH:mm")
  }

  function daysLabel(alarm) {
    if (alarm.snoozed)
      return strings.t("alarm.snoozedUntil").arg(new Date(alarm.nextFire).toLocaleTimeString(view.labelLocale, view.use12h ? "h:mm AP" : "HH:mm"))
    var kind = Time.daysKind(alarm.days)
    if (kind !== "custom") return strings.t("alarm." + kind)
    return view.weekdays.filter(function(day) { return alarm.days.indexOf(day) !== -1 })
      .map(function(day) { return view.labelLocale.dayName(day, Locale.ShortFormat) })
      .join(strings.t("list.separator"))
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
        id: timeField
        width: Style.space(110)
        anchors.verticalCenter: parent.verticalCenter
        placeholderText: Time.localizeNumber(view.use12h ? "7:30 am" : "07:30", Commons.I18n.zeroDigit, ":")
        foreground: view.foreground
        font.family: view.fontFamily
        onTextChanged: view.invalid = false
        onAccepted: view.submit()
        Keys.onPressed: function(event) { view.fieldKey(event) }
      }

      TextField {
        id: labelField
        width: parent.width - timeField.width - addButton.width - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        placeholderText: strings.t("field.name")
        maximumLength: 40
        foreground: view.foreground
        font.family: view.fontFamily
        onAccepted: view.submit()
        Keys.onPressed: function(event) { view.fieldKey(event) }
      }

      Button {
        id: addButton
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t("alarm.add")
        bordered: true
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.submit()
      }
    }

    Row {
      spacing: Style.space(6)

      Repeater {
        model: view.weekdays

        Button {
          required property var modelData
          text: view.labelLocale.dayName(modelData, Locale.ShortFormat)
          bordered: true
          selected: view.selectedDays.indexOf(modelData) !== -1
          foreground: view.foreground
          fontFamily: view.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: view.toggleDay(modelData)
        }
      }
    }

    Text {
      visible: view.invalid
      text: strings.t("alarm.hint")
      textFormat: Text.PlainText
      color: Commons.Color.accent
      font.family: view.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Text {
    visible: view.alarms.length === 0 && !view.invalid
    anchors.centerIn: list
    text: strings.t("alarm.empty")
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
      spacing: Style.space(10)

      Repeater {
        model: view.alarms

        Item {
          id: row
          required property var modelData
          width: rows.width
          height: Math.max(details.implicitHeight, Style.space(30))

          Column {
            id: details
            anchors.left: parent.left
            anchors.right: controls.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              width: parent.width
              text: view.timeLabel(row.modelData.hour, row.modelData.minute)
                + (row.modelData.label ? "  " + row.modelData.label : "")
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: row.modelData.enabled ? view.foreground : Qt.darker(view.foreground, 1.7)
              font.family: view.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              width: parent.width
              text: view.daysLabel(row.modelData)
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Qt.darker(view.foreground, row.modelData.enabled ? 1.4 : 1.9)
              font.family: view.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Row {
            id: controls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            ToggleSwitch {
              anchors.verticalCenter: parent.verticalCenter
              checked: row.modelData.enabled
              foreground: view.foreground
              onToggled: view.service.setAlarmEnabled(row.modelData.id, !row.modelData.enabled)
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: Time.ICONS.remove
              tooltipText: strings.t("action.remove")
              foreground: view.foreground
              fontFamily: view.fontFamily
              onClicked: view.service.removeAlarm(row.modelData.id)
            }
          }
        }
      }
    }
  }
}
