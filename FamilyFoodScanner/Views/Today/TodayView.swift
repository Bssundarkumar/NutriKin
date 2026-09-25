import SwiftUI

/// The home screen: how today is going for one person, and quick ways to log food and workouts.
struct TodayView: View {
    var onScan: () -> Void

    @Environment(FamilyStore.self) private var family
    @Environment(TrackingStore.self) private var tracking
    @Environment(AIConnection.self) private var ai
    @Environment(MedicationStore.self) private var medications
    @Environment(HealthKitManager.self) private var health
    @AppStorage("healthMemberID") private var healthMemberID = ""
    @AppStorage("todayMemberID") private var selectedID = ""
    @State private var showFood = Demo.opensLogFood
    @State private var showWorkout = Demo.opensLogWorkout
    @State private var editingWorkout: Workout?
    @State private var viewingWorkout: Workout?
    @State private var showDatePicker = false
    @State private var showSchedule = false
    @State private var pickedDay = Date()
    @State private var showAsk = false
    @State private var showMeds = Demo.opensMeds

    private var member: Member? {
        if Demo.isOn, let i = Demo.memberIndex, family.members.indices.contains(i) { return family.members[i] }
        return family.members.first { $0.id.uuidString == selectedID } ?? family.members.first
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
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
                        let order = TodayLayout.cards(
                            for: member,
                            hasMedications: !medications.medications(for: member).isEmpty,
                            needsAttention: tracking.isToday && doses.contains { $0.state == .due || $0.state == .missed })
                        ForEach(order, id: \.self) { card in
                            cardView(card, member: member, budget: budget)
                        }
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
            .refreshable { await tracking.load(householdId: family.householdId) }
            .task(id: family.householdId) { await tracking.load(householdId: family.householdId) }
            .sheet(isPresented: $showFood) { if let member { LogFoodSheet(member: member) } }
            .sheet(isPresented: $showWorkout) { if let member { LogWorkoutSheet(member: member) } }
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
            .sheet(isPresented: $showSchedule) { if let member { ScheduleView(member: member) } }
            .sheet(item: $viewingWorkout) { w in WorkoutDetailView(workout: w) { editingWorkout = w } }
            .sheet(item: $editingWorkout) { w in
                if let member { if w.workoutKind == .strength { StrengthSessionView(member: member, editing: w) } else { LogWorkoutSheet(member: member, editing: w) } }
            }
            .sheet(isPresented: $showAsk) { AskAIView(product: nil) }
            .sheet(isPresented: $showMeds) { if let member { MedicationsManageView(member: member) } }
            .task(id: tracking.day) {
                medications.updateMemberNames(family.members)
                await medications.load(householdId: family.householdId, day: tracking.day)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrikinActivityAction)) { _ in
                let actions = NotificationRouter.pendingActivity; NotificationRouter.pendingActivity = []
                Task { for a in actions { await logScheduled(memberID: a.memberID, kind: a.kind, minutes: a.minutes, at: a.at) } }
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

    @ViewBuilder
    private func cardView(_ card: TodayCard, member: Member, budget: DayBudget) -> some View {
        switch card {
        case .hero:
            VStack(spacing: 22) {
                hero(member, budget)
                DayTipCard(member: member, budget: budget, steps: health.activity.steps, weekMinutes: tracking.weeklyMinutes(for: member))
            }
        case .quickActions: quickActions
        case .medications: MedicationsCard(member: member) { showMeds = true }.id("meds")
        case .limits: nutrients(budget)
        case .eaten: foodSection(member)
        case .workouts: workoutSection(member)
        }
    }

    // MARK: Day navigation

    private var dayTitle: String {
        if tracking.isToday { return "Today" }
        if Calendar.current.isDateInYesterday(tracking.day) { return "Yesterday" }
        return tracking.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private var dayNavigator: some View {
        HStack {
            Button { Task { await tracking.moveDay(by: -1) } } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
            Spacer()
            VStack(spacing: 0) {
                Text(dayTitle).font(.headline)
                Text(tracking.day.formatted(.dateTime.day().month(.wide).year())).font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { pickedDay = tracking.day; showDatePicker = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Pick a date")
            if !tracking.isToday {
                Button("Today") { Task { await tracking.goToToday() } }.font(.footnote.weight(.semibold))
            }
            Spacer()
            Button { Task { await tracking.moveDay(by: 1) } } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
                .disabled(tracking.isToday)
        }
        .font(.body.weight(.semibold))
        .padding(.horizontal, 4)
    }

    // MARK: Hero

    private func hero(_ member: Member, _ budget: DayBudget) -> some View {
        let color = Theme.color(for: budget.calorieStatus)
        let left = Int(budget.remaining.rounded())
        return VStack(spacing: 16) {
            HStack(spacing: 18) {
                ScoreRingLabel(fraction: budget.calorieShare, color: color, primary: "\(abs(left))",
                               secondary: left >= 0 ? "kcal left" : "kcal over")
                    .frame(width: 132, height: 132)
                VStack(alignment: .leading, spacing: 6) {
                    Text(statusHeadline(budget)).font(.headline).foregroundStyle(Theme.color(for: budget.status))
                    Text(statusDetail(member, budget)).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                StatTile(title: "Eaten", value: "\(Int(budget.eaten.calories.rounded()))", symbol: "fork.knife")
                StatTile(title: "Exercise", value: "+\(budget.burned)", symbol: "flame.fill", tint: .orange)
                StatTile(title: "Goal", value: "\(Int(budget.limits.calories.rounded()))", symbol: "target", tint: .blue)
            }
        }
        .card()
    }

    private func statusHeadline(_ b: DayBudget) -> String {
        if b.calorieShare >= 1 { return "Over today's calories" }
        if let alert = b.nutrientAlert {
            return alert.share >= 1 ? "\(alert.name.capitalized) limit reached" : "Close to the \(alert.name) limit"
        }
        if b.calorieShare >= 0.8 { return "Nearly at today's calories" }
        return b.eaten.calories == 0 ? "A fresh day" : "On track"
    }

    private func statusDetail(_ member: Member, _ b: DayBudget) -> String {
        if b.eaten.calories == 0 && b.burned == 0 { return "Nothing logged yet for \(member.name). Scan or log a meal to start." }
        if b.burned > 0 {
            let source = b.healthBurned > b.loggedBurned ? " (from Apple Health)" : ""
            return "\(Int(b.exerciseBonus.rounded())) kcal from exercise is added to \(member.name)'s allowance (half of the \(b.burned) burned\(source))."
        }
        return "Calories and limits for \(member.name)'s day."
    }

    // MARK: Actions and nutrients

    private var quickActions: some View {
        HStack(spacing: 8) {
            QuickAction(title: "Scan", symbol: "barcode.viewfinder", action: onScan)
            QuickAction(title: "Log food", symbol: "plus.circle.fill") { showFood = true }
            QuickAction(title: "Workout", symbol: "figure.run", tint: .orange) { showWorkout = true }
            QuickAction(title: "Ask AI", symbol: "sparkles", tint: .purple) { showAsk = true }
        }
    }

    private func nutrients(_ b: DayBudget) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Daily limits and targets")
            NutrientBar(title: "Sugar", share: b.sugarShare, detail: "\(Int(b.eaten.sugarG.rounded())) / \(Int(b.limits.sugarG.rounded())) g")
            NutrientBar(title: "Sodium", share: b.sodiumShare, detail: "\(Int(b.eaten.sodiumMg.rounded())) / \(Int(b.limits.sodiumMg.rounded())) mg")
            NutrientBar(title: "Saturated fat", share: b.satFatShare, detail: "\(Int(b.eaten.satFatG.rounded())) / \(Int(b.limits.satFatG.rounded())) g")
            NutrientBar(title: "Fibre", share: b.fiberShare, detail: "\(Int(b.eaten.fiberG.rounded())) / \(Int(b.limits.fiberG.rounded())) g", goodWhenHigh: true)
            HStack {
                Text("Carbs \(Int(b.eaten.carbsG.rounded())) g").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Protein \(Int(b.eaten.proteinG.rounded())) g").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Fat \(Int(b.eaten.fatG.rounded())) g").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: Lists

    private func foodSection(_ member: Member) -> some View {
        let list = tracking.entries(for: member)
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Eaten", actionTitle: "Add") { showFood = true }
            if list.isEmpty {
                EmptyState(symbol: "fork.knife", title: "Nothing logged", message: "Scan a product and tap \u{201C}Log as eaten\u{201D}, or add a meal.")
            } else {
                VStack(spacing: 0) {
                    ForEach(list) { e in
                        row(symbol: symbol(for: e.source), title: e.label, subtitle: e.eatenAt.formatted(date: .omitted, time: .shortened),
                            trailing: TodayLayout.showsCalorieSummary(for: member) ? "\(Int(e.calories.rounded())) kcal" : "", tint: Theme.brand) {
                            Task { await tracking.delete(e) }
                        }
                        if e.id != list.last?.id { Divider().padding(.leading, 48) }
                    }
                }
            }
        }
        .card()
    }

    /// One card for everything about activity: Health's steps and calories, workouts waiting to be added from
    /// Health, and the workouts already logged.
    private func workoutSection(_ member: Member) -> some View {
        let list = tracking.workouts(for: member)
        let showsHealth = HealthActivityCard.isVisible(for: member, linkedID: healthMemberID, health: health)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: TodayLayout.isChild(member) ? "Active play" : "Workouts", actionTitle: "Add") { showWorkout = true }
            if TodayLayout.isChild(member) { KidActivityCard(member: member, healthMinutes: showsHealth ? health.activity.exerciseMinutes : nil) }
            scheduledToday(member)
            HealthActivityCard(member: member)
            goalBars(member, showsSteps: showsHealth)
            if list.isEmpty {
                if !showsHealth {
                    EmptyState(symbol: "figure.run", title: TodayLayout.isChild(member) ? "No play logged yet" : "No workout yet",
                                   message: TodayLayout.isChild(member) ? "Log free play, sports, cycling or any activity to earn today's star." : "Log a walk, a run or any activity to add to today's allowance.")
                } else {
                    Text("No workouts logged for this day yet.").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                if showsHealth { Divider() }
                VStack(spacing: 0) {
                    ForEach(list) { w in
                        row(symbol: w.workoutKind.symbol, title: w.workoutKind.title,
                            subtitle: "\(w.minutes) min \u{00B7} \(w.intensity.title)" + (w.source == "health" ? " \u{00B7} Health" : "") + StrengthSummary.text(w.exercises) + (w.note.map { " \u{00B7} \($0)" } ?? ""),
                            trailing: "\(w.caloriesBurned) kcal", tint: .orange,
                            onTap: (w.exercises?.isEmpty == false) ? { viewingWorkout = w } : nil,
                            onEdit: w.source == "health" ? nil : { editingWorkout = w }) {
                            Task { await tracking.delete(w) }
                        }
                        if w.id != list.last?.id { Divider().padding(.leading, 48) }
                    }
                }
            }
        }
        .card()
        .id("health")
    }

    @ViewBuilder
    private func scheduledToday(_ member: Member) -> some View {
        let todays = tracking.isToday ? ScheduleMath.items(tracking.schedules, for: member.id, on: Date()) : []
        let pending = todays.filter { !ScheduleMath.isLogged($0, workouts: tracking.workouts(for: member), on: Date()) }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(pending) { s in
                HStack(spacing: 10) {
                    Image(systemName: s.workoutKind.symbol).foregroundStyle(.orange)
                    Text("\(s.title) at \(ScheduleMath.timeText(s.time))").font(.subheadline)
                    Spacer()
                    if family.canManage(member) {
                        Button("Went") { Task { await logScheduled(memberID: member.id, kind: s.kind, minutes: s.minutes, at: Date()) } }
                            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small).tint(.orange)
                    }
                }
            }
            Button { showSchedule = true } label: {
                Label(tracking.schedules(for: member).isEmpty ? "Set up a weekly schedule" : "Weekly schedule", systemImage: "calendar")
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private func logScheduled(memberID: UUID, kind: String, minutes: Int, at: Date) async {
        guard let m = family.members.first(where: { $0.id == memberID }), family.canManage(m) else { return }
        let k = WorkoutKind(rawValue: kind) ?? .other
        let w = Workout(householdId: family.householdId, memberId: memberID, doneAt: at, kind: kind, minutes: minutes, intensity: .moderate,
                        caloriesBurned: WorkoutEstimator.calories(kind: k, intensity: .moderate, minutes: minutes, weightKg: m.weightKg))
        if await tracking.add(w) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    @ViewBuilder
    private func goalBars(_ member: Member, showsSteps: Bool) -> some View {
        let steps = showsSteps ? health.activity.steps : nil
        let week = tracking.weeklyMinutes(for: member)
        if (member.goals.dailySteps != nil && steps != nil) || member.goals.weeklyWorkoutMinutes != nil {
            VStack(spacing: 10) {
                if let goal = member.goals.dailySteps, let steps {
                    goalBar(title: "Steps", detail: "\(steps.formatted()) of \(goal.formatted())", fraction: ActivityGoals.fraction(done: steps, goal: goal) ?? 0, tint: .blue)
                }
                if let goal = member.goals.weeklyWorkoutMinutes {
                    goalBar(title: "Workouts this week", detail: "\(week) of \(goal) min", fraction: ActivityGoals.fraction(done: week, goal: goal) ?? 0, tint: .orange)
                }
            }
        }
    }

    private func goalBar(title: String, detail: String, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.subheadline.weight(.semibold)); Spacer(); Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            ProgressView(value: fraction).tint(fraction >= 1 ? .green : tint)
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(for source: FoodSource) -> String {
        switch source {
        case .scan: "barcode.viewfinder"
        case .plate: "camera.viewfinder"
        case .ai: "sparkles"
        case .manual: "pencil"
        }
    }

    private func row(symbol: String, title: String, subtitle: String, trailing: String, tint: Color, onTap: (() -> Void)? = nil, onEdit: (() -> Void)? = nil, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle()).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if onTap != nil { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
            Text(trailing).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            Menu {
                if let onEdit { Button("Edit", systemImage: "pencil", action: onEdit) }
                Button("Remove", systemImage: "trash", role: .destructive, action: onDelete)
            } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 30, height: 34) }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .padding(.vertical, 8)
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
                Text(secondary).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { animate() }
        .onChange(of: fraction) { _, _ in animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(primary) \(secondary)")
    }

    private func animate() {
        let target = min(max(fraction, 0.01), 1)
        if reduceMotion { shown = target } else { withAnimation(.easeOut(duration: 0.9)) { shown = target } }
    }
}
