#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/config.sh"

export LC_ALL=C

VERBOSE=false
FORCE_REFRESH=false

for arg in "$@"; do
    if [[ "$arg" == "--auto" ]]; then
        # Meander: "auto detect" hands the location back to Omarchy's own
        # detection (geo.omarchy.org) for Omarchy's panel as well.
        command -v omarchy-weather-location >/dev/null 2>&1 && omarchy-weather-location --clear
        FORCE_REFRESH=true
    elif [[ "$arg" == "--verbose" || "$arg" == "-v" ]]; then
        VERBOSE=true
    elif [[ "$arg" == "--refresh" || "$arg" == "-r" ]]; then
        FORCE_REFRESH=true
    fi
done

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "\e[1;34m[LOCATION-DEBUG]\e[0m $1" >&2
    fi
}

get_existing_location() {
    local gen
    gen="$(get_setting "general" '{}')"
    echo "$gen" | jq -c '.location // empty' 2>/dev/null
}

save_location() {
    local loc_data="$1"
    local gen
    gen="$(get_setting "general" '{}')"
    local updated
    updated="$(echo "$gen" | jq --argjson loc "$loc_data" '.location = $loc')"
    set_setting "general" "$updated"
    "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/weather.sh" --getdata >/dev/null 2>&1 &
}

try_ipapi() {
    log_debug "Attempting primary provider: ipapi.co..."
    local resp
    resp="$(curl -s --max-time 5 -H "User-Agent: meander-location/1.0" "https://ipapi.co/json/" 2>/dev/null)"
    if echo "$resp" | jq -e '(.error | not) and .latitude != null and .longitude != null' >/dev/null 2>&1; then
        echo "$resp" | jq -c '{
            ip: (.ip // null),
            latitude: .latitude,
            longitude: .longitude,
            city: (.city // "Unknown"),
            region: (.region // "Unknown"),
            region_code: (.region_code // null),
            country_name: (.country_name // "Unknown"),
            country_code: (.country_code // null),
            postal: (.postal // null),
            timezone: (.timezone // "UTC"),
            utc_offset: (.utc_offset // null),
            currency: (.currency // null),
            languages: (.languages // null),
            asn: (.asn // null),
            org: (.org // null),
            source: "ipapi.co"
        }'
        return 0
    fi
    return 1
}

try_ip_api_com() {
    log_debug "ipapi.co failed or rate-limited. Falling back to ip-api.com..."
    local resp
    resp="$(curl -s --max-time 5 "http://ip-api.com/json/?fields=status,message,query,lat,lon,city,regionName,region,country,countryCode,zip,timezone,currency,as,org" 2>/dev/null)"
    if echo "$resp" | jq -e '.status == "success" and .lat != null and .lon != null' >/dev/null 2>&1; then
        echo "$resp" | jq -c '{
            ip: (.query // null),
            latitude: .lat,
            longitude: .lon,
            city: (.city // "Unknown"),
            region: (.regionName // "Unknown"),
            region_code: (.region // null),
            country_name: (.country // "Unknown"),
            country_code: (.countryCode // null),
            postal: (.zip // null),
            timezone: (.timezone // "UTC"),
            utc_offset: null,
            currency: (.currency // null),
            languages: null,
            asn: (.as // null),
            org: (.org // null),
            source: "ip-api.com"
        }'
        return 0
    fi
    return 1
}

try_ipwhois() {
    log_debug "ip-api.com failed. Falling back to ipwho.is..."
    local resp
    resp="$(curl -s --max-time 5 "https://ipwho.is/" 2>/dev/null)"
    if echo "$resp" | jq -e '.success == true and .latitude != null and .longitude != null' >/dev/null 2>&1; then
        echo "$resp" | jq -c '{
            ip: (.ip // null),
            latitude: .latitude,
            longitude: .longitude,
            city: (.city // "Unknown"),
            region: (.region // "Unknown"),
            region_code: (.region_code // null),
            country_name: (.country // "Unknown"),
            country_code: (.country_code // null),
            postal: (.postal // null),
            timezone: (.timezone.id // "UTC"),
            utc_offset: (.timezone.utc // null),
            currency: (.connection.currency // null),
            languages: null,
            asn: ((.connection.asn | tostring) // null),
            org: (.connection.org // null),
            source: "ipwho.is"
        }'
        return 0
    fi
    return 1
}

fetch_ip_location() {
    local res
    if res="$(try_ipapi)" && [[ -n "$res" ]]; then
        echo "$res"
        return 0
    fi
    if res="$(try_ip_api_com)" && [[ -n "$res" ]]; then
        echo "$res"
        return 0
    fi
    if res="$(try_ipwhois)" && [[ -n "$res" ]]; then
        echo "$res"
        return 0
    fi
    return 1
}

# Meander: the location is Omarchy's. omarchy-weather-location owns
# ~/.local/state/omarchy/settings/weather.json ({"name", "latitude"?,
# "longitude"?}); with no file, geo.omarchy.org places the network (the same
# order Omarchy's weather panel uses). general.location stays a cache in
# upstream's shape, keyed by omarchy_key so an edit to weather.json (from
# Omarchy's panel or the CLI) re-resolves it. The IP providers above are only
# a fallback for when Omarchy has no answer.
OMARCHY_LOC_FILE="$HOME/.local/state/omarchy/settings/weather.json"

omarchy_location_key() {
    if [[ -s "$OMARCHY_LOC_FILE" ]] && jq -e '(.name // "" | length) > 0 or .latitude != null' "$OMARCHY_LOC_FILE" >/dev/null 2>&1; then
        jq -cS '{name, latitude, longitude}' "$OMARCHY_LOC_FILE" 2>/dev/null
    else
        echo "auto"
    fi
}

# Open-Meteo geocoding (what Omarchy's location picker searches): the result
# nearest to lat/lon when given, else the first. Prints one result or nothing.
geocode_name() {
    local name="$1" lat="${2:-}" lon="${3:-}" resp
    resp="$(curl -fsS --max-time 6 -G "https://geocoding-api.open-meteo.com/v1/search" \
        --data-urlencode "name=$name" -d count=10 -d language=en -d format=json 2>/dev/null)"
    echo "$resp" | jq -c --arg lat "$lat" --arg lon "$lon" '
        (.results // []) | if length == 0 then empty
        elif ($lat == "" or $lon == "") then .[0]
        else min_by(((.latitude - ($lat|tonumber)) | . * .) + ((.longitude - ($lon|tonumber)) | . * .)) end' 2>/dev/null
}

# Builds upstream's location object from a name, coordinates and an optional
# geocoding hit (region, country, timezone).
omarchy_location_object() {
    local name="$1" lat="$2" lon="$3" geo="${4:-}" source="$5" key="$6" tz
    [[ -n "$geo" ]] || geo='{}'
    tz="$(echo "$geo" | jq -r '.timezone // empty')"
    if [[ -z "$tz" ]]; then
        tz="$(curl -fsS --max-time 6 "https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&timezone=auto" 2>/dev/null | jq -r '.timezone // empty' 2>/dev/null)"
    fi
    jq -n --arg name "$name" --argjson lat "$lat" --argjson lon "$lon" --argjson geo "$geo" \
        --arg tz "${tz:-UTC}" --arg source "$source" --arg key "$key" '{
            latitude: $lat,
            longitude: $lon,
            city: (if $name != "" then $name else ($geo.name // "Unknown") end),
            region: ($geo.admin1 // "Unknown"),
            country_name: ($geo.country // "Unknown"),
            country_code: ($geo.country_code // null),
            postal: (($geo.postcodes // [])[0] // null),
            timezone: $tz,
            source: $source,
            omarchy_key: $key
        }'
}

fetch_omarchy_location() {
    local key="$1" name lat lon geo resp
    if [[ "$key" == "auto" ]]; then
        log_debug "No Omarchy location set. Asking geo.omarchy.org..."
        resp="$(curl -fsS --max-time 5 https://geo.omarchy.org/ 2>/dev/null)"
        echo "$resp" | jq -e '.latitude != null and .longitude != null' >/dev/null 2>&1 || return 1
        name="$(echo "$resp" | jq -r '.name // ""')"
        lat="$(echo "$resp" | jq -r '.latitude')"
        lon="$(echo "$resp" | jq -r '.longitude')"
        geo="$(geocode_name "$name" "$lat" "$lon")"
        [[ -n "$geo" ]] || geo="$(echo "$resp" | jq -c '{country_code: .country, timezone}')"
        omarchy_location_object "$name" "$lat" "$lon" "$geo" "geo.omarchy.org" "$key"
        return
    fi

    name="$(echo "$key" | jq -r '.name // "" | if type == "string" then . else "" end')"
    lat="$(echo "$key" | jq -r '.latitude // empty')"
    lon="$(echo "$key" | jq -r '.longitude // empty')"
    if [[ -n "$lat" && -n "$lon" ]]; then
        log_debug "Omarchy location: $name ($lat, $lon)."
        geo=""
        [[ -n "$name" ]] && geo="$(geocode_name "$name" "$lat" "$lon")"
        omarchy_location_object "$name" "$lat" "$lon" "$geo" "omarchy" "$key"
        return
    fi
    [[ -n "$name" ]] || return 1
    log_debug "Omarchy location is a name only ($name). Geocoding it..."
    geo="$(geocode_name "$name")"
    [[ -n "$geo" ]] || return 1
    omarchy_location_object "$name" "$(echo "$geo" | jq '.latitude')" "$(echo "$geo" | jq '.longitude')" "$geo" "omarchy" "$key"
}

resolve_location() {
    local existing key
    existing="$(get_existing_location)"
    key="$(omarchy_location_key)"

    if [[ "$FORCE_REFRESH" == "false" && -n "$existing" && "$existing" != "null" ]] &&
        [[ "$(echo "$existing" | jq -c '.omarchy_key // empty' 2>/dev/null)" == "$(jq -cn --arg k "$key" '$k')" ]]; then
        # A stored Omarchy location never goes stale; an auto-detected one is
        # re-checked once a day, as upstream did.
        local updated_at diff
        updated_at=$(echo "$existing" | jq -r '.updated_at // 0')
        diff=$(( $(date +%s) - updated_at ))
        if [[ "$key" != "auto" || $diff -lt 86400 ]]; then
            log_debug "Cached location matches Omarchy's. Returning it."
            echo "$existing"
            return
        fi
    fi

    log_debug "Fetching location details..."
    local raw_loc
    raw_loc="$(fetch_omarchy_location "$key")"
    if [[ -z "$raw_loc" || "$raw_loc" == "null" ]]; then
        log_debug "Omarchy gave no location. Falling back to IP providers."
        raw_loc="$(fetch_ip_location)"
        [[ -n "$raw_loc" ]] && raw_loc="$(echo "$raw_loc" | jq -c --arg k "$key" '. + {omarchy_key: $k}')"
    fi

    if [[ -n "$raw_loc" && "$raw_loc" != "null" ]]; then
        log_debug "Geolocation retrieved successfully."
        local final_loc
        final_loc=$(echo "$raw_loc" | jq -c --argjson ts "$(date +%s)" '. + {updated_at: $ts}')
        save_location "$final_loc"
        echo "$final_loc"
    elif [[ -n "$existing" && "$existing" != "null" ]]; then
        log_debug "All providers failed. Falling back to existing config location."
        echo "$existing"
    else
        log_debug "No location data or config available. Defaulting to fallback payload."
        local fallback
        fallback='{"latitude": 0.0, "longitude": 0.0, "city": "Unknown", "region": "Unknown", "country_name": "Unknown", "timezone": "UTC", "updated_at": 0}'
        save_location "$fallback"
        echo "$fallback"
    fi
}

resolve_location
