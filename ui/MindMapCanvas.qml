import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property var treeData: null
    property var allNodes: ({})
    property var nodePositions: ({})
    property var collapsedNodes: ({})
    property var dragOffsets: ({})  // Track user drag offsets per node
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

    readonly property real hGap: 60
    readonly property real vGap: 12
    readonly property real nodePadding: 16
    readonly property real avgCharWidth: 7.0

    readonly property string threadColor: "#B48250"
    readonly property string nodeBg: Theme.contentBg
    readonly property string nodeBorder: Theme.divider
    readonly property string rootBg: "#B48250"
    readonly property string rootText: "#FFFFFF"

    // Tooltip - parented to Flickable content so it scrolls with the canvas
    Rectangle {
        id: tooltip
        parent: canvasContainer
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

        function show(text, cx, cy) {
            if (!text || text.length === 0) { visible = false; return }
            tooltipText.text = text
            var tx = cx + 15
            var ty = cy - height - 5
            if (tx + width > canvasContainer.width)
                tx = cx - width - 15
            if (ty < 0)
                ty = cy + 20
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
        var node = allNodes[nodeId]
        if (!node) return threadColor
        var branchId = node.branchId || ""
        if (branchId && branchColors[branchId]) return branchColors[branchId]
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

        // Apply any user drag offset
        var offsetX = dragOffsets[node.id] ? dragOffsets[node.id].x : 0
        var offsetY = dragOffsets[node.id] ? dragOffsets[node.id].y : 0
        nodePositions[node.id] = { x: x + offsetX, y: y + offsetY, visible: true }

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
        var startX = rootW / 2 + 60
        var startY = totalHeight / 2 + 60
        positionVisible(treeData, startX, startY, 0)

        var maxX = 60
        var keys = Object.keys(allNodes)
        for (var i = 0; i < keys.length; i++) {
            var p = nodePositions[keys[i]]
            var nd = allNodes[keys[i]]
            if (p && p.visible && nd) {
                var right = p.x + nd.w / 2
                if (right > maxX) maxX = right
            }
        }
        canvasWidth = maxX + 160
        canvasHeight = totalHeight + 120
    }

    function buildTree(data) {
        treeData = data
        allNodes = {}
        collapsedNodes = {}
        dragOffsets = {}  // Reset drag offsets on new tree
        nodePositions = {}

        collectAllNodes(data, 0, "")
        nodeCount = Object.keys(allNodes).length

        relayout()

        nodeList.model = 0
        nodeList.model = nodeCount
    }

    function centerView() {
        var rootPos = nodePositions["root"]
        if (!rootPos) return
        var contentW = scrollFlickable.contentWidth
        var contentH = scrollFlickable.contentHeight
        var viewW = scrollFlickable.width
        var viewH = scrollFlickable.height

        // Guard against NaN when content is smaller than view
        if (contentW <= viewW) {
            scrollFlickable.contentX = (contentW - viewW) / 2
        } else {
            var cx = rootPos.x * zoomLevel - viewW / 3
            scrollFlickable.contentX = Math.max(0, Math.min(cx, contentW - viewW))
        }
        if (contentH <= viewH) {
            scrollFlickable.contentY = (contentH - viewH) / 2
        } else {
            var cy = rootPos.y * zoomLevel - viewH / 2
            scrollFlickable.contentY = Math.max(0, Math.min(cy, contentH - viewH))
        }
    }

    function fitToView() {
        if (canvasWidth === 0 || canvasHeight === 0) return
        var zx = scrollFlickable.width / (canvasWidth + 80)
        var zy = scrollFlickable.height / (canvasHeight + 80)
        zoomLevel = Math.max(0.15, Math.min(1.0, Math.min(zx, zy)))
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
        dragOffsets = {}
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
        canvas.requestPaint()
    }

    function expandAll() {
        collapsedNodes = {}
        relayout()
        fitToView()
    }

    function collapseAll() {
        var keys = Object.keys(allNodes)
        for (var i = 0; i < keys.length; i++) {
            var nd = allNodes[keys[i]]
            if (nd && nd.hasChildren && keys[i] !== "root") {
                collapsedNodes[keys[i]] = true
            }
        }
        relayout()
        fitToView()
    }

    // Right-click context menu
    Menu {
        id: contextMenu

        property string contextNodeId: ""

        MenuItem {
            text: contextMenu.contextNodeId === "root" ? "Collapse All" : "Toggle Branch"
            onTriggered: {
                if (contextMenu.contextNodeId === "root") {
                    collapseAll()
                } else {
                    toggleCollapse(contextMenu.contextNodeId)
                }
            }
        }
        MenuSeparator {}
        MenuItem {
            text: "Expand All"
            onTriggered: expandAll()
        }
        MenuItem {
            text: "Collapse All"
            onTriggered: collapseAll()
        }
        MenuSeparator {}
        MenuItem {
            text: "Reset Position"
            onTriggered: {
                delete dragOffsets[contextMenu.contextNodeId]
                relayout()
                canvas.requestPaint()
            }
        }
        MenuItem {
            text: "Fit to View"
            onTriggered: fitToView()
        }
    }

    Flickable {
        id: scrollFlickable
        anchors.fill: parent
        contentWidth: canvasWidth * zoomLevel
        contentHeight: canvasHeight * zoomLevel
        clip: true
        flickableDirection: Flickable.HorizontalAndVerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        // Canvas background
        Rectangle {
            id: bgRect
            anchors.fill: parent
            color: Theme.canvasBg
        }

        // Zoom with scroll wheel - on a passive MouseArea that doesn't steal flick events
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: function(wheel) {
                var oldZoom = zoomLevel
                if (wheel.angleDelta.y > 0)
                    zoomLevel = Math.min(3.0, zoomLevel * 1.12)
                else
                    zoomLevel = Math.max(0.15, zoomLevel / 1.12)

                // Zoom toward cursor position
                var ratio = zoomLevel / oldZoom
                scrollFlickable.contentX = wheel.x * ratio - (wheel.x - scrollFlickable.contentX)
                scrollFlickable.contentY = wheel.y * ratio - (wheel.y - scrollFlickable.contentY)
                canvas.requestPaint()
            }
        }

        Item {
            id: canvasContainer
            width: canvasWidth * zoomLevel
            height: canvasHeight * zoomLevel

            Canvas {
                id: canvas
                anchors.fill: parent

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

                        var sx = pos.x + nd.w / 2
                        var sy = pos.y
                        var ex = childPos.x - childNd.w / 2
                        var ey = childPos.y

                        var midX = (sx + ex) / 2

                        ctx.moveTo(sx, sy)
                        ctx.bezierCurveTo(midX, sy, midX, ey, ex, ey)
                        ctx.stroke()
                        ctx.globalAlpha = 1.0

                        // Draw collapsed indicator
                        if (collapsedNodes[child.id] && childNd.hasChildren) {
                            var indicatorX = ex
                            var indicatorY = ey
                            ctx.beginPath()
                            ctx.arc(indicatorX - 6, indicatorY, 8, 0, 2 * Math.PI)
                            ctx.fillStyle = lineColor
                            ctx.globalAlpha = 0.15
                            ctx.fill()
                            ctx.globalAlpha = 1.0
                            ctx.strokeStyle = lineColor
                            ctx.lineWidth = 1.5
                            ctx.stroke()

                            // Draw "..." or count
                            ctx.fillStyle = lineColor
                            ctx.font = "bold 9px sans-serif"
                            ctx.textAlign = "center"
                            ctx.textBaseline = "middle"
                            ctx.fillText(childNd.childCount + "", indicatorX - 6, indicatorY)
                        }

                        drawNodeConnections(ctx, child)
                    }
                }
            }

            // Nodes rendered as children of canvasContainer (scaled coordinates)
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
                    property string branchColor: getBranchColor(nodeId)
                    property string nodeDescription: nd.description || ""

                    // Position in scaled space (canvasContainer is already sized to zoomLevel)
                    x: isVisible ? (pos.x || 0) * zoomLevel - (nd.w || 100) * zoomLevel / 2 : -9999
                    y: isVisible ? (pos.y || 0) * zoomLevel - (nd.h || 40) * zoomLevel / 2 : -9999
                    width: (nd.w || 100) * zoomLevel
                    height: (nd.h || 40) * zoomLevel
                    radius: isRoot ? 24 : 20

                    visible: true
                    opacity: isVisible ? 1.0 : 0.0

                    color: {
                        if (isRoot) return rootBg
                        if (isBranch && nd.depth === 1) return branchColor
                        return nodeBg
                    }
                    border.color: {
                        if (isBranch && nd.depth === 1) return Qt.darker(branchColor, 1.1)
                        return nodeBorder
                    }
                    border.width: 1
                    z: isRoot ? 10 : 1

                    Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

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

                        // Collapse/expand indicator
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

                    // Single MouseArea for hover + click + right-click + drag
                    // Uses pressAndHold threshold to distinguish click from drag
                    MouseArea {
                        id: nodeInteraction
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: nodeRect.isBranch ? Qt.PointingHandCursor : Qt.ArrowCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        drag.target: nodeRect
                        drag.axis: Drag.XAndY
                        drag.threshold: 10

                        property real pressX: 0
                        property real pressY: 0
                        property bool wasDragged: false

                        onPressed: function(mouse) {
                            pressX = mouse.x
                            pressY = mouse.y
                            wasDragged = false

                            if (mouse.button === Qt.RightButton) {
                                mouse.accepted = true
                                contextMenu.contextNodeId = nodeId
                                contextMenu.popup()
                                return
                            }
                        }

                        onPositionChanged: function(mouse) {
                            // Show tooltip on hover
                            if (!drag.active && nodeRect.nodeDescription) {
                                // Convert to canvasContainer coordinates
                                var globalX = nodeRect.x + mouse.x
                                var globalY = nodeRect.y + mouse.y
                                tooltip.show(nodeRect.nodeDescription, globalX, globalY)
                            }

                            // Track if this is a significant drag
                            if (drag.active) {
                                var dx = mouse.x - pressX
                                var dy = mouse.y - pressY
                                if (Math.abs(dx) > 5 || Math.abs(dy) > 5) {
                                    wasDragged = true
                                }
                            }
                        }

                        onClicked: function(mouse) {
                            if (mouse.button === Qt.RightButton) return
                            // Only toggle collapse if it wasn't a drag
                            if (!wasDragged && nodeRect.isBranch) {
                                toggleCollapse(nodeId)
                            }
                        }

                        onReleased: function(mouse) {
                            if (mouse.button === Qt.RightButton) return
                            // If dragged, save the offset for relayout persistence
                            if (wasDragged) {
                                var keys = Object.keys(allNodes)
                                if (index < keys.length) {
                                    var nid = keys[index]
                                    var origPos = nodePositions[nid]
                                    if (origPos) {
                                        var newX = (nodeRect.x + nodeRect.width / 2) / zoomLevel
                                        var newY = (nodeRect.y + nodeRect.height / 2) / zoomLevel
                                        dragOffsets[nid] = {
                                            x: newX - origPos.x + (dragOffsets[nid] ? dragOffsets[nid].x : 0),
                                            y: newY - origPos.y + (dragOffsets[nid] ? dragOffsets[nid].y : 0)
                                        }
                                        // Update the position directly so connections follow
                                        nodePositions[nid].x = newX
                                        nodePositions[nid].y = newY
                                        canvas.requestPaint()
                                    }
                                }
                            }
                        }

                        onEntered: {
                            nodeRect.scale = 1.03
                        }
                        onExited: {
                            nodeRect.scale = 1.0
                            tooltip.visible = false
                        }
                    }

                    // Smooth scale animation
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    // Zoom controls
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        width: 36; height: 150
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
                MouseArea { id: zoomMinusMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: { zoomLevel = Math.max(0.15, zoomLevel / 1.2); canvas.requestPaint() } }
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

            // Expand/Collapse all
            Rectangle {
                width: 28; height: 28; radius: 14
                color: expandMouse.containsMouse ? Theme.chipBg : Theme.inputBg
                border.color: Theme.divider
                anchors.horizontalCenter: parent.horizontalCenter
                Text { anchors.centerIn: parent; text: "\u2261"; color: Theme.textPrimary; font.pixelSize: 14 }
                MouseArea { id: expandMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: expandAll() }
            }

            // Reset
            Rectangle {
                width: 28; height: 28; radius: 14
                color: resetMouse.containsMouse ? Theme.chipBg : Theme.inputBg
                border.color: Theme.divider
                anchors.horizontalCenter: parent.horizontalCenter
                Text { anchors.centerIn: parent; text: "\u21BB"; color: Theme.textPrimary; font.pixelSize: 14 }
                MouseArea { id: resetMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: { resetZoom() } }
            }
        }
    }
}