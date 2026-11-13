import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// A single-line text field that never lets Qt read the clipboard on its own.
//
// Qt's TextInput (under every TextField) reads the whole clipboard offer
// whenever the clipboard changes while it is writable, to decide whether
// Paste is available, with no size or time limit, inside the shell. TextEdit
// makes that decision from the offered formats alone (QQuickTextControl::
// canPaste -> QMimeData::hasText -> the offer's type list), so this field is
// built on TextEdit and styled like the host TextField. TextEdit fetches
// clipboard data in exactly two places, both taken over here:
//
// - The Paste key sequence (Ctrl+V, Shift+Insert, the Paste key) is caught
//   before the editor sees it, and middle-click (the primary selection) is
//   taken by a mouse area on top. Each runs wl-paste in a child process
//   instead: at most `pasteLimit` bytes within 2 seconds, killed with its
//   whole process group at the deadline, used only on a clean exit, and
//   rejected when longer.
// - A reply is used only if nothing happened since the paste was asked for:
//   typing, moving the cursor or selection, or leaving the field cancels it.
//
// TextEdit has no drop handling or context menu. Typing and input methods
// work as in any field. The field also drops focus while it is hidden or its
// popup is closed (`live`).
FocusScope {
  id: root

  // False while the popup that holds the field is closed.
  property bool live: true
  readonly property bool usable: live && visible && enabled
  readonly property int pasteLimit: 1024

  property alias text: edit.text
  property alias font: edit.font
  property alias inputMethodHints: edit.inputMethodHints
  property alias cursorPosition: edit.cursorPosition
  readonly property alias length: edit.length
  property string placeholderText: ""
  property int maximumLength: 32767
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY

  signal accepted()

  function selectAll() { edit.selectAll() }
  function select(start, end) { edit.select(start, end) }

  property int pasteRequest: 0
  property int pendingRequest: -1
  property int pasteStart: 0
  property int pasteEnd: 0
  property bool applyingPaste: false
  property string pasteOutput: ""
  property bool pasteStreamDone: false
  property int pasteExit: -1

  readonly property var borderSpec: Border.controlSpec(activeFocus ? "focus" : (hover.hovered ? "hover-cursor" : "normal"), foreground, accent)

  activeFocusOnTab: true
  implicitWidth: 200
  implicitHeight: Math.round(edit.implicitHeight + 2 * verticalPadding + Border.top(borderSpec) + Border.bottom(borderSpec))

  onUsableChanged: if (!usable && activeFocus) focus = false
  onActiveFocusChanged: {
    if (!activeFocus) invalidatePaste()
    else if (!usable) focus = false
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
    if (!activeFocus || pasteProc.running) return
    pasteStart = Math.min(edit.selectionStart, edit.selectionEnd)
    pasteEnd = Math.max(edit.selectionStart, edit.selectionEnd)
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
    if (request < 0 || request !== pasteRequest || !activeFocus || !usable) return
    var value = String(reply || "")
    if (value === "" || unescape(encodeURIComponent(value)).length > pasteLimit) return
    value = value.replace(/[\x00-\x1f\x7f]+/g, " ").trim()
    var room = Math.max(0, maximumLength - (edit.length - (pasteEnd - pasteStart)))
    var incoming = value.slice(0, room)
    applyingPaste = true
    edit.remove(pasteStart, pasteEnd)
    edit.insert(pasteStart, incoming)
    edit.cursorPosition = pasteStart + incoming.length
    applyingPaste = false
    pasteRequest++
  }

  // Keeps the field one line long and within maximumLength, whatever the
  // source (typing, an input method, or code setting text).
  // Typing past maximumLength is refused before it is inserted (see the key
  // handler). This catches what still gets through, such as an input-method
  // commit or text set by code: it uses edits rather than reassigning text,
  // and cuts an over-long insertion where it was typed rather than at the end.
  property bool fixingText: false
  readonly property var lineBreak: new RegExp("[\\r\\n\\u2028\\u2029]")
  function fixText() {
    if (fixingText) return
    fixingText = true
    var at
    while ((at = edit.text.search(lineBreak)) >= 0) {
      edit.remove(at, at + 1)
      edit.insert(at, " ")
    }
    var excess = edit.length - maximumLength
    if (excess > 0) {
      var end = edit.cursorPosition
      var start = Math.max(0, end - excess)
      edit.remove(start, end)
      if (edit.length > maximumLength) edit.remove(maximumLength, edit.length)
    }
    fixingText = false
  }

  HoverHandler {
    id: hover
    cursorShape: Qt.IBeamCursor
  }

  Ui.BorderSurface {
    anchors.fill: parent
    color: Style.controlFill(root.activeFocus, hover.hovered, root.foreground, root.accent)
    borderSpec: root.borderSpec
    radius: Style.cornerRadius
  }

  // Clicking the padding focuses the field too.
  TapHandler {
    onTapped: root.forceActiveFocus()
  }

  Item {
    id: viewport
    anchors.fill: parent
    anchors.leftMargin: root.horizontalPadding + Border.left(root.borderSpec)
    anchors.rightMargin: root.horizontalPadding + Border.right(root.borderSpec)
    anchors.topMargin: root.verticalPadding + Border.top(root.borderSpec)
    anchors.bottomMargin: root.verticalPadding + Border.bottom(root.borderSpec)
    clip: true

    // Scrolls a long line so the cursor stays in view.
    property real scroll: 0
    function follow() {
      var x = edit.cursorRectangle.x
      if (edit.contentWidth <= width) scroll = 0
      else if (x - scroll > width - 1) scroll = x - width + 1
      else if (x < scroll) scroll = x
    }
    onWidthChanged: follow()

    Text {
      anchors.fill: parent
      verticalAlignment: Text.AlignVCenter
      text: root.placeholderText
      textFormat: Text.PlainText
      elide: Text.ElideRight
      visible: edit.length === 0 && edit.preeditText === ""
      color: Qt.darker(root.foreground, 1.6)
      font: edit.font
    }

    TextEdit {
      id: edit
      focus: true
      x: -viewport.scroll
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(viewport.width, implicitWidth)
      wrapMode: TextEdit.NoWrap
      textFormat: TextEdit.PlainText
      selectByMouse: true
      persistentSelection: false
      color: root.foreground
      selectionColor: Style.selectionFillFor(root.foreground, root.accent)
      selectedTextColor: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body

      onTextChanged: {
        root.fixText()
        if (!root.applyingPaste) root.invalidatePaste()
      }
      onCursorRectangleChanged: viewport.follow()
      onCursorPositionChanged: root.invalidatePaste()
      onSelectionStartChanged: root.invalidatePaste()
      onSelectionEndChanged: root.invalidatePaste()

      // The caller's own key handlers (on root) see each key first; then this
      // takes paste, Enter and Tab before the editor can.
      Keys.forwardTo: [root]
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        var shift = (event.modifiers & Qt.ShiftModifier) !== 0
        if (event.matches(StandardKey.Paste) || event.key === Qt.Key_Paste
            || (ctrl && event.key === Qt.Key_V) || (shift && event.key === Qt.Key_Insert)) {
          event.accepted = true
          root.requestPaste(false)
        } else if (event.text.length > 0 && !ctrl && event.text.charCodeAt(0) >= 32
                   && edit.length - Math.abs(edit.selectionEnd - edit.selectionStart) + event.text.length > root.maximumLength) {
          // A full field ignores further typing, so nothing has to be trimmed
          // afterwards (which would split the edit across two undo steps).
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          event.accepted = true
          root.accepted()
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          event.accepted = true
          var next = root.nextItemInFocusChain(event.key === Qt.Key_Tab && !shift)
          if (next && next !== root) next.forceActiveFocus(Qt.TabFocusReason)
        }
      }
    }
  }

  // Takes the middle button before the editor can paste the primary
  // selection through Qt.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton
    cursorShape: Qt.IBeamCursor
    onPressed: function(mouse) {
      if (!root.usable) return
      root.forceActiveFocus()
      var point = mapToItem(edit, mouse.x, mouse.y)
      edit.cursorPosition = edit.positionAt(point.x, point.y)
      root.requestPaste(true)
    }
  }

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
