// ==============================
// === HOVER FEELS LIKE TOOLTIP ===
// ==============================
Item {
    id: feelsLikeTooltip
    width: 180
    height: 80
    visible: false
    z: 2000 // Always on top
    opacity: 0
    property real targetX: 0
    property real targetY: 0

    // Background with subtle blur
    Rectangle {
        anchors.fill: parent
        color: textColorLight ? "#111111" : "#eeeeee"
        radius: 12
        border.color: textColorLight ? "#333333" : "#dddddd"
        border.width: 1
        opacity: 0.95

        // Subtle inner glow for depth
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            color: "transparent"
            border.color: textColorLight ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.1)"
            border.width: 1
            radius: 11
        }
    }

    // Text content
    Column {
        anchors.centerIn: parent
        spacing: 2
        Text {
            text: i18n("Feels like %1°", atmosphereWidget.feelsLikeTemp)
            font.pixelSize: widgetFontSize * 0.75
            color: textColorLight ? "#ffffff" : "#111111"
            font.bold: true
        }
        Text {
            text: atmosphereWidget.comfortLevel + " • " + atmosphereWidget.weatherMood
            font.pixelSize: widgetFontSize * 0.65
            color: textColorLight ? "#cccccc" : "#555555"
        }
    }

    // Animation: Fade in/out
    Behavior on opacity {
        NumberAnimation {
            duration: 200
            easing.type: Easing.InOutQuad
        }
    }

    // Position: Centered above the temperature display
    x: atmosphereWidget.temperatureLabel.x + (atmosphereWidget.temperatureLabel.width - width) / 2
    y: atmosphereWidget.temperatureLabel.y - height - 10

    // Hide by default
    Component.onCompleted: {
        visible = false
        opacity = 0
    }
}

// --- MOUSE AREA TO TRIGGER TOOLTIP ---
MouseArea {
    id: tempHoverArea
    anchors.fill: temperatureLabel // <-- This assumes your main temp label is named 'temperatureLabel'
    hoverEnabled: true
    acceptedButtons: Qt.NoButton

    onEntered: {
        feelsLikeTooltip.visible = true
        feelsLikeTooltip.opacity = 1
    }

    onExited: {
        feelsLikeTooltip.opacity = 0
        setTimeout(function() {
            feelsLikeTooltip.visible = false
        }, 250)
    }
}
