FontIcon {
    id: feelsLikeIcon
    text: IconTools.getIconCode("feelslike", "owm", getPartOfDayIndex())
    font.family: "weathericons"
    font.pixelSize: widgetFontSize * 0.8
    color: textColorLight ? "#000000" : "#ffffff"
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right
    margins: 5
}
