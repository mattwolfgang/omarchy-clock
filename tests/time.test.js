// Run with: node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const Time = require("../Time.js")

const MIN = 60000
const local = (y, m, d, h = 0, min = 0) => new Date(y, m - 1, d, h, min).getTime()

test("parseDuration reads the forms people type", () => {
  const cases = {
    "5": 5 * MIN, "1.5": 90000, "1:30": 90000, "1:02:03": 3723000,
    "1h 30m": 90 * MIN, "90s": 90000, "2 min": 2 * MIN, "1h": 60 * MIN, " 10M ": 10 * MIN
  }
  for (const [text, ms] of Object.entries(cases)) assert.equal(Time.parseDuration(text), ms, text)
})

test("parseDuration rejects nonsense and out-of-range values", () => {
  for (const text of ["", "  ", "abc", "0", "1:75", "-5", "5x", "101h", null, undefined])
    assert.equal(Time.parseDuration(text), 0, String(text))
})

test("parseAlarmTime reads 12 and 24 hour forms", () => {
  const cases = {
    "7": [7, 0], "7:30": [7, 30], "730": [7, 30], "19:30": [19, 30], "1930": [19, 30],
    "7pm": [19, 0], "7:30 a.m.": [7, 30], "12am": [0, 0], "12 pm": [12, 0], "0:05": [0, 5]
  }
  for (const [text, [hour, minute]] of Object.entries(cases))
    assert.deepEqual(Time.parseAlarmTime(text), { hour, minute }, text)
})

test("parseAlarmTime rejects impossible times", () => {
  for (const text of ["", "25", "7:75", "13pm", "0am", "soon"])
    assert.equal(Time.parseAlarmTime(text), null, text)
})

test("numbers follow the language both ways", () => {
  assert.equal(Time.localizeNumber("1:05.3", "۰", "٫"), "۱:۰۵٫۳")
  assert.equal(Time.localizeNumber("1:05.3", "0", ","), "1:05,3")
  assert.equal(Time.normalizeInput("۱:۳۰", "۰", "٫"), "1:30")
  assert.equal(Time.parseDuration(Time.normalizeInput("۱٫۵", "۰", "٫")), 90000)
  assert.equal(Time.parseDuration(Time.normalizeInput("1,5", "0", ",")), 90000)
  assert.equal(Time.parseDuration(Time.normalizeInput("1,5", "0", ".")), 90000)
  assert.deepEqual(Time.parseAlarmTime(Time.normalizeInput("۷:۳۰", "۰", "٫")), { hour: 7, minute: 30 })
})

test("countdown rounds up, elapsed rounds down", () => {
  assert.equal(Time.formatCountdown(5 * MIN), "5:00")
  assert.equal(Time.formatCountdown(299001), "5:00")
  assert.equal(Time.formatCountdown(1), "0:01")
  assert.equal(Time.formatCountdown(0), "0:00")
  assert.equal(Time.formatCountdown(3723000), "1:02:03")
  assert.equal(Time.formatElapsed(1999), "0:01")
  assert.equal(Time.formatStopwatch(61250), "1:01.2")
})

test("daysKind names the common repeat sets", () => {
  assert.equal(Time.daysKind([]), "once")
  assert.equal(Time.daysKind([0, 1, 2, 3, 4, 5, 6]), "daily")
  assert.equal(Time.daysKind([5, 4, 3, 2, 1]), "weekdays")
  assert.equal(Time.daysKind([6, 0]), "weekends")
  assert.equal(Time.daysKind([1, 3]), "custom")
})

test("nextAlarmFire picks today, tomorrow, or the next allowed day", () => {
  const monday9 = local(2026, 11, 2, 9)
  assert.equal(Time.nextAlarmFire(10, 0, [], monday9), local(2026, 11, 2, 10))
  assert.equal(Time.nextAlarmFire(8, 0, [], monday9), local(2026, 11, 3, 8))
  assert.equal(Time.nextAlarmFire(9, 0, [], monday9), local(2026, 11, 3, 9), "exactly now is not next")
  assert.equal(Time.nextAlarmFire(8, 0, [3], monday9), local(2026, 11, 4, 8), "Wednesday")
  assert.equal(Time.nextAlarmFire(8, 0, [1], monday9), local(2026, 11, 9, 8), "next Monday, a week out")
})

test("timers pause, resume, and restart without losing time", () => {
  let timer = Time.newTimer("a", "Tea", 5 * MIN, 1000)
  assert.equal(Time.timerRemaining(timer, 1000 + MIN), 4 * MIN)
  timer = Time.pauseTimer(timer, 1000 + MIN)
  assert.equal(timer.state, "paused")
  assert.equal(Time.timerRemaining(timer, 1000 + 99 * MIN), 4 * MIN)
  timer = Time.resumeTimer(timer, 100 * MIN)
  assert.equal(timer.endsAt, 104 * MIN)
  assert.equal(Time.timerProgress(timer, 100 * MIN), 0.8)
  timer = Time.restartTimer(timer, 200 * MIN)
  assert.equal(Time.timerRemaining(timer, 200 * MIN), 5 * MIN)
})

test("stopwatch accumulates across pauses and records splits", () => {
  let watch = Time.toggleStopwatch(Time.newStopwatch(), 1000)
  assert.equal(Time.stopwatchElapsed(watch, 4000), 3000)
  watch = Time.addLap(watch, 4000)
  watch = Time.toggleStopwatch(watch, 6000)
  assert.equal(watch.accumulatedMs, 5000)
  assert.equal(Time.stopwatchElapsed(watch, 99999), 5000)
  assert.equal(Time.addLap(watch, 7000), watch, "no laps while paused")
  watch = Time.toggleStopwatch(watch, 10000)
  watch = Time.addLap(watch, 11000)
  assert.deepEqual(Time.lapRows(watch.laps), [
    { number: 2, split: 3000, total: 6000 },
    { number: 1, split: 3000, total: 3000 }
  ])
})

test("advance rings what is due and leaves the rest alone", () => {
  const state = Time.emptyState()
  state.timers = [Time.newTimer("due", "Tea", MIN, 0), Time.newTimer("later", "", 10 * MIN, 0)]
  const result = Time.advance(state, MIN)
  assert.deepEqual(result.due.map(e => e.id), ["due"])
  assert.deepEqual(result.missed, [])
  assert.equal(result.state.timers[0].state, "done")
  assert.equal(result.state.timers[1].state, "running")
  assert.equal(state.timers[0].state, "running", "input not mutated")
  assert.deepEqual(Time.advance(result.state, MIN + 1).due, [], "rings once")
})

test("a one-shot alarm turns off and a repeating one moves on", () => {
  const now = local(2026, 11, 2, 7)
  const state = Time.emptyState()
  state.alarms = [
    Time.newAlarm("once", "", 7, 30, [], now),
    Time.newAlarm("daily", "", 7, 30, [0, 1, 2, 3, 4, 5, 6], now)
  ]
  const result = Time.advance(state, local(2026, 11, 2, 7, 30))
  assert.equal(result.due.length, 2)
  assert.equal(result.state.alarms[0].enabled, false)
  assert.equal(result.state.alarms[0].nextFire, 0)
  assert.equal(result.state.alarms[1].enabled, true)
  assert.equal(result.state.alarms[1].nextFire, local(2026, 11, 3, 7, 30))
})

test("an item long overdue is missed rather than rung", () => {
  const now = local(2026, 11, 2, 7)
  const state = Time.emptyState()
  state.alarms = [Time.newAlarm("a", "", 7, 30, [1], now)]
  state.timers = [Time.newTimer("t", "", MIN, now)]

  const soon = Time.advance(state, local(2026, 11, 2, 7, 40))
  assert.deepEqual(soon.due.map(e => e.id).sort(), ["a"])
  assert.deepEqual(soon.missed.map(e => e.id), ["t"])

  const late = Time.advance(state, local(2026, 11, 2, 12))
  assert.deepEqual(late.due, [])
  assert.deepEqual(late.missed.map(e => e.id).sort(), ["a", "t"])
  assert.equal(late.state.alarms[0].nextFire, local(2026, 11, 9, 7, 30), "still rings next week")
})

test("snooze brings back only what rang, and re-enables a one-shot alarm", () => {
  const now = local(2026, 11, 2, 7, 30)
  const state = Time.advance({
    timers: [Time.newTimer("t", "", MIN, now - MIN), Time.newTimer("other", "", 60 * MIN, now)],
    alarms: [Time.newAlarm("a", "", 7, 30, [], now - MIN)],
    stopwatch: Time.newStopwatch()
  }, now)
  const after = Time.snooze(state.state, state.due, now)
  assert.equal(after.timers[0].state, "running")
  assert.equal(after.timers[0].endsAt, now + Time.SNOOZE_MS)
  assert.equal(after.timers[0].durationMs, MIN, "restart still uses the real duration")
  assert.equal(after.timers[1].endsAt, now + 60 * MIN)
  assert.equal(after.alarms[0].enabled, true)
  assert.equal(after.alarms[0].snoozed, true)
  assert.equal(after.alarms[0].nextFire, now + Time.SNOOZE_MS)

  const fired = Time.advance(after, now + Time.SNOOZE_MS)
  assert.equal(fired.due.length, 2)
  assert.equal(fired.state.alarms[0].enabled, false, "one-shot is done after its snooze")
  assert.equal(fired.state.alarms[0].snoozed, false)
})

test("turning an alarm off and on clears its snooze", () => {
  const now = local(2026, 11, 2, 7)
  let alarm = Object.assign(Time.newAlarm("a", "", 7, 30, [], now), { snoozed: true, nextFire: now + 1 })
  alarm = Time.setAlarmEnabled(alarm, false, now)
  assert.deepEqual([alarm.enabled, alarm.snoozed, alarm.nextFire], [false, false, 0])
  alarm = Time.setAlarmEnabled(alarm, true, now)
  assert.equal(alarm.nextFire, local(2026, 11, 2, 7, 30))
})

test("barStatus prefers the soonest timer, then the stopwatch", () => {
  const state = Time.emptyState()
  assert.equal(Time.barStatus(state, 0), null)
  state.stopwatch = Time.toggleStopwatch(state.stopwatch, 0)
  assert.equal(Time.barStatus(state, 65000).text, "1:05")
  state.timers = [Time.newTimer("a", "", 10 * MIN, 0), Time.newTimer("b", "", MIN, 0)]
  assert.equal(Time.barStatus(state, 0).text, "1:00")
  state.timers[1] = Time.pauseTimer(state.timers[1], 0)
  assert.equal(Time.barStatus(state, 0).text, "10:00")
})

test("normalizeState survives garbage and keeps what is valid", () => {
  assert.deepEqual(Time.normalizeState(null, 0), Time.emptyState())
  assert.deepEqual(Time.normalizeState("nope", 0), Time.emptyState())
  assert.deepEqual(Time.normalizeState({ timers: "x", alarms: 3, stopwatch: [] }, 0), Time.emptyState())

  const now = local(2026, 11, 2, 7)
  const state = Time.normalizeState({
    timers: [
      null,
      { id: "bad", durationMs: -1, state: "running" },
      { id: "bad2", durationMs: 5, state: "exploded" },
      { id: "ok", label: "Tea", durationMs: 1000, state: "paused", remainingMs: 500 }
    ],
    alarms: [
      { id: "bad", hour: 25, minute: 0 },
      { id: "noNext", hour: 7, minute: 30, days: [1, 1, 9, "x"], enabled: true }
    ],
    stopwatch: { running: true, startedAt: 5, accumulatedMs: 10, laps: [1, "x", 2] }
  }, now)
  assert.deepEqual(state.timers.map(t => t.id), ["ok"])
  assert.deepEqual(state.alarms[0].days, [1])
  assert.equal(state.alarms[0].nextFire, local(2026, 11, 2, 7, 30))
  assert.deepEqual(state.stopwatch.laps, [1, 2])
})
