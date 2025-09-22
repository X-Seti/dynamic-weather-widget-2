/*
 * Copyright 2015  Martin Kotelnik <clearmartin@seznam.cz>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http: //www.gnu.org/licenses/>.
 */
import QtQuick
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Loader {
    id: compactRepresentation

    anchors.fill: parent

    property int defaultWidgetSize: -1

    sourceComponent: compactIteminTray

    CompactIteminTray {
        id: compactIteminTray
    }

    MouseArea {
        anchors.fill: parent

        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        hoverEnabled: true

        onClicked: {
            dbgprint("CompactRepresentationInTray")
            let t = main.expanded
            if (t) {
                dbgprint("Closing FullRepresentationInTray")
            } else {
                dbgprint("Opening FullRepresentationInTray")

            }
            if (mouse.button === Qt.MiddleButton) {
                loadingData.failedAttemptCount = 0
                main.loadDataFromInternet()
            } else {
                main.expanded = !main.expanded
            }
        }

        onEntered: main.refreshTooltipSubText()

    }
    Component.onCompleted: {
        if (main.inTray)
            layoutTimer1.start()
    }
    Timer {
        id: layoutTimer1
        interval: 100
        running: false
        repeat: false
        onTriggered: {
            if ((defaultWidgetSize === -1) && ( compactRepresentation.width > 0 ||  compactRepresentation.height)) {
                defaultWidgetSize = Math.min(compactRepresentation.width, compactRepresentation.height)
            }
        }
    }
}
