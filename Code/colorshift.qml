Text {
    text: i18n("Feels like %1°", feelsLikeTemp)
    font.pixelSize: widgetFontSize * 0.7
    color: textColorLight ? "#000000" : "#ffffff"
    anchors.top: parent.bottom
    anchors.left: parent.left
    margin: 5
}

Text {
    text: comfortLevel + " • " + weatherMood
    font.pixelSize: widgetFontSize * 0.6
    color: textColorLight ? "#aaaaaa" : "#cccccc"
    anchors.top: previousElement.bottom
    anchors.left: parent.left
    margin: 2
}
