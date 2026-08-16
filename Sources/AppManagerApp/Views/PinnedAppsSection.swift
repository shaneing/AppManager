import SwiftUI
import AppManagerCore

public struct PinnedAppsSection: View {
    @ObservedObject var viewModel: MenuBarViewModel

    public var body: some View {
        if !viewModel.pinnedApps.isEmpty {
            LazyVStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("PINNED APPS (\(viewModel.pinnedApps.count))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)

                LazyVStack(spacing: 2) {
                    ForEach(viewModel.pinnedApps) { app in
                        AppRowView(app: app, viewModel: viewModel)
                    }
                }

                Divider()
                    .padding(.vertical, 4)
            }
        }
    }
}
