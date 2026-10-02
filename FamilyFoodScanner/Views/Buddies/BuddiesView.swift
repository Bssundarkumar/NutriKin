import SwiftUI

/// Adult buddy groups share workouts; logging remains limited to the signed-in member.
struct BuddiesView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(TrackingStore.self) private var tracking
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var activityTextSize
    @Environment(BuddyStore.self) private var store
    var presentedAsTab = false
    @State private var selected: UUID?
    @State private var participants: Set<UUID> = []
    @State private var showGroupMembers = false
    @AppStorage("buddyDayParticipants") private var storedParticipants = Data()
    @State private var mode: Mode = .none
    @State private var text = ""
    @State private var copying: BuddyPost?
    @State private var viewing: BuddyPost?
    @State private var showAnalysis = false
    @State private var showLog = false
    @State private var showStrength = false
    @State private var strengthPrefill: [StrengthExercise]?
    @State private var quickKind: WorkoutKind = .walking
    @State private var filterID: UUID?
    @State private var previousWeek = false
    @State private var showAll = false
    @State private var activityDay = Calendar.current.startOfDay(for: Date())
    @State private var showActivityCalendar = false
    @State private var confirmLeave = false
    private enum Mode { case none, create, join }
    private var me: Member? { family.myMember }
    private var eligible: Bool { (me?.age ?? 0) >= 18 }
    private var group: BuddyGroup? { store.groups.first { $0.id == selected } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    pageHeader
                    if let error = store.errorMessage {
                        Text(error).readableFont(16).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !eligible {
                        Text("Gym buddies are for adults. Open your profile in Family, turn on ‘This is me’ and add your age (18 or over).")
                            .readableFont(17).card()
                    } else if store.isLoading && store.groups.isEmpty {
                        ProgressView("Loading your groups…").padding(24)
                    } else if store.groups.isEmpty {
                        startSection.card()
                    } else if let group {
                        groupCard(group)
                        quickAdd
                        weeklyCard(group)
                        recentActivity(group)
                        if mode != .none { startSection.card() }
                    } else {
                        groupTiles
                        if mode != .none { startSection.card() }
                    }
                    Text("Buddies see only your workouts: type, time, effort, notes and strength sets. Food, medicines, weight and Health readings stay private. Group members can log shared sessions for selected participants. Only adults can join; you can leave any time.")
                        .readableFont(13).foregroundStyle(.secondary).padding(.horizontal, 4)
                }.padding(16)
            }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .task { await reload() }
            .refreshable { await reload() }
            .onChange(of: selected) { _, _ in filterID = nil; showGroupMembers = false; restoreParticipants() }
            .onChange(of: store.buddies) { _, _ in restoreParticipants() }
            .sheet(item: $copying) { post in
                if let me, let group {
                    BuddyGroupWorkoutSheet(member: me, group: group, participantIDs: participants.sorted { $0.uuidString < $1.uuidString },
                                           day: activityDay, initialKind: .strength,
                                           prefill: StrengthMath.forReuse(post.workout.exercises ?? []))
                }
            }
            .sheet(item: $viewing) { post in WorkoutDetailView(workout: post.workout, onEdit: {}, readOnly: true) }
            .sheet(isPresented: $showAnalysis) {
                if let group { BuddyAnalysisView(group: group, initialMemberID: filterID ?? me?.id) }
            }
            .sheet(isPresented: $showLog) {
                if let me, let group {
                    BuddyGroupWorkoutSheet(member: me, group: group, participantIDs: participants.sorted { $0.uuidString < $1.uuidString }, day: activityDay, initialKind: quickKind)
                }
            }
            .sheet(isPresented: $showStrength) {
                if let me, let group {
                    BuddyGroupWorkoutSheet(member: me, group: group, participantIDs: participants.sorted { $0.uuidString < $1.uuidString }, day: activityDay, initialKind: .strength, prefill: strengthPrefill)
                }
            }
            .sheet(isPresented: $showActivityCalendar) {
                NavigationStack {
                    DatePicker("Activity day", selection: $activityDay, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .navigationTitle("Activity date").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Today") { activityDay = Calendar.current.startOfDay(for: Date()); showActivityCalendar = false }
                            }
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showActivityCalendar = false } }
                        }
                }.presentationDetents([.medium, .large])
            }
            .task(id: activityDay) { await store.loadActivity(day: activityDay, myUserId: family.myUserId) }
            .onChange(of: activityDay) { _, _ in showAll = false; restoreParticipants() }
            .onChange(of: showLog) { _, showing in if !showing { Task { await store.loadActivity(day: activityDay, myUserId: family.myUserId) } } }
            .onChange(of: showStrength) { _, showing in if !showing { Task { await store.loadActivity(day: activityDay, myUserId: family.myUserId) } } }
            .onChange(of: copying) { _, post in if post == nil { Task { await store.loadActivity(day: activityDay, myUserId: family.myUserId) } } }

            .confirmationDialog("Leave this group?", isPresented: $confirmLeave, titleVisibility: .visible) {
                if let group { Button("Leave group", role: .destructive) { Task { await store.leave(group, myUserId: family.myUserId); selected = nil; filterID = nil } } }
            }
        }.tint(Theme.brand)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if selected != nil || !presentedAsTab {
                    Button { if selected != nil { selected = nil; filterID = nil } else { dismiss() } } label: {
                        Image(systemName: "chevron.left").readableFont(20, weight: .semibold)
                            .frame(width: 44, height: 44).background(.background, in: Circle())
                    }.accessibilityLabel(selected == nil ? "Close gym buddies" : "Back to groups")
                }
                Spacer()
                if let group {
                    ShareLink(item: inviteText(group)) {
                        Label("Invite", systemImage: "person.badge.plus").readableFont(16, weight: .semibold)
                            .padding(.horizontal, 14).frame(minHeight: 44).background(Theme.brand.opacity(0.07), in: Capsule())
                    }
                }
                Menu {
                    Button("Start another group", systemImage: "person.2.fill") { mode = .create; text = "" }
                        .disabled(!eligible || store.groups.count >= 5)
                    Button("Join with a code", systemImage: "key.fill") { mode = .join; text = "" }
                        .disabled(!eligible || store.groups.count >= 5)
                    if group != nil { Button("Leave group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true } }
                } label: {
                    Image(systemName: "ellipsis").readableFont(20, weight: .bold)
                        .frame(width: 44, height: 44).background(.background, in: Circle())
                }.accessibilityLabel("Group options")
            }
            HStack(spacing: 12) {
                Image(systemName: "dumbbell.fill").readableFont(30, weight: .semibold)
                    .frame(width: 68, height: 68).background(Theme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gym Buddies").readableFont(30, weight: .bold).foregroundStyle(.primary)
                    Text("Stay stronger together").readableFont(18).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var groupTiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your groups").readableFont(22, weight: .bold)
                Spacer()
                Button { mode = .create; text = "" } label: { Label("New", systemImage: "plus") }
                    .disabled(store.groups.count >= 5)
            }
            ForEach(store.groups) { item in
                Button { selected = item.id; mode = .none } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3.fill").readableFont(26).foregroundStyle(Theme.brand)
                            .frame(width: 52, height: 52).background(Theme.brand.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).readableFont(21, weight: .bold).foregroundStyle(.primary)
                            Text("\(store.buddies(in: item).count) members · View group activity")
                                .readableFont(14).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.card()
                }.buttonStyle(.plain)
            }
        }
    }

    private func groupCard(_ group: BuddyGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "person.3.fill").readableFont(25).frame(width: 48, height: 48)
                    .background(Theme.brand.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name).readableFont(21, weight: .bold)
                    Text("\(store.buddies(in: group).count) of \(BuddyMath.maxGroupSize) people · Code \(group.inviteCode)")
                        .readableFont(14).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                ShareLink(item: inviteText(group)) { Image(systemName: "square.and.arrow.up").readableFont(21).frame(width: 44, height: 44) }
            }
            DisclosureGroup(isExpanded: $showGroupMembers) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(store.buddies(in: group)) { buddy in
                        Button { filterID = buddy.memberId } label: {
                            VStack(spacing: 4) {
                                Text(buddy.displayName).readableFont(14, weight: .semibold).foregroundStyle(.primary)
                                Text(buddy.userId == family.myUserId ? "You" : "Buddy").readableFont(12).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                    ShareLink(item: inviteText(group)) {
                        VStack(spacing: 4) {
                            Image(systemName: "plus").readableFont(22).frame(width: 48, height: 48)
                                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4])))
                            Text("Invite").readableFont(14)
                        }.foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "chart.bar.fill").readableFont(24)
                        Text("Group streak").readableFont(12).foregroundStyle(.secondary)
                        Text("\(streak(posts(in: group))) days").readableFont(18, weight: .bold).foregroundStyle(.primary)
                    }.padding(.leading, 4)
                }
            }
            } label: {
                Text(showGroupMembers ? "Hide members" : "Show members")
                    .readableFont(15, weight: .medium).frame(minHeight: 44)
            }
        }.card()
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick add for").readableFont(18, weight: .bold)
                Spacer()
                Button(participants.isEmpty ? "Select all" : "Deselect all") {
                    participants = participants.isEmpty ? Set(group.map { store.buddies(in: $0).map(\.memberId) } ?? []) : []
                    persistParticipants()
                }.readableFont(14)
            }
            if let group {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.buddies(in: group)) { buddy in
                            Button {
                                if participants.contains(buddy.memberId) { participants.remove(buddy.memberId) }
                                else { participants.insert(buddy.memberId) }
                                persistParticipants()
                            } label: {
                                Label(buddy.displayName, systemImage: participants.contains(buddy.memberId) ? "checkmark.circle.fill" : "circle")
                                    .readableFont(15, weight: .medium).padding(10).frame(minHeight: 44)
                                    .background(Theme.brand.opacity(participants.contains(buddy.memberId) ? 0.12 : 0.04), in: Capsule())
                            }.buttonStyle(.plain).accessibilityAddTraits(participants.contains(buddy.memberId) ? .isSelected : [])
                        }
                    }
                }
                Text("Applies to every workout you add for \(activityDay.formatted(date: .abbreviated, time: .omitted)) in this group.")
                    .readableFont(13).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickButton("Strength", symbol: "dumbbell.fill", tint: .pink) { strengthPrefill = nil; showStrength = true }
                    quickButton("Cardio", symbol: "figure.run", tint: .blue) { quickKind = .running; showLog = true }
                    quickButton("Yoga", symbol: "figure.yoga", tint: .purple) { quickKind = .yoga; showLog = true }
                    quickButton("Abs", symbol: "figure.core.training", tint: .orange) {
                        strengthPrefill = [StrengthExercise(name: "Crunch", sets: [StrengthSet(reps: 10, weightKg: 0)])]
                        showStrength = true
                    }
                    quickButton("Custom", symbol: "square.grid.2x2", tint: .secondary) { quickKind = .other; showLog = true }
                }
            }
        }.card()
    }

    private func quickButton(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).readableFont(14, weight: .medium)
                .foregroundStyle(tint).padding(12).frame(minHeight: 44)
                .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).disabled(participants.isEmpty)
    }

    private func weeklyCard(_ group: BuddyGroup) -> some View {
        let start = weekStart
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? .now
        let week = posts(in: group).filter { $0.workout.doneAt >= start && $0.workout.doneAt < end }
        let workouts = week.map(\.workout)
        let days = Set(workouts.map { Calendar.current.startOfDay(for: $0.doneAt) }).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(previousWeek ? "Last week" : "This week").readableFont(21, weight: .bold)
                Spacer()
                Button { showAnalysis = true } label: {
                    Label("Analysis", systemImage: "chart.xyaxis.line")
                        .readableFont(13, weight: .medium).frame(minHeight: 44)
                }.buttonStyle(.plain)
                Menu {
                    Button("This week") { previousWeek = false }
                    Button("Last week") { previousWeek = true }
                } label: { Label("Week", systemImage: "calendar").readableFont(14).padding(8).background(Theme.brand.opacity(0.05), in: Capsule()) }
            }
            Text("\(start.formatted(.dateTime.month(.abbreviated).day())) – \((end.addingTimeInterval(-1)).formatted(.dateTime.month(.abbreviated).day()))")
                .readableFont(13).foregroundStyle(.secondary)
            SingleRow(spacing: 8) {
                weeklyStat("Workouts", value: "\(workouts.count)", symbol: "dumbbell.fill", tint: .green, values: daily(workouts) { _ in 1 })
                weeklyStat("Total time", value: "\(workouts.reduce(0) { $0 + $1.minutes }) min", symbol: "clock", tint: .blue, values: daily(workouts) { Double($0.minutes) })
                weeklyStat("Total lifted", value: "\(StrengthMath.display(kg: workouts.reduce(0) { $0 + StrengthMath.volumeKg($1.exercises ?? []) }, pounds: false)) kg", symbol: "flame.fill", tint: .orange, values: daily(workouts) { StrengthMath.volumeKg($0.exercises ?? []) })
                weeklyStat("Days active", value: "\(days)", symbol: "circle.inset.filled", tint: .purple, values: daily(workouts) { _ in 1 }.map { min($0, 1) })
            }
        }.card()
    }

    private func weeklyStat(_ title: String, value: String, symbol: String, tint: Color, values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).readableFont(20).foregroundStyle(tint).frame(width: 32, height: 32)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            Text(value).readableFont(19, weight: .bold).fixedSize(horizontal: false, vertical: true)
            Text(title).readableFont(12).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2).fill(tint.opacity(values[index] > 0 ? 0.8 : 0.12))
                        .frame(height: max(3, 24 * values[index] / max(values.max() ?? 1, 1)))
                }
            }.frame(height: 24).accessibilityHidden(true)
        }.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func recentActivity(_ group: BuddyGroup) -> some View {
        let roster = store.buddies(in: group)
        let ids = Set(roster.map(\.memberId))
        let displayedMemberID = filterID.flatMap { ids.contains($0) ? $0 : nil }
            ?? me.flatMap { ids.contains($0.id) ? $0.id : nil }
            ?? roster.first?.memberId
        let cached = store.activityDay == Calendar.current.startOfDay(for: activityDay) ? store.dayPosts : []
        let all = Dictionary((cached + posts(in: group)).filter { ids.contains($0.workout.memberId) }.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest }).values.sorted { $0.workout.doneAt > $1.workout.doneAt }
        let filtered = all.filter {
            Calendar.current.isDate($0.workout.doneAt, inSameDayAs: activityDay)
                && $0.workout.memberId == displayedMemberID
        }
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(store.buddies(in: group)) { buddy in
                        Button { filterID = buddy.memberId } label: { chip(buddy.displayName, active: displayedMemberID == buddy.memberId) }
                    }
                }.buttonStyle(.plain)
            }
            HStack {
                Text(Calendar.current.isDateInToday(activityDay) ? "Today's activity" : "Activity")
                    .readableFont(22, weight: .bold)
                Spacer()
                Button { showActivityCalendar = true } label: {
                    Label(activityDay.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                        .readableFont(14).padding(.horizontal, 10).frame(minHeight: 44)
                        .background(Theme.brand.opacity(0.06), in: Capsule())
                }.accessibilityLabel("Choose activity date, \(activityDay.formatted(date: .complete, time: .omitted))")
            }
            if store.isLoadingDay { ProgressView("Loading activity…").frame(maxWidth: .infinity).padding() }
            else if filtered.isEmpty { Text("No exercises logged for this person on this day.").readableFont(16).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).card() }
            let tiles = filtered.flatMap { post -> [BuddyExerciseTile] in
                let exercises = post.workout.exercises ?? []
                if exercises.isEmpty { return [BuddyExerciseTile(post: post, exercise: nil, position: 0)] }
                return exercises.enumerated().map { BuddyExerciseTile(post: post, exercise: $0.element, position: $0.offset) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: activityTextSize.isAccessibilitySize ? 1 : 3), alignment: .leading, spacing: 10) {
                ForEach(Array(tiles.prefix(showAll ? tiles.count : 9))) { tile in postCard(tile) }
            }
            if tiles.count > 9 {
                Button(showAll ? "Show less" : "See all for this day") { showAll.toggle() }
                    .readableFont(14).frame(minHeight: 44)
            }
        }
    }

    private struct BuddyExerciseTile: Identifiable {
        let post: BuddyPost
        let exercise: StrengthExercise?
        let position: Int
        var id: String { "\(post.id.uuidString)/\(position)" }
    }

    private func postCard(_ tile: BuddyExerciseTile) -> some View {
        let post = tile.post
        let exercises = tile.exercise.map { [$0] } ?? []
        return VStack(alignment: .leading, spacing: 5) {
            Button { viewing = post } label: {
                VStack(alignment: .leading, spacing: 5) {
                    if let first = exercises.first, let image = ExerciseIllustrations.image(for: first.name) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity).frame(height: 72)
                            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: post.workout.workoutKind.symbol).readableFont(30)
                            .foregroundStyle(Theme.brand).frame(maxWidth: .infinity).frame(height: 72)
                            .background(Theme.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Text(post.name).readableFont(14, weight: .bold).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(exercises.first?.name ?? post.workout.workoutKind.title)
                        .readableFont(12, weight: .medium).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(post.workout.doneAt.formatted(date: .omitted, time: .shortened))
                        .readableFont(11).foregroundStyle(.secondary)
                    if !exercises.isEmpty {
                        Text("\(exercises.count) exercises · \(StrengthMath.totalSets(exercises)) sets")
                            .readableFont(11).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(tile.exercise == nil ? "\(post.workout.minutes) min · \(post.workout.caloriesBurned) kcal" : "\(post.workout.minutes) min session")
                        .readableFont(12, weight: .semibold).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).accessibilityHint("Open full workout details")
            Spacer(minLength: 0)
            if !exercises.isEmpty {
                Button {
                    var copied = post
                    copied.workout.exercises = exercises
                    copying = copied
                } label: {
                    Label("Copy", systemImage: "square.on.square").readableFont(12, weight: .semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.brand.opacity(0.07), in: Capsule())
                }.buttonStyle(.plain).disabled(participants.isEmpty)
                    .accessibilityLabel("Copy \(tile.exercise?.name ?? post.workout.workoutKind.title) for selected people")
            }
        }
        .padding(8).frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var selectionKey: String? {
        guard let user = family.myUserId, let group else { return nil }
        return "\(user.uuidString)/\(group.id.uuidString)/\(Calendar.current.startOfDay(for: activityDay).timeIntervalSince1970)"
    }
    private func restoreParticipants() {
        guard let key = selectionKey, let group else { participants = []; return }
        let saved = (try? JSONDecoder().decode([String: [UUID]].self, from: storedParticipants)) ?? [:]
        let allowed = Set(store.buddies(in: group).map(\.memberId))
        let initial = me.map { [$0.id] } ?? []
        participants = Set(saved[key] ?? initial).intersection(allowed)
    }
    private func persistParticipants() {
        guard let key = selectionKey else { return }
        var saved = (try? JSONDecoder().decode([String: [UUID]].self, from: storedParticipants)) ?? [:]
        saved[key] = Array(participants)
        if let data = try? JSONEncoder().encode(saved) { storedParticipants = data }
    }

    private func reload() async {
        await store.load(myUserId: family.myUserId)
        if let household = family.householdId, !Demo.isOn { await tracking.loadWeek(household) }
        await store.loadActivity(day: activityDay, myUserId: family.myUserId)
    }

    private func chip(_ title: String, active: Bool) -> some View {
        Text(title).readableFont(14, weight: .semibold).foregroundStyle(active ? .white : .secondary)
            .padding(.horizontal, 18).frame(minHeight: 44)
            .background(active ? Theme.brand : Color(.secondarySystemGroupedBackground), in: Capsule())
    }
    private func inviteText(_ group: BuddyGroup) -> String { "Join my gym buddies group ‘\(group.name)’ on NutriKin with the code \(group.inviteCode)." }
    private func posts(in group: BuddyGroup) -> [BuddyPost] {
        let ids = Set(store.buddies(in: group).map(\.memberId))
        let mine = me.flatMap { ids.contains($0.id) ? $0 : nil }.map { member in tracking.recentWorkouts(for: member).map { BuddyPost(workout: $0, name: member.name) } } ?? []
        return Dictionary((store.posts.filter { ids.contains($0.workout.memberId) } + mine).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values.sorted { $0.workout.doneAt > $1.workout.doneAt }
    }
    private var weekStart: Date { Calendar.current.date(byAdding: .day, value: previousWeek ? -7 : 0, to: ActivityGoals.weekStart()) ?? .now }
    private func daily(_ workouts: [Workout], value: (Workout) -> Double) -> [Double] {
        (0..<7).map { offset in
            let start = Calendar.current.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
            return workouts.filter { $0.doneAt >= start && $0.doneAt < end }.reduce(0) { $0 + value($1) }
        }
    }
    private func streak(_ posts: [BuddyPost]) -> Int {
        let cal = Calendar.current
        let days = Set(posts.map { cal.startOfDay(for: $0.workout.doneAt) })
        var day = cal.startOfDay(for: .now)
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while days.contains(day) && count < 21 { count += 1; day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        return count
    }
    private var startSection: some View {
        Section {
            switch mode {
            case .none:
                Button { mode = .create } label: { Label("Start a group", systemImage: "person.2.fill") }.disabled(store.groups.count >= 5)
                Button { mode = .join } label: { Label("Join with a code", systemImage: "key.fill") }.disabled(store.groups.count >= 5)
            case .create:
                TextField("Group name, for example Gym crew", text: $text)
                Button("Create group") { Task { if let me, await store.create(name: text, member: me, myUserId: family.myUserId) { selected = store.groups.last?.id; mode = .none; text = "" } } }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Back") { mode = .none }
            case .join:
                TextField("Invite code", text: $text).textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button("Join") { Task { if let me, await store.join(code: text, member: me, myUserId: family.myUserId) { selected = store.groups.first { $0.inviteCode.uppercased() == text.trimmingCharacters(in: .whitespaces).uppercased() }?.id; mode = .none; text = "" } } }
                    .disabled(text.trimmingCharacters(in: .whitespaces).count < 4)
                Button("Back") { mode = .none }
            }
        } header: { Text("Train together") } footer: {
            Text("Join up to 5 groups. Each group can have up to \(BuddyMath.maxGroupSize) adults.")
        }
    }


}
