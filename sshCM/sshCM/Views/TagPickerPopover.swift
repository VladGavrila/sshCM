import SwiftUI

struct TagPickerPopover: View {
    @Binding var selection: HostTag?
    var onPick: ((HostTag?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(TagsStore.self) private var tagsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(tagsStore.tagOrder) { tag in
                    Button {
                        choose(tag)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 22, height: 22)
                            if selection == tag {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(tagsStore.displayName(for: tag))
                }
            }

            Divider()

            Button {
                choose(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "nosign")
                    Text("No Tag")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    private func choose(_ tag: HostTag?) {
        selection = tag
        onPick?(tag)
        dismiss()
    }
}
