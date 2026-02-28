import SwiftUI

/// Drill-down list showing all collapsed groups for a given signal type within a confidence section
struct CollapsedGroupListView: View {
    let categories: [PhotoCategory]
    let signalName: String
    @ObservedObject var viewModel: ScanViewModel

    var body: some View {
        List {
            ForEach(categories) { category in
                NavigationLink(destination: CategoryDetailView(
                    category: category,
                    viewModel: viewModel
                )) {
                    CategoryRow(category: category, status: viewModel.categoryStatuses[category.id])
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(categories.count) \(signalName) Groups")
        .navigationBarTitleDisplayMode(.inline)
    }
}
