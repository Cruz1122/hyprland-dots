pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import QtPositioning

import qs.modules.common

Singleton {
    id: root
    // 10 minute
    readonly property int fetchInterval: Config.options.bar.weather.fetchInterval * 60 * 1000
    readonly property string city: Config.options.bar.weather.city
    readonly property bool useUSCS: Config.options.bar.weather.useUSCS
    readonly property bool gpsEnabled: Config.options.bar.weather.enableGPS
    property bool gpsActive: gpsEnabled
    // Consecutive GPS failures; drives the retry backoff and limits
    // notifications to one per failure streak.
    property int gpsFailureStreak: 0
    readonly property int gpsRetryBaseMs: 60 * 1000
    readonly property int gpsRetryMaxMs: 30 * 60 * 1000

    onGpsEnabledChanged: {
        gpsRetryTimer.stop();
        root.gpsFailureStreak = 0;
        root.gpsActive = root.gpsEnabled && positionSource.valid;
        if (root.gpsActive)
            positionSource.start();
        else
            positionSource.stop();
        root.getData();
    }

    function scheduleGpsRetry() {
        if (!root.gpsEnabled)
            return;
        if (root.gpsFailureStreak === 0)
            Quickshell.execDetached(["notify-send", Translation.tr("Weather Service"), Translation.tr("Could not get the GPS location. Using the city instead and retrying later."), "-a", "Shell"]);
        root.gpsFailureStreak += 1;
        gpsRetryTimer.interval = Math.min(root.gpsRetryBaseMs * Math.pow(2, root.gpsFailureStreak - 1), root.gpsRetryMaxMs);
        gpsRetryTimer.restart();
    }

    onUseUSCSChanged: {
        root.getData();
    }
    onCityChanged: {
        root.getData();
    }

    property var location: ({
        valid: false,
        lat: 0,
        lon: 0
    })

    property var data: ({
        uv: 0,
        humidity: 0,
        sunrise: 0,
        sunset: 0,
        windDir: 0,
        wCode: 0,
        city: 0,
        wind: 0,
        precip: 0,
        visib: 0,
        press: 0,
        temp: 0,
        tempFeelsLike: 0,
        lastRefresh: 0,
    })

    function refineData(data) {
        let temp = {};
        temp.uv = data?.current?.uvIndex || 0;
        temp.humidity = (data?.current?.humidity || 0) + "%";
        temp.sunrise = data?.astronomy?.sunrise || "0.0";
        temp.sunset = data?.astronomy?.sunset || "0.0";
        temp.windDir = data?.current?.winddir16Point || "N";
        temp.wCode = data?.current?.weatherCode || "113";
        temp.city = data?.location?.areaName[0]?.value || "City";
        temp.temp = "";
        temp.tempFeelsLike = "";
        if (root.useUSCS) {
            temp.wind = (data?.current?.windspeedMiles || 0) + " mph";
            temp.precip = (data?.current?.precipInches || 0) + " in";
            temp.visib = (data?.current?.visibilityMiles || 0) + " m";
            temp.press = (data?.current?.pressureInches || 0) + " psi";
            temp.temp += (data?.current?.temp_F || 0);
            temp.tempFeelsLike += (data?.current?.FeelsLikeF || 0);
            temp.temp += "°F";
            temp.tempFeelsLike += "°F";
        } else {
            temp.wind = (data?.current?.windspeedKmph || 0) + " km/h";
            temp.precip = (data?.current?.precipMM || 0) + " mm";
            temp.visib = (data?.current?.visibility || 0) + " km";
            temp.press = (data?.current?.pressure || 0) + " hPa";
            temp.temp += (data?.current?.temp_C || 0);
            temp.tempFeelsLike += (data?.current?.FeelsLikeC || 0);
            temp.temp += "°C";
            temp.tempFeelsLike += "°C";
        }
        temp.lastRefresh = DateTime.time + " • " + DateTime.date;
        root.data = temp;
    }

    function getData() {
        let place;
        if (root.gpsActive && root.location.valid)
            place = `${Number(root.location.lat)},${Number(root.location.long)}`;
        else
            place = formatCityName(root.city);
        // argv only: the city is user input and must never reach a shell.
        fetcher.command = ["curl", "-s", "--max-time", "20", `https://wttr.in/${place}?format=j1`];
        fetcher.running = true;
    }

    // wttr.in reads "+" as a space; every word is percent-encoded so quotes,
    // "?", "#" or "/" in the city cannot change the URL.
    function formatCityName(cityName) {
        return cityName.trim().split(/\s+/).filter(word => word.length > 0).map(encodeURIComponent).join('+');
    }

    // Only the current weather, location and astronomy data are used.
    function pickData(raw) {
        return {
            current: raw?.current_condition?.[0],
            location: raw?.nearest_area?.[0],
            astronomy: raw?.weather?.[0]?.astronomy?.[0]
        };
    }

    Component.onCompleted: {
        if (!root.gpsActive) return;
        console.info("[WeatherService] Starting the GPS service.");
        positionSource.start();
    }

    Process {
        id: fetcher
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0)
                    return;
                try {
                    const parsedData = root.pickData(JSON.parse(text));
                    root.refineData(parsedData);
                    // console.info(`[ data: ${JSON.stringify(parsedData)}`);
                } catch (e) {
                    console.error(`[WeatherService] ${e.message}`);
                }
            }
        }
    }

    PositionSource {
        id: positionSource
        updateInterval: root.fetchInterval

        onPositionChanged: {
            // update the location if the given location is valid
            // if it fails getting the location, use the last valid location
            if (position.latitudeValid && position.longitudeValid) {
                root.location.lat = position.coordinate.latitude;
                root.location.long = position.coordinate.longitude;
                root.location.valid = true;
                root.gpsFailureStreak = 0;
                gpsRetryTimer.stop();
                // console.info(`📍 Location: ${position.coordinate.latitude}, ${position.coordinate.longitude}`);
                root.getData();
            } else {
                console.error("[WeatherService] Failed to get the GPS location.");
                // Keep the last valid fix; without one, use the city fallback
                // until a backoff retry gets a fix.
                if (root.location.valid || !root.gpsActive)
                    return;
                positionSource.stop();
                root.gpsActive = false;
                root.scheduleGpsRetry();
            }
        }

        onValidityChanged: {
            if (!positionSource.valid) {
                positionSource.stop();
                root.location.valid = false;
                root.gpsActive = false;
                Quickshell.execDetached(["notify-send", Translation.tr("Weather Service"), Translation.tr("Cannot find a GPS service. Using the fallback method instead."), "-a", "Shell"]);
                console.error("[WeatherService] Could not aquire a valid backend plugin.");
            }
        }
    }

    Timer {
        id: gpsRetryTimer
        repeat: false
        onTriggered: {
            if (!root.gpsEnabled || !positionSource.valid)
                return;
            console.info("[WeatherService] Retrying the GPS service.");
            root.gpsActive = true;
            positionSource.start();
        }
    }

    Timer {
        running: !root.gpsActive
        repeat: true
        interval: root.fetchInterval
        triggeredOnStart: !root.gpsActive
        onTriggered: root.getData()
    }
}
