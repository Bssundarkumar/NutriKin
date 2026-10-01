import SwiftUI
import UIKit

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
    @State private var demoSelection: UUID? = Demo.memberIndex.flatMap { index in
        Demo.members.indices.contains(index) ? Demo.members[index].id : nil
    }
    @State private var showFood = Demo.opensLogFood || Demo.opensPlate
    @State private var showDatePicker = false
    @State private var pickedDay = Date()
    @State private var showAsk = false
    @State private var editingFood: FoodEntry?
    @State private var showPlan = Demo.opensPlan
    @State private var showActivity = Demo.opensActivity || Demo.opensLogWorkout || Demo.opensPlan || Demo.opensGrowth
    @State private var activityStartsLogging = Demo.opensLogWorkout
    @State private var showMeds = Demo.opensMeds
    @State private var showTimeline = false
    @AppStorage("lastGoalCommentIndex") private var lastGoalCommentIndex = -1
    @State private var goalComment = ""
    @State private var showHunger = false
    @State private var showAddChoice = false
    @State private var editingWorkout: Workout?
    @State private var viewingWorkout: Workout?
    @ScaledMetric(relativeTo: .body) private var macroWidth: CGFloat = 105
    @ScaledMetric(relativeTo: .title) private var calorieRingSize: CGFloat = 100
    @ScaledMetric(relativeTo: .title) private var activityRingSize: CGFloat = 96

    private var member: Member? {
        if Demo.isOn { return family.members.first { $0.id == demoSelection } ?? family.members.first }
        return family.members.first { $0.id.uuidString == selectedID } ?? family.members.first
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    dashboardHeader
                    dayNavigator
                    if family.members.isEmpty {
                        EmptyState(symbol: "person.3", title: "Add your family first",
                                   message: "Add people in the Family tab, then track what they eat and how they move.")
                            .card()
                    } else if let member {
                        MemberStrip(members: family.members, selectedID: member.id) { person in
                            if Demo.isOn { demoSelection = person.id }
                            else { selectedID = person.id.uuidString }
                        }
                        let usesHealth = HealthActivityCard.isVisible(for: member, linkedID: healthMemberID, health: health) && (Demo.isOn || health.dataDay == tracking.day)
                        let budget = tracking.budget(for: member, healthActiveKcal: usesHealth ? health.activity.activeKcal : nil)
                        let doses = medications.doses(for: member)
                        let hasMedications = !medications.medications(for: member).isEmpty
                        let needsAttention = tracking.isToday && doses.contains { $0.state == .due || $0.state == .missed }

                        VStack(spacing: 10) {
                            if hasMedications && needsAttention { compactMedications(member).staggeredAppear(0) }
                            if !TodayLayout.isChild(member) {
                                CheckInsCard(member: member, day: tracking.day).staggeredAppear(2)
                            }
                            if TodayLayout.isChild(member) {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionTitle(title: "Active play", actionTitle: "Open", action: { activityStartsLogging = false; showActivity = true },
                                                 symbol: "figure.run", tint: .orange)
                                    KidActivityCard(member: member, healthMinutes: usesHealth ? health.activity.exerciseMinutes : nil)
                                }
                                .todaySurface(tint: .orange).id("health").staggeredAppear(3)
                                ladderSection(member).staggeredAppear(4)
                                if !hasMedications || !needsAttention { compactMedications(member).staggeredAppear(5) }
                            } else {
                                hero(member, budget) { showPlan = true }.staggeredAppear(3)
                                compactMeals(member).staggeredAppear(4)
                                compactActivity(member).id("activity").staggeredAppear(5)
                                if !hasMedications || !needsAttention {
                                    compactMedications(member).staggeredAppear(6)
                                }
                                compactLimits(budget).staggeredAppear(7)
                                if let insight = TodayInsight.line(for: budget) {
                                    InsightCard(headline: insight.headline, detail: insight.detail).staggeredAppear(6)
                                }
                            }
                        }
                        .animation(.smooth(duration: 0.3), value: tracking.day)
                        if let message = tracking.errorMessage {
                            Text(message).readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .task(id: member?.id) {
                guard Demo.isOn, let target = Demo.scrollTarget else { return }
                try? await Task.sleep(for: .milliseconds(500))
                proxy.scrollTo(target, anchor: .top)
            }
            }
            .background(TodayBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showHunger) {
                if let member { HungerCheckInView(member: member, day: tracking.day).presentationDetents([.medium, .large]) }
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

    private var dashboardHeader: some View {
        HStack {
            Text("Today").readableFont(36, weight: .bold, relativeTo: .largeTitle)
            Spacer()
            Button { pickedDay = tracking.day; showDatePicker = true } label: {
                Image(systemName: "calendar").foregroundStyle(.primary)
                    .frame(width: 44, height: 44).background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .accessibilityLabel("Pick a date")
            .simultaneousGesture(LongPressGesture().onEnded { _ in showTimeline = true })
            Button { showAsk = true } label: {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                    .frame(width: 44, height: 44).background(Color.purple.opacity(0.1), in: Circle())
            }.accessibilityLabel("Ask AI")
            Menu {
                Button("Hunger check-in", systemImage: "fork.knife") { showHunger = true }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.primary)
                    .frame(width: 44, height: 44).background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .accessibilityLabel("Optional check-ins")
            .disabled(member == nil)
        }.padding(.top, 4)
    }

    private var dayNavigator: some View {
        HStack {
            Button { Task { await tracking.moveDay(by: -1) } } label: {
                Image(systemName: "chevron.left").readableFont(17, weight: .semibold, relativeTo: .subheadline)
                    .frame(width: 44, height: 44).background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            Text(tracking.day.formatted(.dateTime.day().month(.wide).year()))
                .readableFont(17, weight: .regular, relativeTo: .subheadline).foregroundStyle(.secondary)
                .onTapGesture { pickedDay = tracking.day; showDatePicker = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Pick a date")
            if !tracking.isToday {
                Button("Today") { Task { await tracking.goToToday() } }.readableFont(16, weight: .semibold, relativeTo: .footnote).padding(.leading, 6)
            }
            Spacer(minLength: 12)
            Button { Task { await tracking.moveDay(by: 1) } } label: {
                Image(systemName: "chevron.right").readableFont(17, weight: .semibold, relativeTo: .subheadline)
                    .frame(width: 44, height: 44).background(Color(.secondarySystemGroupedBackground), in: Circle())
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
        let eaten = Int(budget.eaten.calories.rounded())
        let target = Int(budget.limits.calories.rounded())
        let goals = macroGoals(budget.limits.calories)
        return Button(action: showPlan) {
            VStack(alignment: .leading, spacing: 14) {
                ReadableStack(spacing: 16) {
                    ScoreRingLabel(fraction: budget.calorieShare, color: color,
                                   primary: abs(left).formatted(), secondary: left >= 0 ? "kcal left" : "kcal over",
                                   lineWidth: 10, primaryFontSize: 32)
                        .frame(width: calorieRingSize, height: calorieRingSize).padding(5)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily Calories").readableFont(22, weight: .bold, relativeTo: .title3)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Text("\(eaten.formatted()) of \(target.formatted()) kcal")
                            .readableFont(17).foregroundStyle(.secondary)
                        Capsule().fill(color.opacity(0.12)).frame(height: 8)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Capsule().fill(color.gradient)
                                        .frame(width: geo.size.width * min(max(budget.calorieShare, 0), 1))
                                }
                            }.accessibilityHidden(true)
                        HStack(alignment: .top, spacing: 8) {
                            calorieEndpoint(eaten, caption: "consumed", alignment: .leading)
                            Spacer(minLength: 0)
                            calorieEndpoint(target, caption: "daily goal", alignment: .trailing)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                SingleRow(spacing: 8) {
                    MacroBar(symbol: "leaf.fill", tint: .blue, title: "Carbs", value: budget.eaten.carbsG, goal: goals.carbsG)
                    MacroBar(symbol: "drop.fill", tint: .purple, title: "Protein", value: budget.eaten.proteinG, goal: goals.proteinG)
                    MacroBar(symbol: "drop.fill", tint: .orange, title: "Fat", value: budget.eaten.fatG, goal: goals.fatG)
                }
            }
            .todaySurface()
        }.buttonStyle(.plain).accessibilityHint("Open weight and daily intake plan")
    }

    private func calorieEndpoint(_ value: Int, caption: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text("\(value.formatted()) kcal").readableFont(14, weight: .semibold)
            Text(caption).readableFont(13).foregroundStyle(.secondary)
        }
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
            sleepHours: tracking.isToday && HealthActivityCard.isVisible(for: member, linkedID: healthMemberID, health: health) ? health.snapshot.sleepHoursLastNight : nil,
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
        .todaySurface()
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
                    .readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(event.tint.color)
                    .frame(width: 44, height: 44)
                    .background(Circle().strokeBorder(event.tint.color, lineWidth: 2))
                if !isLast {
                    Rectangle().fill(event.tint.color.opacity(0.3)).frame(width: 2).frame(minHeight: 20).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(event.detail.isEmpty ? event.title : "\(event.title) \(event.detail)").readableFont(17, weight: .semibold, relativeTo: .subheadline)
                Text(event.at.formatted(date: .omitted, time: .shortened)).readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
            }
            .padding(.top, 5).padding(.bottom, isLast ? 4 : 18)
            Spacer(minLength: 0)
            if isEditable {
                Menu {
                    Button("Edit", systemImage: "pencil") { editLadderEvent(event, member: member) }
                    Button("Remove", systemImage: "trash", role: .destructive) { Task { await removeLadderEvent(event, member: member) } }
                } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 44, height: 44) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let w = ladderWorkout(event, member: member) { viewingWorkout = w }
            else if let e = ladderFoodEntry(event, member: member) { editingFood = e }
        }
        .slideToDelete(enabled: event.workoutId != nil) { Task { await removeLadderEvent(event, member: member) } }
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
            SectionTitle(title: "Today's Meals", actionTitle: "Add +", action: { showFood = true }, symbol: "fork.knife", tint: Theme.brand, compact: true)
            if events.isEmpty {
                Text("No meals logged yet. Tap Add to log your first meal.")
                    .readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        compactMealRow(event, member: member, isLast: index == events.count - 1)
                    }
                }
            }
        }
        .todaySurface()
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
                        .readableFont(15, weight: .regular, design: .default).foregroundStyle(.secondary)
                    Text(event.title).readableFont(15, weight: .semibold, relativeTo: .caption).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 2)
                if !event.detail.isEmpty { Text(event.detail).readableFont(15, weight: .regular, design: .default).foregroundStyle(.primary) }
                Image(systemName: "chevron.right").readableFont(15, weight: .semibold, design: .default).foregroundStyle(.tertiary)
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

    /// Daily exercise progress and supporting metrics, using only available Health/app data.
    private func compactActivity(_ member: Member) -> some View {
        let showsHealth = HealthActivityCard.isVisible(for: member, linkedID: healthMemberID, health: health)
        let logged = tracking.workouts(for: member)
        let minutes = max(logged.reduce(0) { $0 + $1.minutes }, showsHealth ? (health.activity.exerciseMinutes ?? 0) : 0)
        let dailyGoal = max(ActivityGoals.suggested(for: member).weeklyMinutes / 7, 20)
        let reachedGoal = minutes >= dailyGoal
        let fraction = Double(minutes) / Double(dailyGoal)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "figure.run").readableFont(25, weight: .semibold).foregroundStyle(.orange)
                    .frame(width: 46, height: 46).background(Color.orange.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity").readableFont(23, weight: .bold)
                    Text("Move more, feel better!").readableFont(14).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { activityStartsLogging = false; showActivity = true } label: {
                    HStack(spacing: 5) { Text("See all"); Image(systemName: "chevron.right") }.readableFont(15, weight: .semibold)
                        .foregroundStyle(.orange).padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Color.orange.opacity(0.08), in: Capsule())
                }.buttonStyle(.plain)
            }
            activityRingAndGoal {

                ZStack {
                    Circle().stroke(Color.orange.opacity(0.13), lineWidth: 10)
                    Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                        .stroke(Color.orange.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Image(systemName: "figure.run").readableFont(20, weight: .semibold).foregroundStyle(.orange)
                        Text(minutes.formatted()).readableFont(30, weight: .bold).monospacedDigit()
                        Text("of \(dailyGoal) min").readableFont(13).foregroundStyle(.secondary)
                        Text("\(Int((fraction * 100).rounded()))%")
                            .readableFont(13, weight: .bold).foregroundStyle(.orange)
                    }
                }
                .frame(width: activityRingSize + 20, height: activityRingSize + 20).padding(5)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Exercise, \(minutes) of \(dailyGoal) minutes, \(Int((fraction * 100).rounded())) percent")
                VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: reachedGoal ? "checkmark.circle.fill" : "clock.fill")
                        .readableFont(26).foregroundStyle(reachedGoal ? Theme.brand : .orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(reachedGoal ? "Goal reached!" : "Keep moving!")
                            .readableFont(18, weight: .bold).foregroundStyle(reachedGoal ? Theme.brand : .orange)
                        Text(reachedGoal
                             ? (minutes == dailyGoal ? "You've met your exercise goal today." : "You're \(minutes - dailyGoal) min over your goal today.")
                             : "\(dailyGoal - minutes) min to reach your exercise goal.")
                            .readableFont(14).foregroundStyle(.secondary)
                        if reachedGoal {
                            Text(goalComment)
                                .readableFont(12).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .onAppear { rotateGoalComment() }
                                .onChange(of: member.id) { _, _ in rotateGoalComment() }
                                .onChange(of: tracking.day) { _, _ in rotateGoalComment() }
                        }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background((reachedGoal ? Theme.brand : Color.orange).opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            SingleRow(spacing: 8) {
                activitySummary("shoeprints.fill", title: "Steps", value: showsHealth ? (health.activity.steps.map { $0.formatted() } ?? "—") : "—", tint: .blue)
                activitySummary("flame.fill", title: "Active kcal", value: showsHealth ? (health.activity.activeKcal.map { Int($0.rounded()).formatted() } ?? "—") : "—", tint: .orange)
                activitySummary("dumbbell.fill", title: "Workout kcal", value: logged.reduce(0) { $0 + $1.caloriesBurned }.formatted(), tint: .purple)
                activitySummary("heart.fill", title: "Avg. heart rate",
                                value: showsHealth ? (health.activity.averageHeartRateBpm.map { "\(Int($0.rounded())) bpm" } ?? "—") : "—",
                                detail: showsHealth ? (health.activity.restingHeartRateBpm.map { "Resting \(Int($0.rounded())) bpm" } ?? "Resting unavailable") : "Resting unavailable", tint: .pink)
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.08)))
            SingleRow(spacing: 8) {
                activitySummary("clock", title: "Duration", value: "\(minutes) min", tint: .orange)
                activitySummary("figure.walk", title: "Distance", value: showsHealth ? (health.activity.walkingRunningDistanceMeters.map {
                    ($0 / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
                } ?? "—") : "—", tint: .green)
                activitySummary("bolt.fill", title: "Total kcal", value: showsHealth ? (health.activity.totalEnergyKcal.map { Int($0.rounded()).formatted() } ?? "—") : "—", tint: .yellow)
                activitySummary("stairs", title: "Flights", value: showsHealth ? (health.activity.flightsClimbed.map { $0.formatted() } ?? "—") : "—", tint: .blue)
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.08)))
        }
        .todaySurface(tint: .orange)
        .contentShape(Rectangle())
        .onTapGesture { activityStartsLogging = false; showActivity = true }
    }

    private func rotateGoalComment() {
        let comments = [
            "Your sofa misses you. 😄",
            "Your sneakers have earned bragging rights. 👟",
            "Plot twist: you were the energy boost. ⚡",
            "The stairs are asking for a rematch. 😄",
            "Your watch would high-five you if it could. 🙌",
            "Today's side quest: completed. 🎉",
            "You gave the couch a day off. 🛋️",
            "Look at you, collecting minutes like trophies. 🏆"
        ]
        let next = (max(lastGoalCommentIndex, -1) + 1) % comments.count
        lastGoalCommentIndex = next
        goalComment = comments[next]
    }

    @Environment(\.dynamicTypeSize) private var activityTextSize

    private func activityRingAndGoal<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let layout = activityTextSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout { content() }
    }

    @ScaledMetric(relativeTo: .caption) private var activityLabelHeight: CGFloat = 32

    private func activitySummary(_ symbol: String, title: String, value: String, detail: String? = nil, tint: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 3) {
                Image(systemName: symbol).readableFont(11, weight: .medium).foregroundStyle(tint)
                    .padding(.top, 2).accessibilityHidden(true)
                Text(title).readableFont(12).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight: activityLabelHeight, alignment: .topLeading)
            Text(value).readableFont(18, weight: .bold).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.85)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, value, detail].compactMap { $0 }.joined(separator: ", "))
    }

    /// "Medications": the compact, two-column-width sibling of `MedicationsCard`, showing just today's
    /// doses in brief. Used both in the normal two-column row and, when a dose needs attention, promoted
    /// full-width above everything else.
    private func compactMedications(_ member: Member) -> some View {
        let doses = medications.doses(for: member)
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Medications", actionTitle: "Manage", action: { showMeds = true }, symbol: "pills.fill", tint: .blue, compact: true, actionShowsChevron: true)
            if doses.isEmpty {
                HStack {
                    Text("No medications scheduled").readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add", systemImage: "plus") { showMeds = true }
                        .readableFont(15, weight: .semibold, relativeTo: .caption).buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(doses.prefix(4)) { dose in
                        compactDoseRow(dose, member: member)
                        if dose.id != doses.prefix(4).last?.id { Divider() }
                    }
                }
            }
        }
        .todaySurface()
        .id("meds")
        .alert("Family reminder", isPresented: Binding(get: { medications.reminderResult != nil }, set: { if !$0 { medications.reminderResult = nil } })) {
            Button("OK") { medications.reminderResult = nil }
        } message: { Text(medications.reminderResult ?? "") }
    }

    private func compactDoseRow(_ dose: ScheduledDose, member: Member) -> some View {
        VStack(alignment: .leading, spacing: 4) {
        ReadableStack(spacing: 8) {
            Image(systemName: dose.state == .taken ? "checkmark.circle.fill" : dose.state == .skipped ? "xmark.circle" : "clock")
                .readableFont(16, weight: .regular, relativeTo: .footnote)
                .foregroundStyle(dose.state == .taken ? .green : dose.state == .missed ? .red : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(dose.medication.name).readableFont(17, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                Text(dose.dueAt.formatted(date: .omitted, time: .shortened)).readableFont(15, weight: .regular, relativeTo: .caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            if dose.state != .taken && dose.state != .skipped && family.canManage(member) {
                Button("Take") { Task { await medications.mark(dose, as: .taken) } }
                    .readableFont(15, weight: .semibold, relativeTo: .caption2).buttonStyle(.bordered).controlSize(.regular)
                    .lineLimit(1).fixedSize()
            } else if dose.state == .taken {
                Text("Taken").readableFont(15, weight: .semibold, relativeTo: .caption2).foregroundStyle(.green).lineLimit(1).fixedSize()
            }
            if family.canManage(member) {
                Menu {
                    if dose.state != .taken { Button("Mark taken", systemImage: "checkmark") { Task { await medications.mark(dose, as: .taken) } } }
                    if dose.state != .skipped { Button("Skip", systemImage: "forward") { Task { await medications.mark(dose, as: .skipped) } } }
                    Button("Manage medications", systemImage: "pills") { showMeds = true }
                } label: { Image(systemName: "ellipsis").readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary).frame(width: 44, height: 44) }
            }
        }
        if MedicationStore.canRemind(dose, member: member, userID: family.myUserId) {
            Button {
                Task { await medications.remind(dose, member: member, userID: family.myUserId) }
            } label: {
                Label(medications.sendingReminder == dose.id ? "Sending…" : "Remind them", systemImage: "bell.badge")
                    .readableFont(16, weight: .semibold).frame(minHeight: 44)
            }
            .disabled(medications.sendingReminder != nil)
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: macroWidth * 1.4), spacing: 16)], spacing: 12) {
            NutrientBar(title: "Sugar", share: b.sugarShare, detail: "\(Int(b.eaten.sugarG.rounded())) / \(Int(b.limits.sugarG.rounded())) g")
            NutrientBar(title: "Sodium", share: b.sodiumShare, detail: "\(Int(b.eaten.sodiumMg.rounded())) / \(Int(b.limits.sodiumMg.rounded())) mg")
            NutrientBar(title: "Saturated fat", share: b.satFatShare, detail: "\(Int(b.eaten.satFatG.rounded())) / \(Int(b.limits.satFatG.rounded())) g")
            NutrientBar(title: "Fibre", share: b.fiberShare, detail: "\(Int(b.eaten.fiberG.rounded())) / \(Int(b.limits.fiberG.rounded())) g", goodWhenHigh: true)
            }
        }
        .todaySurface()
    }
}

/// A progress ring with a big number and a small caption inside.
struct ScoreRingLabel: View {
    let fraction: Double
    let color: Color
    let primary: String
    let secondary: String
    /// Ring stroke width and primary-number font size, for a smaller ring (e.g. the narrow Activity
    /// card) that would otherwise look stroke-heavy and oversized relative to its own frame.
    var lineWidth: CGFloat = 14
    var primaryFontSize: CGFloat = 34
    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle().trim(from: 0, to: shown)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(primary).readableFont(primaryFontSize, weight: .bold, design: .rounded, relativeTo: .title).monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text(secondary).readableFont(15, weight: .regular, relativeTo: .caption2).foregroundStyle(.secondary)
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
        let target = min(max(fraction, 0), 1)
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
            Text(letter).readableFont(18, weight: .bold, design: .rounded).foregroundStyle(color)
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

/// One macro (carbs/protein/fat) against a rough daily goal, as an icon, label, value and a thin bar —
/// used three-up under the calorie ring on the Daily Calories card.
struct MacroBar: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let symbol: String
    let tint: Color
    let title: String
    let value: Double
    let goal: Double
    private var fraction: Double { goal > 0 ? max(value / goal, 0) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if textSize >= .xxxLarge {
                VStack(alignment: .leading, spacing: 5) { icon; summary }
            } else {
                HStack(spacing: 4) { icon; summary }
            }
            Capsule().fill(tint.opacity(0.15)).frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(tint.gradient)
                            .frame(width: geo.size.width * min(fraction, 1))
                    }
                }.accessibilityHidden(true)
            if textSize >= .xxxLarge {
                VStack(alignment: .leading, spacing: 2) { percentage; remaining }
            } else {
                HStack(spacing: 2) { percentage; Spacer(minLength: 0); remaining }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private var icon: some View {
        Image(systemName: symbol).readableFont(16, weight: .semibold).foregroundStyle(tint)
            .frame(width: 26, height: 32).background(tint.opacity(0.13), in: Circle())
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).readableFont(14, weight: .bold).fixedSize()
            Text("\(Int(value.rounded())) / \(Int(goal.rounded())) g")
                .readableFont(12).foregroundStyle(.secondary).fixedSize()
        }
    }
    private var percentage: some View {
        Text("\(Int((fraction * 100).rounded()))%").readableFont(13, weight: .bold).foregroundStyle(tint).fixedSize()
    }
    private var remaining: some View {
        Text("\(Int(max(goal - value, 0).rounded())) g left").readableFont(11).foregroundStyle(.secondary).fixedSize()
    }
}

/// A rule-based "how's today going" card, from `TodayInsight` — a free, always-on companion to the
/// AI-written tip pill at the top, in the same spirit as `ScoringEngine`'s explainable scoring.
struct InsightCard: View {
    let headline: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill").readableFont(18, weight: .regular, relativeTo: .body).foregroundStyle(.blue)
                .frame(width: 44, height: 44).background(Color.blue.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Today's insight").readableFont(15, weight: .semibold, relativeTo: .caption).foregroundStyle(.blue)
                Text(headline).readableFont(17, weight: .semibold, relativeTo: .subheadline)
                Text(detail).readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").readableFont(15, weight: .semibold, relativeTo: .caption).foregroundStyle(.tertiary)
        }
        .todaySurface()
    }
}

/// Soft surfaces specific to the Today dashboard.
private extension View {
    func todaySurface(tint: Color? = nil) -> some View {
        card(padding: 16, radius: 18, tint: tint)
    }
}

private struct TodayBackground: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppBackground()
            Image(systemName: "leaf.fill")
                .font(.system(size: 100)).rotationEffect(.degrees(-30))
                .foregroundStyle(.green.opacity(0.09)).offset(x: 25, y: 85)
        }.ignoresSafeArea()
    }
}
