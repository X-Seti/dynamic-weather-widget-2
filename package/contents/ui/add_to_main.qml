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
