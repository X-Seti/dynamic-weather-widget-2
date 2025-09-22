// ==============================
// === DYNAMIC WALLPAPER CONTROL ===
// ==============================
Item {
    id: wallpaperController
    property real baseBrightness: 100   // Starting point
    property string currentWallpaperPath: ""  // Will be set later

    // Define your 4 wallpapers — adjust paths to match your system!
    property string morningWallpaper: "/home/x2/Wallpapers/System-Defaults/fruitdark.jpg"
    property string afternoonWallpaper: "/home/x2/Wallpapers/System-Defaults/fruit.jpg"
    property string eveningWallpaper: "/home/x2/Wallpapers/System-Defaults/fruitdarker.jpg"
    property string nightWallpaper: "/home/x2/Wallpapers/System-Defaults/fruitdarkest.jpg"

    // --- CALCULATE FINAL BRIGHTNESS & WALLPAPER ---
    // Combine time-of-day + weather condition for dynamic mood
    property real calculatedBrightness: {
        var hour = new Date().getHours()
        var cond = currentProvider ? currentProvider.currentCondition.toLowerCase() : ""

        // Base brightness by time (from your script)
        var timeBrightness = 100
        if (hour >= 6 && hour < 12) timeBrightness = 85
        else if (hour >= 12 && hour < 17) timeBrightness = 100
        else if (hour >= 17 && hour < 20) timeBrightness = 75
        else timeBrightness = 40

        // Adjust for weather
        var weatherAdjustment = 0
        if (cond.includes("snow")) weatherAdjustment = 10   // Snow adds soft glow
        else if (cond.includes("rain") || cond.includes("drizzle")) weatherAdjustment = -15
        else if (cond.includes("cloudy") || cond.includes("overcast")) weatherAdjustment = -20
        else if (cond.includes("clear") || cond.includes("sun")) weatherAdjustment = 5

        var final = Math.max(20, Math.min(100, timeBrightness + weatherAdjustment))
        return final
    }

    // --- SWITCH WALLPAPER BASED ON TIME ---
    property string selectedWallpaper: {
        var hour = new Date().getHours()
        if (hour >= 6 && hour < 12) return morningWallpaper
        else if (hour >= 12 && hour < 17) return afternoonWallpaper
        else if (hour >= 17 && hour < 20) return eveningWallpaper
        else return nightWallpaper
    }

    // --- APPLY WALLPAPER VIA PLASMA DBUS ---
    function applyWallpaperWithBrightness() {
        var wallpaperPath = selectedWallpaper

        // Check if file exists
        if (!Qt.os.contains("linux") || !Qt.canOpenFile(wallpaperPath)) {
            console.warn("Wallpaper not found or unsupported:", wallpaperPath)
            return
        }

        // Use ImageMagick to adjust brightness only if needed
        // We'll use a simple trick: if brightness != 100, create a temp adjusted version
        if (calculatedBrightness !== 100) {
            var tempPath = Qt.binding(function() {
                return Qt.resolvedUrl("file:///tmp/plasma-adjusted-wallpaper-" + plasmoid.id + ".jpg")
            })
            var cmd = "convert \"" + wallpaperPath + "\" -modulate 100," + calculatedBrightness + ",100 \"" + tempPath + "\""

            // Execute command asynchronously
            var process = new QtObject()
            process.execute = function(command) {
                var result = Qt.runCommand(command)
                return result
            }
            process.execute(cmd)

            // Wait briefly then use temp file
            setTimeout(function() {
                setPlasmaWallpaper(tempPath)
            }, 800)
        } else {
            // No adjustment needed
            setPlasmaWallpaper(wallpaperPath)
        }
    }

    // --- SET WALLPAPER VIA PLASMA DBUS ---
    function setPlasmaWallpaper(path) {
        if (!path || path === "") return

        // Escape path for JS string
        var escapedPath = path.replace(/"/g, '\\"')
        var script = `
            var allDesktops = desktops();
            for (i=0; i<allDesktops.length; i++) {
                d = allDesktops[i];
                d.wallpaperPlugin = 'org.kde.image';
                d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
                d.writeConfig('Image', 'file://${escapedPath}');
            }
        `

        try {
            qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript(script)
            console.log("Wallpaper updated to:", path, "with brightness", calculatedBrightness)
        } catch (e) {
            console.error("Failed to set wallpaper via DBus:", e.message)
        }
    }

    // --- INITIALIZE AND UPDATE ---
    Component.onCompleted: {
        // Initial call
        applyWallpaperWithBrightness()

        // Update every 5 minutes (or when weather/time changes)
        Timer {
            interval: 5 * 60 * 1000
            repeat: true
            running: true
            onTriggered: applyWallpaperWithBrightness()
        }

        // Also update on weather change
        if (currentProvider) {
            currentProvider.onCurrentConditionChanged.connect(applyWallpaperWithBrightness)
        }

        // Also update on time change (every minute)
        Timer {
            interval: 60 * 1000
            repeat: true
            running: true
            onTriggered: applyWallpaperWithBrightness()
        }
    }
}
