MouseArea {
    id: tempHoverArea
    anchors.fill: temperatureLabel
    hoverEnabled: true
    acceptedButtons: Qt.NoButton

    onEntered: {
        feelsLikeTooltip.visible = true
        feelsLikeTooltip.opacity = 1
    }

    onExited: {
        feelsLikeTooltip.opacity = 0
        setTimeout(() => feelsLikeTooltip.visible = false, 250)
    }

    // 👇 This is the key: follow mouse!
    onPositionChanged: {
        if (feelsLikeTooltip.visible) {
            feelsLikeTooltip.x = mouseX - feelsLikeTooltip.width / 2
            feelsLikeTooltip.y = mouseY - feelsLikeTooltip.height - 15
        }
    }
}
