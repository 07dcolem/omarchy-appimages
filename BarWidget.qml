import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.Commons
import qs.Ui

// Bar chip. The icon is the drop target. Holding a file on it opens the panel.
BarWidget {
  id: root

  moduleName: "07dcolem.appimages"
  property var shell: null

  readonly property string pluginId: "07dcolem.appimages"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property int barSlot: Style.bar.iconSlot

  property bool dragHover: false

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
