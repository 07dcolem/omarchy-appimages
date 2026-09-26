import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Install, list, and remove AppImages. The shell summons this panel; the bar
// widget is a separate entry point and only opens it.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool dragging: false
  property bool focusPrimed: false
  property bool busy: false
  property bool fuseOk: true
  property string mode: "list" // list | confirm | remove
  property string status: ""
  property var apps: []
  property int cursor: 0

  property string pendingPath: ""
  property string pendingName: ""
  property string pendingDest: ""
  property string hash: ""
  property bool hashPending: false
  property bool canReplace: false
  property bool inspectPending: false
  property bool confirmEnabled: true
  property string confirmTitle: "Install this AppImage?"
  property string confirmDetail: ""
  property string confirmNote: "Install moves the file into Applications."
  property string confirmButton: "Install"
  property var pendingRemove: null

  readonly property string pluginId: (manifest && manifest.id) || "07dcolem.appimages"
  readonly property string home: Quickshell.env("HOME")
  readonly property string binDir: scriptDir()
  readonly property string listBin: binDir + "/omarchy-appimage-list"
  readonly property string installBin: binDir + "/omarchy-appimage-install"
  readonly property string removeBin: binDir + "/omarchy-appimage-remove"
  readonly property string launchBin: binDir + "/omarchy-launch-appimage"

  readonly property var barState: shell && shell.bar ? shell.bar : null
  readonly property string barPosition: barState && barState.position ? String(barState.position) : "top"
  readonly property real barThickness: barState && barState.barSize ? Number(barState.barSize) : Style.space(36)
  readonly property real gap: Style.gapsOut
  readonly property real cardW: 440
  readonly property real cardH: Math.min(520, Math.max(240,
    body.implicitHeight + card.contentTopInset + card.contentBottomInset))
  readonly property color textColor: Color.popups.text
  readonly property color muted: Color.muted
  readonly property string fontFamily: Style.font.family

  function scriptDir() {
    var url = Qt.resolvedUrl("bin/omarchy-appimage-list").toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    try { url = decodeURIComponent(url) } catch (e) {}
    var slash = url.lastIndexOf("/")
    return slash >= 0 ? url.substring(0, slash) : url
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    root.opened = true
    root.dragging = payload.drag === true
    if (!root.dragging) {
      root.focusPrimed = false
      prime.restart()
    }
    refresh()
    if (payload.path) considerPath(String(payload.path))
    else if (payload.entries) considerEntries(payload.entries)
    Qt.callLater(function () {
      if (root.opened) keys.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
    root.dragging = false
    root.busy = false
    root.mode = "list"
    root.clearConfirm()
    prime.stop()
    listProc.running = false
    installProc.running = false
    removeProc.running = false
    hashProc.running = false
    inspectProc.running = false
  }

  function dismiss() {
    if (root.mode !== "list") {
      cancelDialog()
      return
    }
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function refresh() {
    if (listProc.running) listProc.running = false
    listProc.command = [listBin]
    listProc.running = true
  }

  function applyList(code, text) {
    var parsed = Model.parseList(text)
    if (code !== 0 || !parsed.ok) {
      root.status = parsed.error || "Could not read installed AppImages"
      return
    }
    root.fuseOk = parsed.fuse
    root.apps = parsed.apps
    if (root.cursor >= root.apps.length) root.cursor = Math.max(0, root.apps.length - 1)
  }

  function considerEntries(entries) {
    var paths = []
    var list = entries || []
    for (var i = 0; i < list.length; i++) {
      var path = Model.fileUrlToPath(list[i])
      if (Model.isAppImagePath(path)) paths.push(path)
    }
    if (paths.length === 0) {
      root.status = "Drop a single .AppImage file."
      root.mode = "list"
      return
    }
    if (paths.length > 1) root.status = "Installing the first AppImage. Drop one file at a time."
    considerPath(paths[0])
  }

  function considerPath(path) {
    if (!Model.isAppImagePath(path)) {
      root.status = "Only .AppImage files can be installed."
      root.mode = "list"
      return
    }
    root.pendingPath = path
    root.pendingName = Model.baseName(path)
    root.pendingDest = Model.destination(home, path)
    root.hash = ""
    root.hashPending = true
    root.canReplace = false
    root.confirmEnabled = false
    root.confirmTitle = "Install this AppImage?"
    root.confirmDetail = "Reading the AppImage…"
    root.confirmNote = "Install moves the file into Applications."
    root.confirmButton = "Install"
    root.inspectPending = true
    root.mode = "confirm"
    root.dragging = false
    if (hashProc.running) hashProc.running = false
    hashProc.command = ["sha256sum", path]
    hashProc.running = true
    root.startInspect()
    Qt.callLater(function () { if (root.opened) keys.forceActiveFocus() })
  }

  function clearConfirm() {
    root.inspectPending = false
    root.canReplace = false
    root.confirmEnabled = true
    root.confirmTitle = "Install this AppImage?"
    root.confirmDetail = ""
    root.confirmNote = "Install moves the file into Applications."
    root.confirmButton = "Install"
  }

  function startInspect() {
    if (root.mode !== "confirm" || !root.pendingPath) {
      root.inspectPending = false
      return
    }
    // A drop that arrives while a read is in progress stops that read. Its
    // exit starts the read for the path now pending.
    if (inspectProc.running) {
      inspectProc.running = false
      return
    }
    inspectProc.startedPath = root.pendingPath
    inspectProc.command = [installBin, "--inspect", root.pendingPath]
    inspectProc.running = true
  }

  function finishInspect(code, stdout, stderr) {
    root.inspectPending = false
    if (root.mode !== "confirm") return
    var parsed = Model.parseInspect(stdout)
    if (code !== 0 || !parsed.ok || parsed.source !== root.pendingPath) {
      root.confirmEnabled = true
      root.confirmDetail = ""
      if (code !== 0) {
        var err = String(stderr || "").trim()
        root.status = Model.clip(err || "Could not read this AppImage.", 400)
      }
      return
    }
    var plan = Model.planFromInspect(parsed)
    root.canReplace = plan.replace === true
    root.confirmEnabled = plan.enabled === true
    root.confirmTitle = plan.title
    root.confirmDetail = plan.detail
    root.confirmNote = plan.note
    root.confirmButton = plan.button
  }

  function pickFile() {
    fileDialog.currentFolder = "file://" + home + "/Downloads"
    fileDialog.open()
  }

  function install(replace) {
    if (root.busy || !root.pendingPath) return
    root.busy = true
    root.canReplace = false
    root.status = replace ? "Updating…" : "Installing…"
    if (installProc.running) installProc.running = false
    var command = [installBin, root.pendingPath]
    if (replace) command.push("--replace")
    installProc.command = command
    installProc.running = true
  }

  function finishInstall(code, stdout, stderr) {
    root.busy = false
    var err = String(stderr || "").trim()
    var out = String(stdout || "").trim()
    if (code !== 0) {
      // "already exists and is used by" is a different app's payload. --replace
      // cannot fix that, so only a launcher-name collision becomes an update.
      var launcherExists = err.indexOf("A launcher named") !== -1
      root.canReplace = launcherExists
      root.confirmEnabled = true
      if (launcherExists) {
        root.confirmTitle = "Update this AppImage?"
        root.confirmButton = "Update"
        root.confirmNote = "Update replaces the installed launcher."
        root.confirmDetail = ""
      }
      root.status = Model.clip(err || "Install failed.", 400)
      return
    }
    root.mode = "list"
    root.clearConfirm()
    root.status = Model.clip(out.split("\n")[0] || "Installed.", 400)
    refresh()
  }

  function askRemove(app) {
    root.pendingRemove = app
    root.mode = "remove"
    root.clearConfirm()
    Qt.callLater(function () { if (root.opened) keys.forceActiveFocus() })
  }

  function removeApp(keepFile) {
    var app = root.pendingRemove
    if (root.busy || !app) return
    root.busy = true
    root.status = keepFile ? "Removing launcher…" : "Removing…"
    if (removeProc.running) removeProc.running = false
    var command = ["env", "OMARCHY_REMOVE_NOTIFY=false", removeBin]
    if (keepFile) command.push("--keep-file")
    command.push(String(app.name || ""))
    removeProc.command = command
    removeProc.running = true
  }

  function finishRemove(code, stdout, stderr) {
    root.busy = false
    var err = String(stderr || "").trim()
    if (code !== 0) {
      root.status = err || String(stdout || "").trim() || "Remove failed."
      return
    }
    root.mode = "list"
    root.pendingRemove = null
    root.status = "Removed."
    refresh()
  }

  function launchApp(app) {
    if (!app || !app.payload) return
    Quickshell.execDetached([launchBin, String(app.payload)])
    root.status = "Opening " + String(app.name || "app") + "."
  }

  function launchCursor() {
    if (root.mode !== "list" || root.apps.length === 0) return
    if (root.cursor < 0 || root.cursor >= root.apps.length) return
    launchApp(root.apps[root.cursor])
  }

  function acceptDialog() {
    if (root.mode === "confirm") {
      if (root.busy || root.inspectPending || !root.confirmEnabled) return
      install(root.canReplace)
      return
    }
    if (root.mode === "remove") removeApp(false)
  }

  function cancelDialog() {
    root.mode = "list"
    root.clearConfirm()
    root.pendingRemove = null
    inspectProc.running = false
  }

  function moveCursor(delta) {
    if (root.mode !== "list" || root.apps.length === 0) return
    var next = root.cursor + delta
    if (next < 0) next = 0
    if (next >= root.apps.length) next = root.apps.length - 1
    root.cursor = next
  }

  Process {
    id: listProc
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: function (code) {
      Qt.callLater(function () { root.applyList(code, listOut.text) })
    }
  }

  Process {
    id: installProc
    stdout: StdioCollector { id: installOut; waitForEnd: true }
    stderr: StdioCollector { id: installErr; waitForEnd: true }
    onExited: function (code) {
      Qt.callLater(function () { root.finishInstall(code, installOut.text, installErr.text) })
    }
  }

  Process {
    id: removeProc
    stdout: StdioCollector { id: removeOut; waitForEnd: true }
    stderr: StdioCollector { id: removeErr; waitForEnd: true }
    onExited: function (code) {
      Qt.callLater(function () { root.finishRemove(code, removeOut.text, removeErr.text) })
    }
  }

  Process {
    id: inspectProc
    property string startedPath: ""
    stdout: StdioCollector { id: inspectOut; waitForEnd: true }
    stderr: StdioCollector { id: inspectErr; waitForEnd: true }
    onExited: function (code) {
      var started = inspectProc.startedPath
      var out = String(inspectOut.text || "")
      var err = String(inspectErr.text || "")
      Qt.callLater(function () {
        if (started !== root.pendingPath || root.mode !== "confirm") {
          if (root.mode === "confirm" && started !== root.pendingPath) root.startInspect()
          else root.inspectPending = false
          return
        }
        root.finishInspect(code, out, err)
      })
    }
  }

  Process {
    id: hashProc
    stdout: StdioCollector { id: hashOut; waitForEnd: true }
    onExited: function (code) {
      Qt.callLater(function () {
        root.hashPending = false
        if (code === 0) {
          var hashed = String(hashOut.text || "").trim()
          var cut = hashed.indexOf(" ")
          root.hash = cut >= 0 ? hashed.slice(0, cut) : hashed
        }
      })
    }
  }

  Timer {
    id: prime
    interval: 75
    onTriggered: root.focusPrimed = true
  }

  component TextButton: Rectangle {
    id: button
    property string label: ""
    property bool primary: false
    signal clicked()
    implicitWidth: labelText.implicitWidth + Style.space(20)
    implicitHeight: Style.space(28)
    radius: Style.cornerRadius
    color: button.primary ? Color.accent : Style.hoverFill
    opacity: button.enabled ? 1 : 0.45

    Text {
      id: labelText
      anchors.centerIn: parent
      text: button.label
      color: button.primary ? Color.background : Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      anchors.fill: parent
      enabled: button.enabled
      onClicked: button.clicked()
    }
  }

  PanelWindow {
    id: window
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "07dcolem-appimages"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: !root.opened || root.dragging
      ? WlrKeyboardFocus.None
      : (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)

    implicitWidth: root.cardW
    implicitHeight: root.cardH

    anchors {
      top: true
      left: true
    }

    margins {
      top: {
        if (root.barPosition === "bottom")
          return Math.max(root.gap, (window.screen ? window.screen.height : root.cardH) - root.barThickness - root.cardH - root.gap)
        if (root.barPosition === "left" || root.barPosition === "right") return root.gap
        return root.barThickness + root.gap
      }
      left: {
        var screenW = window.screen ? window.screen.width : root.cardW
        if (root.barPosition === "left") return root.barThickness + root.gap
        if (root.barPosition === "right")
          return Math.max(root.gap, screenW - root.barThickness - root.cardW - root.gap)
        return Math.max(root.gap, screenW - root.cardW - root.gap)
      }
    }

    FileDialog {
      id: fileDialog
      title: "Add an AppImage"
      nameFilters: ["AppImages (*.AppImage *.appimage)"]
      fileMode: FileDialog.OpenFile
      onAccepted: root.considerPath(Model.fileUrlToPath(String(selectedFile)))
    }

    BorderSurface {
      id: card
      anchors.fill: parent
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.space(14)
      radius: Style.cornerRadius

      FocusScope {
        id: keys
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        focus: true

        Keys.onEscapePressed: function (event) { root.dismiss(); event.accepted = true }
        Keys.onUpPressed: function (event) { root.moveCursor(-1); event.accepted = true }
        Keys.onDownPressed: function (event) { root.moveCursor(1); event.accepted = true }
        Keys.onReturnPressed: function (event) {
          if (root.mode === "list") root.launchCursor()
          else root.acceptDialog()
          event.accepted = true
        }
        Keys.onEnterPressed: function (event) {
          if (root.mode === "list") root.launchCursor()
          else root.acceptDialog()
          event.accepted = true
        }

        Column {
          id: body
          width: parent.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            height: Style.space(28)

            Image {
              id: headerIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              height: Style.space(18)
              source: Qt.resolvedUrl("assets/icon.svg")
              sourceSize.width: width
              sourceSize.height: height
              fillMode: Image.PreserveAspectFit
            }

            Text {
              anchors.left: headerIcon.right
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "AppImages"
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              TextButton {
                label: "Add"
                enabled: !root.busy
                onClicked: root.pickFile()
              }

              TextButton {
                label: "Close"
                onClicked: {
                  root.mode = "list"
                  if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
                  else root.close()
                }
              }
            }
          }

          Text {
            visible: !root.fuseOk
            width: parent.width
            wrapMode: Text.WordWrap
            text: "FUSE is missing. Install can still proceed. Running an AppImage may fail until fuse2 or fuse3 is installed."
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Column {
            id: listColumn
            visible: root.mode === "list"
            width: parent.width
            spacing: Style.space(4)

            Text {
              visible: root.apps.length === 0
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Nothing installed yet. Drop an AppImage on the bar icon, or use Add."
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: root.apps
              delegate: Rectangle {
                id: row
                required property int index
                required property var modelData
                width: listColumn.width
                height: Style.space(48)
                radius: Style.cornerRadius
                color: index === root.cursor ? Style.selectedFill : "transparent"

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.cursor = row.index
                }

                Image {
                  id: rowIcon
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(28)
                  height: Style.space(28)
                  visible: row.modelData.icon !== ""
                  source: Model.fileUrl(row.modelData.icon)
                  fillMode: Image.PreserveAspectFit
                }

                Column {
                  anchors.left: rowIcon.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: rowActions.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 1

                  Text {
                    width: parent.width
                    text: row.modelData.name
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    visible: row.modelData.comment && row.modelData.comment !== row.modelData.name
                    text: row.modelData.comment || ""
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Row {
                  id: rowActions
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)

                  TextButton {
                    label: "Open"
                    onClicked: root.launchApp(row.modelData)
                  }

                  TextButton {
                    label: "Remove"
                    enabled: !root.busy
                    onClicked: root.askRemove(row.modelData)
                  }
                }
              }
            }
          }

          Column {
            visible: root.mode === "confirm"
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: root.confirmTitle
              textFormat: Text.PlainText
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              width: parent.width
              wrapMode: Text.WrapAnywhere
              text: "File  " + root.pendingName
              textFormat: Text.PlainText
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              wrapMode: Text.WrapAnywhere
              text: "To  " + root.pendingDest
              textFormat: Text.PlainText
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              wrapMode: Text.WrapAnywhere
              text: root.hashPending ? "sha256  hashing…" : (root.hash ? "sha256  " + root.hash : "sha256  unavailable")
              textFormat: Text.PlainText
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              width: parent.width
              visible: root.confirmDetail !== ""
              wrapMode: Text.WordWrap
              text: root.confirmDetail
              textFormat: Text.PlainText
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              visible: root.confirmNote !== ""
              wrapMode: Text.WordWrap
              text: root.confirmNote
              textFormat: Text.PlainText
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              spacing: Style.space(8)
              TextButton {
                label: root.confirmButton
                primary: true
                visible: root.inspectPending || root.confirmEnabled
                enabled: !root.busy && root.confirmEnabled && !root.inspectPending
                onClicked: root.install(root.canReplace)
              }
              TextButton {
                label: "Cancel"
                enabled: !root.busy
                onClicked: root.cancelDialog()
              }
            }
          }

          Column {
            visible: root.mode === "remove"
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Remove " + ((root.pendingRemove && root.pendingRemove.name) || "this app") + "? The launcher and icon are deleted. Remove also deletes the file in Applications."
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Row {
              spacing: Style.space(8)
              TextButton {
                label: "Remove"
                primary: true
                enabled: !root.busy
                onClicked: root.removeApp(false)
              }
              TextButton {
                label: "Keep file"
                enabled: !root.busy
                onClicked: root.removeApp(true)
              }
              TextButton {
                label: "Cancel"
                enabled: !root.busy
                onClicked: root.cancelDialog()
              }
            }
          }

          Text {
            visible: root.status !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.status
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      DropArea {
        z: -1
        anchors.fill: parent
        onEntered: function (drag) {
          if (!drag.hasUrls && !drag.hasText) return
          drag.accept(Qt.CopyAction)
          root.dragging = true
        }
        onExited: root.dragging = false
        onDropped: function (drop) {
          root.dragging = false
          var entries = []
          if (drop.hasUrls && drop.urls) {
            for (var i = 0; i < drop.urls.length; i++) entries.push(String(drop.urls[i]))
          } else if (drop.text) {
            var lines = String(drop.text).split("\n")
            for (var j = 0; j < lines.length; j++) if (lines[j]) entries.push(lines[j])
          }
          if (entries.length > 0) drop.accept(Qt.CopyAction)
          root.considerEntries(entries)
        }
      }
    }
  }
}
