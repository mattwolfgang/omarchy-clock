// Pure logic for timers, alarms, and the stopwatch. Free of Qt so it can run
// under node (tests/time.test.js). Every function that changes state returns a
// new object rather than editing its argument, so QML bindings see the change.
//
// Times are epoch milliseconds, never tick counts: a timer has to come out right
// after a suspend or a shell restart, when no ticks happened at all.

var GRACE_MS = 15 * 60000       // Later than this, a due item is "missed" and stays silent.
var SNOOZE_MS = 5 * 60000
var MAX_DURATION_MS = 100 * 3600000
var MAX_ITEMS = 20
var MAX_LAPS = 99
var MAX_LABEL = 40

var ICONS = {
  calendar: "\u{F00ED}",
  timer: "\u{F051F}",
  alarm: "\u{F0020}",
  stopwatch: "\u{F13AB}",
  play: "\u{F040A}",
  pause: "\u{F03E4}",
  restart: "\u{F0450}",
  remove: "\u{F01B4}",
  lap: "\u{F023B}",
  ringing: "\u{F009E}",
  snooze: "\u{F068E}",
  add: "\u{F0415}"
}

// Digits and decimal point as the language writes them. Pure so it can be tested;
// callers pass the values from Commons.I18n.
function localizeNumber(text, zeroDigit, decimal) {
  var zero = String(zeroDigit || "0").charCodeAt(0)
  return String(text).replace(/[0-9.]/g, function(ch) {
    return ch === "." ? (decimal || ".") : String.fromCharCode(zero + Number(ch))
  })
}

// The reverse, for what people type: Persian or Bengali digits and a comma
// decimal all read the same as "1.5".
function normalizeInput(text, zeroDigit, decimal) {
  var zero = String(zeroDigit || "0").charCodeAt(0)
  var out = ""
  var raw = String(text === undefined || text === null ? "" : text)
  for (var i = 0; i < raw.length; i++) {
    var offset = raw.charCodeAt(i) - zero
    out += offset >= 0 && offset <= 9 ? String(offset) : raw[i]
  }
  return out.split(decimal || ".").join(".").replace(/,/g, ".")
}

function pad2(value) {
  return (value < 10 ? "0" : "") + value
}

// ---- Parsing what people type.

// "5" and "1.5" are minutes, the unit a kitchen timer speaks. "1:30" is minutes
// and seconds, "1:02:03" adds hours, and "1h 30m", "90s", "2 min" name their own.
// Returns 0 for anything unreadable or out of range.
function parseDuration(text) {
  var value = String(text === undefined || text === null ? "" : text).trim().toLowerCase()
  var ms = 0
  var match

  if (/^\d+(\.\d+)?$/.test(value)) {
    ms = parseFloat(value) * 60000
  } else if ((match = /^(?:(\d+):)?(\d+):(\d{1,2})$/.exec(value))) {
    if (Number(match[3]) > 59) return 0
    ms = (Number(match[1] || 0) * 3600 + Number(match[2]) * 60 + Number(match[3])) * 1000
  } else if ((match = /^(?:(\d+)\s*(?:h|hr|hrs|hour|hours))?\s*(?:(\d+)\s*(?:m|min|mins|minute|minutes))?\s*(?:(\d+)\s*(?:s|sec|secs|second|seconds))?$/.exec(value))) {
    ms = (Number(match[1] || 0) * 3600 + Number(match[2] || 0) * 60 + Number(match[3] || 0)) * 1000
  }

  ms = Math.round(ms)
  return ms > 0 && ms <= MAX_DURATION_MS ? ms : 0
}

// "7", "7:30", "730", "19:30", "1930", "7pm", "7:30 a.m.". Null if unreadable.
function parseAlarmTime(text) {
  var value = String(text === undefined || text === null ? "" : text).trim().toLowerCase()
  var match = /^(\d{1,2})(?::?(\d{2}))?\s*(?:([ap])\.?(?:m\.?)?)?$/.exec(value)
  if (!match) return null

  var hour = Number(match[1])
  var minute = Number(match[2] || 0)
  if (minute > 59) return null

  if (match[3]) {
    if (hour < 1 || hour > 12) return null
    hour = (hour % 12) + (match[3] === "p" ? 12 : 0)
  } else if (hour > 23) {
    return null
  }
  return { hour: hour, minute: minute }
}

// ---- Formatting.

// Rounds up so a timer reads 5:00 when it starts and 0:00 only when it is done.
function formatCountdown(ms) {
  return formatSeconds(Math.ceil(Math.max(0, ms) / 1000))
}

function formatSeconds(total) {
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor(total / 60) % 60
  var seconds = total % 60
  return hours > 0
    ? hours + ":" + pad2(minutes) + ":" + pad2(seconds)
    : minutes + ":" + pad2(seconds)
}

function formatElapsed(ms) {
  return formatSeconds(Math.floor(Math.max(0, ms) / 1000))
}

function formatStopwatch(ms) {
  var tenths = Math.floor(Math.max(0, ms) / 100) % 10
  return formatElapsed(ms) + "." + tenths
}

// How a set of repeat days reads: "once", "daily", "weekdays", "weekends", or
// "custom" when the caller has to list the day names.
function daysKind(days) {
  var sorted = (days || []).slice().sort()
  var joined = sorted.join("")
  if (joined === "") return "once"
  if (joined === "0123456") return "daily"
  if (joined === "12345") return "weekdays"
  if (joined === "06") return "weekends"
  return "custom"
}

// ---- Alarms.

// Next time this alarm rings after `after`. Local-time constructors on purpose:
// 7:30 stays 7:30 across a daylight-saving change. Eight days covers a weekly
// alarm whose only day is today but whose time has passed.
function nextAlarmFire(hour, minute, days, after) {
  var base = new Date(after)
  var allowed = days || []
  for (var i = 0; i <= 8; i++) {
    var candidate = new Date(base.getFullYear(), base.getMonth(), base.getDate() + i, hour, minute, 0, 0)
    if (candidate.getTime() <= after) continue
    if (allowed.length === 0 || allowed.indexOf(candidate.getDay()) !== -1) return candidate.getTime()
  }
  return 0
}

function newAlarm(id, label, hour, minute, days, now) {
  var repeat = (days || []).slice().sort()
  return {
    id: id,
    label: String(label || "").slice(0, MAX_LABEL),
    hour: hour,
    minute: minute,
    days: repeat,
    enabled: true,
    snoozed: false,
    nextFire: nextAlarmFire(hour, minute, repeat, now)
  }
}

function setAlarmEnabled(alarm, enabled, now) {
  return Object.assign({}, alarm, {
    enabled: !!enabled,
    snoozed: false,
    nextFire: enabled ? nextAlarmFire(alarm.hour, alarm.minute, alarm.days, now) : 0
  })
}

// ---- Timers. A finished timer stays listed as "done", one click from running
//      again, because a tea timer is the same timer tomorrow.

function newTimer(id, label, durationMs, now) {
  return {
    id: id,
    label: String(label || "").slice(0, MAX_LABEL),
    durationMs: durationMs,
    state: "running",
    endsAt: now + durationMs,
    remainingMs: durationMs
  }
}

function timerRemaining(timer, now) {
  if (timer.state === "running") return Math.max(0, timer.endsAt - now)
  if (timer.state === "paused") return timer.remainingMs
  return 0
}

function pauseTimer(timer, now) {
  if (timer.state !== "running") return timer
  return Object.assign({}, timer, { state: "paused", remainingMs: timerRemaining(timer, now), endsAt: 0 })
}

function resumeTimer(timer, now) {
  if (timer.state !== "paused") return timer
  return Object.assign({}, timer, { state: "running", endsAt: now + timer.remainingMs })
}

function restartTimer(timer, now) {
  return Object.assign({}, timer, { state: "running", endsAt: now + timer.durationMs, remainingMs: timer.durationMs })
}

function timerProgress(timer, now) {
  if (timer.durationMs <= 0) return 0
  return Math.max(0, Math.min(1, timerRemaining(timer, now) / timer.durationMs))
}

// ---- Stopwatch.

function newStopwatch() {
  return { running: false, startedAt: 0, accumulatedMs: 0, laps: [] }
}

function stopwatchElapsed(watch, now) {
  return watch.accumulatedMs + (watch.running ? Math.max(0, now - watch.startedAt) : 0)
}

function toggleStopwatch(watch, now) {
  if (watch.running)
    return Object.assign({}, watch, { running: false, startedAt: 0, accumulatedMs: stopwatchElapsed(watch, now) })
  return Object.assign({}, watch, { running: true, startedAt: now })
}

function addLap(watch, now) {
  if (!watch.running || watch.laps.length >= MAX_LAPS) return watch
  return Object.assign({}, watch, { laps: watch.laps.concat([stopwatchElapsed(watch, now)]) })
}

// Newest first, each with its own split and the running total.
function lapRows(laps) {
  var rows = []
  for (var i = laps.length - 1; i >= 0; i--)
    rows.push({ number: i + 1, split: laps[i] - (i > 0 ? laps[i - 1] : 0), total: laps[i] })
  return rows
}

// ---- The tick.

// Moves everything due at `now` on to its next state and reports what fell due.
// An item more than GRACE_MS late goes in `missed` rather than `due`: the machine
// was off or asleep, and nobody wants a siren for this morning's alarm at noon.
function advance(state, now) {
  var due = []
  var missed = []

  function report(kind, item, at) {
    var event = {
      kind: kind,
      id: item.id,
      label: item.label,
      durationMs: item.durationMs,
      hour: item.hour,
      minute: item.minute
    }
    if (now - at > GRACE_MS) missed.push(event)
    else due.push(event)
  }

  var timers = state.timers.map(function(timer) {
    if (timer.state !== "running" || timer.endsAt > now) return timer
    report("timer", timer, timer.endsAt)
    return Object.assign({}, timer, { state: "done", endsAt: 0, remainingMs: 0 })
  })

  var alarms = state.alarms.map(function(alarm) {
    if (!alarm.enabled || !alarm.nextFire || alarm.nextFire > now) return alarm
    report("alarm", alarm, alarm.nextFire)
    var repeats = alarm.days.length > 0
    return Object.assign({}, alarm, {
      enabled: repeats,
      snoozed: false,
      nextFire: repeats ? nextAlarmFire(alarm.hour, alarm.minute, alarm.days, now) : 0
    })
  })

  return {
    state: Object.assign({}, state, { timers: timers, alarms: alarms }),
    due: due,
    missed: missed
  }
}

// Brings whatever just rang back in five minutes.
function snooze(state, events, now) {
  var at = now + SNOOZE_MS
  function rang(kind, id) {
    return events.some(function(event) { return event.kind === kind && event.id === id })
  }
  return Object.assign({}, state, {
    timers: state.timers.map(function(timer) {
      if (!rang("timer", timer.id)) return timer
      return Object.assign({}, timer, { state: "running", endsAt: at, remainingMs: SNOOZE_MS })
    }),
    alarms: state.alarms.map(function(alarm) {
      if (!rang("alarm", alarm.id)) return alarm
      return Object.assign({}, alarm, { enabled: true, snoozed: true, nextFire: at })
    })
  })
}

// What the bar shows next to the time: the timer closest to done, otherwise a
// running stopwatch, otherwise nothing.
function barStatus(state, now) {
  var soonest = null
  for (var i = 0; i < state.timers.length; i++) {
    var timer = state.timers[i]
    if (timer.state === "running" && (!soonest || timer.endsAt < soonest.endsAt)) soonest = timer
  }
  if (soonest) return { icon: ICONS.timer, text: formatCountdown(soonest.endsAt - now) }
  if (state.stopwatch.running)
    return { icon: ICONS.stopwatch, text: formatElapsed(stopwatchElapsed(state.stopwatch, now)) }
  return null
}

// ---- Persistence. The state file is hand-editable, so nothing in it is trusted
//      to have the right shape; an entry that makes no sense is dropped.

function emptyState() {
  return { timers: [], alarms: [], stopwatch: newStopwatch() }
}

function isCount(value) {
  return typeof value === "number" && isFinite(value) && value >= 0
}

function validDays(days) {
  if (!Array.isArray(days)) return []
  return days.filter(function(day, index) {
    return day === Math.floor(day) && day >= 0 && day <= 6 && days.indexOf(day) === index
  }).sort()
}

function normalizeState(raw, now) {
  var state = emptyState()
  if (!raw || typeof raw !== "object") return state

  if (Array.isArray(raw.timers)) {
    state.timers = raw.timers.filter(function(timer) {
      return timer && typeof timer.id === "string" && isCount(timer.durationMs) && timer.durationMs > 0
        && ["running", "paused", "done"].indexOf(timer.state) !== -1
        && isCount(timer.endsAt || 0) && isCount(timer.remainingMs || 0)
    }).map(function(timer) {
      return {
        id: timer.id,
        label: String(timer.label || "").slice(0, MAX_LABEL),
        durationMs: timer.durationMs,
        state: timer.state,
        endsAt: timer.endsAt || 0,
        remainingMs: timer.remainingMs || 0
      }
    }).slice(0, MAX_ITEMS)
  }

  if (Array.isArray(raw.alarms)) {
    state.alarms = raw.alarms.filter(function(alarm) {
      return alarm && typeof alarm.id === "string"
        && alarm.hour === Math.floor(alarm.hour) && alarm.hour >= 0 && alarm.hour <= 23
        && alarm.minute === Math.floor(alarm.minute) && alarm.minute >= 0 && alarm.minute <= 59
    }).map(function(alarm) {
      var days = validDays(alarm.days)
      var enabled = alarm.enabled === true
      return {
        id: alarm.id,
        label: String(alarm.label || "").slice(0, MAX_LABEL),
        hour: alarm.hour,
        minute: alarm.minute,
        days: days,
        enabled: enabled,
        snoozed: enabled && alarm.snoozed === true,
        nextFire: !enabled ? 0
          : (isCount(alarm.nextFire) && alarm.nextFire > 0 ? alarm.nextFire : nextAlarmFire(alarm.hour, alarm.minute, days, now))
      }
    }).slice(0, MAX_ITEMS)
  }

  var watch = raw.stopwatch
  if (watch && typeof watch === "object" && isCount(watch.accumulatedMs)) {
    var running = watch.running === true && isCount(watch.startedAt) && watch.startedAt > 0
    state.stopwatch = {
      running: running,
      startedAt: running ? watch.startedAt : 0,
      accumulatedMs: watch.accumulatedMs,
      laps: Array.isArray(watch.laps) ? watch.laps.filter(isCount).slice(0, MAX_LAPS) : []
    }
  }
  return state
}

if (typeof module !== "undefined") {
  module.exports = {
    GRACE_MS: GRACE_MS,
    SNOOZE_MS: SNOOZE_MS,
    ICONS: ICONS,
    localizeNumber: localizeNumber,
    normalizeInput: normalizeInput,
    parseDuration: parseDuration,
    parseAlarmTime: parseAlarmTime,
    formatCountdown: formatCountdown,
    formatElapsed: formatElapsed,
    formatStopwatch: formatStopwatch,
    daysKind: daysKind,
    nextAlarmFire: nextAlarmFire,
    newAlarm: newAlarm,
    setAlarmEnabled: setAlarmEnabled,
    newTimer: newTimer,
    timerRemaining: timerRemaining,
    pauseTimer: pauseTimer,
    resumeTimer: resumeTimer,
    restartTimer: restartTimer,
    timerProgress: timerProgress,
    newStopwatch: newStopwatch,
    stopwatchElapsed: stopwatchElapsed,
    toggleStopwatch: toggleStopwatch,
    addLap: addLap,
    lapRows: lapRows,
    advance: advance,
    snooze: snooze,
    barStatus: barStatus,
    emptyState: emptyState,
    normalizeState: normalizeState
  }
}
