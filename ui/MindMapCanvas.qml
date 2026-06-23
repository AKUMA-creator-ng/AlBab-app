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

    // Branch colors for visual distinction
    property var branchColors: ({
        "branch_0": "#E74C3C", "branch_1": "#3498DB", "branch_2": "#2ECC71",
        "branch_3": "#F39C12", "branch_4": "#9B59B6", "branch_5": "#1ABC9C",
        "branch_6": "#E67E22", "branch_7": "#E84393"
    })

    readonly property real hGap: 50
    readonly property real vGap: 10
    readonly property real nodePadding: 16
    readonly property real avgCharWidth: 7.0

    readonly property string threadColor: "#B48250"
    readonly property string nodeBg: Theme.contentBg
    readonly property string nodeBorder: Theme.divider
    readonly property string rootBg: "#B48250"
    readonly property string rootText: "#FFFFFF"

    // Tooltip for node descriptions
    Rectangle {
        id: tooltip
        z: 200
        visible: false
        width: tooltipText.implicitWidth + 20
        height: tooltipText.implicitHeight + 12
        radius: 8
        color: "#2A2A2A"
        border.color: "#555555"
        border.width: 1

        Text {
            id: tooltipText
            anchors.centerIn: parent
            width: 260
            color: "#EEEEEE"
            font.pixelSize: 11
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignLeft
        }

        function show(text, mx, my) {
            if (!text || text.length === 0) { visible = false; return }
            tooltipText.text = text
            var tx = mx + 15
            var ty = my - height - 5
            if (tx + width > scrollFlickable.contentX + scrollFlickable.width)
                tx = mx - width - 15
            if (ty < scrollFlickable.contentY)
                ty = my + 20
            tooltip.x = tx
            tooltip.y = ty
            visible = true
        }
    }

    function getNodeWidth(label, isRoot, depth) {
        var textW = label.length * avgCharWidth + nodePadding * 2
        if (isRoot) return Math.max(180, Math.min(textW, 260))
        if (depth === 1) return Math.max(140, Math.min(textW, 220))
        return Math.max(100, Math.min(textW, 180))
    }

    function getNodeHeight(isRoot, depth) {
        if (isRoot) return 48
        if (depth === 1) return 40
        return 34
    }

    function getBranchColor(nodeId) {
        // Walk up the tree to find which branch this node belongs to
        var node = allNodes[nodeId]
        if (!node) return threadColor
        var branchId = node.branchId || ""
        if (branchId && branchColors[branchId]) return branchColors[branchId]
        // Check if the node itself has a color from the AI
        if (node.color) return node.color
        return threadColor
    }

    function collectAllNodes(node, depth, branchId) {
        if (!node || !node.id) return
        var isRoot = node.id === "root"
        var myBranchId = branchId
        if (depth === 1) myBranchId = node.id

        allNodes[node.id] = {
            label: node.label || "",
            description: node.description || "",
            depth: depth,
            branchId: myBranchId,
            hasChildren: node.children && node.children.length > 0,
            childCount: node.children ? node.children.length : 0,
            color: node.color || "",
            w: getNodeWidth(node.label, isRoot, depth),
            h: getNodeHeight(isRoot, depth)
        }

        if (node.children) {
            for (var i = 0; i < node.children.length; i++) {
                collectAllNodes(node.children[i], depth + 1, myBranchId)
            }
        }
    }

    function measureVisible(node) {
        if (!node || !node.id) return 0
        var nd = allNodes[node.id]
        var isRoot = node.id === "root"
        if (collapsedNodes[node.id]) {
            return nd ? nd.h : getNodeHeight(isRoot, 0)
        }
        if (!node.children || node.children.length === 0) {
            return nd ? nd.h : getNodeHeight(isRoot, 0)
        }
        var childrenTotal = 0
        for (var i = 0; i < node.children.length; i++) {
            childrenTotal += measureVisible(node.children[i])
        }
        childrenTotal += (node.children.length - 1) * vGap
        var myH = nd ? nd.h : getNodeHeight(isRoot, 0)
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

        collectAllNodes(data, 0, "")
        nodeCount = Object.keys(allNodes).length

        relayout()

        nodeList.model = 0
        nodeList.model = nodeCount
    }

    function centerView() {
        var rootPos = nodePositions["root"]
        if (rootPos) {
            var cx = rootPos.x * zoomLevel - scrollFlickable.width / 3
            var cy = rootPos.y * zoomLevel - scrollFlickable.height / 2
            scrollFlickable.contentX = Math.max(0, Math.min(cx, scrollFlickable.contentWidth - scrollFlickable.width))
            scrollFlickable.contentY = Math.max(0, Math.min(cy, scrollFlickable.contentHeight - scrollFlickable.height))
        }
    }

    function fitToView() {
        if (canvasWidth === 0 || canvasHeight === 0) return
        var zx = scrollFlickable.width / (canvasWidth + 80)
        var zy = scrollFlickable.height / (canvasHeight + 80)
        zoomLevel = Math.max(0.3, Math.min(1.0, Math.min(zx, zy)))
        // Center after zoom
        scrollFlickable.contentX = (canvasWidth * zoomLevel - scrollFlickable.width) / 2
        scrollFlickable.contentY = (canvasHeight * zoomLevel - scrollFlickable.height) / 2
        canvas.requestPaint()
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
                    zoomLevel = Math.max(0.2, zoomLevel / 1.1)

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

                    // Use branch color for connections
                    var lineColor = getBranchColor(child.id)

                    ctx.beginPath()
                    ctx.strokeStyle = lineColor
                    ctx.lineWidth = 2.5
                    ctx.lineCap = "round"
                    ctx.globalAlpha = 0.6

                    var startX2 = pos.x + nd.w / 2
                    var startY2 = pos.y
                    var endX = childPos.x - childNd.w / 2
                    var endY = childPos.y

                    var midX = (startX2 + endX) / 2

                    ctx.moveTo(startX2, startY2)
                    ctx.bezierCurveTo(midX, startY2, midX, endY, endX, endY)
                    ctx.stroke()
                    ctx.globalAlpha = 1.0

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
                property string branchColor: getBranchColor(nodeId)
                property string nodeDescription: nd.description || ""

                x: isDragged ? nodeRect.x : (isVisible ? (pos.x || 0) * zoomLevel - (nd.w || 100) * zoomLevel / 2 : -500)
                y: isDragged ? nodeRect.y : (isVisible ? (pos.y || 0) * zoomLevel - (nd.h || 40) * zoomLevel / 2 : -500)
                width: (nd.w || 100) * zoomLevel
                height: (nd.h || 40) * zoomLevel
                radius: isRoot ? 24 : 20

                visible: true
                opacity: isVisible ? 1.0 : 0.0
                scale: isHovered ? 1.05 : 1.0

                color: {
                    if (isRoot) return rootBg
                    if (isBranch && nd.depth === 1) return branchColor
                    return nodeBg
                }
                border.color: {
                    if (isDragged) return branchColor
                    if (isHovered) return branchColor
                    if (isBranch && nd.depth === 1) return branchColor
                    return nodeBorder
                }
                border.width: isHovered ? 2 : 1
                z: isDragged ? 100 : (isRoot ? 10 : 1)

                Behavior on x { NumberAnimation { duration: isDragged ? 0 : 400; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: isDragged ? 0 : 400; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                // Colored left accent for branch nodes
                Rectangle {
                    visible: !nodeRect.isRoot && nodeRect.nd.depth === 1
                    width: 4 * zoomLevel
                    height: parent.height * 0.5
                    radius: 2 * zoomLevel
                    color: "#FFFFFF"
                    opacity: 0.3
                    anchors.left: parent.left
                    anchors.leftMargin: 8 * zoomLevel
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 4 * zoomLevel

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: nodeRect.nd.label || ""
                        color: {
                            if (nodeRect.isRoot) return rootText
                            if (nodeRect.isBranch && nodeRect.nd.depth === 1) return "#FFFFFF"
                            return Theme.textPrimary
                        }
                        font.pixelSize: (nodeRect.isRoot ? 14 : (nodeRect.nd.depth === 1 ? 12 : 11)) * zoomLevel
                        font.weight: nodeRect.isRoot ? Font.Bold : (nodeRect.nd.depth === 1 ? Font.DemiBold : Font.Medium)
                        width: nodeRect.width - (nodeRect.isBranch ? 32 : 16) * zoomLevel
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        verticalAlignment: Text.AlignVCenter
                    }

                    // Collapse/expand button
                    Rectangle {
                        visible: nodeRect.isBranch
                        width: 18 * zoomLevel; height: 18 * zoomLevel; radius: 9 * zoomLevel
                        color: nodeRect.isCollapsed ? (nodeRect.isRoot ? "#AAFFFFFF" : nodeRect.branchColor) : "transparent"
                        border.color: nodeRect.isRoot ? "#AAFFFFFF" : nodeRect.branchColor
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: nodeRect.isCollapsed ? "+" : "\u2212"
                            color: nodeRect.isCollapsed ? "#FFFFFF" : (nodeRect.isRoot ? "#AAFFFFFF" : nodeRect.branchColor)
                            font.pixelSize: 11 * zoomLevel
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: toggleCollapse(nodeId)
                        }
                    }
                }

                // Hover area for descriptions
                MouseArea {
                    id: nodeHoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    cursorShape: nodeRect.isBranch ? Qt.PointingHandCursor : Qt.ArrowCursor

                    onEntered: {
                        tooltip.show(nodeRect.nodeDescription, nodeRect.x + nodeRect.width / 2, nodeRect.y)
                    }
                    onExited: {
                        tooltip.visible = false
                    }
                    onPositionChanged: {
                        if (nodeRect.nodeDescription) {
                            tooltip.show(nodeRect.nodeDescription, mouseX, mouseY)
                        }
                    }
                }

                MouseArea {
                    id: nodeDragArea
                    anchors.fill: parent
                    drag.target: nodeRect
                    drag.axis: Drag.XAndY
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton

                    onPressed: function(mouse) {
                        // Store initial position for drag threshold
                        nodeRect._dragStartX = nodeRect.x
                        nodeRect._dragStartY = nodeRect.y
                    }

                    onPositionChanged: {
                        // Update canvas connections in real-time during drag
                        if (drag.active) {
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

                    onClicked: function(mouse) {
                        if (nodeRect.isBranch) {
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

    // Zoom controls
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        width: 36; height: 130
        radius: 18
        color: Theme.glassBase
        border.color: Theme.divider
        z: 50
        opacity: 0.9

        Column {
            anchors.centerIn: parent
            spacing: 4

            Rectangle {
                width: 28; height: 28; radius: 14
                color: zoomPlusMouse.containsMouse ? Theme.chipBg : Theme.inputBg
                border.color: Theme.divider
                anchors.horizontalCenter: parent.horizontalCenter
                Text { anchors.centerIn: parent; text: "+"; color: Theme.textPrimary; font.pixelSize: 14; font.weight: Font.Bold }
                MouseArea { id: zoomPlusMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: { zoomLevel = Math.min(3.0, zoomLevel * 1.2); canvas.requestPaint() } }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(zoomLevel * 100) + "%"
                color: Theme.textMuted
                font.pixelSize: 9
            }

            Rectangle {
                width: 28; height: 28; radius: 14
                color: zoomMinusMouse.containsMouse ? Theme.chipBg : Theme.inputBg
                border.color: Theme.divider
                anchors.horizontalCenter: parent.horizontalCenter
                Text { anchors.centerIn: parent; text: "\u2212"; color: Theme.textPrimary; font.pixelSize: 14; font.weight: Font.Bold }
                MouseArea { id: zoomMinusMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: { zoomLevel = Math.max(0.2, zoomLevel / 1.2); canvas.requestPaint() } }
            }

            // Separator
            Rectangle { width: 20; height: 1; color: Theme.divider; anchors.horizontalCenter: parent.horizontalCenter }

            // Fit to view
            Rectangle {
                width: 28; height: 28; radius: 14
                color: fitMouse.containsMouse ? Theme.chipBg : Theme.inputBg
                border.color: Theme.divider
                anchors.horizontalCenter: parent.horizontalCenter
                Text { anchors.centerIn: parent; text: "\u25A1"; color: Theme.textPrimary; font.pixelSize: 12 }
                MouseArea { id: fitMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: fitToView() }
            }

            // Reset
            Rectangle {
                width: 28; height: 28; radius: 14
                color: resetMouse.containsMouse ? Theme.chipBg : Theme.inputBg
                border.color: Theme.divider
                anchors.horizontalCenter: parent.horizontalCenter
                Text { anchors.centerIn: parent; text: "\u21BB"; color: Theme.textPrimary; font.pixelSize: 14 }
                MouseArea { id: resetMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: { resetZoom(); canvas.requestPaint() } }
            }
        }
    }
}