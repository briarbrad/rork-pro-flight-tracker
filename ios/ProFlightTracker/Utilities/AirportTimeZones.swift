import Foundation

/// Airport code → time zone, so every time on screen reads in the zone of the
/// airport it belongs to: a JFK departure in New York time, a CDG arrival in
/// Paris time.
///
/// The backend's own `local_display` strings win wherever it ships them, but its
/// zone lookup comes back empty for plenty of routes. Device-local time is never
/// an acceptable fallback — it silently shows the wrong hour for any airport the
/// traveller isn't standing in — so the full airport→zone table is bundled and
/// resolved on device. Zulu is the last resort, and it's always labelled.
nonisolated enum AirportTimeZones {
    /// Zone for a single ICAO or IATA code.
    static func zone(for code: String?) -> TimeZone? {
        guard let code, !code.isEmpty else { return nil }
        return table[code.trimmingCharacters(in: .whitespaces).uppercased()]
    }

    /// First code that resolves wins — pass the codes in confidence order,
    /// e.g. `zone(forAnyOf: flight.originIcao, flight.originIata)`.
    static func zone(forAnyOf codes: String?...) -> TimeZone? {
        for code in codes {
            if let zone = zone(for: code) { return zone }
        }
        return nil
    }

    /// Zone from an Olson identifier the backend sent ("America/New_York").
    static func named(_ identifier: String?) -> TimeZone? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return TimeZone(identifier: identifier)
    }

    /// "New York" / "Paris" — the city half of a zone id, for captions.
    static func cityName(_ zone: TimeZone?) -> String? {
        guard let zone else { return nil }
        return zone.identifier.split(separator: "/").last?
            .replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Table

    /// Lazily built once, immutable afterwards — safe to read from any actor.
    private static let table: [String: TimeZone] = loadTable()

    private static func loadTable() -> [String: TimeZone] {
        var map: [String: TimeZone] = [:]
        map.reserveCapacity(40_000)
        // Bundled long tail: every airport with a known zone, grouped by zone id
        // with space-separated ICAO and IATA codes.
        if let url = Bundle.main.url(forResource: "airport-timezones", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let grouped = try? JSONDecoder().decode([String: String].self, from: data) {
            insert(grouped, into: &map)
        } else {
            print("[AirportTimeZones] bundled table unavailable — major hubs only")
        }
        // Seed hubs are merged either way so the common routes are correct even
        // if the bundled resource ever goes missing.
        insert(hubSeed, into: &map)
        return map
    }

    private static func insert(_ grouped: [String: String], into map: inout [String: TimeZone]) {
        for (identifier, codes) in grouped {
            guard let zone = TimeZone(identifier: identifier) else { continue }
            for code in codes.split(separator: " ") {
                map[String(code)] = zone
            }
        }
    }

    private static let hubSeed: [String: String] = [
        "Africa/Addis_Ababa": "ADD HAAB",
        "Africa/Cairo": "CAI HECA",
        "Africa/Casablanca": "CMN GMMN",
        "Africa/Johannesburg": "CPT FACT FAOR JNB",
        "Africa/Lagos": "DNMM LOS",
        "Africa/Nairobi": "HKJK NBO",
        "America/Anchorage": "ANC PANC",
        "America/Argentina/Buenos_Aires": "EZE SAEZ",
        "America/Bogota": "BOG SKBO",
        "America/Cancun": "CUN MMUN",
        "America/Chicago": "AUS BNA DAL DFW IAH KAUS KBNA KDAL KDFW KIAH KMCI KMDW KMKE KMSP KMSY KORD KSAT KSTL MCI MDW MKE MSP MSY ORD SAT STL",
        "America/Denver": "DEN KDEN KSLC SLC",
        "America/Detroit": "DTW KDTW",
        "America/Edmonton": "CYYC YYC",
        "America/Indiana/Indianapolis": "IND KIND",
        "America/Lima": "LIM SPJC",
        "America/Los_Angeles": "BUR KBUR KLAS KLAX KOAK KPDX KSAN KSEA KSFO KSMF KSNA LAS LAX OAK PDX SAN SEA SFO SMF SNA",
        "America/Mexico_City": "MEX MMMX",
        "America/New_York": "ATL BOS BWI CLE CLT CMH CVG DCA EWR FLL IAD JAX JFK KATL KBOS KBWI KCLE KCLT KCMH KCVG KDCA KEWR KFLL KIAD KJAX KJFK KLGA KMCO KMIA KPHL KPIT KRDU KTPA LGA MCO MIA PHL PIT RDU TPA",
        "America/Panama": "MPTO PTY",
        "America/Phoenix": "KPHX PHX",
        "America/Puerto_Rico": "SJU TJSJ",
        "America/Santiago": "SCEL SCL",
        "America/Sao_Paulo": "GIG GRU SBGL SBGR",
        "America/Toronto": "CYUL CYYZ YUL YYZ",
        "America/Vancouver": "CYVR YVR",
        "Asia/Bahrain": "BAH OBBI",
        "Asia/Bangkok": "BKK HAN HKT VTBS VTSP VVNB",
        "Asia/Colombo": "CMB VCBI",
        "Asia/Dhaka": "DAC VGHS",
        "Asia/Dubai": "AUH DXB OMAA OMDB",
        "Asia/Ho_Chi_Minh": "SGN VVTS",
        "Asia/Hong_Kong": "HKG VHHH",
        "Asia/Jakarta": "CGK WIII",
        "Asia/Jerusalem": "LLBG TLV",
        "Asia/Kathmandu": "KTM VNKT",
        "Asia/Kolkata": "BLR BOM CCU DEL HYD MAA VABB VECC VIDP VOBL VOHS VOMM",
        "Asia/Kuala_Lumpur": "KUL WMKK",
        "Asia/Kuwait": "KWI OKKK",
        "Asia/Makassar": "DPS WADD",
        "Asia/Manila": "MNL RPLL",
        "Asia/Muscat": "MCT OOMS",
        "Asia/Qatar": "DOH OTHH",
        "Asia/Riyadh": "JED OEJN OERK RUH",
        "Asia/Seoul": "GMP ICN RKSI RKSS",
        "Asia/Shanghai": "CAN CKG CTU HGH PEK PKX PVG SHA SZX XIY ZBAA ZBAD ZGGG ZGSZ ZLXY ZSHC ZSPD ZSSS ZUCK ZUUU",
        "Asia/Singapore": "SIN WSSS",
        "Asia/Taipei": "RCTP TPE",
        "Asia/Tokyo": "CTS FUK HND KIX NGO NRT RJAA RJBB RJCC RJFF RJGG RJTT",
        "Atlantic/Reykjavik": "BIKF KEF",
        "Australia/Adelaide": "ADL YPAD",
        "Australia/Brisbane": "BNE YBBN",
        "Australia/Melbourne": "MEL YMML",
        "Australia/Perth": "PER YPPH",
        "Australia/Sydney": "SYD YSSY",
        "Europe/Amsterdam": "AMS EHAM",
        "Europe/Athens": "ATH LGAV",
        "Europe/Berlin": "BER CGN DUS EDDB EDDF EDDH EDDK EDDL EDDM EDDS FRA HAM MUC STR",
        "Europe/Brussels": "BRU EBBR",
        "Europe/Bucharest": "LROP OTP",
        "Europe/Budapest": "BUD LHBP",
        "Europe/Copenhagen": "CPH EKCH",
        "Europe/Dublin": "DUB EIDW",
        "Europe/Helsinki": "EFHK HEL",
        "Europe/Istanbul": "AYT IST LTAI LTFJ LTFM SAW",
        "Europe/Lisbon": "LIS LPPR LPPT OPO",
        "Europe/London": "EDI EGCC EGKK EGLC EGLL EGPH LCY LGW LHR MAN",
        "Europe/Madrid": "AGP BCN LEBL LEMD LEMG LEPA MAD PMI",
        "Europe/Oslo": "ENGM OSL",
        "Europe/Paris": "CDG GVA LFLL LFMN LFPG LFPO LSGG LYS NCE ORY",
        "Europe/Prague": "LKPR PRG",
        "Europe/Riga": "EVRA RIX",
        "Europe/Rome": "FCO LIMC LIML LIN LIPZ LIRF LIRN MXP NAP VCE",
        "Europe/Sofia": "LBSF SOF",
        "Europe/Stockholm": "ARN ESSA",
        "Europe/Tallinn": "EETN TLL",
        "Europe/Vienna": "LOWW VIE",
        "Europe/Vilnius": "EYVI VNO",
        "Europe/Warsaw": "EPKK EPWA KRK WAW",
        "Europe/Zurich": "LSZH ZRH",
        "Pacific/Auckland": "AKL CHC NZAA NZCH NZWN WLG",
        "Pacific/Fiji": "NAN NFFN",
        "Pacific/Guam": "GUM PGUM",
        "Pacific/Honolulu": "HNL OGG PHNL PHOG",
        "Pacific/Tahiti": "NTAA PPT",
    ]
}
