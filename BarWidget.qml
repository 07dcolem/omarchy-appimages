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
  readonly property bool showLabel: !(bar && bar.vertical)
  readonly property int labelWidth: showLabel ? Style.space(78) : 0
  readonly property int contentWidth: Style.bar.iconCanvas + labelWidth + (showLabel ? Style.space(6) : 0)
  readonly property int barSlot: contentWidth + Style.space(10)

  property bool dragHover: false

  implicitWidth: bar && bar.vertical ? bar.barSize : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  function summon(payload) {
    if (!shell || typeof shell.summon !== "function") return
    shell.summon(pluginId, JSON.stringify(payload || {}))
  }

  function togglePanel() {
    if (shell && typeof shell.toggle === "function")
      shell.toggle(pluginId, "{}")
    else
      summon({})
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
    opticalSize: root.contentWidth
    tooltipText: "AppImages"
    active: root.dragHover
    useActiveColor: false

    iconComponent: Component {
      Item {
        Image {
          id: glyph
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
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

        Text {
          visible: root.showLabel
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: glyph.right
          anchors.leftMargin: Style.space(6)
          text: "AppImages"
          color: root.dragHover ? Color.accent : root.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
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
