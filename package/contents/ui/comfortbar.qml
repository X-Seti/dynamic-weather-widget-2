Rectangle {
    width: parent.width * 0.8
    height: 8
    radius: 4
    color: "black"
    opacity: 0.5
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: previousElement.bottom
    margin: 5

    Rectangle {
        width: parent.width * (feelsLikeTemp / 40) // Scale to 0–40°C
        height: parent.height
        radius: 4
        color: feelsLikeTemp < 10 ? "blue" :
               feelsLikeTemp < 20 ? "green" :
               feelsLikeTemp < 30 ? "yellow" : "red"
        anchors.left: parent.left
    }
}
