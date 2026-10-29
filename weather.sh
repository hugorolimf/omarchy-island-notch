#!/bin/bash
# Island Notch weather card: prints {"location": ..., "fetchedAt": ..., "data": <open-meteo>}.
# Location comes from the same place as omarchy.weather: the weather.json state
# file (omarchy-weather-location); without coordinates there, it is detected
# from the IP via wttr.in (cached for a day). The forecast is cached for
# 10 minutes; --force skips the cache.

set -u
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/island-notch"
LOC_FILE="$HOME/.local/state/omarchy/settings/weather.json"
AUTO_LOC="$CACHE_DIR/location.json"
FORECAST="$CACHE_DIR/weather.json"
mkdir -p "$CACHE_DIR"

force=0
[[ ${1:-} == "--force" ]] && force=1

age() { echo $(( $(date +%s) - $(stat -c %Y "$1" 2>/dev/null || echo 0) )); }

name="" lat="" lon=""
if [[ -s $LOC_FILE ]]; then
  name=$(jq -r '.name // ""' "$LOC_FILE" 2>/dev/null)
  lat=$(jq -r '.latitude // ""' "$LOC_FILE" 2>/dev/null)
  lon=$(jq -r '.longitude // ""' "$LOC_FILE" 2>/dev/null)
fi

if [[ -z $lat || -z $lon ]]; then
  if [[ ! -s $AUTO_LOC || $(age "$AUTO_LOC") -gt 86400 ]]; then
    query=""
    [[ -n $name ]] && query=$(jq -rn --arg n "$name" '$n | @uri')
    if curl -fsS --max-time 8 "https://wttr.in/${query}?format=j1" |
      jq -ce '.nearest_area[0] | {name: .areaName[0].value, latitude: .latitude, longitude: .longitude}' >"$AUTO_LOC.tmp" 2>/dev/null; then
      mv "$AUTO_LOC.tmp" "$AUTO_LOC"
    else
      rm -f "$AUTO_LOC.tmp"
    fi
  fi
  if [[ -s $AUTO_LOC ]]; then
    [[ -z $name ]] && name=$(jq -r '.name // ""' "$AUTO_LOC")
    lat=$(jq -r '.latitude // ""' "$AUTO_LOC")
    lon=$(jq -r '.longitude // ""' "$AUTO_LOC")
  fi
fi

key="$lat,$lon"
if (( force )) || [[ ! -s $FORECAST || $(age "$FORECAST") -gt 600 ]] || [[ $(jq -r '.key // ""' "$FORECAST" 2>/dev/null) != "$key" ]]; then
  if [[ -n $lat && -n $lon ]]; then
    url="https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon"
    url+="&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
    url+="&hourly=temperature_2m,weather_code,is_day,precipitation_probability&forecast_hours=7"
    url+="&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&forecast_days=5"
    url+="&timezone=auto"
    if curl -fsS --max-time 8 "$url" |
      jq -ce --arg name "$name" --arg key "$key" '{location: $name, key: $key, fetchedAt: (now | floor), data: .}' >"$FORECAST.tmp" 2>/dev/null; then
      mv "$FORECAST.tmp" "$FORECAST"
    else
      rm -f "$FORECAST.tmp"
    fi
  fi
fi

if [[ -s $FORECAST ]]; then
  cat "$FORECAST"
else
  echo '{"error": "offline"}'
fi
