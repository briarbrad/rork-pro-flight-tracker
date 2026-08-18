import SwiftUI

/// One plain-English glossary definition for an FAA/aviation abbreviation.
nonisolated struct GlossaryEntry: Identifiable, Hashable, Sendable {
    let term: String
    let name: String
    let definition: String
    var id: String { term }
}

/// Plain-English explanation attached to a risk signal.
nonisolated struct SignalExplanation: Sendable {
    let meaning: String
    let next: String
}

/// Offline FAA-lingo translation engine: jargon definitions, NOTAM contraction
/// expansion, PIREP decoding, METAR weather codes, and risk-signal explainers.
/// Everything decodes instantly on device — no network, no AI cost.
enum FAAGlossary {

    // MARK: - Jargon dictionary (tappable dotted-underline terms)

    static let terms: [String: GlossaryEntry] = [
        "GDP": GlossaryEntry(term: "GDP", name: "Ground Delay Program",
            definition: "The FAA slows the flow of arrivals into a congested or weather-hit airport by holding flights at their departure airports. Each affected flight gets an EDCT — a specific wheels-up time slot. You usually board on time, then sit at the gate or on a taxiway until your slot."),
        "GS": GlossaryEntry(term: "GS", name: "Ground Stop",
            definition: "The FAA's strictest traffic measure: flights headed to the affected airport are held on the ground at their origin and cannot depart until the stop is lifted. Ground stops are usually short but often extend in bad weather."),
        "EDCT": GlossaryEntry(term: "EDCT", name: "Expect Departure Clearance Time",
            definition: "A specific wheels-up time slot assigned to a flight during a ground delay program. The aircraft can't take off before its EDCT, which is why you sometimes board on time and then wait."),
        "ATC": GlossaryEntry(term: "ATC", name: "Air Traffic Control",
            definition: "The FAA controllers who direct aircraft on the ground and in the air. When people say 'ATC delay', it means traffic management — not the airline — is holding the flight."),
        "ATFM": GlossaryEntry(term: "ATFM", name: "Air Traffic Flow Management",
            definition: "The umbrella term for FAA programs (ground stops, ground delay programs, reroutes) that balance traffic demand against what airports and airspace can handle."),
        "TBFM": GlossaryEntry(term: "TBFM", name: "Time-Based Flow Management",
            definition: "An FAA system that meters arrivals into busy airports by assigning precise crossing times. When TBFM is active, flights get slowed en route to smooth the arrival flow."),
        "TFMS": GlossaryEntry(term: "TFMS", name: "Traffic Flow Management System",
            definition: "The FAA's national system for tracking and managing traffic flow, including delay programs and reroutes."),
        "TFDM": GlossaryEntry(term: "TFDM", name: "Terminal Flight Data Manager",
            definition: "An FAA system that meters departures on the airport surface, sequencing taxi-outs so aircraft aren't stuck burning fuel in long takeoff queues."),
        "STDDS": GlossaryEntry(term: "STDDS", name: "SWIM Terminal Data Distribution System",
            definition: "An FAA feed of airport surface events — runway configuration, surface movement, and departure queue data."),
        "SWIM": GlossaryEntry(term: "SWIM", name: "System Wide Information Management",
            definition: "The FAA's live data backbone. This app listens to SWIM feeds for NOTAMs, surface data, and flow-management messages — the same data airlines' ops centers watch."),
        "NAS": GlossaryEntry(term: "NAS", name: "National Airspace System",
            definition: "The whole US air-traffic network: airports, airspace, controllers, and equipment. 'NAS status' means the FAA's live report of delays and closures across the country."),
        "METAR": GlossaryEntry(term: "METAR", name: "Aviation routine weather report",
            definition: "The standard airport surface weather observation, updated about once an hour (more often when conditions change fast). It covers wind, visibility, clouds, temperature, and active weather."),
        "TAF": GlossaryEntry(term: "TAF", name: "Terminal Aerodrome Forecast",
            definition: "A 24-30 hour weather forecast written specifically for the area around an airport. Airlines use TAFs to predict delay programs hours ahead."),
        "NOTAM": GlossaryEntry(term: "NOTAM", name: "Notice to Air Missions",
            definition: "An official notice about a runway closure, out-of-service equipment, construction, or hazard. NOTAMs are written in heavy abbreviations — this app translates them for you."),
        "PIREP": GlossaryEntry(term: "PIREP", name: "Pilot Report",
            definition: "A live report from a pilot actually flying in the area — turbulence, icing, cloud tops. Often the earliest sign of conditions that later cause delays."),
        "SIGMET": GlossaryEntry(term: "SIGMET", name: "Significant Meteorological Information",
            definition: "A warning of weather hazardous to all aircraft: severe turbulence, severe icing, thunderstorm areas, or volcanic ash."),
        "AIRMET": GlossaryEntry(term: "AIRMET", name: "Airmen's Meteorological Information",
            definition: "A weather advisory for conditions less severe than a SIGMET — moderate turbulence or icing, strong surface winds, or widespread low visibility."),
        "RVR": GlossaryEntry(term: "RVR", name: "Runway Visual Range",
            definition: "How far a pilot can see down the runway, measured by sensors alongside it, in feet. Low RVR forces wider spacing between arrivals and can halt departures."),
        "IFR": GlossaryEntry(term: "IFR", name: "Instrument Flight Rules conditions",
            definition: "Ceilings of 500-1,000 ft or visibility of 1-3 miles. Pilots fly on instruments and the airport accepts fewer arrivals per hour — delays get likely."),
        "LIFR": GlossaryEntry(term: "LIFR", name: "Low Instrument Flight Rules conditions",
            definition: "Ceilings below 500 ft or visibility under 1 mile — the worst category. Arrival rates drop sharply and diversions become possible."),
        "MVFR": GlossaryEntry(term: "MVFR", name: "Marginal Visual Flight Rules conditions",
            definition: "Ceilings of 1,000-3,000 ft or visibility of 3-5 miles. Flyable, but the first hint that weather could tighten operations."),
        "VFR": GlossaryEntry(term: "VFR", name: "Visual Flight Rules conditions",
            definition: "Good weather — ceilings above 3,000 ft and visibility over 5 miles. The airport can run at full capacity."),
        "ILS": GlossaryEntry(term: "ILS", name: "Instrument Landing System",
            definition: "Radio guidance that lets aircraft land in low visibility. If an ILS is out of service and weather is poor, that runway may become unusable."),
        "TRACON": GlossaryEntry(term: "TRACON", name: "Terminal Radar Approach Control",
            definition: "The radar facility handling aircraft arriving and departing within roughly 40 miles of a major airport."),
        "ARTCC": GlossaryEntry(term: "ARTCC", name: "Air Route Traffic Control Center",
            definition: "A regional FAA center controlling high-altitude traffic between airports. Center-level constraints can delay flights far from either airport."),
        "AFP": GlossaryEntry(term: "AFP", name: "Airspace Flow Program",
            definition: "Like a ground delay program, but for a chunk of airspace instead of an airport — flights crossing a storm-blocked region get metered departure times."),
        "MIT": GlossaryEntry(term: "MIT", name: "Miles-In-Trail",
            definition: "A spacing restriction: controllers must keep, say, 20 miles between successive aircraft on a route. It quietly slows every flight through the affected flow."),
        "CDM": GlossaryEntry(term: "CDM", name: "Collaborative Decision Making",
            definition: "The FAA-airline data-sharing process used to plan delay programs. CDM messages are often the first public sign a program is coming."),
        "ITWS": GlossaryEntry(term: "ITWS", name: "Integrated Terminal Weather System",
            definition: "The FAA's terminal-area weather radar product: wind shear alerts, storm cells, and gust fronts near the airport."),
        "ADS-B": GlossaryEntry(term: "ADS-B", name: "Automatic Dependent Surveillance-Broadcast",
            definition: "Aircraft continuously broadcast their GPS position. This is where the live map position comes from."),
        "ETE": GlossaryEntry(term: "ETE", name: "Estimated Time En Route",
            definition: "The planned flying time from takeoff to landing."),

        // App verdict language — the risk badge and confidence label are
        // jargon too, and get the same tap-to-define treatment as GDP/EDCT.
        "WATCH": GlossaryEntry(term: "Watch", name: "Moderate-risk verdict",
            definition: "Something could still move this flight, but nothing has confirmed it yet — worth keeping an eye on, not yet an active problem. It escalates to High risk when a threat is confirmed (an active FAA program, weather below limits, a broken aircraft rotation) and drops to Low risk when the picture clears."),
        "LOW RISK": GlossaryEntry(term: "Low risk", name: "Low-risk verdict",
            definition: "The full analysis checked every source that carries signal at this horizon and found nothing likely to move this flight. Only a complete pre-flight brief can claim this — a quick status check never does, because it can't see weather or FAA programs."),
        "HIGH RISK": GlossaryEntry(term: "High risk", name: "High-risk verdict",
            definition: "At least one confirmed factor is expected to disrupt this flight — an active FAA program, weather below operating limits, a broken aircraft rotation, or an official major delay or cancellation. Treat disruption as the base case and check the recommended action."),
        "CONFIDENCE": GlossaryEntry(term: "Confidence", name: "How current the assessment is",
            definition: "Confidence measures how close the flight is to departure — NOT how certain any single predicted number is. Near departure, live data (positions, EDCTs, gate times) is authoritative, so confidence reads High. Far out, conditions can still change, so it stays Medium or Low even when everything looks clear. A High-confidence Watch means the assessment is current — not that the outcome is locked in."),
    ]

    static func entry(for term: String) -> GlossaryEntry? {
        terms[term.uppercased()]
    }

    /// glossary:/// deep link for a term — tappable chips and labels route
    /// through the same `glossaryLinkHandler` as dotted-underline prose.
    static func url(for term: String) -> URL? {
        let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? term
        return URL(string: "glossary:///\(encoded)")
    }

    // MARK: - Tappable jargon (dotted underline + glossary:// links)

    private static let termRegex: NSRegularExpression? = {
        let sorted = terms.keys.sorted { $0.count > $1.count }
        let alternation = sorted.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try? NSRegularExpression(pattern: "\\b(" + alternation + ")\\b")
    }()

    /// Marks known abbreviations in the text as tappable glossary links
    /// with a dotted teal underline.
    static func attributed(_ text: String) -> AttributedString {
        guard let regex = termRegex else { return AttributedString(text) }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return AttributedString(text) }

        var result = AttributedString()
        var cursor = 0
        for match in matches {
            let range = match.range
            if range.location > cursor {
                result += AttributedString(ns.substring(with: NSRange(location: cursor, length: range.location - cursor)))
            }
            let term = ns.substring(with: range)
            var piece = AttributedString(term)
            if terms[term] != nil {
                let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? term
                piece.link = URL(string: "glossary:///\(encoded)")
                piece.underlineStyle = Text.LineStyle(pattern: .dot)
                piece.foregroundColor = Theme.teal
            }
            result += piece
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            result += AttributedString(ns.substring(from: cursor))
        }
        return result
    }

    // MARK: - NOTAM contraction expansion

    private static let notamContractions: [String: String] = [
        "NOT AVBL": "not available", "U/S": "unserviceable", "N/A": "not available",
        "RWY": "runway", "TWY": "taxiway", "APRON": "apron", "CLSD": "closed",
        "OTS": "out of service", "WIP": "work in progress", "AVBL": "available",
        "UNAVBL": "unavailable", "MAINT": "maintenance", "OBST": "obstacle",
        "LGTD": "lighted", "LGTS": "lights", "LGT": "lighting",
        "PAPI": "PAPI approach lights", "VASI": "VASI approach lights",
        "LOC": "localizer", "DME": "distance measuring equipment",
        "NDB": "radio beacon", "APCH": "approach", "DEP": "departure",
        "ARR": "arrival", "TKOF": "takeoff", "LDG": "landing", "ACFT": "aircraft",
        "ARPT": "airport", "AD": "aerodrome", "FREQ": "frequency", "SVC": "service",
        "EQPT": "equipment", "INOP": "inoperative", "RTE": "route",
        "SID": "standard departure route", "STAR": "standard arrival route",
        "TFC": "traffic", "THR": "threshold", "DTHR": "displaced threshold",
        "BTN": "between", "EXC": "except", "DLY": "daily", "TIL": "until",
        "PERM": "permanent", "TEMPO": "temporary", "HEL": "helicopter",
        "PSN": "position", "ADJ": "adjacent", "WI": "within", "OPS": "operations",
        "OPN": "open", "PAX": "passengers", "RCLL": "runway centerline lights",
        "RCL": "runway centerline", "REDL": "runway edge lights",
        "RTZL": "touchdown zone lights", "TWR": "tower", "CTC": "contact",
        "EXP": "expect", "FLW": "following", "GRVL": "gravel", "SFC": "surface",
        "SKED": "scheduled", "PRKG": "parking", "TMPRY": "temporary",
        "UFN": "until further notice", "UNREL": "unreliable", "CNL": "cancelled",
        "FICON": "field condition", "RSC": "runway surface condition",
        "CONST": "construction", "CONC": "concrete", "ASPH": "asphalt",
        "ELEV": "elevation", "MSL": "above sea level", "AGL": "above ground level",
        "VIS": "visibility", "WX": "weather", "HAZ": "hazard", "PLW": "plow",
        "SR": "sunrise", "SS": "sunset", "MON": "Monday", "TUE": "Tuesday",
        "WED": "Wednesday", "THU": "Thursday", "FRI": "Friday", "SAT": "Saturday",
        "SUN": "Sunday",
    ]

    private static let notamKeysSorted: [String] =
        notamContractions.keys.sorted { $0.count > $1.count }

    /// Expands NOTAM shorthand into plain English, leaving identifiers intact.
    /// "RWY 22L CLSD WIP" → "runway 22L closed work in progress".
    static func expandNotam(_ text: String) -> String {
        var result = text
        for key in notamKeysSorted {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: key) + "\\b"
            result = result.replacingOccurrences(of: pattern,
                                                 with: notamContractions[key] ?? key,
                                                 options: .regularExpression)
        }
        return result
    }

    // MARK: - PIREP decoding

    private static let pirepCodes: [String: String] = [
        "LGT": "light", "MOD": "moderate", "SEV": "severe", "EXTRM": "extreme",
        "NEG": "none reported", "CONT": "continuous", "OCNL": "occasional",
        "INTMT": "intermittent", "CHOP": "choppy air", "CAT": "clear-air turbulence",
        "LLWS": "low-level wind shear", "RIME": "rime ice", "MXD": "mixed ice",
        "BKN": "broken clouds", "OVC": "overcast", "SCT": "scattered clouds",
        "FEW": "few clouds", "SKC": "sky clear", "TOPS": "tops at",
        "BASES": "bases at", "BLO": "below", "ABV": "above",
        "DURD": "during descent", "DURC": "during climb",
        "ZL": "freezing drizzle", "ZR": "freezing rain",
    ]

    private static let pirepKeysSorted: [String] =
        pirepCodes.keys.sorted { $0.count > $1.count }

    /// Turns a raw PIREP into labeled, readable lines.
    static func decodePirep(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "\\bUUA\\b", with: "URGENT pilot report",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: "\\bUA\\b", with: "Pilot report",
                                         options: .regularExpression)
        let markers: [(String, String)] = [
            ("/OV", "\nNear: "), ("/TM", "\nTime (UTC): "), ("/FL", "\nAltitude: "),
            ("/TP", "\nAircraft: "), ("/SK", "\nSky: "), ("/WX", "\nWeather: "),
            ("/TA", "\nTemperature (°C): "), ("/WV", "\nWind: "),
            ("/TB", "\nTurbulence: "), ("/IC", "\nIcing: "), ("/RM", "\nRemarks: "),
        ]
        for (marker, label) in markers {
            text = text.replacingOccurrences(of: marker, with: label)
        }
        for key in pirepKeysSorted {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: key) + "\\b"
            text = text.replacingOccurrences(of: pattern,
                                             with: pirepCodes[key] ?? key,
                                             options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - METAR weather phenomena

    private static let wxCodes: [String: String] = [
        "TS": "thunderstorm", "RA": "rain", "SN": "snow", "DZ": "drizzle",
        "GR": "hail", "GS": "small hail", "PL": "ice pellets", "IC": "ice crystals",
        "UP": "precipitation", "FZ": "freezing", "SH": "showers of", "BR": "mist",
        "FG": "fog", "FU": "smoke", "HZ": "haze", "DU": "dust", "SA": "sand",
        "VA": "volcanic ash", "SQ": "squalls", "FC": "funnel cloud",
        "PO": "dust whirls", "BL": "blowing", "DR": "drifting", "MI": "shallow",
        "BC": "patches of", "PR": "partial",
    ]

    /// Decodes METAR phenomena like "-FZRA BR" → "light freezing rain, mist".
    static func decodeWx(_ phenomena: String) -> String {
        let tokens = phenomena.uppercased().split(separator: " ")
        let decoded = tokens.map { decodeWxToken(String($0)) }
        return decoded.joined(separator: ", ")
    }

    private static func decodeWxToken(_ token: String) -> String {
        var code = token
        var parts: [String] = []
        if code.hasPrefix("+") { parts.append("heavy"); code.removeFirst() }
        else if code.hasPrefix("-") { parts.append("light"); code.removeFirst() }
        if code.hasPrefix("VC") { parts.append("nearby"); code.removeFirst(2) }
        while code.count >= 2 {
            let pair = String(code.prefix(2))
            parts.append(wxCodes[pair] ?? pair.lowercased())
            code.removeFirst(2)
        }
        if !code.isEmpty { parts.append(code.lowercased()) }
        return parts.joined(separator: " ")
    }

    // MARK: - Cloud coverage & categories

    static func cloudCoverage(_ code: String) -> String {
        switch code.uppercased() {
        case "FEW": return "Few clouds (1-2/8 of the sky)"
        case "SCT": return "Scattered clouds (3-4/8 of the sky)"
        case "BKN": return "Broken clouds (5-7/8) — counts as a ceiling"
        case "OVC": return "Overcast — a solid layer"
        case "CLR", "SKC": return "Clear skies"
        case "VV": return "Sky obscured (vertical visibility only)"
        default: return code
        }
    }

    static func categoryExplanation(_ category: String) -> String {
        switch category.uppercased() {
        case "VFR":
            return "Good weather. Ceilings above 3,000 ft and visibility over 5 miles — the airport can run at full arrival capacity."
        case "MVFR":
            return "Marginal conditions. Ceilings 1,000-3,000 ft or visibility 3-5 miles. Flyable, but the first hint that operations could tighten."
        case "IFR":
            return "Instrument conditions. Ceilings 500-1,000 ft or visibility 1-3 miles. Arrivals need wider spacing, so the airport accepts fewer flights per hour — delays become likely."
        case "LIFR":
            return "Very low conditions. Ceilings under 500 ft or visibility below 1 mile — the worst category. Arrival rates drop sharply and diversions become possible."
        default:
            return "Flight category not reported."
        }
    }

    /// Decodes TAF change indicators like FM / TEMPO / BECMG / PROB30.
    static func decodeChangeIndicator(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let upper = raw.uppercased()
        if upper.hasPrefix("FM") { return "From" }
        if upper.contains("TEMPO") { return "Temporarily" }
        if upper.contains("BECMG") { return "Becoming" }
        if upper.hasPrefix("PROB") {
            let digits = upper.dropFirst(4)
            return digits.isEmpty ? "Chance of" : "\(digits)% chance of"
        }
        return raw
    }

    // MARK: - Risk signal explainers

    /// Plain-English "what it means / what happens next" for a fired signal key.
    static func explain(signalKey key: String) -> SignalExplanation? {
        if key == "flight.cancelled" || key == "flight.status-cancel" {
            return SignalExplanation(
                meaning: "The airline has formally scrubbed this flight. It will not operate under this flight number today.",
                next: "Rebooking usually opens immediately in the airline's app — act fast, seats on later flights go quickly. The aircraft and crew may be reassigned, which can ripple into other flights.")
        }
        if key == "flight.diverted" {
            return SignalExplanation(
                meaning: "The flight is no longer heading to its planned destination — weather, a medical event, or a technical issue forced a change.",
                next: "The airline will announce onward plans after landing: often a refuel-and-continue, sometimes a bus or rebooking. Bags stay with the aircraft.")
        }
        if key == "flight.status-delay" {
            return SignalExplanation(
                meaning: "The airline's own status feed is now calling this flight delayed — the delay is official, not just a trend.",
                next: "Watch the estimated times: a delay that keeps growing in small steps often signals a deeper problem (late aircraft, crew timing, or a traffic program).")
        }
        if key == "flight.dep-slip-major" {
            return SignalExplanation(
                meaning: "The estimated departure has slipped 45+ minutes past schedule. At most airlines this is the threshold where connections start breaking and crew duty-time limits come into play.",
                next: "Check your connection window now. If the crew hits a duty limit the flight can cancel late — have a backup flight in mind.")
        }
        if key == "flight.dep-slip" {
            return SignalExplanation(
                meaning: "The estimated departure is running 15+ minutes behind schedule — an early tell, often before the airline sends any notification.",
                next: "Small slips frequently grow. Watch whether the inbound aircraft is late or a traffic program is active at either airport.")
        }
        if key == "flight.arr-slip" {
            return SignalExplanation(
                meaning: "The projected arrival is trending 30+ minutes late, even if departure looks fine — usually en-route winds, reroutes, or arrival metering.",
                next: "If you have a connection, check its gate and departure time. Airlines can hold connections briefly, but only for groups.")
        }
        if key.hasSuffix(".ground-stop") {
            return SignalExplanation(
                meaning: "The FAA has ordered flights bound for this airport to stay on the ground at their origins. Nothing departs for it until the stop lifts. This is the strongest traffic measure the FAA has.",
                next: "Ground stops have a published end time but often extend. When one lifts, expect a surge of delayed departures and a slow recovery over several hours.")
        }
        if key.hasSuffix(".gdp") {
            return SignalExplanation(
                meaning: "A Ground Delay Program is metering arrivals into this airport. Departing flights get an EDCT — a fixed wheels-up slot — so you may board on time and then wait.",
                next: "Expect the posted delay to change as the program is revised. GDPs often run for hours; flights late in the day accumulate the most delay.")
        }
        if key.hasSuffix(".delays") {
            return SignalExplanation(
                meaning: "The FAA's national status board is reporting general arrival or departure delays at this airport — traffic volume, weather, staffing, or runway configuration.",
                next: "These delays usually grow through the afternoon and peak in the evening. Earlier flights are safer bets.")
        }
        if key.hasSuffix(".closure") {
            return SignalExplanation(
                meaning: "A runway or portion of the airport is closed — construction, an incident, or snow removal. Fewer runways means fewer arrivals and departures per hour.",
                next: "If weather is good the impact may be small. If weather turns, a closure amplifies delays fast because there's no spare capacity.")
        }
        if key == "chain.turn-negative" {
            return SignalExplanation(
                meaning: "Your aircraft's inbound leg is projected to land after your flight is scheduled to depart. The math doesn't work — a delay is effectively certain even though nothing is posted yet.",
                next: "The airline will either delay your flight or swap in a different aircraft. Watch for a tail-number change; a swap can actually erase the delay.")
        }
        if key == "chain.turn-tight" {
            return SignalExplanation(
                meaning: "The time between your aircraft arriving and your flight departing is below the normal minimum turn time for this aircraft type. Cleaning, catering, fueling, and boarding all have to be rushed.",
                next: "Tight turns often add 10-30 minutes. If the inbound slips any further, your departure almost certainly moves.")
        }
        if key == "chain.inbound-cancelled" {
            return SignalExplanation(
                meaning: "The flight that was supposed to bring your aircraft was cancelled. Your airplane isn't coming on its planned rotation.",
                next: "The airline must find another aircraft. At a hub this can be quick; at a smaller station it often means long delay or cancellation. Watch for an equipment swap or schedule change.")
        }
        if key == "chain.inbound-late" {
            return SignalExplanation(
                meaning: "The aircraft assigned to your flight is running late on its previous leg. This is the single most common cause of departure delays — and it shows up here before the airline posts anything.",
                next: "Your departure usually slips by roughly the inbound's lateness minus any schedule padding. Track the inbound leg to see the trend.")
        }
        if key.hasSuffix(".lifr") {
            return SignalExplanation(
                meaning: "Conditions at this airport are LIFR — ceilings under 500 ft or visibility below 1 mile. Only the most capable aircraft and crews can land, with wide spacing between arrivals.",
                next: "Expect significant delays and possible diversions. Recovery depends entirely on the weather lifting.")
        }
        if key.hasSuffix(".ifr") {
            return SignalExplanation(
                meaning: "Conditions at this airport are IFR — low ceilings or reduced visibility. Arrivals need bigger gaps between them, cutting the airport's hourly capacity.",
                next: "If traffic demand is high, the FAA often responds with a ground delay program. Watch for one within the next hour or two.")
        }
        if key.hasSuffix(".gusts") {
            return SignalExplanation(
                meaning: "Strong gusty winds are hitting the field. Gusts force wider arrival spacing, can close certain runways (crosswind limits), and make ground handling slower.",
                next: "Expect a reduced arrival rate. If gusts align badly with the runways, delays climb quickly.")
        }
        if key.hasSuffix(".taf-ts") {
            return SignalExplanation(
                meaning: "The airport's forecast calls for thunderstorms within the next 12 hours. Storms are the #1 driver of FAA delay programs.",
                next: "Programs are usually announced 1-3 hours before storms arrive. If your flight is near the forecast window, expect metering or a ground stop.")
        }
        if key.hasSuffix(".ts") {
            return SignalExplanation(
                meaning: "Thunderstorms are on the field right now. Arrivals and departures pause or reroute around cells, and the ramp may close for lightning.",
                next: "Storm delays are usually sharp but temporary — flow recovers within an hour or two of the cells moving through.")
        }
        if key.hasSuffix(".fz") {
            return SignalExplanation(
                meaning: "Freezing precipitation is being reported. Every departing aircraft needs deicing, which adds 15-45 minutes per flight and creates queues at the deice pads.",
                next: "Expect rolling departure delays that compound through the day. Cancellations rise if precipitation is heavy or holdover times get short.")
        }
        if key.contains("lightning") {
            return SignalExplanation(
                meaning: "Lightning is striking near the airport. When strikes get within about 5 miles, the ramp closes: no boarding, no bag loading, no fueling, no pushbacks.",
                next: "Ramp closures usually last 10-40 minutes after the last close strike, then everything restarts at once — expect a burst of short delays.")
        }
        return nil
    }
}
