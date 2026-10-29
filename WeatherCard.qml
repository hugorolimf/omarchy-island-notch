import QtQuick
import Quickshell
import Quickshell.Io
import "Icons.js" as Icons

// Weather card for the island, laid out like the anatomy prototype: a line
// figure, the temperature, condition · place, a mono detail line and the next
// six hours. Data comes from weather.sh (same location
// source as omarchy.weather, Open-Meteo forecast, 10 min disk cache). Nothing
// is fetched while the card is closed: opening it shows the cached report at
// once and refreshes it in the background when stale.
Item {
  id: root
  // Portuguese, or English for every other locale.
  readonly property bool portuguese: Qt.locale().name.indexOf("pt") === 0
  readonly property var enText: ({ "SENSAÇÃO ": "FEELS LIKE ", "° · UMIDADE ": "° · HUMIDITY ", "% · VENTO ": "% · WIND ",
    "SEM CONEXÃO COM O SERVIÇO DO TEMPO": "NO CONNECTION TO THE WEATHER SERVICE", "CARREGANDO O TEMPO…": "LOADING THE WEATHER…" })
  function tr(text) { return portuguese || enText[text] === undefined ? text : enText[text] }

  property bool active: false
  // per-monitor size factor (see BarWidget): measures × k, fonts +1 px
  property real k: 1
  readonly property bool big: k > 1.05
  function u(v) { return v * k }
  function fontPx(base) { return big ? (base >= 20 ? base + 2 : Math.floor(base) + 1) : base }
  property string sansFont: "Adwaita Sans"
  property string monoFont: "JetBrainsMono Nerd Font"
  property color strong: "#e6e6e6"
  property color muted: "#6e6e6e"
  property color hi: "#d4d4d4"
  property color blue: "#6b9bff"

  readonly property string script: String(Qt.resolvedUrl("weather.sh")).replace(/^file:\/\//, "")
  property var report: null
  property bool failed: false
  readonly property var wx: report && report.data ? report.data : null
  readonly property var current: wx && wx.current ? wx.current : null
  readonly property var hourly: wx && wx.hourly ? wx.hourly : null
  readonly property var daily: wx && wx.daily ? wx.daily : null
  readonly property bool night: current ? Number(current.is_day) === 0 : false

  implicitWidth: Math.max(u(340), Math.ceil(content.implicitWidth) + u(32))
  implicitHeight: Math.max(u(124), Math.ceil(content.implicitHeight) + u(24))

  onActiveChanged: if (active) load()
  Component.onCompleted: if (active) load()

  function load() {
    if (fetchProc.running) return
    fetchProc.stage = "cached"
    fetchProc.command = ["bash", "-c", 'f="${XDG_CACHE_HOME:-$HOME/.cache}/island-notch/weather.json"; [ -s "$f" ] && cat "$f" || echo "{}"']
    fetchProc.running = true
  }

  function apply(raw) {
    try {
      var parsed = JSON.parse(String(raw || "").trim() || "{}")
      if (parsed && parsed.data) { root.report = parsed; root.failed = false }
      else if (parsed && parsed.error) root.failed = root.report === null
    } catch (e) {
      root.failed = root.report === null
    }
  }

  Process {
    id: fetchProc
    property string stage: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
    onExited: {
      if (stage !== "cached") return
      var age = root.report ? Date.now() / 1000 - Number(root.report.fetchedAt || 0) : Infinity
      if (age < 600) return
      stage = "fresh"
      command = ["bash", root.script]
      running = true
    }
  }

  function deg(v) {
    var n = parseFloat(String(v))
    return isNaN(n) ? "–" : String(Math.round(n))
  }

  readonly property var hours: {
    var out = []
    if (!hourly || !hourly.time) return out
    for (var i = 1; i < hourly.time.length && out.length < 6; i++) {
      out.push({
        label: String(hourly.time[i]).slice(11, 13) + "h",
        icon: Icons.weather(hourly.weather_code[i], Number(hourly.is_day[i]) === 0),
        temp: deg(hourly.temperature_2m[i]) + "°",
        rain: hourly.precipitation_probability ? Number(hourly.precipitation_probability[i]) : 0
      })
    }
    return out
  }

  Row {
    id: content
    x: root.u(16)
    y: root.u(12)
    spacing: root.u(18)
    opacity: root.current ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1] } }

    StrokeIcon {
      size: root.u(64)
      strokeWidth: 1.1
      color: root.hi
      path: root.current ? Icons.weather(root.current.weather_code, root.night) : ""
    }

    Column {
      spacing: 0

      Row {
        spacing: root.u(2)
        Text {
          text: root.current ? root.deg(root.current.temperature_2m) : ""
          color: root.strong
          font.family: root.sansFont
          font.pixelSize: root.fontPx(30)
          font.weight: Font.Light
          lineHeightMode: Text.FixedHeight
          lineHeight: root.fontPx(30)
          textFormat: Text.PlainText
        }
        Text {
          text: "°C"
          color: root.muted
          font.family: root.sansFont
          font.pixelSize: root.fontPx(13)
          textFormat: Text.PlainText
        }
      }

      Text {
        topPadding: root.u(4)
        text: root.current ? [Icons.condition(root.current.weather_code, !root.portuguese), root.report.location || ""].filter(function(s) { return s !== "" }).join(" · ") : ""
        color: root.strong
        font.family: root.monoFont
        font.pointSize: root.fontPx(10.5) * 0.75
        font.weight: Font.Medium
        textFormat: Text.PlainText
      }

      Text {
        text: root.current ? (root.tr("SENSAÇÃO ") + root.deg(root.current.apparent_temperature) + root.tr("° · UMIDADE ")
          + Math.round(Number(root.current.relative_humidity_2m)) + root.tr("% · VENTO ")
          + Math.round(Number(root.current.wind_speed_10m)) + " KM/H") : ""
        color: root.muted
        font.family: root.monoFont
        font.pixelSize: root.fontPx(10)
        textFormat: Text.PlainText
      }

      Row {
        topPadding: root.u(8)
        spacing: root.u(14)
        Repeater {
          model: root.hours
          Column {
            required property var modelData
            spacing: root.u(3)
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: modelData.label
              color: root.muted
              font.family: root.monoFont
              font.pixelSize: root.fontPx(10)
              textFormat: Text.PlainText
            }
            StrokeIcon {
              anchors.horizontalCenter: parent.horizontalCenter
              size: root.u(16)
              strokeWidth: 1.2
              color: modelData.rain >= 50 ? root.blue : root.hi
              path: modelData.icon
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: modelData.temp
              color: root.strong
              font.family: root.monoFont
              font.pixelSize: root.fontPx(10)
              font.weight: Font.Medium
              textFormat: Text.PlainText
            }
          }
        }
      }
    }
  }

  // Loading / offline
  Text {
    anchors.centerIn: parent
    opacity: root.current ? 0 : 1
    text: root.tr(root.failed ? "SEM CONEXÃO COM O SERVIÇO DO TEMPO" : "CARREGANDO O TEMPO…")
    color: root.muted
    font.family: root.monoFont
    font.pointSize: root.fontPx(10.5) * 0.75
    textFormat: Text.PlainText
    Behavior on opacity { NumberAnimation { duration: 250 } }
  }
}
