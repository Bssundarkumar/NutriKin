import SwiftUI

/// The home screen: how today is going for one person, and quick ways to log food and workouts.
struct TodayView: View {
    var onScan: () -> Void

    @Environment(FamilyStore.self) private var family
    @Environment(TrackingStore.self) private var tracking
    @Environment(AIConnection.self) private var ai
    @AppStorage("todayMemberID") private var selectedID = ""
    @State private var showFood = Demo.opensLogFood
    @State private var showWorkout = Demo.opensLogWorkout
    @State private var showAsk = false

    private var member: Member? { family.members.first { $0.id.uuidString == selectedID } ?? family.members.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    dayNavigator
                    if family.members.isEmpty {
                        EmptyState(symbol: "person.3", title: "Add your family first",
                                   message: "Add people in the Family tab, then track what they eat and how they move.")
                            .card()
                    } else if let member {
                        MemberStrip(members: family.members, selectedID: member.id) { selectedID = $0.id.uuidString }
                        let budget = tracking.budget(for: member)
                        hero(member, budget)
                        quickActions
                        nutrients(budget)
                        foodSection(member)
                        workoutSection(member)
                        if let message = tracking.errorMessage {
                            Text(message).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .background(AppBackground())
            .navigationTitle("Today")
            .refreshable { await tracking.load(householdId: family.householdId) }
            .task(id: family.householdId) { await tracking.load(householdId: family.householdId) }
            .sheet(isPresented: $showFood) { if let member { LogFoodSheet(member: member) } }
            .sheet(isPresented: $showWorkout) { if let member { LogWorkoutSheet(member: member) } }
            .sheet(isPresented: $showAsk) { AskAIView(product: nil) }
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
            .onTapGesture { Task { await tracking.goToToday() } }
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
            return "\(Int(b.exerciseBonus.rounded())) kcal from exercise is added to \(member.name)'s allowance (half of the \(b.burned) burned)."
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
                            trailing: "\(Int(e.calories.rounded())) kcal", tint: Theme.brand) {
                            Task { await tracking.delete(e) }
                        }
                        if e.id != list.last?.id { Divider().padding(.leading, 48) }
                    }
                }
            }
        }
        .card()
    }

    private func workoutSection(_ member: Member) -> some View {
        let list = tracking.workouts(for: member)
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Workouts", actionTitle: "Add") { showWorkout = true }
            if list.isEmpty {
                EmptyState(symbol: "figure.run", title: "No workout yet", message: "Log a walk, a run or any activity to add to today's allowance.")
            } else {
                VStack(spacing: 0) {
                    ForEach(list) { w in
                        row(symbol: w.workoutKind.symbol, title: w.workoutKind.title,
                            subtitle: "\(w.minutes) min \u{00B7} \(w.intensity.title)" + (w.note.map { " \u{00B7} \($0)" } ?? ""),
                            trailing: "\(w.caloriesBurned) kcal", tint: .orange) {
                            Task { await tracking.delete(w) }
                        }
                        if w.id != list.last?.id { Divider().padding(.leading, 48) }
                    }
                }
            }
        }
        .card()
    }

    private func symbol(for source: FoodSource) -> String {
        switch source {
        case .scan: "barcode.viewfinder"
        case .plate: "camera.viewfinder"
        case .ai: "sparkles"
        case .manual: "pencil"
        }
    }

    private func row(symbol: String, title: String, subtitle: String, trailing: String, tint: Color, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle()).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(trailing).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            Menu {
                Button("Remove", systemImage: "trash", role: .destructive, action: onDelete)
            } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 30, height: 34) }
        }
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
