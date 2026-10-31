import SwiftUI
import FamilyControls
import Combine
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: BlockModel
    @State private var chooseCore = false
    @State private var chooseExtra = false
    @State private var confirm = false
    @State private var chooseDuration = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Form {
                Section("Protection") {
                    Label(model.authorization == .approved ? "Screen Time authorized" : "Permission required",
                          systemImage: model.authorization == .approved ? "shield.checkered" : "shield.slash")
                    if model.authorization != .approved {
                        Button("Authorize Screen Time") { Task { await model.authorize() } }
                    }
                    Text("Committed blocks have no cancel, pause, or emergency unlock in this app. iOS permission changes can still remove enforcement.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                }
                Section("Blocked apps and sites") {
                    Button("Core: choose additional apps") { chooseCore = true }
                        .disabled(model.profilesLocked || model.authorization != .approved)
                    Text("Core selection: \(model.core.applicationTokens.count) apps, \(model.core.categoryTokens.count) categories, \(model.core.webDomainTokens.count) websites")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Threads and Facebook are included automatically: their apps are hidden during active Core and Extra blocks, and their websites are blocked. Instagram and TikTok websites are also included; select their native apps above.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Extra: choose YouTube and additional apps") { chooseExtra = true }
                        .disabled(model.profilesLocked || model.authorization != .approved)
                    Text("Extra selection: \(model.extra.applicationTokens.count) apps, \(model.extra.categoryTokens.count) categories, \(model.extra.webDomainTokens.count) websites")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Extra includes all Core selections, the Reddit app, Reddit websites, and YouTube websites. The Reddit app is hidden while Extra is active. Select the YouTube app above. Profiles freeze until all committed blocks finish.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Commit a block") {
                    Picker("Mode", selection: $model.mode) {
                        ForEach(BlockMode.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Start later", isOn: $model.startLater)
                    if model.startLater {
                        DatePicker("Starts", selection: $model.startsAt, in: Date()...,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                    Button {
                        dismissKeyboard()
                        chooseDuration = true
                    } label: {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(model.duration.summary).foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                    Text("Duration: \(model.duration.summary). Choose between 1 second and 7 days.")
                        .font(.footnote).foregroundStyle(model.duration.timeInterval == nil ? .red : .secondary)
                    if let seconds = model.duration.timeInterval, seconds < LockWindow.minimumMonitoringDuration {
                        Text("Very short blocks may finish late if iOS delays a background callback. Keep this app open for the most accurate short countdown.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.mode == .core {
                        Toggle("Block all YouTube websites too", isOn: $model.wholeYouTube)
                        Text("Shorts-only blocking is unavailable here. If you want YouTube fully blocked, also select its native app in Core.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("While active, blocks prevent deletion of all apps and manual time changes. You can download new apps. A scheduled block cannot be cancelled after commitment.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Review and commit") { dismissKeyboard(); confirm = true }
                        .disabled(model.authorization != .approved || model.committing || model.pending.count >= 8 || model.duration.timeInterval == nil)
                }
                if !model.pending.isEmpty {
                    Section("Committed blocks") {
                        ForEach(model.pending) { block in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(block.mode.title) · \(block.window.isActive(at: model.now) ? "Active" : "Scheduled")")
                                    .font(.headline)
                                Text("\(block.window.start.formatted(date: .abbreviated, time: .standard)) → \(block.window.end.formatted(date: .abbreviated, time: .standard))")
                                    .font(.footnote)
                                if block.window.isActive(at: model.now) {
                                    Text(block.window.end, style: .timer).monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Locked Blocks")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .sheet(isPresented: $chooseDuration) {
                NavigationStack {
                    VStack(spacing: 16) {
                        HStack(spacing: 0) {
                            durationWheel("Hours", selection: $model.duration.hours, values: 0...168)
                            durationWheel("Minutes", selection: $model.duration.minutes, values: 0...59)
                            durationWheel("Seconds", selection: $model.duration.seconds, values: 0...59)
                        }
                        Text(model.duration.summary).font(.headline).monospacedDigit()
                        if model.duration.timeInterval == nil {
                            Text("Choose between 1 second and 7 days.").foregroundStyle(.red)
                        }
                    }
                    .padding()
                    .navigationTitle("Block duration")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { chooseDuration = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .familyActivityPicker(isPresented: $chooseCore, selection: $model.core)
            .sheet(isPresented: $chooseExtra, onDismiss: model.saveProfiles) {
                NavigationStack {
                    FamilyActivityPicker(selection: $model.extra)
                        .navigationTitle("Extra apps and sites")
                        .toolbar { Button("Done") { chooseExtra = false } }
                }
            }
            .onChange(of: chooseCore) { _, showing in if !showing { model.saveProfiles() } }
            .onReceive(clock) { _ in model.tick() }
            .confirmationDialog("Commit \(model.duration.summary) \(model.mode.title) block?",
                                isPresented: $confirm, titleVisibility: .visible) {
                Button("Commit block") { model.commit() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Once committed, this app cannot cancel or shorten the block. Verify your selected apps before starting.")
            }
        }
    }

    private func durationWheel(_ title: String, selection: Binding<Int>, values: ClosedRange<Int>) -> some View {
        VStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityLabel("Duration \(title.lowercased())")
        }
        .frame(maxWidth: .infinity)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
