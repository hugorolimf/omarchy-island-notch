.pragma library

// Line icons on a 24-unit grid (anatomy style). Weather glyphs follow the
// WMO codes Open-Meteo reports.

var cloud = "M7.5 18h9a3.5 3.5 0 0 0 .4-7A5 5 0 0 0 7.3 9.6 4.2 4.2 0 0 0 7.5 18z"
var cloudHigh = "M7.5 14.5h9a3.5 3.5 0 0 0 .4-7A5 5 0 0 0 7.3 6.1 4.2 4.2 0 0 0 7.5 14.5z"
var cloudSmall = "M9.5 19h8a3 3 0 0 0 .3-6A4.3 4.3 0 0 0 9.4 11.8 3.6 3.6 0 0 0 9.5 19z"
var sun = "M15.6 12a3.6 3.6 0 1 1-7.2 0a3.6 3.6 0 1 1 7.2 0zM12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M5.6 18.4L7 17M17 7l1.4-1.4"
var moon = "M19 14.5A7.5 7.5 0 0 1 9.5 5a7.5 7.5 0 1 0 9.5 9.5z"
var sunPeek = "M7.6 11.2A3.2 3.2 0 1 1 12.9 8.3M9.5 3v1.3M3.6 8.6h1.3M5.3 4.6l.9.9M13.7 4.6l-.9.9"
var moonPeek = "M12.6 8.4A4 4 0 0 1 7.1 3.6a4.2 4.2 0 0 0 .6 7.5"
var fog = "M4 8.5h16M6 12h12M4 15.5h16M8 19h8"
var rain = cloudHigh + "M9 17.5l-1 2.8M13 17.5l-1 2.8M17 17.5l-1 2.8"
var drizzle = cloudHigh + "M9.2 18v.6M13.2 18v.6M11.2 20.6v.6M15.2 20.6v.6"
var storm = cloudHigh + "M12.8 16l-2 3h3l-2 3"
var snow = cloudHigh + "M8.8 18.2v.2M12 19.6v.2M15.2 18.2v.2M10.4 21.4v.2M13.6 21.4v.2"

var previous = "M18 6.5v11L10 12zM7 6.5v11"
var next = "M6 6.5v11l8-5.5zM17 6.5v11"
var play = "M8 5.5v13l10.5-6.5z"
var pause = "M9 6v12M15 6v12"
var stop = "M7.5 7.5h9v9h-9z"

function weather(code, night) {
  var c = parseInt(String(code), 10)
  if (c === 0) return night ? moon : sun
  if (c === 1 || c === 2) return (night ? moonPeek : sunPeek) + cloudSmall
  if (c === 3) return cloud
  if (c === 45 || c === 48) return fog
  if (c >= 51 && c <= 57) return drizzle
  if ((c >= 61 && c <= 67) || (c >= 80 && c <= 82)) return rain
  if ((c >= 71 && c <= 77) || c === 85 || c === 86) return snow
  if (c >= 95) return storm
  return cloud
}

// Weather code to words, Portuguese or English.
var conditionsEn = {
  "Céu limpo": "Clear sky", "Quase limpo": "Mainly clear", "Parcialmente nublado": "Partly cloudy", "Nublado": "Overcast",
  "Neblina": "Fog", "Garoa": "Drizzle", "Garoa congelante": "Freezing drizzle", "Chuva fraca": "Light rain", "Chuva": "Rain",
  "Chuva forte": "Heavy rain", "Chuva congelante": "Freezing rain", "Neve": "Snow", "Pancadas fracas": "Light showers",
  "Pancadas de chuva": "Rain showers", "Pancadas fortes": "Heavy showers", "Pancadas de neve": "Snow showers",
  "Trovoadas": "Thunderstorms", "Trovoadas com granizo": "Thunderstorms with hail"
}
function condition(code, english) {
  var words = conditionPt(code)
  return english && conditionsEn[words] ? conditionsEn[words] : words
}

function conditionPt(code) {
  var c = parseInt(String(code), 10)
  if (c === 0) return "Céu limpo"
  if (c === 1) return "Quase limpo"
  if (c === 2) return "Parcialmente nublado"
  if (c === 3) return "Nublado"
  if (c === 45 || c === 48) return "Neblina"
  if (c >= 51 && c <= 55) return "Garoa"
  if (c === 56 || c === 57) return "Garoa congelante"
  if (c === 61) return "Chuva fraca"
  if (c === 63) return "Chuva"
  if (c === 65) return "Chuva forte"
  if (c === 66 || c === 67) return "Chuva congelante"
  if (c >= 71 && c <= 77) return "Neve"
  if (c === 80) return "Pancadas fracas"
  if (c === 81) return "Pancadas de chuva"
  if (c === 82) return "Pancadas fortes"
  if (c === 85 || c === 86) return "Pancadas de neve"
  if (c === 95) return "Trovoadas"
  if (c === 96 || c === 99) return "Trovoadas com granizo"
  return ""
}

// Rewrites an SVG path drawn on the 24-unit grid at `f` times its size, so
// icons are tessellated at their real pixel size instead of being scaled
// by a transform. Arc flags and rotation are left alone.
var _counts = { m: 2, l: 2, t: 2, h: 1, v: 1, c: 6, s: 4, q: 4, a: 7, z: 0 }
function scalePath(d, f) {
  if (!d || f === 1) return d || ""
  var tokens = String(d).match(/[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/g) || []
  var out = []
  var cmd = ""
  var index = 0
  for (var i = 0; i < tokens.length; i++) {
    var t = tokens[i]
    if (/^[A-Za-z]$/.test(t)) {
      cmd = t.toLowerCase()
      index = 0
      out.push(t)
      continue
    }
    var n = parseFloat(t)
    var count = _counts[cmd] || 2
    var slot = index % count
    var keep = cmd === "a" && (slot === 2 || slot === 3 || slot === 4)
    out.push(String(keep ? n : Math.round(n * f * 1000) / 1000))
    index++
  }
  return out.join(" ")
}

var alarm = "M18.5 13a6.5 6.5 0 1 1-13 0a6.5 6.5 0 1 1 13 0zM12 9.5V13l2.2 1.6M5 4.5L3 6.5M19 4.5l2 2"
var bell = "M6.5 16.5V11a5.5 5.5 0 0 1 11 0v5.5l1.5 2h-14zM10 20.5a2 2 0 0 0 4 0"
var message = "M5.5 6h13A1.5 1.5 0 0 1 20 7.5v8a1.5 1.5 0 0 1-1.5 1.5H12l-4 3v-3H5.5A1.5 1.5 0 0 1 4 15.5v-8A1.5 1.5 0 0 1 5.5 6z"
var phone = "M8.5 3h7A1.5 1.5 0 0 1 17 4.5v15a1.5 1.5 0 0 1-1.5 1.5h-7A1.5 1.5 0 0 1 7 19.5v-15A1.5 1.5 0 0 1 8.5 3zM10.75 18h2.5"
// solid media controls (FillIcon)
var playFill = "M8 4.8v14.4c0 .8.9 1.3 1.6.8l10.4-7.2c.6-.4.6-1.2 0-1.6L9.6 4c-.7-.5-1.6 0-1.6.8z"
var pauseFill = "M7 4.5h3.2v15H7zM13.8 4.5H17v15h-3.8z"
var nextFill = "M3.5 6.2v11.6c0 .7.8 1.1 1.4.7l7.4-5.8c.4-.4.4-1 0-1.4L4.9 5.5c-.6-.4-1.4 0-1.4.7zM12 6.2v11.6c0 .7.8 1.1 1.4.7l7.4-5.8c.4-.4.4-1 0-1.4l-7.4-5.8c-.6-.4-1.4 0-1.4.7z"
var previousFill = "M20.5 6.2v11.6c0 .7-.8 1.1-1.4.7l-7.4-5.8c-.4-.4-.4-1 0-1.4l7.4-5.8c.6-.4 1.4 0 1.4.7zM12 6.2v11.6c0 .7-.8 1.1-1.4.7l-7.4-5.8c-.4-.4-.4-1 0-1.4l7.4-5.8c.6-.4 1.4 0 1.4.7z"
// on-screen indicators (hud)
var hudSpeaker = "M4 9.5h3.5L12 5.5v13l-4.5-4H4z"
var hudWave1 = "M15 10a3 3 0 0 1 0 4"
var hudWave2 = "M17.3 7.6a6.2 6.2 0 0 1 0 8.8"
var hudWave3 = "M19.6 5.3a9.4 9.4 0 0 1 0 13.4"
var hudMute = "M16 9.5l5 5M21 9.5l-5 5"
var hudSun = "M12 8.2a3.8 3.8 0 1 0 0 7.6a3.8 3.8 0 1 0 0-7.6zM12 2.8v1.8M12 19.4v1.8M2.8 12h1.8M19.4 12h1.8M5.5 5.5l1.3 1.3M17.2 17.2l1.3 1.3M5.5 18.5l1.3-1.3M17.2 6.8l1.3-1.3"
var hudMic = "M12 3.5a3 3 0 0 1 3 3v5a3 3 0 0 1-6 0v-5a3 3 0 0 1 3-3zM5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"
var hudSlash = "M4 4l16 16"
var hudKeyboard = "M4 6.5h16a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1zM7 10h.01M10 10h.01M13 10h.01M16 10h.01M8 14h8"
var hudNote = "M9 17.5V6l10-2v11.5M9 17.5a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0zM19 15.5a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0z"
var hudPower = "M12 3.5v8M7 6.5a7.5 7.5 0 1 0 10 0"
var hudTouchpad = "M5 5h14a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zM4 15h16M12 15v4"
