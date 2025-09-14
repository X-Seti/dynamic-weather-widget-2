// ==============================
// === WEATHER EFFECTS LAYER ====
// ==============================
Item {
    id: weatherEffectsContainer
    anchors.fill: parent
    z: 1000

    // --- WIND DIRECTION HANDLER ---
    // We'll use the first weather entry's wind direction
    property real windDirection: actualWeatherModel.count > 0 ? actualWeatherModel.get(0).windDirection : 0

    // --- RAIN EFFECT ---
    Item {
        id: rainContainer
        anchors.fill: parent
        rotation: windDirection - 90  // Adjust: 0° = North → we want 0° = upward, so subtract 90

        ParticleSystem {
            id: rainSystem
            width: parent.width
            height: parent.height
            running: false

            ImageParticle {
                source: "qrc:/effects/raindrop.svg"
                colorVariation: 0.1
                alpha: 0.7
                size: 8
                sizeVariation: 3
                lifeSpan: 1500
                velocityFromAngle: 90       // Base direction: downward
                velocityFromMagnitude: 110
                velocityVariation: 30
            }

            Emitter {
                anchors.fill: parent
                emitRate: 150
                lifeSpan: 1500
                lifeSpanVariation: 200
            }
        }
    }

    // --- SNOW EFFECT ---
    Item {
        id: snowContainer
        anchors.fill: parent
        rotation: windDirection - 90  // Same logic: align snowfall with wind

        ParticleSystem {
            id: snowSystem
            width: parent.width
            height: parent.height
            running: false

            ImageParticle {
                source: "qrc:/effects/snowflake.svg"
                color: "#ffffff"
                alpha: 0.9
                size: 12
                sizeVariation: 4
                lifeSpan: 4000
                velocityFromAngle: 90
                velocityFromMagnitude: 15
                velocityVariation: 30
                rotationSpeed: 100
                rotationSpeedVariation: 50
            }

            Emitter {
                anchors.fill: parent
                emitRate: 60
                lifeSpan: 4000
                lifeSpanVariation: 500
            }
        }
    }

    // --- DAY/NIGHT OVERLAY (DIMMING) ---
    Rectangle {
        id: lightingOverlay
        anchors.fill: parent
        color: "black"
        opacity: 0
        z: 999

        Behavior on opacity {
            NumberAnimation {
                duration: 3000
                easing.type: Easing.InOutQuad
            }
        }

        opacity: {
            var cond = currentProvider ? currentProvider.currentCondition.toLowerCase() : ""
            var hour = new Date().getHours()

            if (cond.includes("snow") || cond.includes("sleet")) return 0.5
            else if (cond.includes("rain") || cond.includes("drizzle")) return 0.4
            else if (cond.includes("cloudy") || cond.includes("overcast")) return 0.3
            else if (hour >= 18 || hour < 6) return 0.6
            else return 0.0
        }
    }

    // --- SUBTLE SUN GLINT (NEW!) ---
    Item {
        id: sunGlint
        width: 40
        height: 40
        radius: 20
        color: "white"
        opacity: 0
        z: 1001 // Slightly above everything else
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        visible: !lightingOverlay.opacity && 
                 !((currentProvider && (
                     currentProvider.currentCondition.toLowerCase().includes("cloudy") ||
                     currentProvider.currentCondition.toLowerCase().includes("rain") ||
                     currentProvider.currentCondition.toLowerCase().includes("snow")
                 )))

        Behavior on opacity {
            NumberAnimation {
                duration: 1500
                easing.type: Easing.InOutQuad
            }
        }

        // Animate gently across the top
        SequentialAnimation on x {
            loops: Animation.Infinite
            running: visible
            PropertyAnimation { to: parent.width / 2 - 20; duration: 4000 }
            PropertyAnimation { to: parent.width / 2 + 20; duration: 4000 }
        }

        Timer {
            interval: 3000
            repeat: true
            running: visible
            onTriggered: {
                opacity = 0.9
                setTimeout(() => opacity = 0, 600)
            }
        }
    }

    // --- TRIGGER EFFECTS WHEN WEATHER OR WIND CHANGES ---
    Component.onCompleted: {
        if (!currentProvider) return

        // Watch for changes in condition
        currentProvider.onCurrentConditionChanged.connect(function() {
            var cond = currentProvider.currentCondition.toLowerCase()
            rainSystem.running = cond.includes("rain") || cond.includes("drizzle")
            snowSystem.running = cond.includes("snow") || cond.includes("sleet")
        })

        // Watch for changes in wind direction (via model)
        function updateWindEffect() {
            if (actualWeatherModel.count > 0) {
                windDirection = actualWeatherModel.get(0).windDirection
            }
        }

        // Initial call
        updateWindEffect()

        // Listen for model changes
        actualWeatherModel.onCountChanged.connect(updateWindEffect)
        actualWeatherModel.onDataChanged.connect(updateWindEffect)
    }
}
