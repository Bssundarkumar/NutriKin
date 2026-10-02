import SwiftUI
import Charts

struct BuddyAnalysisView: View {
    let group: BuddyGroup
    let initialMemberID: UUID?
    @Environment(BuddyStore.self) private var buddies
    @Environment(\.dismiss) private var dismiss
    @State private var memberID: UUID?
    @State private var days = 30
    @State private var workouts: [Workout] = []
    @State private var exercise = ""
    @State private var isLoading = false
    @State private var message: String?
    @State private var selectedTimeDay: Date?
    @State private var selectedWeightDay: Date?
    @AppStorage("strengthUsesPounds") private var pounds = false

    private var roster: [Buddy] { buddies.buddies(in: group) }
    private var selectedID: UUID? { memberID ?? initialMemberID ?? roster.first?.memberId }
    private var end: Date { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? .now }
    private var start: Date { Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end }
    private var exerciseNames: [String] { Array(Set(workouts.flatMap { $0.exercises ?? [] }.map(\.name))).sorted() }
    private var time: [BuddyAnalytics.DayPoint] { BuddyAnalytics.time(workouts, start: start, end: end) }
    private var weights: [BuddyAnalytics.DayPoint] { BuddyAnalytics.weight(workouts, exercise: exercise) }
    private var volume: [BuddyAnalytics.DayPoint] { BuddyAnalytics.volume(workouts, exercise: exercise) }
    private var unit: String { pounds ? "lb" : "kg" }
    private func loadValue(_ kg: Double) -> Double { pounds ? kg / StrengthMath.kgPerLb : kg }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.name).readableFont(22, weight: .bold)
                        Picker("Person", selection: Binding(get: { selectedID }, set: { memberID = $0 })) {
                            ForEach(roster) { Text($0.displayName).tag(Optional($0.memberId)) }
                        }
                        Picker("Period", selection: $days) {
                            Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90)
                        }.pickerStyle(.segmented)
                    }.card()
                    if isLoading { ProgressView("Loading analysis…").frame(maxWidth: .infinity).padding() }
                    else if let message {
                        Text(message).foregroundStyle(.red)
                        Button("Retry") { Task { await load() } }.frame(minHeight: 44)
                    } else if workouts.isEmpty {
                        Text("No workouts recorded for this person in this period.").readableFont(17).foregroundStyle(.secondary).card()
                    } else {
                        timeChart
                        if !exerciseNames.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Exercise progress").readableFont(21, weight: .bold)
                                Picker("Exercise", selection: $exercise) {
                                    ForEach(exerciseNames, id: \.self) { Text($0).tag($0) }
                                }
                                Toggle("Use pounds", isOn: $pounds)
                            }.card()
                            weightChart
                            volumeChart
                        }
                    }
                }.padding(16)
            }
            .background(AppBackground())
            .navigationTitle("Analysis").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: "\(selectedID?.uuidString ?? "")/\(days)") { await load() }
            .onChange(of: exercise) { _, _ in selectedWeightDay = nil }
        }.tint(Theme.brand)
    }

    private var timeChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workout time").readableFont(21, weight: .bold)
            Text("\(workouts.reduce(0) { $0 + $1.minutes }) min · \(workouts.count) workouts")
                .readableFont(17, weight: .semibold)
            Chart(time) { point in
                BarMark(x: .value("Day", point.day, unit: .day), y: .value("Minutes", point.value))
                    .foregroundStyle(Theme.brand)
                if let selectedTimeDay, Calendar.current.isDate(point.day, inSameDayAs: selectedTimeDay) {
                    RuleMark(x: .value("Day", point.day)).foregroundStyle(.secondary)
                }
            }
            .chartXSelection(value: $selectedTimeDay)
            .chartXScale(domain: start...end)
            .chartYAxisLabel("Minutes")
            .frame(height: 190)
            if let selectedTimeDay, let point = time.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selectedTimeDay) }) {
                Text("\(point.day.formatted(date: .abbreviated, time: .omitted)): \(Int(point.value)) min").readableFont(15)
            }
            Text("Each workout session is counted once, even when it includes several exercises.")
                .readableFont(13).foregroundStyle(.secondary)
        }.card()
    }
    private var weightChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weight used · \(unit)").readableFont(21, weight: .bold)
            Text(exercise).readableFont(16, weight: .medium)
            if weights.isEmpty {
                Text("No weighted sets recorded for this exercise. Bodyweight sets have no external load to plot.")
                    .readableFont(16).foregroundStyle(.secondary)
            } else {
                Chart(weights) { point in
                    LineMark(x: .value("Day", point.day), y: .value("Weight", loadValue(point.value))).foregroundStyle(.blue)
                    PointMark(x: .value("Day", point.day), y: .value("Weight", loadValue(point.value))).foregroundStyle(.blue)
                }
                .chartXSelection(value: $selectedWeightDay)
                .chartXScale(domain: start...end)
                .chartYAxisLabel(unit)
                .frame(height: 190)
                if let point = selectedWeightPoint {
                    Text("\(point.day.formatted(date: .abbreviated, time: .omitted)): \(loadValue(point.value).formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                        .readableFont(15, weight: .semibold)
                }
                Text("Heaviest working set each day. Only dates with recorded weighted sets appear; gaps do not mean zero weight.")
                    .readableFont(13).foregroundStyle(.secondary)
            }
        }.card()
    }
    private var volumeChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Total lifted · \(unit)").readableFont(21, weight: .bold)
            if !volume.isEmpty {
                Chart(volume) { point in
                    BarMark(x: .value("Day", point.day, unit: .day), y: .value("Total lifted", loadValue(point.value)))
                        .foregroundStyle(Theme.brand)
                }.chartXScale(domain: start...end).chartYAxisLabel(unit).frame(height: 170)
            }
            Text("Weight × reps, summed over this exercise's sets. Use it alongside working weight to see changes in training volume.")
                .readableFont(13).foregroundStyle(.secondary)
        }.card()
    }
    private var selectedWeightPoint: BuddyAnalytics.DayPoint? {
        guard let selectedWeightDay else { return weights.last }
        return weights.min { abs($0.day.timeIntervalSince(selectedWeightDay)) < abs($1.day.timeIntervalSince(selectedWeightDay)) }
    }
    private func load() async {
        guard let selectedID else { workouts = []; return }
        let requestedDays = days
        isLoading = true; message = nil; selectedTimeDay = nil; selectedWeightDay = nil
        do {
            let rows = try await buddies.analysisWorkouts(group: group, memberID: selectedID, start: start, end: min(end, Date()))
            guard !Task.isCancelled, self.selectedID == selectedID, days == requestedDays else { return }
            workouts = BuddyAnalytics.unique(rows)
            if !exerciseNames.contains(exercise) { exercise = exerciseNames.first ?? "" }
            isLoading = false
        } catch {
            guard !Task.isCancelled, self.selectedID == selectedID, days == requestedDays else { return }
            workouts = []; message = "Couldn't load analysis. \(error.localizedDescription)"; isLoading = false
        }
    }
}
