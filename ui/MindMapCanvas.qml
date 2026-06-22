import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property var treeData: null
    property var allNodes: ({})
    property var nodePositions: ({})
    property var collapsedNodes: ({})
    property real zoomLevel: 1.0
    property real canvasWidth: 800
    property real canvasHeight: 600
    property int nodeCount: 0

    readonly property real hGap: 60
    readonly property real vGap: 16
    readonly property real nodePadding: 20
    readonly property real avgCharWidth: 7.5

    readonly property string threadColor: "#B48250"
    readonly property string nodeBg: Theme.contentBg
    readonly property string nodeBorder: Theme.divider
    readonly property string rootBg: "#B48250"
    readonly property string rootText: "#FFFFFF"

    function getNodeWidth(label, isRoot) {
        var textW = label.length * avgCharWidth + nodePadding * 2
        var base = isRoot ? 180 : 150
        return Math.max(base, Math.min(textW, 240))
    }

    function getNodeHeight(isRoot) {
        return isRoot ? 48 : 40
    }

    function collectAllNodes(node, depth) {
        if (!node || !node.id) return
        var isRoot = node.id === "root"
        allNodes[node.id] = {
            label: node.label || "",
            depth: depth,
            hasChildren: node.children && node.children.length > 0,
            childCount: node.children ? node.children.length : 0,
            w: getNodeWidth(node.label, isRoot),
            h: getNodeHeight(isRoot)
        }
        if (node.children) {
            for (var i = 0; i < node.children.length; i++) {
                collectAllNodes(node.children[i], depth + 1)
            }
        }
    }

    function measureVisible(node) {
        if (!node || !node.id) return 0
        var nd = allNodes[node.id]
        var isRoot = node.id === "root"
        if (collapsedNodes[node.id]) {
            return nd ? nd.h : getNodeHeight(isRoot)
        }
        if (!node.children || node.children.length === 0) {
            return nd ? nd.h : getNodeHeight(isRoot)
        }
        var childrenTotal = 0
        for (var i = 0; i < node.children.length; i++) {
            childrenTotal += measureVisible(node.children[i])
        }
        childrenTotal += (node.children.length - 1) * vGap
        var myH = nd ? nd.h : getNodeHeight(isRoot)
        return Math.max(myH, childrenTotal)
    }

    function positionVisible(node, x, y, depth) {
        if (!node || !node.id) return
        var nd = allNodes[node.id]
        var w = nd ? nd.w : 150
        var h = nd ? nd.h : 40

        nodePositions[node.id] = { x: x, y: y, visible: true }

        if (collapsedNodes[node.id]) return
        if (!node.children || node.children.length === 0) return

        var totalChildHeight = 0
        var childHeights = []
        for (var i = 0; i < node.children.length; i++) {
            var ch = measureVisible(node.children[i])
            childHeights.push(ch)
            totalChildHeight += ch
        }
        totalChildHeight += (node.children.length - 1) * vGap

        var childStartY = y + h / 2 - totalChildHeight / 2
        var childX = x + w / 2 + hGap

        var cursorY = childStartY
        for (var j = 0; j < node.children.length; j++) {
            var child = node.children[j]
            if (!child || !child.id) continue
            var cy = cursorY + childHeights[j] / 2
            positionVisible(child, childX, cy, depth + 1)
            cursorY += childHeights[j] + vGap
        }
    }

    function hideAllPositions() {
        var keys = Object.keys(allNodes)
        for (var i = 0; i < keys.length; i++) {
            nodePositions[keys[i]] = { x: 0, y: 0, visible: false }
        }
    }

    function relayout() {
        nodePositions = {}
        hideAllPositions()
        if (!treeData) return
        var totalHeight = measureVisible(treeData)
        var rootW = allNodes["root"] ? allNodes["root"].w : 180
        var startX = rootW / 2 + 40
        var startY = totalHeight / 2 + 40
        positionVisible(treeData, startX, startY, 0)

        var maxX = 40
        var keys = Object.keys(allNodes)
        for (var i = 0; i < keys.length; i++) {
            var p = nodePositions[keys[i]]
            var nd = allNodes[keys[i]]
            if (p && p.visible && nd) {
                var right = p.x + nd.w / 2
                if (right > maxX) maxX = right
            }
        }
        canvasWidth = maxX + 120
        canvasHeight = totalHeight + 80
    }

    function buildTree(data) {
        treeData = data
        allNodes = {}
        collapsedNodes = {}
        nodePositions = {}

        collectAllNodes(data, 0)
        nodeCount = Object.keys(allNodes).length

        relayout()

        nodeList.model = 0
        nodeList.model = nodeCount
    }

    function centerView() {
        var rootPos = nodePositions["root"]
        if (rootPos) {
            scrollFlickable.contentX = rootPos.x * zoomLevel - scrollFlickable.width / 3
            scrollFlickable.contentY = rootPos.y * zoomLevel - scrollFlickable.height / 2
        }
    }

    function forceRepaint() {
        canvas.requestPaint()
    }

    function clear() {
        treeData = null
        allNodes = {}
        nodePositions = {}
        collapsedNodes = {}
        nodeCount = 0
        nodeList.model = 0
        canvas.requestPaint()
    }

    function toggleCollapse(nodeId) {
        if (collapsedNodes[nodeId]) {
            delete collapsedNodes[nodeId]
        } else {
            collapsedNodes[nodeId] = true
        }
        relayout()
        canvas.requestPaint()
    }

    function resetZoom() {
        zoomLevel = 1.0
        centerView()
    }

    Flickable {
        id: scrollFlickable
        anchors.fill: parent
        contentWidth: canvasWidth * zoomLevel
        contentHeight: canvasHeight * zoomLevel
        clip: true
        flickableDirection: Flickable.HorizontalAndVerticalFlick

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: function(wheel) {
                var oldZoom = zoomLevel
                if (wheel.angleDelta.y > 0)
                    zoomLevel = Math.min(3.0, zoomLevel * 1.1)
                else
                    zoomLevel = Math.max(0.3, zoomLevel / 1.1)

                var ratio = zoomLevel / oldZoom
                scrollFlickable.contentX = wheel.x * ratio - (wheel.x - scrollFlickable.contentX)
                scrollFlickable.contentY = wheel.y * ratio - (wheel.y - scrollFlickable.contentY)
                canvas.requestPaint()
            }
        }

        Canvas {
            id: canvas
            width: canvasWidth * zoomLevel
            height: canvasHeight * zoomLevel

            onPaint: {
                var ctx = getContext("2d")
                if (!ctx) return
                ctx.clearRect(0, 0, width, height)
                ctx.save()
                ctx.scale(zoomLevel, zoomLevel)
                drawConnections(ctx)
                ctx.restore()
            }

            function drawConnections(ctx) {
                if (!treeData) return
                drawNodeConnections(ctx, treeData)
            }

            function drawNodeConnections(ctx, node) {
                if (!node || !node.id) return
                var pos = nodePositions[node.id]
                if (!pos || !pos.visible) return
                if (collapsedNodes[node.id]) return
                if (!node.children) return

                var nd = allNodes[node.id]
                if (!nd) return

                for (var i = 0; i < node.children.length; i++) {
                    var child = node.children[i]
                    if (!child || !child.id) continue
                    var childPos = nodePositions[child.id]
                    var childNd = allNodes[child.id]
                    if (!childPos || !childPos.visible || !childNd) continue

                    ctx.beginPath()
                    ctx.strokeStyle = threadColor
                    ctx.lineWidth = 2.5
                    ctx.lineCap = "round"

                    var startX2 = pos.x + nd.w / 2
                    var startY2 = pos.y
                    var endX = childPos.x - childNd.w / 2
                    var endY = childPos.y

                    var midX = (startX2 + endX) / 2

                    ctx.moveTo(startX2, startY2)
                    ctx.bezierCurveTo(midX, startY2, midX, endY, endX, endY)
                    ctx.stroke()

                    drawNodeConnections(ctx, child)
                }
            }
        }

        Repeater {
            id: nodeList
            model: nodeCount

            Rectangle {
                id: nodeRect
                property string nodeId: {
                    var keys = Object.keys(allNodes)
                    return index < keys.length ? keys[index] : ""
                }
                property var nd: allNodes[nodeId] || ({})
                property var pos: nodePositions[nodeId] || ({})
                property bool isVisible: pos.visible === true
                property bool isRoot: nodeId === "root"
                property bool isBranch: nd.hasChildren === true
                property bool isCollapsed: collapsedNodes[nodeId] === true
                property bool isDragged: nodeDragArea.drag.active
                property bool isHovered: nodeHoverArea.containsMouse && !isDragged

                x: isVisible ? (pos.x || 0) * zoomLevel - (nd.w || 100) * zoomLevel / 2 : -200
                y: isVisible ? (pos.y || 0) * zoomLevel - (nd.h || 40) * zoomLevel / 2 : -200
                width: (nd.w || 100) * zoomLevel
                height: (nd.h || 40) * zoomLevel
                radius: 20

                visible: true
                opacity: isVisible ? 1.0 : 0.0
                scale: isHovered ? 1.04 : 1.0

                color: isRoot ? rootBg : nodeBg
                border.color: {
                    if (isDragged) return threadColor
                    if (isHovered) return threadColor
                    return nodeBorder
                }
                border.width: isHovered ? 2 : 1
                z: isDragged ? 100 : (isRoot ? 10 : 1)

                Behavior on x { NumberAnimation { duration: isDragged ? 0 : 350; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: isDragged ? 0 : 350; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: nodeRect.nd.label || ""
                        color: nodeRect.isRoot ? rootText : Theme.textPrimary
                        font.pixelSize: (nodeRect.isRoot ? 14 : 12) * zoomLevel
                        font.weight: nodeRect.isRoot ? Font.Bold : Font.DemiBold
                        width: nodeRect.width - (nodeRect.isBranch ? 36 : 16) * zoomLevel
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        visible: nodeRect.isBranch
                        width: 20 * zoomLevel; height: 20 * zoomLevel; radius: 10 * zoomLevel
                        color: nodeRect.isCollapsed ? threadColor : "transparent"
                        border.color: nodeRect.isRoot ? "#AAFFFFFF" : threadColor
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: nodeRect.isCollapsed ? "+" : "\u2212"
                            color: nodeRect.isCollapsed ? "#FFFFFF" : (nodeRect.isRoot ? "#AAFFFFFF" : threadColor)
                            font.pixelSize: 12 * zoomLevel
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: toggleCollapse(nodeId)
                        }
                    }
                }

                MouseArea {
                    id: nodeHoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    cursorShape: nodeRect.isBranch ? Qt.PointingHandCursor : Qt.ArrowCursor
                }

                MouseArea {
                    id: nodeDragArea
                    anchors.fill: parent
                    drag.target: nodeRect
                    drag.axis: Drag.XAndY
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: function(mouse) {
                        if (mouse.button === Qt.LeftButton && nodeRect.isBranch) {
                            toggleCollapse(nodeId)
                        }
                    }

                    onReleased: {
                        if (isDragged) {
                            var keys = Object.keys(allNodes)
                            if (index < keys.length) {
                                var nid = keys[index]
                                var p = nodePositions[nid]
                                if (p) {
                                    p.x = (nodeRect.x + nodeRect.width / 2) / zoomLevel
                                    p.y = (nodeRect.y + nodeRect.height / 2) / zoomLevel
                                    canvas.requestPaint()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        width: 120; height: 100
        radius: Theme.radiusSm
        color: Theme.glassBase
        border.color: Theme.divider
        z: 50
        opacity: 0.9

        Column {
            anchors.centerIn: parent
            spacing: 6

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: zoomPlusMouse.containsMouse ? Theme.chipBg : Theme.inputBg
                    border.color: Theme.divider
                    Text { anchors.centerIn: parent; text: "+"; color: Theme.textPrimary; font.pixelSize: 14; font.weight: Font.Bold }
                    MouseArea { id: zoomPlusMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: { zoomLevel = Math.min(3.0, zoomLevel * 1.2); canvas.requestPaint() } }
                }

                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: zoomMinusMouse.containsMouse ? Theme.chipBg : Theme.inputBg
                    border.color: Theme.divider
                    Text { anchors.centerIn: parent; text: "-"; color: Theme.textPrimary; font.pixelSize: 14; font.weight: Font.Bold }
                    MouseArea { id: zoomMinusMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: { zoomLevel = Math.max(0.3, zoomLevel / 1.2); canvas.requestPaint() } }
                }

                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: resetMouse.containsMouse ? Theme.chipBg : Theme.inputBg
                    border.color: Theme.divider
                    Text { anchors.centerIn: parent; text: "\u21BB"; color: Theme.textPrimary; font.pixelSize: 14 }
                    MouseArea { id: resetMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: { resetZoom(); canvas.requestPaint() } }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(zoomLevel * 100) + "%"
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeXs
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Click nodes to expand"
                color: Theme.textMuted
                font.pixelSize: 8
            }
        }
    }
}
