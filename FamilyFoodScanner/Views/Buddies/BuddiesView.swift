import SwiftUI

/// Gym buddies: adult friends (in any family) who share their workouts. Buddies see only each other's workouts.
struct BuddiesView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(TrackingStore.self) private var tracking
    @Environment(\.dismiss) private var dismiss
    @State private var store = BuddyStore()
    @State private var selected: UUID?
    @State private var mode: Mode = .none
    @State private var text = ""
    @State private var copying: BuddyPost?
    @State private var viewing: BuddyPost?

    private enum Mode { case none, create, join }

    private var me: Member? { family.myMember }
    private var group: BuddyGroup? { store.groups.first { $0.id == selected } ?? store.groups.first }

    var body: some View {
        NavigationStack {
            List {
                if let error = store.errorMessage { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
                if me == nil || (me?.age ?? 0) < 18 {
                    Section {
                        Text("Gym buddies are for adults. Open your profile in the Family tab, turn on \u{201C}This is me\u{201D} and add your age (18 or over).")
                            .font(.subheadline)
                    }
                } else if store.groups.isEmpty {
                    startSection
                } else if let group {
                    groupSections(group)
                }
                Section {
                    Text("Buddies see only your workouts (type, time, effort, notes and strength sets). They never see your food, medicines, weight, health data or anyone else in your family. Only adults can join, and you can leave any time.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .softList()
            .navigationTitle("Gym buddies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await store.load(myUserId: family.myUserId) }
            .refreshable { await store.load(myUserId: family.myUserId) }
            .sheet(item: $copying) { post in
                if let me { StrengthSessionView(member: me, prefill: (post.workout.exercises ?? []).map { StrengthExercise(name: $0.name, sets: $0.sets) }) }
            }
            .sheet(item: $viewing) { post in WorkoutDetailView(workout: post.workout, onEdit: {}, readOnly: true) }
        }
    }

    // MARK: No group yet

    private var startSection: some View {
        Section {
            switch mode {
            case .none:
                Button { mode = .create } label: { Label("Start a group", systemImage: "person.2.fill") }
                Button { mode = .join } label: { Label("Join with a code", systemImage: "key.fill") }
            case .create:
                TextField("Group name, for example Gym crew", text: $text)
                Button("Create group") { Task { if let me, await store.create(name: text, member: me, myUserId: family.myUserId) { mode = .none; text = "" } } }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Back") { mode = .none }
            case .join:
                TextField("Invite code", text: $text).textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button("Join") { Task { if let me, await store.join(code: text, member: me, myUserId: family.myUserId) { mode = .none; text = "" } } }
                    .disabled(text.trimmingCharacters(in: .whitespaces).count < 4)
                Button("Back") { mode = .none }
            }
        } header: { Text("Train together") } footer: {
            Text("Start a group of up to \(BuddyMath.maxGroupSize) adults and share the code, or join a friend's group.")
        }
    }

    // MARK: A group

    @ViewBuilder
    private func groupSections(_ group: BuddyGroup) -> some View {
        if store.groups.count > 1 {
            Section { Picker("Group", selection: Binding(get: { group.id }, set: { selected = $0 })) { ForEach(store.groups) { Text($0.name).tag($0.id) } } }
        }
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.headline)
                    Text("\(store.buddies(in: group).count) of \(BuddyMath.maxGroupSize) people \u{00B7} code \(group.inviteCode)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ShareLink(item: "Join my gym buddies group \u{201C}\(group.name)\u{201D} on NutriKin with the code \(group.inviteCode).") { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.borderless)
            }
            Text(store.buddies(in: group).map(\.displayName).joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Your group") }

        let members = Set(store.buddies(in: group).map(\.memberId))
        let posts = store.posts.filter { members.contains($0.workout.memberId) }
        let mine = me.map { tracking.recentWorkouts(for: $0) } ?? []
        let week = BuddyMath.week(posts + mine.map { BuddyPost(workout: $0, name: "You") }, since: ActivityGoals.weekStart())
        if !week.isEmpty {
            Section("This week") {
                ForEach(week) { line in
                    HStack {
                        Text(line.name).font(.subheadline.weight(line.name == "You" ? .bold : .regular))
                        Spacer()
                        Text("\(line.sessions) workout\(line.sessions == 1 ? "" : "s") \u{00B7} \(line.minutes) min" + (line.volumeKg > 0 ? " \u{00B7} \(StrengthMath.display(kg: line.volumeKg, pounds: false)) kg lifted" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        Section("What your buddies did") {
            if posts.isEmpty { Text("No workouts from your buddies in the last three weeks.").font(.footnote).foregroundStyle(.secondary) }
            let myExercises = mine.flatMap { $0.exercises ?? [] }
            ForEach(posts.prefix(40)) { post in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: post.workout.workoutKind.symbol).frame(width: 32, height: 32)
                            .background(Color.orange.opacity(0.14), in: Circle()).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(post.name) \u{00B7} \(post.workout.workoutKind.title)").font(.subheadline.weight(.semibold))
                            Text("\(post.workout.doneAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) \u{00B7} \(post.workout.minutes) min" + StrengthSummary.text(post.workout.exercises))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if post.workout.exercises?.isEmpty == false { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    }
                    let shared = BuddyMath.sharedExercises(post, with: myExercises)
                    if !shared.isEmpty { Text("You both did \(shared.prefix(3).joined(separator: ", "))").font(.caption).foregroundStyle(Theme.brand) }
                    if post.workout.exercises?.isEmpty == false {
                        Button { copying = post } label: { Label("Copy to my workout", systemImage: "square.on.square").font(.footnote.weight(.semibold)) }
                            .buttonStyle(.borderless)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if post.workout.exercises?.isEmpty == false { viewing = post } }
            }
        }
        Section {
            Button("Leave this group", role: .destructive) { Task { await store.leave(group, myUserId: family.myUserId) } }
        }
    }
}
