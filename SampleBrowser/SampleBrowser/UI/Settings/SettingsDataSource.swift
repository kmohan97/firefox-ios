// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit

class SettingsDataSource: NSObject, UITableViewDataSource {
    var models: [SettingsCellViewModel] {
        return [
            SettingsCellViewModel(settingType: .contentBlocking,
                                  title: "Trigger content blocking"),
            SettingsCellViewModel(settingType: .findInPage,
                                  title: "Trigger find in page"),
            SettingsCellViewModel(settingType: .scrollingToTop,
                                  title: "Trigger scroll to top"),
            SettingsCellViewModel(settingType: .zoom,
                                  title: "Trigger zoom")
        ]
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return models.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: SettingsCell.identifier,
                                                       for: indexPath) as? SettingsCell
        else {
            return UITableViewCell()
        }

        cell.configureCell(viewModel: models[indexPath.row])
        return cell
    }
}
