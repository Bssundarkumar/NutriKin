import SwiftUI

/// The home screen: how today is going for one person, and quick ways to log food and workouts.
struct TodayView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(TrackingStore.self) private var tracking
    @Environment(AIConnection.self) private var ai
    @Environment(MedicationStore.self) private var medications
    @Environment(HealthKitManager.self) private var health
    @Environment(DailyCheckInStore.self) private var checkIns
    @AppStorage("healthMemberID") private var healthMemberID = ""
    @AppStorage("todayMemberID") private var selectedID = ""
    @State private var showFood = Demo.opensLogFood || Demo.opensPlate
    @State private var showDatePicker = false
    @State private var pickedDay = Date()
    @State private var showAsk = false
    @State private var editingFood: FoodEntry?
    @State private var showPlan = Demo.opensPlan
    @State private var showActivity = Demo.opensLogWorkout || Demo.opensPlan || Demo.opensGrowth
    @State private var activityStartsLogging = Demo.opensLogWorkout
    @State private var showMeds = Demo.opensMeds
    @State private var showTimeline = false
    @State private var showAddChoice = false
    @State private var editingWorkout: Workout?
    @State private var viewingWorkout: Workout?

    private var member: Member? {
        if Demo.isOn, let i = Demo.memberIndex, family.members.indices.contains(i) { return family.members[i] }
        return family.members.first { $0.id.uuidString == selectedID } ?? family.members.first
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    dayNavigator
                    if family.members.isEmpty {
                        EmptyState(symbol: "person.3", title: "Add your family first",
                                   message: "Add people in the Family tab, then track what they eat and how they move.")
                            .card()
                    } else if let member {
                        MemberStrip(members: family.members, selectedID: member.id) { selectedID = $0.id.uuidString }
                        let usesHealth = Demo.isOn ? member.id == Demo.members.first?.id : healthMemberID == member.id.uuidString
                        let budget = tracking.budget(for: member, healthActiveKcal: usesHealth ? health.activity.activeKcal : nil)
                        let doses = medications.doses(for: member)
                        let hasMedications = !medications.medications(for: member).isEmpty
                        let needsAttention = tracking.isToday && doses.contains { $0.state == .due || $0.state == .missed }

                        VStack(spacing: 18) {
                            if hasMedications && needsAttention { compactMedications(member).staggeredAppear(0) }
                            DayTipCard(member: member, budget: budget, steps: health.activity.steps, weekMinutes: tracking.weeklyMinutes(for: member))
                                .staggeredAppear(1)
                            if !TodayLayout.isChild(member) {
                                CheckInsCard(member: member, day: tracking.day).staggeredAppear(2)
                            }
                            if TodayLayout.isChild(member) {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionTitle(title: "Active play", actionTitle: "Open", action: { activityStartsLogging = false; showActivity = true },
                                                 symbol: "figure.run", tint: .orange)
                                    KidActivityCard(member: member, healthMinutes: health.activity.exerciseMinutes)
                                }
                                .card(tint: .orange).id("health").staggeredAppear(3)
                                ladderSection(member).staggeredAppear(4)
                                if !hasMedications || !needsAttention { compactMedications(member).staggeredAppear(5) }
                            } else {
                                hero(member, budget) { showPlan = true }.staggeredAppear(3)
                                AIFirstTimeNote()
                                HStack(alignment: .top, spacing: 14) {
                                    compactMeals(member).frame(maxWidth: .infinity)
                                    compactActivity(member).frame(maxWidth: .infinity)
                                }
                                .staggeredAppear(4)
                                HStack(alignment: .top, spacing: 14) {
                                    if !hasMedications || !needsAttention { compactMedications(member).frame(maxWidth: .infinity) }
                                    compactLimits(budget).frame(maxWidth: .infinity)
                                }
                                .staggeredAppear(5)
                                if let insight = TodayInsight.line(for: budget) {
                                    InsightCard(headline: insight.headline, detail: insight.detail).staggeredAppear(6)
                                }
                            }
                        }
                        .animation(.smooth(duration: 0.3), value: tracking.day)
                        if let message = tracking.errorMessage {
                            Text(message).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .onAppear { if let target = Demo.scrollTarget { proxy.scrollTo(target, anchor: .top) } }
            }
            .background(AppBackground())
            .navigationTitle("Today")
            .toolbar {
                if member != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 14) {
                            Button { pickedDay = tracking.day; showDatePicker = true } label: {
                                Image(systemName: "calendar")
                                    .frame(width: 34, height: 34).background(Color(.secondarySystemGroupedBackground), in: Circle())
                            }
                            .accessibilityLabel("Pick a date")
                            .simultaneousGesture(LongPressGesture().onEnded { _ in showTimeline = true })
                            Button { showAsk = true } label: {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
                                    .frame(width: 34, height: 34).background(Color.purple.opacity(0.15), in: Circle())
                            }
                            .accessibilityLabel("Ask AI")
                        }
                    }
                }
            }
            .sheet(isPresented: $showTimeline) { if let member { DayTimelineView(member: member, day: tracking.day) } }
            .refreshable { await tracking.load(householdId: family.householdId) }
            .task(id: family.householdId) { await tracking.load(householdId: family.householdId) }
            .sheet(isPresented: $showFood) { if let member { LogFoodSheet(member: member) } }
            .sheet(isPresented: $showActivity) { if let member { ActivityScreen(member: member, startInLogging: activityStartsLogging) } }
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    DatePicker("Day", selection: $pickedDay, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .navigationTitle("Go to a day").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDatePicker = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Show") { showDatePicker = false; Task { await tracking.load(householdId: family.householdId, day: pickedDay) } }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showAsk) { AskAIView(product: nil) }
            .sheet(item: $editingFood) { EditFoodEntryView(entry: $0) }
            .sheet(item: $viewingWorkout) { w in WorkoutDetailView(workout: w) { editingWorkout = w } }
            .sheet(item: $editingWorkout) { w in
                if let member {
                    if w.workoutKind == .strength { StrengthSessionView(member: member, editing: w) } else { LogWorkoutSheet(member: member, editing: w) }
                }
            }
            .sheet(isPresented: $showPlan) { if let member { NutritionPlanView(member: member) } }
            .sheet(isPresented: $showMeds) { if let member { MedicationsManageView(member: member) } }
            .task(id: tracking.day) {
                medications.updateMemberNames(family.members)
                await medications.load(householdId: family.householdId, day: tracking.day)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrikinActivityAction)) { _ in
                let actions = NotificationRouter.pendingActivity; NotificationRouter.pendingActivity = []
                Task {
                    for a in actions {
                        guard let m = family.members.first(where: { $0.id == a.memberID }), family.canManage(m) else { continue }
                        await tracking.logActivity(for: m, kind: a.kind, minutes: a.minutes, at: a.at, householdId: family.householdId)
                    }
                }
            }
            .onChange(of: tracking.schedules) { _, list in
                let mine = list.filter { s in family.members.first { $0.id == s.memberId }.map(family.canManage) ?? false }
                let plans = ActivityReminders.plans(for: mine) { id in family.members.first { $0.id == id }?.name }
                Task { await ActivityReminders.reschedule(plans) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrikinDoseAction)) { _ in
                Task { await medications.drainPendingActions() }
            }
        }
    }

    // MARK: Day navigation

    private var dayNavigator: some View {
        HStack {
            Button { Task { await tracking.moveDay(by: -1) } } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34).background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            Spacer()
            Text(tracking.day.formatted(.dateTime.day().month(.wide).year()))
                .font(.subheadline).foregroundStyle(.secondary)
                .onTapGesture { pickedDay = tracking.day; showDatePicker = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Pick a date")
            if !tracking.isToday {
                Button("Today") { Task { await tracking.goToToday() } }.font(.footnote.weight(.semibold)).padding(.leading, 6)
            }
            Spacer()
            Button { Task { await tracking.moveDay(by: 1) } } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34).background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .disabled(tracking.isToday)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Hero

    /// A rough, standard macro split used only to give the three macro bars below something to measure
    /// against (30% of calories from carbs, 20% from protein, 30% from fat) — NutriKin doesn't collect
    /// per-macro goals the way it does for calories/sugar/sodium/saturated fat.
    private func macroGoals(_ calories: Double) -> (carbsG: Double, proteinG: Double, fatG: Double) {
        (carbsG: 0.3 * calories / 4, proteinG: 0.2 * calories / 4, fatG: 0.3 * calories / 9)
    }

    private func hero(_ member: Member, _ budget: DayBudget, showPlan: @escaping () -> Void) -> some View {
        let color = Theme.color(for: budget.calorieStatus)
        let left = Int(budget.remaining.rounded())
        let grade = FoodGrade.average(tracking.entries(for: member))
        let goals = macroGoals(budget.limits.calories)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                ScoreRingLabel(fraction: budget.calorieShare, color: color, primary: "\(abs(left))",
                               secondary: left >= 0 ? "kcal left" : "kcal over")
                    .frame(width: 108, height: 108)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Daily Calories").font(.headline)
                            Text("\(Int(budget.eaten.calories.rounded())) of \(Int(budget.limits.calories.rounded())) kcal")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if let grade { FoodGradeBadge(percent: grade.percent, letter: grade.grade.letter) }
                    }
                    Capsule().fill(color.opacity(0.18)).frame(height: 7)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule().fill(color).frame(width: geo.size.width * min(max(budget.calorieShare, 0.02), 1))
                            }
                        }
                        .frame(height: 7)
                }
            }
            // All three macros in one row, under the ring and the rest — spans the card's full width
            // so each bar has room to read clearly, rather than being squeezed into the narrow column
            // beside the ring.
            HStack(spacing: 18) {
                MacroBar(symbol: "leaf.fill", tint: .blue, title: "Carbs", value: budget.eaten.carbsG, goal: goals.carbsG, iconTint: .green)
                MacroBar(symbol: "drop.fill", tint: .purple, title: "Protein", value: budget.eaten.proteinG, goal: goals.proteinG, iconTint: .orange)
                MacroBar(symbol: "drop.fill", tint: .orange, title: "Fat", value: budget.eaten.fatG, goal: goals.fatG)
            }
            if !TodayLayout.isChild(member) {
                Button("Weight & daily intake plan", action: showPlan)
                    .font(.caption.weight(.semibold))
            }
        }
        .card(tint: color)
    }

    // MARK: Lists

    /// Everything "in and out" for the day, as one connecting ladder: food, activity, and the quick
    /// check-ins (water, weight, sleep, hunger, mood) in time order. Medication has its own card right
    /// above this one, so doses aren't repeated here. Built on `DayTimeline.events`, the same builder the
    /// full-day timeline sheet uses — one place that assembles the list, so the two never drift apart.
    private func ladderSection(_ member: Member) -> some View {
        let showsCalories = TodayLayout.showsCalorieSummary(for: member)
        var events = DayTimeline.events(
            foodEntries: tracking.entries(for: member),
            workouts: tracking.workouts(for: member),
            doses: [],
            waterTimes: checkIns.waterTimes(for: member.id, day: tracking.day),
            hungerEntries: checkIns.hungerEntries(for: member.id, day: tracking.day),
            moodEntries: checkIns.moodEntries(for: member.id, day: tracking.day),
            weightEntries: checkIns.weightEntries(for: member.id, day: tracking.day),
            sleepHours: tracking.isToday ? health.snapshot.sleepHoursLastNight : nil,
            sleepAnchor: Calendar.current.startOfDay(for: tracking.day)
        )
        if !showsCalories {
            for i in events.indices where events[i].kind == .food { events[i].detail = "" }
        }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Eaten & burned", actionTitle: "Add", action: { showAddChoice = true }, symbol: "fork.knife", tint: Theme.brand)
            if events.isEmpty {
                EmptyState(symbol: "fork.knife", title: "Nothing logged",
                            message: "Log a meal, snack or workout to start today's ladder.",
                            actionTitle: "Add") { showAddChoice = true }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        ladderRow(event, member: member, isLast: index == events.count - 1)
                    }
                }
            }
        }
        .card(tint: Theme.brand)
        .confirmationDialog("Add to today", isPresented: $showAddChoice, titleVisibility: .visible) {
            Button("Log food") { showFood = true }
            Button("Log activity") { activityStartsLogging = true; showActivity = true }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func ladderRow(_ event: TimelineEvent, member: Member, isLast: Bool) -> some View {
        let isEditable = event.foodEntryId != nil || event.workoutId != nil
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: event.symbol)
                    .font(.footnote).foregroundStyle(event.tint.color)
                    .frame(width: 34, height: 34)
                    .background(Circle().strokeBorder(event.tint.color, lineWidth: 2))
                if !isLast {
                    Rectangle().fill(event.tint.color.opacity(0.3)).frame(width: 2).frame(minHeight: 20).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(event.detail.isEmpty ? event.title : "\(event.title) \(event.detail)").font(.subheadline.weight(.semibold))
                Text(event.at.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 5).padding(.bottom, isLast ? 4 : 18)
            Spacer(minLength: 0)
            if isEditable {
                Menu {
                    Button("Edit", systemImage: "pencil") { editLadderEvent(event, member: member) }
                    Button("Remove", systemImage: "trash", role: .destructive) { Task { await removeLadderEvent(event, member: member) } }
                } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 30, height: 34) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let w = ladderWorkout(event, member: member) { viewingWorkout = w }
            else if let e = ladderFoodEntry(event, member: member) { editingFood = e }
        }
    }

    /// The overflow menu's "Edit" jumps straight to the edit form — unlike a tap on a workout row,
    /// which opens its read-only detail first (the same as the Activity screen's own list does).
    private func editLadderEvent(_ event: TimelineEvent, member: Member) {
        if let w = ladderWorkout(event, member: member) { editingWorkout = w }
        else if let e = ladderFoodEntry(event, member: member) { editingFood = e }
    }

    private func removeLadderEvent(_ event: TimelineEvent, member: Member) async {
        if let w = ladderWorkout(event, member: member) { await tracking.delete(w) }
        else if let e = ladderFoodEntry(event, member: member) { await tracking.delete(e) }
    }

    /// One place that maps a ladder event back to the real `Workout`/`FoodEntry` it came from, so tap,
    /// edit and remove don't each re-implement the same lookup.
    private func ladderWorkout(_ event: TimelineEvent, member: Member) -> Workout? {
        guard let id = event.workoutId else { return nil }
        return tracking.workouts(for: member).first { $0.id == id }
    }

    private func ladderFoodEntry(_ event: TimelineEvent, member: Member) -> FoodEntry? {
        guard let id = event.foodEntryId else { return nil }
        return tracking.entries(for: member).first { $0.id == id }
    }

    // MARK: Two-column compact cards

    /// "Today's Meals": food only (no workouts — those are the Activity card alongside it), the most
    /// recent few. Reuses `ladderRow`/`DayTimeline.events` so the row look and the edit/delete behavior
    /// stay identical to the full ladder shown for children.
    private func compactMeals(_ member: Member) -> some View {
        let showsCalories = TodayLayout.showsCalorieSummary(for: member)
        var events = DayTimeline.events(foodEntries: tracking.entries(for: member), workouts: [], doses: [],
                                         waterTimes: [], hungerEntries: [], moodEntries: []).suffix(4)
        if !showsCalories { for i in events.indices { events[i].detail = "" } }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Today's Meals", actionTitle: "Add +", action: { showAddChoice = true }, symbol: "fork.knife", tint: Theme.brand, compact: true)
            if events.isEmpty {
                EmptyState(symbol: "fork.knife", title: "Nothing yet", message: "Log a meal to start.", actionTitle: "Add") { showAddChoice = true }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        compactMealRow(event, member: member, isLast: index == events.count - 1)
                    }
                }
            }
        }
        .card(tint: Theme.brand)
        .confirmationDialog("Add to today", isPresented: $showAddChoice, titleVisibility: .visible) {
            Button("Log food") { showFood = true }
            Button("Log activity") { activityStartsLogging = true; showActivity = true }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// A single meal row sized for the narrow half-width "Today's Meals" column: time on the left, a
    /// plain colored dot on a connecting line (no icon glyph — there's no room for one at this width),
    /// then the title and calories on one line, with a trailing chevron.
    private func compactMealRow(_ event: TimelineEvent, member: Member, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                VStack(spacing: 0) {
                    Circle().fill(event.tint.color).frame(width: 9, height: 9)
                    if !isLast { Rectangle().fill(event.tint.color.opacity(0.3)).frame(width: 1.5).frame(maxHeight: .infinity) }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.at.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(event.title).font(.caption.weight(.semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 2)
                if !event.detail.isEmpty { Text(event.detail).font(.system(size: 10)).foregroundStyle(.primary) }
                Image(systemName: "chevron.right").font(.system(size: 9).weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            if !isLast { Divider() }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let w = ladderWorkout(event, member: member) { viewingWorkout = w }
            else if let e = ladderFoodEntry(event, member: member) { editingFood = e }
        }
    }

    /// "Activity": active minutes as a small ring, plus steps and workout count — the compact,
    /// two-column-width sibling of `ActivitySummaryCard`.
    private func compactActivity(_ member: Member) -> some View {
        let showsHealth = HealthActivityCard.isVisible(for: member, linkedID: healthMemberID, health: health)
        let logged = tracking.workouts(for: member)
        let minutes = max(logged.reduce(0) { $0 + $1.minutes }, showsHealth ? (health.activity.exerciseMinutes ?? 0) : 0)
        let dailyGoal = max(ActivityGoals.suggested(for: member).weeklyMinutes / 7, 20)
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Activity", actionTitle: "See all", action: { activityStartsLogging = false; showActivity = true },
                         symbol: "figure.run", tint: .orange, compact: true, actionShowsChevron: true)
            ZStack(alignment: .top) {
                ScoreRingLabel(fraction: Double(minutes) / Double(dailyGoal), color: .orange, primary: "\(minutes)", secondary: "Active min")
                    .frame(width: 92, height: 92)
                Image(systemName: "figure.run")
                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.orange, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .offset(y: -4)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                StatTile(title: "Steps", value: showsHealth ? (health.activity.steps.map { $0.formatted() } ?? "\u{2013}") : "\u{2013}", symbol: "figure.walk", tint: .blue)
                StatTile(title: "Workouts", value: "\(logged.count)", symbol: "figure.run", tint: .orange)
            }
        }
        .card(tint: .orange)
        .contentShape(Rectangle())
        .onTapGesture { activityStartsLogging = false; showActivity = true }
    }

    /// "Medications": the compact, two-column-width sibling of `MedicationsCard`, showing just today's
    /// doses in brief. Used both in the normal two-column row and, when a dose needs attention, promoted
    /// full-width above everything else.
    private func compactMedications(_ member: Member) -> some View {
        let doses = medications.doses(for: member)
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Medications", actionTitle: "Manage", action: { showMeds = true }, symbol: "pills.fill", tint: .blue, compact: true, actionShowsChevron: true)
            if doses.isEmpty {
                EmptyState(symbol: "pills", title: "Nothing scheduled", message: "Add a medication to track doses.", actionTitle: "Add") { showMeds = true }
            } else {
                VStack(spacing: 0) {
                    ForEach(doses.prefix(4)) { dose in
                        compactDoseRow(dose, member: member)
                        if dose.id != doses.prefix(4).last?.id { Divider() }
                    }
                }
            }
        }
        .card(tint: .blue)
        .id("meds")
    }

    private func compactDoseRow(_ dose: ScheduledDose, member: Member) -> some View {
        HStack(spacing: 6) {
            Image(systemName: dose.state == .taken ? "checkmark.circle.fill" : dose.state == .skipped ? "xmark.circle" : "clock")
                .font(.footnote)
                .foregroundStyle(dose.state == .taken ? .green : dose.state == .missed ? .red : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(dose.medication.name).font(.caption.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                Text(dose.dueAt.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            if dose.state != .taken && dose.state != .skipped && family.canManage(member) {
                Button("Take") { Task { await medications.mark(dose, as: .taken) } }
                    .font(.caption2.weight(.semibold)).buttonStyle(.bordered).controlSize(.mini)
                    .lineLimit(1).fixedSize()
            } else if dose.state == .taken {
                Text("Taken").font(.caption2.weight(.semibold)).foregroundStyle(.green).lineLimit(1).fixedSize()
            }
            if family.canManage(member) {
                Menu {
                    if dose.state != .taken { Button("Mark taken", systemImage: "checkmark") { Task { await medications.mark(dose, as: .taken) } } }
                    if dose.state != .skipped { Button("Skip", systemImage: "forward") { Task { await medications.mark(dose, as: .skipped) } } }
                    Button("Manage medications", systemImage: "pills") { showMeds = true }
                } label: { Image(systemName: "ellipsis").font(.caption).foregroundStyle(.secondary).frame(width: 22, height: 22) }
            }
        }
        .padding(.vertical, 6)
    }

    /// "Daily Nutrient Limits": the compact, two-column-width sibling of the old full-width nutrients
    /// card — same `NutrientBar` rows, minus the carbs/protein/fat line, which moved up into the macro
    /// bars on the Daily Calories card.
    private func compactLimits(_ b: DayBudget) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Daily Nutrient Limits", actionTitle: "See all", action: { showPlan = true }, symbol: "chart.bar.fill", tint: .teal, compact: true, actionShowsChevron: true)
            NutrientBar(title: "Sugar", share: b.sugarShare, detail: "\(Int(b.eaten.sugarG.rounded())) / \(Int(b.limits.sugarG.rounded())) g")
            NutrientBar(title: "Sodium", share: b.sodiumShare, detail: "\(Int(b.eaten.sodiumMg.rounded())) / \(Int(b.limits.sodiumMg.rounded())) mg")
            NutrientBar(title: "Saturated fat", share: b.satFatShare, detail: "\(Int(b.eaten.satFatG.rounded())) / \(Int(b.limits.satFatG.rounded())) g")
            NutrientBar(title: "Fibre", share: b.fiberShare, detail: "\(Int(b.eaten.fiberG.rounded())) / \(Int(b.limits.fiberG.rounded())) g", goodWhenHigh: true)
        }
        .card(tint: .teal)
    }
}

/// A progress ring with a big number and a small caption inside.
struct ScoreRingLabel: View {
    let fraction: Double
    let color: Color
    let primary: String
    let secondary: String
    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: 14)
            Circle().trim(from: 0, to: shown)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(primary).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text(secondary).font(.caption).foregroundStyle(.secondary)
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            .padding(.horizontal, 6)
        }
        .onAppear { animate() }
        .onChange(of: fraction) { _, _ in animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(primary) \(secondary)")
        // A fixed circle can't grow with the text, so past a point it shrinks to fit rather than truncating.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func animate() {
        let target = min(max(fraction, 0.01), 1)
        if reduceMotion { shown = target } else { withAnimation(.easeOut(duration: 0.9)) { shown = target } }
    }
}

/// A small ring showing the day's average food grade (A–E), from `FoodGrade`. A rough nutrient-quality
/// read on what's been logged, not a medical or per-condition score — `Verdict` from `ScoringEngine`
/// still handles that at scan time.
struct FoodGradeRing: View {
    let percent: Int
    let letter: String

    var body: some View {
        let color = FoodGradeRing.color(for: letter)
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 5)
            Circle().trim(from: 0, to: Double(percent) / 100).stroke(color.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(letter).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Average food grade \(letter), \(percent) percent")
    }

    static func color(for letter: String) -> Color {
        switch letter {
        case "A": .green
        case "B": Theme.brand
        case "C": .yellow
        case "D": .orange
        default: .red
        }
    }
}

/// A compact pill version of `FoodGradeRing` — letter + percent side by side — for places like the
/// Daily Calories card where a full ring would be too big.
struct FoodGradeBadge: View {
    let percent: Int
    let letter: String

    var body: some View {
        let color = FoodGradeRing.color(for: letter)
        HStack(spacing: 4) {
            Image(systemName: "flame.fill").font(.caption2)
            Text(letter).font(.footnote.weight(.bold))
            Text("\(percent)%").font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Average food grade \(letter), \(percent) percent")
    }
}

/// One macro (carbs/protein/fat) against a rough daily goal, as an icon, label, value and a thin bar —
/// used three-up under the calorie ring on the Daily Calories card.
struct MacroBar: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: Double
    let goal: Double
    /// The icon's own color, when it differs from the bar's — e.g. the reference design's carbs icon is
    /// green (a leaf) while its bar is blue. Defaults to `tint` so existing callers don't need to change.
    var iconTint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption2).foregroundStyle(iconTint ?? tint)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(Int(value.rounded())) / \(Int(goal.rounded())) g").font(.caption.weight(.semibold))
            Capsule().fill(tint.opacity(0.18)).frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(tint).frame(width: geo.size.width * min(max(goal > 0 ? value / goal : 0, 0.02), 1))
                    }
                }
                .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A rule-based "how's today going" card, from `TodayInsight` — a free, always-on companion to the
/// AI-written tip pill at the top, in the same spirit as `ScoringEngine`'s explainable scoring.
struct InsightCard: View {
    let headline: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill").font(.body).foregroundStyle(.blue)
                .frame(width: 34, height: 34).background(Color.blue.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Today's insight").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                Text(headline).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .card(tint: .blue)
    }
}
