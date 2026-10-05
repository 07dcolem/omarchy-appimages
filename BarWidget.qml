import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar chip. The icon is the drop target. Holding a file on it opens the panel.
BarWidget {
  id: root

  moduleName: "07dcolem.appimages"
  property var shell: null

  readonly property string pluginId: "07dcolem.appimages"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property int barSlot: Style.bar.iconSlot

  property bool dragHover: false

  // Set once the host has injected settings. Destruction before that must not
  // clear an association, and a reload must not either: --release turns the
  // association off only when this instance's token is still current.
  property bool settingsSeen: false
  property string associationToken: ""
  property double associationStamp: 0

  implicitWidth: bar && bar.vertical ? bar.barSize : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  // The bar host does not assign this widget's shell property. The scoped
  // summon/toggle handle lives on the bar facade (bar.shell).
  function hostShell() {
    if (shell && typeof shell.toggle === "function") return shell
    var viaBar = bar ? bar.shell : null
    if (viaBar && typeof viaBar.toggle === "function") return viaBar
    return null
  }

  function summon(payload) {
    var body = JSON.stringify(payload || {})
    var api = hostShell()
    if (api && typeof api.summon === "function") {
      api.summon(pluginId, body)
      return
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", pluginId, body])
  }

  function openScript() {
    var url = Qt.resolvedUrl("bin/omarchy-appimage-open").toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    try { url = decodeURIComponent(url) } catch (e) {}
    return url
  }

  function nextStamp() {
    var now = Date.now() * 1000
    if (now <= root.associationStamp) now = root.associationStamp + 1
    root.associationStamp = now
    return String(now)
  }

  function ensureToken() {
    if (root.associationToken) return root.associationToken
    var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    var token = ""
    for (var i = 0; i < 24; i++)
      token += alphabet.charAt(Math.floor(Math.random() * alphabet.length))
    root.associationToken = token
    return token
  }

  // Absence of openWithPanel is off. Apply only after settings exist so a
  // reload cannot --off a saved true before the new instance reads it.
  function applyAssociation() {
    var mode = Model.openWithPanelEnabled(root.settings) ? "on" : "off"
    Quickshell.execDetached([root.openScript(), "--apply", root.ensureToken(), mode, root.nextStamp()])
  }

  function releaseAssociation() {
    if (!root.settingsSeen || !root.associationToken) return
    Quickshell.execDetached([root.openScript(), "--release", root.associationToken])
  }

  onSettingsChanged: {
    root.settingsSeen = true
    root.applyAssociation()
  }

  Component.onDestruction: root.releaseAssociation()

  function togglePanel() {
    var api = hostShell()
    if (api) {
      api.toggle(pluginId, "{}")
      return
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", pluginId, "{}"])
  }

  function pathsFromDrop(drop) {
    var entries = []
    if (drop.hasUrls && drop.urls) {
      for (var i = 0; i < drop.urls.length; i++) entries.push(String(drop.urls[i]))
    } else if (drop.text) {
      var lines = String(drop.text).split("\n")
      for (var j = 0; j < lines.length; j++) {
        if (lines[j]) entries.push(lines[j])
      }
    }
    return entries
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barSlot
    opticalSize: Style.bar.iconCanvas
    tooltipText: "AppImages"
    active: root.dragHover
    useActiveColor: false

    iconComponent: Component {
      Item {
        Image {
          id: glyph
          anchors.centerIn: parent
          width: Style.bar.iconCanvas
          height: Style.bar.iconCanvas
          source: Qt.resolvedUrl("assets/icon.svg")
          sourceSize.width: Style.bar.iconCanvas
          sourceSize.height: Style.bar.iconCanvas
          visible: false
          fillMode: Image.PreserveAspectFit
        }

        ColorOverlay {
          anchors.fill: glyph
          source: glyph
          color: root.dragHover ? Color.accent : root.foreground
        }
      }
    }

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) root.togglePanel()
    }
  }

  DropArea {
    anchors.fill: parent

    onEntered: function (drag) {
      if (!drag.hasUrls && !drag.hasText) return
      drag.accept(Qt.CopyAction)
      root.dragHover = true
      spring.restart()
    }

    onExited: {
      root.dragHover = false
      spring.stop()
    }

    onDropped: function (drop) {
      root.dragHover = false
      spring.stop()
      var entries = root.pathsFromDrop(drop)
      if (entries.length > 0) drop.accept(Qt.CopyAction)
      root.summon({ entries: entries })
    }
  }

  Timer {
    id: spring
    interval: 450
    onTriggered: if (root.dragHover) root.summon({ drag: true })
  }
}
