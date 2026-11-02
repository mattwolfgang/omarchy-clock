import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "Time.js" as Time

// Timers, alarms, and the stopwatch, mounted once for the shell.
//
// Omarchy builds a bar per monitor, so state kept on the widget would exist once
// per screen, and every timer would ring once per screen too. Panels only read
// this object and call its functions.
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property var shell: null
  property var manifest: null

  readonly property string ipcName: "io.github.mattwolfgang.clock"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy"
  readonly property string soundFile: String(Qt.resolvedUrl("sounds/alarm.oga")).replace(/^file:\/\//, "")
  readonly property int soundLimitMs: 60000

  property bool loaded: false
  property var state: Time.emptyState()
  property var ringing: []
  property double now: Date.now()

  readonly property var timers: state.timers
  readonly property var alarms: state.alarms
  readonly property var stopwatch: state.stopwatch
  readonly property var barStatus: statusCache.value

  // A binding on `now` would hand the bar a new object every tick and repaint it
  // even when nothing changed, so this only moves when the text does.
  QtObject {
    id: statusCache
    property var value: null
    function update() {
      var next = Time.barStatus(root.state, root.now)
      if (JSON.stringify(next) !== JSON.stringify(value)) value = next
    }
  }

  function commit(next) {
    root.state = next
    statusCache.update()
    if (root.loaded) stateFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  function patch(values) {
    commit(Object.assign({}, root.state, values))
  }

  function currentTime() {
    root.now = Date.now()
    return root.now
  }

  function makeId() {
    return Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36)
  }

  function mapTimer(id, change) {
    var at = currentTime()
    patch({ timers: root.state.timers.map(function(timer) {
      return timer.id === id ? change(timer, at) : timer
    }) })
  }

  // ---- Timers

  function addTimer(label, durationMs) {
    if (durationMs <= 0 || root.state.timers.length >= 20) return false
    var timer = Time.newTimer(makeId(), label, durationMs, currentTime())
    patch({ timers: [timer].concat(root.state.timers) })
    return true
  }

  function pauseTimer(id) { mapTimer(id, Time.pauseTimer) }
  function resumeTimer(id) { mapTimer(id, Time.resumeTimer) }
  function restartTimer(id) { mapTimer(id, Time.restartTimer) }

  function removeTimer(id) {
    forget("timer", id)
    patch({ timers: root.state.timers.filter(function(timer) { return timer.id !== id }) })
  }

  // ---- Alarms

  function addAlarm(label, hour, minute, days) {
    if (root.state.alarms.length >= 20) return false
    var alarm = Time.newAlarm(makeId(), label, hour, minute, days, currentTime())
    patch({ alarms: root.state.alarms.concat([alarm]) })
    return true
  }

  function setAlarmEnabled(id, enabled) {
    var at = currentTime()
    patch({ alarms: root.state.alarms.map(function(alarm) {
      return alarm.id === id ? Time.setAlarmEnabled(alarm, enabled, at) : alarm
    }) })
  }

  function removeAlarm(id) {
    forget("alarm", id)
    patch({ alarms: root.state.alarms.filter(function(alarm) { return alarm.id !== id }) })
  }

  // ---- Stopwatch

  function toggleStopwatch() { patch({ stopwatch: Time.toggleStopwatch(root.state.stopwatch, currentTime()) }) }
  function lapStopwatch() { patch({ stopwatch: Time.addLap(root.state.stopwatch, currentTime()) }) }
  function resetStopwatch() { patch({ stopwatch: Time.newStopwatch() }) }

  // ---- Ringing

  function headlineFor(event, missed) {
    var key = (missed ? "missed." : "ring.") + event.kind + (event.label ? ".labeled" : "")
    return event.label ? strings.t(key).arg(event.label) : strings.t(key)
  }

  function bodyFor(event) {
    if (event.kind === "timer")
      return Time.localizeNumber(Time.formatCountdown(event.durationMs), Commons.I18n.zeroDigit, Commons.I18n.decimal)
    return new Date(2000, 0, 1, event.hour, event.minute)
      .toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), Locale.ShortFormat)
  }

  function glyphFor(event) {
    return event.kind === "timer" ? Time.ICONS.timer : Time.ICONS.alarm
  }

  function notifyRinging(event) {
    Quickshell.execDetached([
      "omarchy-notification-send", "--app-name", "Clock", "-u", "critical", "-g", glyphFor(event),
      headlineFor(event, false), bodyFor(event),
      "--action", strings.t("ring.dismiss"), "omarchy-shell", root.ipcName, "dismiss",
      "--action", strings.t("ring.snooze").arg(Commons.I18n.formatNumber(5)), "omarchy-shell", root.ipcName, "snooze"
    ])
  }

  function notifyMissed(event) {
    Quickshell.execDetached([
      "omarchy-notification-send", "--app-name", "Clock", "-u", "normal", "-g", glyphFor(event),
      headlineFor(event, true), bodyFor(event)
    ])
  }

  function clearNotification(event) {
    Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "dismiss", headlineFor(event, false)])
  }

  function startSound() {
    soundLimit.restart()
    if (!sound.running) sound.running = true
  }

  function stopSound() {
    soundLimit.stop()
    soundGap.stop()
    sound.running = false
  }

  function silence(events) {
    root.ringing = []
    stopSound()
    events.forEach(clearNotification)
  }

  function dismiss() {
    silence(root.ringing)
  }

  function snooze() {
    var events = root.ringing
    if (events.length === 0) return
    commit(Time.snooze(root.state, events, currentTime()))
    silence(events)
  }

  // A removed item has nothing left to ring for.
  function forget(kind, id) {
    var gone = root.ringing.filter(function(event) { return event.kind === kind && event.id === id })
    if (gone.length === 0) return
    root.ringing = root.ringing.filter(function(event) { return gone.indexOf(event) === -1 })
    gone.forEach(clearNotification)
    if (root.ringing.length === 0) stopSound()
  }

  function tick() {
    var result = Time.advance(root.state, currentTime())
    if (result.due.length === 0 && result.missed.length === 0) {
      statusCache.update()
      return
    }
    commit(result.state)
    result.missed.forEach(notifyMissed)
    if (result.due.length > 0) {
      root.ringing = root.ringing.concat(result.due)
      result.due.forEach(notifyRinging)
      startSound()
    }
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // Times are compared against the wall clock, so this only sets how soon a
  // due item is noticed and how often the bar countdown can change.
  Timer {
    interval: 500
    repeat: true
    running: root.loaded
    onTriggered: root.tick()
  }

  FileView {
    id: stateFile
    path: root.stateDir + "/io.github.mattwolfgang.clock.json"
    onLoaded: {
      var raw = null
      try { raw = JSON.parse(text()) } catch (error) { console.warn("clock: unreadable state file:", error) }
      root.state = Time.normalizeState(raw, Date.now())
      root.loaded = true
      root.tick()
    }
    onLoadFailed: root.loaded = true
  }

  Process {
    id: sound
    command: ["paplay", root.soundFile]
    onExited: if (soundLimit.running) soundGap.restart()
  }

  Timer {
    id: soundGap
    interval: 800
    onTriggered: if (soundLimit.running) sound.running = true
  }

  // The notification and the panel banner stay until dismissed, but nobody who
  // left the room needs the sound going all afternoon.
  Timer {
    id: soundLimit
    interval: root.soundLimitMs
    onTriggered: { soundGap.stop(); sound.running = false }
  }

  ShellIpc {
    target: root.ipcName

    function dismiss(): void { root.dismiss() }
    function snooze(): void { root.snooze() }
  }
}
