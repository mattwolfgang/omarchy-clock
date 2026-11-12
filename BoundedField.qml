import QtQuick
import QtQuick.Controls as Controls
import Quickshell.Io
import qs.Ui as Ui

// A text field that never lets Qt read the clipboard on its own.
//
// A writable Qt text field reads the whole clipboard offer every time the
// clipboard changes (to decide whether Paste is available), and again when
// you paste, with no size or time limit, inside the shell. Another program
// owning the clipboard could stream text into it without end. So:
//
// - The field is read-only unless it has focus, is visible, and its popup is
//   open (`live`). Qt skips the clipboard read for a read-only field. Losing
//   any of those also drops focus, so a hidden field cannot stay writable.
// - Every paste gesture (Ctrl+V and its variants, Shift+Insert, the Paste key,
//   middle-click for the primary selection) runs wl-paste in a child process
//   instead: at most `pasteLimit` bytes within 2 seconds, killed with its
//   whole process group at the deadline. Longer text and failures are
//   rejected, not truncated. The context menu, whose Paste would use Qt's
//   reader, is removed, and text dragged onto the field is discarded unread.
// - A reply is used only if nothing happened since the paste was asked for:
//   typing, moving the cursor or selection, or leaving the field cancels it.
Ui.TextField {
  id: root

  // False while the popup that holds the field is closed.
  property bool live: true
  readonly property bool usable: live && visible && enabled
  readonly property int pasteLimit: 1024

  property int pasteRequest: 0
  property int pendingRequest: -1
  property int pasteStart: 0
  property int pasteEnd: 0
  property bool applyingPaste: false
  property string pasteOutput: ""
  property bool pasteStreamDone: false
  property int pasteExit: -1
  property int keptStart: 0
  property int keptEnd: 0

  readOnly: !(usable && activeFocus)

  onUsableChanged: if (!usable && activeFocus) focus = false

  // Qt moves the cursor to the end when a field turns writable, which would
  // undo a selectAll() made just before focusing it.
  onReadOnlyChanged: {
    if (!readOnly && keptEnd > keptStart) select(keptStart, keptEnd)
  }

  function keepSelection() {
    if (!readOnly) return
    keptStart = Math.min(selectionStart, selectionEnd)
    keptEnd = Math.max(selectionStart, selectionEnd)
  }

  function invalidatePaste() {
    if (applyingPaste) return
    pasteRequest++
    pendingRequest = -1
    if (pasteProc.running) pasteProc.running = false
    pasteWatchdog.stop()
  }

  function requestPaste(primary) {
    if (!usable) return
    forceActiveFocus()
    if (readOnly || pasteProc.running) return
    pasteStart = Math.min(selectionStart, selectionEnd)
    pasteEnd = Math.max(selectionStart, selectionEnd)
    pasteRequest++
    pendingRequest = pasteRequest
    pasteOutput = ""
    pasteStreamDone = false
    pasteExit = -1
    // Fixed argv. timeout puts the pipeline in its own process group and
    // kills the whole group at the deadline; head stops reading one byte past
    // the limit so an oversized offer is detected rather than cut short.
    // pipefail makes a failed or cut-off read exit non-zero, and only a clean
    // exit is pasted, so a prefix sent before a stall is never used.
    pasteProc.command = ["timeout", "-k", "1", "2", "bash", "-c",
      "set -o pipefail; wl-paste --no-newline --type text " + (primary ? "--primary " : "") + "2>/dev/null | head -c " + (pasteLimit + 1)]
    pasteProc.running = true
    pasteWatchdog.restart()
  }

  // The output and the exit can arrive in either order.
  function settlePaste() {
    if (!pasteStreamDone || pasteExit < 0) return
    receivePaste(pasteExit === 0 ? pasteOutput : "")
  }

  function receivePaste(reply) {
    var request = pendingRequest
    pendingRequest = -1
    pasteWatchdog.stop()
    if (request < 0 || request !== pasteRequest || !activeFocus || readOnly) return
    var value = String(reply || "")
    if (value === "" || unescape(encodeURIComponent(value)).length > pasteLimit) return
    value = value.replace(/[\x00-\x1f\x7f]+/g, " ").trim()
    var room = Math.max(0, maximumLength - (length - (pasteEnd - pasteStart)))
    var incoming = value.slice(0, room)
    applyingPaste = true
    remove(pasteStart, pasteEnd)
    insert(pasteStart, incoming)
    cursorPosition = pasteStart + incoming.length
    applyingPaste = false
    pasteRequest++
  }

  onTextEdited: invalidatePaste()
  onCursorPositionChanged: { keepSelection(); invalidatePaste() }
  onSelectionStartChanged: { keepSelection(); invalidatePaste() }
  onSelectionEndChanged: { keepSelection(); invalidatePaste() }
  onActiveFocusChanged: {
    if (!activeFocus) invalidatePaste()
    else if (!usable) focus = false
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    if (event.matches(StandardKey.Paste) || event.key === Qt.Key_Paste
        || (ctrl && event.key === Qt.Key_V) || (shift && event.key === Qt.Key_Insert)) {
      event.accepted = true
      root.requestPaste(false)
    }
  }

  // Takes the middle button before the field can paste the primary selection
  // through Qt.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton
    cursorShape: Qt.IBeamCursor
    onPressed: function(mouse) {
      if (!root.usable) return
      root.forceActiveFocus()
      root.cursorPosition = root.positionAt(mouse.x, mouse.y)
      root.requestPaste(true)
    }
  }

  // Accepted so nothing else reads a drop, and never read here.
  DropArea {
    anchors.fill: parent
    onEntered: function(drag) { drag.accepted = true }
    onDropped: function(drop) { drop.accepted = true }
  }

  Controls.ContextMenu.menu: null

  Process {
    id: pasteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.pasteOutput = text
        root.pasteStreamDone = true
        root.settlePaste()
      }
    }
    onExited: function(code, status) {
      root.pasteExit = status === 0 ? Math.max(0, code) : 255
      root.settlePaste()
    }
    // Also covers a helper that never started, which clears running without
    // an exit.
    onRunningChanged: if (!running) settle.restart()
  }

  // The reply arrives when the helper's output closes, which can land just
  // after running clears; give it that moment before dropping the request.
  Timer {
    id: settle
    interval: 300
    onTriggered: if (!pasteProc.running) root.pendingRequest = -1
  }

  // timeout ends the helper after 2 seconds (3 with the kill); this is the
  // backstop.
  Timer {
    id: pasteWatchdog
    interval: 4000
    onTriggered: root.invalidatePaste()
  }
}
