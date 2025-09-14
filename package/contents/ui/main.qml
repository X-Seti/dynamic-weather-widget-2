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
import QtQuick 2.2
import QtQuick.Layouts 1.1
import QtQuick.Particles 2.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import QtQuick.Controls 1.0
import "../code/data-loader.js" as DataLoader
import "../code/config-utils.js" as ConfigUtils
import "../code/icons.js" as IconTools
import "../code/unit-utils.js" as UnitUtils
import "providers"

Item {
    id: main

    property string placeIdentifier
    property string placeAlias
    property string cacheKey
    property int timezoneID
    property string timezoneShortName
    property int timezoneOffset
    property var cacheMap: {}
    property bool renderMeteogram: plasmoid.configuration.renderMeteogram
    property int temperatureType: plasmoid.configuration.temperatureType
    property int pressureType: plasmoid.configuration.pressureType
    property int windSpeedType: plasmoid.configuration.windSpeedType
    property int timezoneType: plasmoid.configuration.timezoneType
    property string widgetFontName: plasmoid.configuration.widgetFontName
    property int widgetFontSize: plasmoid.configuration.widgetFontSize

    property bool twelveHourClockEnabled: Qt.locale().timeFormat(Locale.ShortFormat).toString().indexOf('AP') > -1
    property string placesJsonStr: plasmoid.configuration.places
    property bool onlyOnePlace: true

    property string datetimeFormat: 'yyyy-MM-dd\'T\'hh:mm:ss'
    property var xmlLocale: Qt.locale('en_GB')
    property var additionalWeatherInfo: {}


    property string overviewImageSource
    property string creditLink
    property string creditLabel

    property int reloadIntervalMin: plasmoid.configuration.reloadIntervalMin   // Download Attempt Frequency in minutes
    property int reloadIntervalMs: reloadIntervalMin * 60 * 1000               // Download Attempt Frequency in milliseconds

    // === SUNRISE/SUNSET API MANAGER ===

    property string sunriseSunsetUrl: "https://api.sunrise-sunset.org/json?lat=" + latitude + "&lng=" + longitude + "&formatted=0"
    property real latitude: 0
    property real longitude: 0
    property date localSunrise: new Date(0)
    property date localSunset: new Date(0)
    property bool hasSunData: false
    property int lastSunUpdate: 0 // timestamp of last successful fetch

    function fetchSunriseSunset() {
        if (!plasmoid.configuration.useSunriseSunset) return

        var xhr = new XMLHttpRequest()
        xhr.open("GET", sunriseSunsetUrl, true)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        if (data.status === "OK") {
                            // Parse ISO8601 strings into Date objects
                            var sunriseUTC = new Date(data.results.sunrise)
                            var sunsetUTC = new Date(data.results.sunset)

                            // Convert UTC to local time using timezoneOffset
                            var offsetMs = timezoneOffset * 60 * 1000 // offset in milliseconds
                            localSunrise = new Date(sunriseUTC.getTime() + offsetMs)
                            localSunset = new Date(sunsetUTC.getTime() + offsetMs)

                            // Log for debugging
                            dbgprint("Sunrise: " + Qt.formatDateTime(localSunrise, Qt.DefaultLocaleShortDate))
                            dbgprint("Sunset: " + Qt.formatDateTime(localSunset, Qt.DefaultLocaleShortDate))

                            hasSunData = true
                            lastSunUpdate = Date.now()

                            // Trigger wallpaper and effect updates
                            applyWallpaperWithBrightness()
                            updateAdditionalWeatherInfoText()
                        }
                    } catch (e) {
                        dbgprint("Error parsing sunrise/sunset API: " + e.message)
                        hasSunData = false
                    }
                } else {
                    dbgprint("Sunrise/sunset API request failed: " + xhr.status)
                    hasSunData = false
                }
            }
        }
        xhr.send()
    }

    // --- INITIALIZE LOCATION ---
    Component.onCompleted: {
        // Try to get location from system (if available)
        var loc = PlasmaCore.LocationSource()
        loc.start()
        loc.onLocationChanged = function(location) {
            if (location.latitude !== undefined && location.longitude !== undefined) {
                latitude = location.latitude
                longitude = location.longitude
                dbgprint("Location acquired: " + latitude + ", " + longitude)
                fetchSunriseSunset()
            }
        }

        // Fallback: Use default location if none found (you can set this manually)
        if (latitude === 0 && longitude === 0) {
            // Example: Replace with your city's coordinates (get them from Google Maps)
            latitude = 45.5089  // Portland, OR
            longitude = -122.678
            dbgprint("Using fallback coordinates: " + latitude + ", " + longitude)
            fetchSunriseSunset()
        }

        // Update every 6 hours (21600000 ms), or when weather changes
        Timer {
            interval: 21600000 // 6 hours
            repeat: true
            running: true
            onTriggered: {
                if (hasSunData && Date.now() - lastSunUpdate > 3600000) { // Only if stale
                    fetchSunriseSunset()
                }
            }
        }

        // Also trigger on weather change
        if (currentProvider) {
            currentProvider.onCurrentConditionChanged.connect(fetchSunriseSunset)
        }
    }

    property double lastloadingStartTime: 0       // Time download last attempted.
    property double lastloadingSuccessTime: 0     // Time download last successful.
    property double nextReload: 0                 // Time next download is due.

    property bool loadingData: false              // Download Attempt in progress Flag.
    property int loadingDataTimeoutMs: 15000      // Download Timeout in ms.
    property var loadingXhrs: []                  // Array of Download Attempt Objects
    property bool loadingError: false             // Whether the last Download Attempt was successful
    property bool imageLoadingError: true
    property bool alreadyLoadedFromCache: false

    property string lastReloadedText: '⬇ 0m ago'
    property string tooltipSubText: ''

    property bool vertical: (plasmoid.formFactor == PlasmaCore.Types.Vertical)
    property bool onDesktop: (plasmoid.location == PlasmaCore.Types.Desktop || plasmoid.location == PlasmaCore.Types.Floating)
    property bool inTray: false
    property string plasmoidCacheId: plasmoid.id

    property int inTrayActiveTimeoutSec: plasmoid.configuration.inTrayActiveTimeoutSec

    property int nextDaysCount: 8

    property bool textColorLight: ((theme.textColor.r + theme.textColor.g + theme.textColor.b) / 3) > 0.5

    // 0 - standard
    // 1 - vertical
    // 2 - compact
    property int layoutType: plasmoid.configuration.layoutType

    property bool updatingPaused: true

    property var currentProvider: null

    property bool meteogramModelChanged: false

    anchors.fill: parent

    property Component crInTray: CompactRepresentationInTray { }
    property Component cr: CompactRepresentation { }

    property Component frInTray: FullRepresentationInTray { }
    property Component fr: FullRepresentation { }

    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation
    Plasmoid.compactRepresentation: cr
    Plasmoid.fullRepresentation: fr

        // --- FEELS LIKE TEMPERATURE ---
    property real feelsLikeTemp: {
        var temp = actualWeatherModel.count > 0 ? actualWeatherModel.get(0).temperature : 0
        var windSpeed = actualWeatherModel.count > 0 ? actualWeatherModel.get(0).windSpeedMps : 0
        var humidity = actualWeatherModel.count > 0 ? actualWeatherModel.get(0).humidity : 0

        // Wind chill (if temp < 10°C and wind > 3km/h)
        var windChill = temp
        if (temp <= 10 && windSpeed > 0.83) { // 3km/h ≈ 0.83m/s
            windChill = 13.12 + 0.6215 * temp - 11.37 * Math.pow(windSpeed, 0.16) + 0.3965 * temp * Math.pow(windSpeed, 0.16)
        }

        // Humidity effect (if temp > 15°C)
        var humidityEffect = 0
        if (temp > 15 && humidity > 70) {
            humidityEffect = (humidity - 70) / 10
        }

        return Math.round(windChill + humidityEffect)
    }

    // --- COMFORT LEVEL ---
    property string comfortLevel: {
        var temp = actualWeatherModel.count > 0 ? actualWeatherModel.get(0).temperature : 0
        var windSpeed = actualWeatherModel.count > 0 ? actualWeatherModel.get(0).windSpeedMps : 0
        var humidity = actualWeatherModel.count > 0 ? actualWeatherModel.get(0).humidity : 0

        if (temp < 5) return "Freezing"
        else if (temp < 10) return "Cold"
        else if (temp < 15) return "Cool"
        else if (temp < 20) return "Comfortable"
        else if (temp < 25) return "Warm"
        else if (temp < 30) return "Hot"
        else return "Very Hot"
    }

    // --- WEATHER MOOD ---
    property string weatherMood: {
        var windSpeed = actualWeatherModel.count > 0 ? actualWeatherModel.get(0).windSpeedMps : 0
        var cond = currentProvider ? currentProvider.currentCondition.toLowerCase() : ""

        if (cond.includes("storm") || cond.includes("thunder")) return "Stormy"
        else if (windSpeed > 15) return "Gusty"
        else if (windSpeed > 8) return "Breezy"
        else if (cond.includes("rain") || cond.includes("drizzle")) return "Wet"
        else if (cond.includes("snow")) return "Snowy"
        else if (cond.includes("cloudy") || cond.includes("overcast")) return "Overcast"
        else return "Calm"
    }

    property bool debugLogging: plasmoid.configuration.debugLogging

    FontLoader {
        source: '../fonts/weathericons-regular-webfont-2.0.10.ttf'
    }

    MetNo {
        id: metnoProvider
    }

    OpenWeatherMap {
        id: owmProvider
    }

    ListModel {
        id: actualWeatherModel
    }

    ListModel {
        id: nextDaysModel
    }

    ListModel {
        id: meteogramModel
    }

    function action_toggleUpdatingPaused() {
        updatingPaused = !updatingPaused
        abortTooLongConnection(true)
        plasmoid.setAction('toggleUpdatingPaused', updatingPaused ? i18n("Resume Updating") : i18n("Pause Updating"), updatingPaused ? 'media-playback-start' : 'media-playback-pause');
    }

    WeatherCache {
        id: weatherCache
        cacheId: plasmoidCacheId
    }

     PlasmaCore.DataSource {
        id: dataSource
        engine: "time"
        connectedSources: ["Local"]
        interval: 0
    }

    Component.onCompleted: {
        if (plasmoid.configuration.firstRun) {
            if (plasmoid.configuration.widgetFontSize === undefined) {
                plasmoid.configuration.widgetFontSize = 32
                widgetFontSize = 32
            }
            switch (Qt.locale().measurementSystem) {
                case (Locale.MetricSystem):
                  plasmoid.configuration.temperatureType = 0
                  plasmoid.configuration.pressureType = 0
                  plasmoid.configuration.windSpeedType = 2
                  break;
                case (Locale.ImperialUSSystem):
                  plasmoid.configuration.temperatureType = 1
                  plasmoid.configuration.pressureType = 1
                  plasmoid.configuration.windSpeedType = 1
                  break;
                case (Locale.ImperialUKSystem):
                  plasmoid.configuration.temperatureType = 0
                  plasmoid.configuration.pressureType = 0
                  plasmoid.configuration.windSpeedType = 1
                  break;
            }
            plasmoid.configuration.firstRun = false
        }
        inTray = (plasmoid.parent !== null && (plasmoid.parent.pluginName === 'org.kde.plasma.private.systemtray' || plasmoid.parent.objectName === 'taskItemContainer'))
        plasmoidCacheId = inTray ? plasmoid.parent.id : plasmoid.id
        dbgprint('inTray=' + inTray + ', plasmoidCacheId=' + plasmoidCacheId)

        additionalWeatherInfo = {
            sunRise: new Date('2000-01-01T00:00:00'),
            sunSet: new Date('2000-01-01T00:00:00'),
            sunRiseTime: '0:00',
            sunSetTime: '0:00',
            nearFutureWeather: {
                iconName: null,
                temperature: null
            }
        }

        // systray settings
        if (inTray) {
            Plasmoid.compactRepresentation = crInTray
            Plasmoid.fullRepresentation = frInTray
        }

        // init contextMenu
        action_toggleUpdatingPaused()

        var cacheContent = weatherCache.readCache()

        // fill xml cache xml
        if (cacheContent) {
            try {
                cacheMap = JSON.parse(cacheContent)
                dbgprint('cacheMap initialized - keys:')
                for (var key in cacheMap) {
                    dbgprint('  ' + key + ', data: ' + cacheMap[key])
                }
            } catch (error) {
                dbgprint('error parsing cacheContent')
            }
        }
        cacheMap = cacheMap || {}

// set initial place
        setNextPlace(true)
    }

    onTimezoneShortNameChanged: {
        refreshTooltipSubText()
    }

    onPlacesJsonStrChanged: {
        if (placesJsonStr === '') {
            return
        }
        onlyOnePlace = ConfigUtils.getPlacesArray().length === 1
        setNextPlace(true)
    }

    function showData() {
        var ok = loadFromCache()
        if (!ok) {
            reloadData()
        }
        updateLastReloadedText()
        reloadMeteogram()
    }

    function setCurrentProviderAccordingId(providerId) {
        if (providerId === 'owm') {
            dbgprint('setting provider OpenWeatherMap')
            currentProvider = owmProvider
        }
        if (providerId === "metno") {
            dbgprint('setting provider metno')
            currentProvider = metnoProvider
        }
     }

    function setNextPlace(initial,direction) {
        actualWeatherModel.clear()
        nextDaysModel.clear()
        meteogramModel.clear()
        if (direction === undefined) {
          direction = "+"
        }

        var places = ConfigUtils.getPlacesArray()
        onlyOnePlace = places.length === 1
        dbgprint('places count=' + places.length + ', placeIndex=' + plasmoid.configuration.placeIndex)
        var placeIndex = plasmoid.configuration.placeIndex
        if (!initial) {
            (direction === "+") ? placeIndex++ :placeIndex--
        }
        if (placeIndex > places.length - 1) {
            placeIndex = 0
        }
        if (placeIndex < 0 ) {
            placeIndex = places.length - 1
        }
        plasmoid.configuration.placeIndex = placeIndex
        dbgprint('placeIndex now: ' + plasmoid.configuration.placeIndex)
        var placeObject = places[placeIndex]
        placeIdentifier = placeObject.placeIdentifier
        placeAlias = placeObject.placeAlias
        if (placeObject.timezoneID  === undefined ) {
          placeObject.timezoneID = -1
        }
        timezoneID = parseInt(placeObject.timezoneID)
        dbgprint('next placeIdentifier is: ' + placeIdentifier)
        cacheKey = DataLoader.generateCacheKey(placeIdentifier)
        dbgprint('next cacheKey is: ' + cacheKey)

        alreadyLoadedFromCache = false

        setCurrentProviderAccordingId(placeObject.providerId)

        timezoneShortName = getLocalTimeZone()
        showData()
    }

    function dataLoadedFromInternet(contentToCache) {
        dbgprint("Data Loaded From Internet successfully.")
        loadingData = false
        nextReload=dateNow() + reloadIntervalMs
        dbgprint('saving cacheKey = ' + cacheKey)
        cacheMap[cacheKey] = contentToCache
        dbgprint('cacheMap now has these keys:')
        for (var key in cacheMap) {
            dbgprint('  ' + key)
        }
        alreadyLoadedFromCache = false
        weatherCache.writeCache(JSON.stringify(cacheMap))

        reloadMeteogram()
        lastloadingSuccessTime=dateNow()
        updateLastReloadedText()

        loadFromCache()
    }

    function reloadDataFailureCallback() {
        dbgprint("Failed to Load Data successfully.")
        main.loadingData = false
        handleLoadError()
    }

    function reloadData() {
        dbgprint("reloadData")

        if (loadingData) {
            dbgprint('still loading')
            return
        }

        loadingData = true
        lastloadingStartTime=dateNow()
        loadingXhrs = currentProvider.loadDataFromInternet(dataLoadedFromInternet, reloadDataFailureCallback, { placeIdentifier: placeIdentifier, timezoneID: timezoneID })

    }

    function reloadMeteogram() {
        currentProvider.reloadMeteogramImage(placeIdentifier)
    }

    function loadFromCache() {
         dbgprint('loading from cache, config key: ' + cacheKey)

        if (alreadyLoadedFromCache) {
            dbgprint('already loaded from cache')
            return true
        }

        creditLink = currentProvider.getCreditLink(placeIdentifier)
        creditLabel = currentProvider.getCreditLabel(placeIdentifier)

        if (!cacheMap || !cacheMap[cacheKey]) {
            dbgprint('cache not available')
            return false
        }

        var success = currentProvider.setWeatherContents(cacheMap[cacheKey])
        if (!success) {
            dbgprint('setting weather contents not successful')
            return false
        }

        alreadyLoadedFromCache = true
        return true
    }

    function handleLoadError() {
        dbgprint('Error getting weather data. Scheduling data reload...')
        nextReload = dateNow()
        loadFromCache()
    }

    onInTrayActiveTimeoutSecChanged: {
        if (placesJsonStr === '') {
            return
        }
        updateLastReloadedText()
    }

    function updateLastReloadedText() {
      dbgprint("updateLastReloadedText: " + lastloadingSuccessTime)
        if (lastloadingSuccessTime > 0) {
            lastReloadedText = '⬇ ' + i18n("%1 ago", DataLoader.getLastReloadedTimeText(dateNow() - lastloadingSuccessTime))
        }
        plasmoid.status = DataLoader.getPlasmoidStatus(lastloadingSuccessTime, inTrayActiveTimeoutSec)
    }


    function updateAdditionalWeatherInfoText() {
        if (additionalWeatherInfo === undefined || additionalWeatherInfo.nearFutureWeather.iconName === null || actualWeatherModel.count === 0) {
            dbgprint('model not yet ready')
            return
        }

        // Update sunrise/sunset times if available
        if (hasSunData) {
            additionalWeatherInfo.sunRise = localSunrise
            additionalWeatherInfo.sunSet = localSunset
        }

        var sunRise = UnitUtils.convertDate(additionalWeatherInfo.sunRise, timezoneType, timezoneOffset)
        var sunSet = UnitUtils.convertDate(additionalWeatherInfo.sunSet, timezoneType, timezoneOffset)
        additionalWeatherInfo.sunRiseTime = Qt.formatTime(sunRise, Qt.locale().timeFormat(Locale.ShortFormat))
        additionalWeatherInfo.sunSetTime = Qt.formatTime(sunSet, Qt.locale().timeFormat(Locale.ShortFormat))

        var nearFutureWeather = additionalWeatherInfo.nearFutureWeather
        var futureWeatherIcon = IconTools.getIconCode(nearFutureWeather.iconName, currentProvider.providerId, getPartOfDayIndex())
        var wind1 = Math.round(actualWeatherModel.get(0).windDirection)
        var windDirectionIcon = IconTools.getWindDirectionIconCode(wind1)
        var subText = ''
        subText += '<br /><font size="4" style="font-family: weathericons;">' + windDirectionIcon + '</font><font size="4"> ' + wind1 + '\u00B0 &nbsp; @ ' + UnitUtils.getWindSpeedText(actualWeatherModel.get(0).windSpeedMps, windSpeedType) + '</font>'
        subText += '<br /><font size="4">' + UnitUtils.getPressureText(actualWeatherModel.get(0).pressureHpa, pressureType) + '</font>'
        subText += '<br /><table>'
        if ((actualWeatherModel.get(0).humidity !== undefined) && (actualWeatherModel.get(0).cloudiness !== undefined)) {
            subText += '<tr>'
            subText += '<td><font size="4"><font style="font-family: weathericons">\uf07a</font>&nbsp;' + actualWeatherModel.get(0).humidity + '%</font></td>'
            subText += '<td><font size="4"><font style="font-family: weathericons">\uf013</font>&nbsp;' + actualWeatherModel.get(0).cloudiness + '%</font></td>'
            subText += '</tr>'
            subText += '<tr><td>&nbsp;</td><td></td></tr>'
        }
        subText += '<tr>'
        subText += '<td><font size="4"><font style="font-family: weathericons">\uf051</font>&nbsp;' + additionalWeatherInfo.sunRiseTime + ' '+timezoneShortName + '&nbsp;&nbsp;&nbsp;</font></td>'
        subText += '<td><font size="4"><font style="font-family: weathericons">\uf052</font>&nbsp;' + additionalWeatherInfo.sunSetTime + ' '+timezoneShortName + '</font></td>'
        subText += '</tr>'
        subText += '</table>'

        subText += '<br /><br />'
        subText += '<font size="3">' + i18n("near future") + '</font>'
        subText += '<b>'
        subText += '<font size="6">&nbsp;&nbsp;&nbsp;' + UnitUtils.getTemperatureNumber(nearFutureWeather.temperature, temperatureType) + UnitUtils.getTemperatureEnding(temperatureType)
        subText += '&nbsp;&nbsp;&nbsp;<font style="font-family: weathericons">' + futureWeatherIcon + '</font></font>'
        subText += '</b>'
        tooltipSubText = subText
    }

    function refreshTooltipSubText() {
        dbgprint('refreshing sub text')
        if (additionalWeatherInfo === undefined || additionalWeatherInfo.nearFutureWeather.iconName === null || actualWeatherModel.count === 0) {
            dbgprint('model not yet ready')
           return
        }
        updateAdditionalWeatherInfoText()
        var nearFutureWeather = additionalWeatherInfo.nearFutureWeather
        var futureWeatherIcon = IconTools.getIconCode(nearFutureWeather.iconName, currentProvider.providerId, getPartOfDayIndex())
        var wind1=Math.round(actualWeatherModel.get(0).windDirection)
        var windDirectionIcon = IconTools.getWindDirectionIconCode(wind1)
        var subText = ''
        subText += '<br /><font size="4" style="font-family: weathericons;">' + windDirectionIcon + '</font><font size="4"> ' + wind1 + '\u00B0 &nbsp; @ ' + UnitUtils.getWindSpeedText(actualWeatherModel.get(0).windSpeedMps, windSpeedType) + '</font>'
        subText += '<br /><font size="4">' + UnitUtils.getPressureText(actualWeatherModel.get(0).pressureHpa, pressureType) + '</font>'
        subText += '<br /><table>'
        if ((actualWeatherModel.get(0).humidity !== undefined) && (actualWeatherModel.get(0).cloudiness !== undefined)) {
            subText += '<tr>'
            subText += '<td><font size="4"><font style="font-family: weathericons">\uf07a</font>&nbsp;' + actualWeatherModel.get(0).humidity + '%</font></td>'
            subText += '<td><font size="4"><font style="font-family: weathericons">\uf013</font>&nbsp;' + actualWeatherModel.get(0).cloudiness + '%</font></td>'
            subText += '</tr>'
            subText += '<tr><td>&nbsp;</td><td></td></tr>'
        }
        subText += '<tr>'
        subText += '<td><font size="4"><font style="font-family: weathericons">\uf051</font>&nbsp;' + additionalWeatherInfo.sunRiseTime + ' '+timezoneShortName + '&nbsp;&nbsp;&nbsp;</font></td>'
        subText += '<td><font size="4"><font style="font-family: weathericons">\uf052</font>&nbsp;' + additionalWeatherInfo.sunSetTime + ' '+timezoneShortName + '</font></td>'
        subText += '</tr>'
        subText += '</table>'

        subText += '<br /><br />'
        subText += '<font size="3">' + i18n("near future") + '</font>'
        subText += '<b>'
        subText += '<font size="6">&nbsp;&nbsp;&nbsp;' + UnitUtils.getTemperatureNumber(nearFutureWeather.temperature, temperatureType) + UnitUtils.getTemperatureEnding(temperatureType)
        subText += '&nbsp;&nbsp;&nbsp;<font style="font-family: weathericons">' + futureWeatherIcon + '</font></font>'
        subText += '</b>'
        tooltipSubText = subText
    }

    function getPartOfDayIndex() {
        var now = new Date().getTime()
        let sunrise1 = additionalWeatherInfo.sunRise.getTime()
        let sunset1 = additionalWeatherInfo.sunSet.getTime()
        let icon = ((now > sunrise1) && (now < sunset1)) ? 0 : 1
// setDebugFlag(true)
        dbgprint(JSON.stringify(additionalWeatherInfo))
        dbgprint("NOW = " + now + "\tSunrise = " + sunrise1 + "\tSunset = " + sunset1 + "\t" + (icon === 0 ? "isDay" : "isNight"))
        dbgprint("\t > Sunrise:" + (now > sunrise1) + "\t\t Sunset:" + (now < sunset1))
// setDebugFlag(false)

        return icon
    }

    function abortTooLongConnection(forceAbort) {
        if (!loadingData) {
            return
        }
        if (forceAbort) {
            dbgprint('timeout reached, aborting existing xhrs')
            loadingXhrs.forEach(function (xhr) {
                xhr.abort()
            })
            reloadDataFailureCallback()
        } else {
            dbgprint('regular loading, no aborting yet')
            return
        }
    }

    function tryReload() {
       updateLastReloadedText()

        if (updatingPaused) {
            return
        }

        reloadData()
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            var now=dateNow()
            dbgprint("*** Timer triggered")
            dbgprint("*** loadingData Flag : " + loadingData)
            dbgprint("*** Last Load Success: " + (lastloadingSuccessTime))
            dbgprint("*** Next Load Due    : " + (nextReload))
            dbgprint("*** Time Now         : " + now)
            dbgprint("*** Next Load in     : " + Math.round((nextReload - now) / 1000) + " sec = "+ ((nextReload - now) / 60000).toFixed(2) + " min")

            updateLastReloadedText()
            if ((lastloadingSuccessTime===0) && (updatingPaused)) {
              toggleUpdatingPaused()
            }

            if (loadingData) {
                dbgprint("Timeout in:" + (lastloadingStartTime + loadingDataTimeoutMs - now))
                if (now > (lastloadingStartTime + loadingDataTimeoutMs)) {
                    console.log("Timed out downloading weather data - aborting attempt. Retrying in 60 seconds time.")
                    abortTooLongConnection(true)
                    nextReload=now + 60000
                }
            } else {
              if (now > nextReload) {
                tryReload()
              }
            }
        }
    }

    onTemperatureTypeChanged: {
        refreshTooltipSubText()
    }

    onPressureTypeChanged: {
        refreshTooltipSubText()
    }

    onWindSpeedTypeChanged: {
        refreshTooltipSubText()
    }

    onTwelveHourClockEnabledChanged: {
        refreshTooltipSubText()
    }

    onTimezoneTypeChanged: {
        if (lastloadingSuccessTime > 0) {
        refreshTooltipSubText()
        }
    }

    function dbgprint(msg) {
        if (!debugLogging) {
            return
        }
        print('[weatherWidget] ' + msg)
    }

    function dateNow() {
        var now=new Date().getTime()
        return now
    }

    function setDebugFlag(flag) {
        debugLogging = flag
    }

    function getLocalTimeZone() {
        return dataSource.data["Local"]["Timezone Abbreviation"]
    }

    // === HOVER FEELS LIKE TOOLTIP ===
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
    // === ATMOSPHERE WIDGET (ALL-IN-ONE) ===
    Item {
        id: atmosphereWidget
        anchors.fill: parent
        z: 1002 // Highest layer — above everything

        // --- SOUND EFFECTS ---
        property bool soundEnabled: plasmoid.configuration.soundEffectsEnabled !== false
        property string soundDir: "qrc:/sounds/"

        SoundEffect {
            id: hourlyDing
            source: soundDir + "ding.mp3"
            volume: 0.3
            enabled: atmosphereWidget.soundEnabled
        }

        SoundEffect {
            id: windWhoosh
            source: soundDir + "wind.mp3"
            volume: 0.2
            enabled: atmosphereWidget.soundEnabled
        }

        SoundEffect {
            id: rainPatter
            source: soundDir + "rain.mp3"
            volume: 0.25
            enabled: atmosphereWidget.soundEnabled
        }

        SoundEffect {
            id: snowCrunch
            source: soundDir + "snow.mp3"
            volume: 0.2
            enabled: atmosphereWidget.soundEnabled
        }

        // --- WALLPAPER PATHS (USE YOUR EXACT PATHS) ---
        property string morningWallpaper: "/home/x2/Wallpapers/System-Defaults/fruitdark.jpg"
        property string afternoonWallpaper: "/home/x2/Wallpapers/System-Defaults/fruit.jpg"
        property string eveningWallpaper: "/home/x2/Wallpapers/System-Defaults/fruitdarker.jpg"
        property string nightWallpaper: "/home/x2/Wallpapers/System-Defaults/fruitdarkest.jpg"

        // --- BASE IMAGE FOR BRIGHTNESS ADJUSTMENT ---
        property string baseWallpaper: afternoonWallpaper // Use brightest as base for modulate

        // --- CALCULATE TIME-BASED WALLPAPER ---

        property string selectedWallpaper: {
            var now = new Date().getTime()
            var useSun = plasmoid.configuration.useSunriseSunset && hasSunData

            if (useSun && localSunrise.getTime() > 0 && localSunset.getTime() > 0) {
                var sunrise = localSunrise.getTime()
                var sunset = localSunset.getTime()

                // Morning: 1 hour before sunrise → 1 hour after sunrise
                if (now > sunrise - 3600000 && now < sunrise + 3600000) return morningWallpaper
                // Day: between sunrise + 1h and sunset - 1h
                else if (now > sunrise + 3600000 && now < sunset - 3600000) return afternoonWallpaper
                // Evening: 1 hour before sunset → 1 hour after sunset
                else if (now > sunset - 3600000 && now < sunset + 3600000) return eveningWallpaper
                // Night: everything else
                else return nightWallpaper
            }

            // Fallback to time-based if API fails or disabled
            var hour = new Date().getHours()
            if (hour >= 6 && hour < 12) return morningWallpaper
            else if (hour >= 12 && hour < 17) return afternoonWallpaper
            else if (hour >= 17 && hour < 20) return eveningWallpaper
            else return nightWallpaper
        }

        // --- CALCULATE BRIGHTNESS (TIME + WEATHER) ---
        property real calculatedBrightness: {
        var now = new Date().getTime()
        var useSun = plasmoid.configuration.useSunriseSunset && hasSunData

        if (useSun && localSunrise.getTime() > 0 && localSunset.getTime() > 0) {
            var sunrise = localSunrise.getTime()
            var sunset = localSunset.getTime()
            var dayLength = sunset - sunrise
            var timeSinceSunrise = now - sunrise

            if (timeSinceSunrise < 0) return 20  // Before sunrise
            if (timeSinceSunrise > dayLength) return 20  // After sunset

            // Linear interpolation: darkest at sunrise/sunset, brightest at noon
            var progress = Math.max(0, Math.min(1, timeSinceSunrise / dayLength))
            var base = 100 * (1 - Math.abs(progress - 0.5) * 2) // Triangle wave: peaks at noon
            return Math.round(base)
        }

        // Fallback to time-based brightness (from your original script)
        var hour = new Date().getHours()
        var brightness_levels = {
            0: 20, 1: 30, 2: 35, 3: 40, 4: 45, 5: 50,
            6: 60, 7: 70, 8: 80, 9: 85, 10: 90, 11: 95,
            12: 100, 13: 100, 14: 95, 15: 90, 16: 85, 17: 80,
            18: 70, 19: 60, 20: 50, 21: 40, 22: 30, 23: 25
        }
        var base = brightness_levels[hour] || 40

        // Weather adjustment
        var cond = currentProvider ? currentProvider.currentCondition.toLowerCase() : ""
        var weatherAdj = 0
        if (cond.includes("snow")) weatherAdj = 15
        else if (cond.includes("sun") || cond.includes("clear")) weatherAdj = 10
        else if (cond.includes("rain") || cond.includes("drizzle")) weatherAdj = -20
        else if (cond.includes("cloudy") || cond.includes("overcast")) weatherAdj = -15

        return Math.max(15, Math.min(100, base + weatherAdj))
    }

        // --- WALLPAPER ADJUSTMENT FUNCTION ---
        function applyWallpaperWithBrightness() {
            var path = selectedWallpaper
            if (!Qt.canOpenFile(path)) {
                console.warn("Wallpaper not found:", path)
                return
            }

            var tempPath = Qt.resolvedUrl("file:///tmp/plasma-adjusted-wallpaper-" + plasmoid.id + ".jpg")

            if (calculatedBrightness === 100) {
                setPlasmaWallpaper(path)
            } else {
                var cmd = "convert \"" + path + "\" -modulate 100," + calculatedBrightness + ",100 \"" + tempPath + "\""
                var process = new QtObject()
                process.execute = function(command) {
                    var result = Qt.runCommand(command)
                    return result
                }
                process.execute(cmd)

                setTimeout(function() {
                    if (Qt.fileExists(tempPath)) {
                        setPlasmaWallpaper(tempPath)
                    } else {
                        setPlasmaWallpaper(path)
                    }
                }, 1000)
            }
        }

        // --- SET WALLPAPER VIA DBUS ---
        function setPlasmaWallpaper(path) {
            if (!path) return

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
                console.log("Wallpaper updated:", path, "brightness:", calculatedBrightness)
            } catch (e) {
                console.error("DBus wallpaper error:", e.message)
            }
        }

        // --- SUN GLINT (GENTLE HIGHLIGHT ON SUNNY DAYS) ---
        Item {
            id: sunGlint
            width: 40
            height: 40
            radius: 20
            color: "white"
            opacity: 0
            z: 1003
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            visible: !currentProvider ? false : (
                !currentProvider.currentCondition.toLowerCase().includes("cloud") &&
                !currentProvider.currentCondition.toLowerCase().includes("rain") &&
                !currentProvider.currentCondition.toLowerCase().includes("snow") &&
                calculatedBrightness > 85
            )

            Behavior on opacity { NumberAnimation { duration: 1500 } }

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

        // --- RAIN AND SNOW PARTICLES WITH WIND ALIGNMENT ---
        property real windDirection: actualWeatherModel.count > 0 ? actualWeatherModel.get(0).windDirection : 0

        Item {
            id: rainContainer
            anchors.fill: parent
            rotation: windDirection - 90
            visible: currentProvider && (
                currentProvider.currentCondition.toLowerCase().includes("rain") ||
                currentProvider.currentCondition.toLowerCase().includes("drizzle")
            )

            ParticleSystem {
                id: rainSystem
                width: parent.width
                height: parent.height

                ImageParticle {
                    source: "qrc:/effects/raindrop.svg"
                    colorVariation: 0.1
                    alpha: 0.7
                    size: 8
                    sizeVariation: 3
                    lifeSpan: 1500
                    velocityFromAngle: 90
                    velocityFromMagnitude: 110 + (actualWeatherModel.count > 0 ? actualWeatherModel.get(0).windSpeedMps * 8 : 0)
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

        Item {
            id: snowContainer
            anchors.fill: parent
            rotation: windDirection - 90
            visible: currentProvider && (
                currentProvider.currentCondition.toLowerCase().includes("snow") ||
                currentProvider.currentCondition.toLowerCase().includes("sleet")
            )

            ParticleSystem {
                id: snowSystem
                width: parent.width
                height: parent.height

                ImageParticle {
                    source: "qrc:/effects/snowflake.svg"
                    color: "#ffffff"
                    alpha: 0.9
                    size: 12
                    sizeVariation: 4
                    lifeSpan: 4000
                    velocityFromAngle: 90
                    velocityFromMagnitude: 15 + (actualWeatherModel.count > 0 ? actualWeatherModel.get(0).windSpeedMps * 2 : 0)
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

        // --- DAY/NIGHT OVERLAY (SOFT DIMMING) ---
        Rectangle {
            id: lightingOverlay
            anchors.fill: parent
            color: "black"
            opacity: 0
            z: 1001

            Behavior on opacity {
                NumberAnimation {
                    duration: 3000
                    easing.type: Easing.InOutQuad
                }
            }

            opacity: {
                var cond = currentProvider ? currentProvider.currentCondition.toLowerCase() : ""
                var hour = new Date().getHours()

                if (cond.includes("snow")) return 0.5
                else if (cond.includes("rain") || cond.includes("drizzle")) return 0.4
                else if (cond.includes("cloudy") || cond.includes("overcast")) return 0.3
                else if (hour >= 18 || hour < 6) return 0.6
                else return 0.0
            }
        }

        // --- SOUND TRIGGERS ---
        function playSound(soundName) {
            if (!atmosphereWidget.soundEnabled) return

            switch (soundName) {
                case "ding": hourlyDing.play(); break
                case "wind": windWhoosh.play(); break
                case "rain": rainPatter.play(); break
                case "snow": snowCrunch.play(); break
            }
        }

        // --- UPDATE LOGIC ---
        Component.onCompleted: {
            // Load sounds from resource if they exist
            var soundFiles = ["ding.mp3", "wind.mp3", "rain.mp3", "snow.mp3"]
            soundFiles.forEach(file => {
                if (!Qt.resourceExists(atmosphereWidget.soundDir + file)) {
                    console.warn("Sound file missing:", atmosphereWidget.soundDir + file)
                }
            })

            // Initial wallpaper update
            applyWallpaperWithBrightness()

            // Update every minute (for time changes)
            Timer {
                interval: 60 * 1000
                repeat: true
                running: true
                onTriggered: {
                    applyWallpaperWithBrightness()

                    // Play ding on the hour
                    var now = new Date()
                    if (now.getMinutes() === 0) {
                        playSound("ding")
                    }

                    // Trigger wind sound on high wind
                    if (actualWeatherModel.count > 0) {
                        var windSpeed = actualWeatherModel.get(0).windSpeedMps
                        if (windSpeed > 7) {
                            playSound("wind")
                        }
                    }
                }
            }

            // Watch weather condition changes
            if (currentProvider) {
                currentProvider.onCurrentConditionChanged.connect(function() {
                    var cond = currentProvider.currentCondition.toLowerCase()
                    if (cond.includes("rain") && !rainContainer.visible) playSound("rain")
                    if (cond.includes("snow") && !snowContainer.visible) playSound("snow")
                    applyWallpaperWithBrightness()
                })
            }

            // Watch wind speed/direction changes
            actualWeatherModel.onDataChanged.connect(function() {
                if (actualWeatherModel.count > 0) {
                    windDirection = actualWeatherModel.get(0).windDirection
                    var windSpeed = actualWeatherModel.get(0).windSpeedMps
                    if (windSpeed > 7) {
                        playSound("wind")
                    }
                }
            })

            // Ensure we get initial wind direction
            if (actualWeatherModel.count > 0) {
                windDirection = actualWeatherModel.get(0).windDirection
            }
        }
    }
}
