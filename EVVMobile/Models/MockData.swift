import Foundation

enum MockData {
    // MARK: - Clients (PA addresses)
    static let clients: [Client] = [
        Client(id: UUID(), name: "James Whitaker", address: "412 Maple St", city: "Harrisburg, PA 17101",
               allergies: ["Penicillin", "Peanuts (severe — EpiPen in kitchen drawer)"],
               safetyAlerts: ["Elopement risk in crowded settings", "Do not leave unattended near water"],
               protocols: ["Seizure protocol on file — time seizures over 2 min, call 911 over 5 min", "2-person transfer for stairs"]),
        Client(id: UUID(), name: "Dorothy Kline", address: "88 Chestnut Ave", city: "Lancaster, PA 17602",
               allergies: ["Sulfa drugs", "Shellfish"],
               safetyAlerts: ["Fall risk — uses walker at all times"],
               protocols: ["Diabetic — check glucose before meals, log readings", "Soft-food diet, cut food to dime size"]),
        Client(id: UUID(), name: "Marcus Bell", address: "2301 Walnut St", city: "Allentown, PA 18104",
               allergies: ["Latex"],
               safetyAlerts: ["May exit vehicle when stopped — child locks required"],
               protocols: ["Behavior support plan on file — use low, calm voice during escalation"]),
        Client(id: UUID(), name: "Sophia Reyes", address: "17 Birch Ln", city: "York, PA 17403",
               allergies: ["No known allergies"],
               safetyAlerts: ["Pica risk — keep small objects out of reach"],
               protocols: ["1:1 line-of-sight supervision in community"]),
        Client(id: UUID(), name: "Henry Osei", address: "540 Spruce Rd", city: "Reading, PA 19601",
               allergies: ["Bee stings (carries EpiPen)"],
               safetyAlerts: ["Wanders at night — door alarm in use"],
               protocols: ["Medication administration requires two-staff verification"]),
        Client(id: UUID(), name: "Linda Cho", address: "9 Willow Ct", city: "Hershey, PA 17033",
               allergies: ["Gluten (celiac)"],
               safetyAlerts: ["Aspiration risk — thickened liquids only"],
               protocols: ["Choking protocol on file", "Positioning: upright 30 min after meals"])
    ]

    // MARK: - Staff
    static let currentStaff = Staff(id: UUID(), name: "Alex Morgan", role: "Direct Support Professional")
    static let staff: [Staff] = [
        currentStaff,
        Staff(id: UUID(), name: "Brianna Cole", role: "Direct Support Professional"),
        Staff(id: UUID(), name: "Devon Price", role: "Community Support Specialist"),
        Staff(id: UUID(), name: "Tanya Ruiz", role: "Program Supervisor")
    ]

    static func date(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    // MARK: - Today's schedule
    static func todaysVisits() -> [Visit] {
        let now = Date()
        return [
            Visit(id: UUID(), clients: [clients[0]], service: .inHomeSupport,
                  scheduledStart: date(daysAgo: 0, hour: 7), scheduledEnd: date(daysAgo: 0, hour: 9),
                  actualStart: date(daysAgo: 0, hour: 7, minute: 2), actualEnd: date(daysAgo: 0, hour: 9, minute: 1),
                  status: .completed, docComplete: false),   // incomplete note — demo "Finish note" card on Today
            Visit(id: UUID(), clients: [clients[1]], service: .communityParticipation,
                  scheduledStart: now.addingTimeInterval(-47 * 60), scheduledEnd: now.addingTimeInterval(73 * 60),
                  actualStart: now.addingTimeInterval(-47 * 60), actualEnd: nil,
                  status: .inProgress),
            Visit(id: UUID(), clients: [clients[2]], service: .companion,
                  scheduledStart: now.addingTimeInterval(90 * 60), scheduledEnd: now.addingTimeInterval(210 * 60),
                  actualStart: nil, actualEnd: nil, status: .scheduled,
                  teamStaff: staff[1]),
            Visit(id: UUID(), clients: [clients[3], clients[4]], service: .communityParticipation,
                  scheduledStart: now.addingTimeInterval(240 * 60), scheduledEnd: now.addingTimeInterval(330 * 60),
                  actualStart: nil, actualEnd: nil, status: .scheduled, isGroup: true),
            Visit(id: UUID(), clients: [clients[5]], service: .respite,
                  scheduledStart: now.addingTimeInterval(390 * 60), scheduledEnd: now.addingTimeInterval(480 * 60),
                  actualStart: nil, actualEnd: nil, status: .scheduled)
        ]
    }

    // MARK: - Past visits (2 weeks)
    static func pastVisits() -> [Visit] {
        var visits: [Visit] = []
        let plan: [(Int, Int, Int, Int, ServiceType, Bool, SyncState)] = [
            (1, 8, 10, 0, .inHomeSupport, true, .synced),
            (1, 13, 15, 1, .companion, true, .synced),
            (1, 16, 18, 2, .communityParticipation, false, .pending),
            (2, 7, 9, 3, .inHomeSupport, true, .synced),
            (2, 10, 13, 4, .respite, true, .synced),
            (3, 9, 11, 5, .companion, true, .synced),
            (3, 14, 16, 0, .communityParticipation, true, .synced),
            (4, 8, 10, 1, .inHomeSupport, false, .synced),
            (5, 9, 12, 2, .respite, true, .synced),
            (5, 13, 15, 3, .companion, true, .synced),
            (6, 7, 9, 4, .inHomeSupport, true, .synced),
            (7, 10, 12, 5, .communityParticipation, true, .synced),
            (8, 8, 11, 0, .inHomeSupport, true, .synced),
            (9, 13, 16, 1, .respite, true, .synced),
            (10, 9, 11, 2, .companion, true, .synced),
            (11, 8, 10, 3, .inHomeSupport, true, .synced),
            (12, 14, 17, 4, .communityParticipation, true, .synced),
            (13, 7, 9, 5, .inHomeSupport, true, .synced)
        ]
        for (days, sh, eh, ci, svc, doc, sync) in plan {
            var v = Visit(id: UUID(), clients: [clients[ci]], service: svc,
                          scheduledStart: date(daysAgo: days, hour: sh),
                          scheduledEnd: date(daysAgo: days, hour: eh),
                          actualStart: date(daysAgo: days, hour: sh, minute: 3),
                          actualEnd: date(daysAgo: days, hour: eh, minute: 1),
                          status: .completed)
            v.docComplete = doc
            v.syncState = sync
            visits.append(v)
        }
        visits[3].timeFixStatus = .pending
        visits[8].timeFixStatus = .approved
        visits[10].deleteRequestStatus = .pending
        // Demo: GPS was unavailable at punch — location entered manually, flagged for manager review
        visits[1].manualLocation = ManualLocation(street: "88 Chestnut Ave", city: "Lancaster", state: "PA", zip: "17602")
        visits[1].manualLocationFlagged = true
        return visits
    }

    // MARK: - Open shifts
    static func openShifts() -> [OpenShift] {
        [
            OpenShift(id: UUID(), client: clients[4], service: .respite,
                      start: date(daysAgo: -1, hour: 9), end: date(daysAgo: -1, hour: 13)),
            OpenShift(id: UUID(), client: clients[2], service: .inHomeSupport,
                      start: date(daysAgo: -2, hour: 15), end: date(daysAgo: -2, hour: 19))
        ]
    }

    // MARK: - ISP Outcomes
    static let outcomes: [Outcome] = [
        Outcome(id: UUID(), clientId: clients[0].id, title: "Meal Preparation",
                goal: "James will prepare a simple meal with no more than 2 verbal prompts."),
        Outcome(id: UUID(), clientId: clients[0].id, title: "Community Safety",
                goal: "James will demonstrate safe street crossing on 4 of 5 opportunities."),
        Outcome(id: UUID(), clientId: clients[1].id, title: "Social Engagement",
                goal: "Dorothy will initiate a greeting with a peer once per outing."),
        Outcome(id: UUID(), clientId: clients[2].id, title: "Money Management",
                goal: "Marcus will complete a purchase and count change with gestural prompts.")
    ]

    // MARK: - Credentials
    static let credentials: [Credential] = [
        Credential(name: "CPR / First Aid", status: .valid, detail: "Expires 03/2027"),
        Credential(name: "Medication Administration", status: .expiringSoon, detail: "Expires 08/2026"),
        Credential(name: "Crisis Intervention", status: .valid, detail: "Expires 01/2027"),
        Credential(name: "Annual HIPAA Training", status: .expired, detail: "Expired 06/2026")
    ]
}
