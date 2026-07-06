import SwiftUI
import AppKit

// MARK: - Pet Builder Tab
// Lets the user choose which animation clips play for each PetMode, with
// random rotation (3–8s dwell, hard cuts) so the pet feels alive.
struct PetBuilderTab: View {
    @ObservedObject var petState: PetState

    @State private var selectedMode: PetMode = .idle
    @State private var previewClipID: String? = nil  // temporarily pinned preview

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Mode picker (5 chips)
                modePicker

                Divider().background(Color.white.opacity(0.1))

                // Randomize toggle
                randomizeToggle

                Divider().background(Color.white.opacity(0.1))

                // Assigned clips for the selected mode (reorderable, deletable)
                assignedClipsSection

                Divider().background(Color.white.opacity(0.1))

                // Library: clips available to add (filtered by mode)
                librarySection
            }
            .padding(16)
        }
        .onAppear {
            petState.isSimulating = true
        }
        .onDisappear {
            petState.isSimulating = false
            petState.save()
            // Return to idle rotation
            petState.setMode(.idle)
        }
    }

    // MARK: - Mode Picker
    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pet State")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))

            HStack(spacing: 6) {
                ForEach(PetMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            selectedMode = mode
                            previewClipID = nil
                            // Live-preview: actually set the pet to this mode
                            petState.setMode(mode, substate: exampleSubstate(for: mode))
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: mode.sfSymbol)
                                .font(.system(size: 14))
                                .foregroundColor(selectedMode == mode
                                    ? Color(NSColor(hex: mode.accentColorHex) ?? .purple)
                                    : .white.opacity(0.5))
                            Text(mode.displayName)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(selectedMode == mode ? .white : .white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedMode == mode
                                      ? Color.white.opacity(0.12)
                                      : Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedMode == mode
                                        ? Color(NSColor(hex: mode.accentColorHex) ?? .purple
                                              ).opacity(0.5)
                                        : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Randomize Toggle
    private var randomizeToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Randomize clip order")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text("Shuffle through the assigned clips (3–8s each).")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Toggle("", isOn: $petState.randomize)
                .labelsHidden()
                .tint(.purple)
                .onChange(of: petState.randomize) { _, _ in petState.save() }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Assigned Clips
    private var assignedClipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Animations for \(selectedMode.displayName)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Button {
                    petState.assignments.reset(selectedMode)
                    petState.save()
                    // Re-trigger preview
                    petState.setMode(selectedMode, substate: exampleSubstate(for: selectedMode))
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            let assigned = petState.assignments.clips(for: selectedMode)
            
            if selectedMode == .busy {
                let grouped = Dictionary(grouping: assigned, by: { $0.busySubstate })
                let sortedSubstates = BusySubstate.allCases.filter { grouped.keys.contains($0) }
                let generalClips = grouped[nil] ?? []
                
                ForEach(sortedSubstates, id: \.self) { substate in
                    if let clips = grouped[substate], !clips.isEmpty {
                        Text(substate.displayName)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.top, 4)
                        ForEach(clips, id: \.id) { clip in
                            assignedRow(clip, isOnlyClip: assigned.count == 1)
                        }
                    }
                }
                
                if !generalClips.isEmpty {
                    Text("General")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 4)
                    ForEach(generalClips, id: \.id) { clip in
                        assignedRow(clip, isOnlyClip: assigned.count == 1)
                    }
                }
            } else {
                ForEach(assigned, id: \.id) { clip in
                    assignedRow(clip, isOnlyClip: assigned.count == 1)
                }
            }
        }
    }

    private func assignedRow(_ clip: AnimationClip, isOnlyClip: Bool) -> some View {
        HStack(spacing: 10) {
            // Live mini preview
            TimelineView(.animation) { context in
                let image = OffscreenPetRenderer.renderFrame(
                    clipID: clip.id,
                    config: petState.config,
                    time: context.date.timeIntervalSince1970
                )
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 36, height: 36)
            }
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(clip.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(clip.description)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer()

            // Preview button — pin this clip on the menu bar pet
            Button {
                previewClipID = clip.id
                petState.currentClipID = clip.id
                petState.animationTrigger = UUID()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.purple)
            }
            .buttonStyle(.plain)

            // Delete (disabled when it's the only clip — prevent deleting all)
            Button {
                guard !isOnlyClip else { return }
                petState.assignments.remove(clip.id, from: selectedMode)
                petState.save()
                petState.setMode(selectedMode, substate: exampleSubstate(for: selectedMode))
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(isOnlyClip ? .white.opacity(0.2) : .red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .disabled(isOnlyClip)
            .help(isOnlyClip ? "Each state needs at least one animation" : "Remove")
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Library (clips available to add)
    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Animation")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))

            let assignedIDs = Set(petState.assignments.ids(for: selectedMode))
            let available = AnimationLibrary.clips(for: selectedMode).filter { !assignedIDs.contains($0.id) }

            if available.isEmpty {
                Text("All animations for this state are already added. 🎉")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.vertical, 8)
            } else {
                if selectedMode == .busy {
                    let grouped = Dictionary(grouping: available, by: { $0.busySubstate })
                    let sortedSubstates = BusySubstate.allCases.filter { grouped.keys.contains($0) }
                    let generalClips = grouped[nil] ?? []
                    
                    ForEach(sortedSubstates, id: \.self) { substate in
                        if let clips = grouped[substate], !clips.isEmpty {
                            Text(substate.displayName)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.top, 4)
                            ForEach(clips, id: \.id) { clip in
                                libraryRow(clip)
                            }
                        }
                    }
                    if !generalClips.isEmpty {
                        Text("General")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.top, 4)
                        ForEach(generalClips, id: \.id) { clip in
                            libraryRow(clip)
                        }
                    }
                } else {
                    ForEach(available, id: \.id) { clip in
                        libraryRow(clip)
                    }
                }
            }
        }
    }

    private func libraryRow(_ clip: AnimationClip) -> some View {
        HStack(spacing: 10) {
            TimelineView(.animation) { context in
                let image = OffscreenPetRenderer.renderFrame(
                    clipID: clip.id,
                    config: petState.config,
                    time: context.date.timeIntervalSince1970
                )
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 36, height: 36)
            }
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(clip.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(clip.description)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                petState.assignments.add(clip.id, to: selectedMode)
                petState.save()
                petState.setMode(selectedMode, substate: exampleSubstate(for: selectedMode))
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers
    /// For `.busy`, use a sample substate so the user sees substate-specific clips.
    private func exampleSubstate(for mode: PetMode) -> BusySubstate? {
        mode == .busy ? .thinking : nil
    }
}
