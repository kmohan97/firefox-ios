// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import TabDataStore
import Shared
import Storage

// TODO: [8188] Middlewares are currently handling actions globally. Need updates for multi-window. Forthcoming.
class TabManagerMiddleware {
    var selectedPanel: TabTrayPanelType = .tabs
    private let profile: Profile

    var normalTabsCountText: String {
        (defaultTabManager.normalTabs.count < 100) ? defaultTabManager.normalTabs.count.description : "\u{221E}"
    }

    init(profile: Profile = AppContainer.shared.resolve()) {
        self.profile = profile
    }

    lazy var tabsPanelProvider: Middleware<AppState> = { state, action in
        switch action {
        case TabTrayAction.tabTrayDidLoad(let panelType):
            let tabTrayModel = self.getTabTrayModel(for: panelType)
            store.dispatch(TabTrayAction.didLoadTabTray(tabTrayModel))

        case TabPanelAction.tabPanelDidLoad(let isPrivate):
            let tabState = self.getTabsDisplayModel(for: isPrivate, shouldScrollToTab: true)
            store.dispatch(TabPanelAction.didLoadTabPanel(tabState))

        case TabTrayAction.changePanel(let panelType):
            self.changePanel(panelType)

        case TabPanelAction.addNewTab(let urlRequest, let isPrivateMode):
            self.addNewTab(with: urlRequest, isPrivate: isPrivateMode)

        case TabPanelAction.moveTab(let originIndex, let destinationIndex):
            self.moveTab(state: state, from: originIndex, to: destinationIndex)

        case TabPanelAction.closeTab(let tabUUID):
            self.closeTabFromTabPanel(with: tabUUID)

        case TabPanelAction.undoClose:
            self.undoCloseTab(state: state)

        case TabPanelAction.closeAllTabs:
            self.closeAllTabs(state: state)

        case TabPanelAction.undoCloseAllTabs:
            self.defaultTabManager.undoCloseAllTabs()

        case TabPanelAction.selectTab(let tabUUID):
            self.selectTab(for: tabUUID)
            store.dispatch(TabTrayAction.dismissTabTray)

        case TabPanelAction.closeAllInactiveTabs:
            self.closeAllInactiveTabs(state: state)

        case TabPanelAction.undoCloseAllInactiveTabs:
            self.undoCloseAllInactiveTabs()

        case TabPanelAction.closeInactiveTabs(let tabUUID):

            self.closeInactiveTab(for: tabUUID, state: state)

        case TabPanelAction.undoCloseInactiveTab:
            self.undoCloseInactiveTab()

        case TabPanelAction.learnMorePrivateMode(let urlRequest):
            self.didTapLearnMoreAboutPrivate(with: urlRequest)

        case RemoteTabsPanelAction.openSelectedURL(let url):
            self.openSelectedURL(url: url)

        case TabPeekAction.didLoadTabPeek(let tabID):
            self.didLoadTabPeek(tabID: tabID)

        case TabPeekAction.addToBookmarks(let tabID):
            self.addToBookmarks(with: tabID)

        case TabPeekAction.sendToDevice(let tabID):
            self.sendToDevice(tabID: tabID)

        case TabPeekAction.copyURL(let tabID):
            self.copyURL(tabID: tabID)

        case TabPeekAction.closeTab(let tabID):
            self.tabPeekCloseTab(with: tabID)
            store.dispatch(TabPanelAction.showToast(.singleTab))
        default:
            break
        }
    }

    private func openSelectedURL(url: URL) {
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .open,
                                     object: .syncTab)
        let urlRequest = URLRequest(url: url)
        self.addNewTab(with: urlRequest, isPrivate: false)
        store.dispatch(TabTrayAction.dismissTabTray)
    }

    /// Gets initial state for TabTrayModel includes panelType, if is on Private mode,
    /// normalTabsCountText and if syncAccount is enabled
    /// 
    /// - Parameter panelType: The selected panelType
    /// - Returns: Initial state of TabTrayModel
    private func getTabTrayModel(for panelType: TabTrayPanelType) -> TabTrayModel {
        selectedPanel = panelType

        let isPrivate = panelType == .privateTabs
        return TabTrayModel(isPrivateMode: isPrivate,
                            selectedPanel: panelType,
                            normalTabsCount: normalTabsCountText,
                            hasSyncableAccount: false)
    }

    /// Gets initial model for TabDisplay from `TabManager`, including list of tabs and inactive tabs.
    /// - Parameter isPrivateMode: if Private mode is enabled or not
    /// - Returns:  initial model for `TabDisplayPanel`
    private func getTabsDisplayModel(for isPrivateMode: Bool,
                                     shouldScrollToTab: Bool) -> TabDisplayModel {
        let tabs = refreshTabs(for: isPrivateMode)
        let inactiveTabs = refreshInactiveTabs(for: isPrivateMode)
        let tabDisplayModel = TabDisplayModel(isPrivateMode: isPrivateMode,
                                              tabs: tabs,
                                              normalTabsCount: normalTabsCountText,
                                              inactiveTabs: inactiveTabs,
                                              isInactiveTabsExpanded: false,
                                              shouldScrollToTab: shouldScrollToTab)
        return tabDisplayModel
    }

    /// Gets the list of tabs from `TabManager` and builds the array of TabModel to use in TabDisplayView
    /// - Parameter isPrivateMode: is on Private mode or not
    /// - Returns: Array of TabModel used to configure collection view
    private func refreshTabs(for isPrivateMode: Bool) -> [TabModel] {
        var tabs = [TabModel]()
        let selectedTab = defaultTabManager.selectedTab
        let tabManagerTabs = isPrivateMode ? defaultTabManager.privateTabs : defaultTabManager.normalActiveTabs
        tabManagerTabs.forEach { tab in
            let tabModel = TabModel(tabUUID: tab.tabUUID,
                                    isSelected: tab == selectedTab,
                                    isPrivate: tab.isPrivate,
                                    isFxHomeTab: tab.isFxHomeTab,
                                    tabTitle: tab.displayTitle,
                                    url: tab.url,
                                    screenshot: tab.screenshot,
                                    hasHomeScreenshot: tab.hasHomeScreenshot)
            tabs.append(tabModel)
        }

        return tabs
    }

    /// Gets the list of inactive tabs from `TabManager` and builds the array of InactiveTabsModel
    /// to use in TabDisplayView
    ///
    /// - Parameter isPrivateMode: is on Private mode or not
    /// - Returns: Array of InactiveTabsModel used to configure collection view
    private func refreshInactiveTabs(for isPrivateMode: Bool = false) -> [InactiveTabsModel] {
        guard !isPrivateMode else { return [InactiveTabsModel]() }

        var inactiveTabs = [InactiveTabsModel]()
        for tab in defaultTabManager.getInactiveTabs() {
            let inactiveTab = InactiveTabsModel(tabUUID: tab.tabUUID,
                                                title: tab.displayTitle,
                                                url: tab.url,
                                                favIconURL: tab.faviconURL)
            inactiveTabs.append(inactiveTab)
        }
        return inactiveTabs
    }

    /// Creates a new tab in `TabManager` using optional `URLRequest`
    ///
    /// - Parameters:
    ///   - urlRequest: URL request to load
    ///   - isPrivate: if the tab should be created in private mode or not
    private func addNewTab(with urlRequest: URLRequest?, isPrivate: Bool) {
        // TODO: Legacy class has a guard to cancel adding new tab if dragging was enabled,
        // check if change is still needed
        let tab = defaultTabManager.addTab(urlRequest, isPrivate: isPrivate)
        defaultTabManager.selectTab(tab)

        let model = getTabsDisplayModel(for: isPrivate, shouldScrollToTab: true)
        store.dispatch(TabPanelAction.refreshTab(model))
        store.dispatch(TabTrayAction.dismissTabTray)
    }

    /// Move tab on `TabManager` array to support drag and drop
    ///
    /// - Parameters:
    ///   - originIndex: from original position
    ///   - destinationIndex: to destination position
    private func moveTab(state: AppState, from originIndex: Int, to destinationIndex: Int) {
        // TODO: [8188] Tab actions will be updated soon to include UUID in related context object. Forthcoming.
        guard let tabsState = state.screenState(TabsPanelState.self, for: .tabsPanel, window: nil) else { return }

        TelemetryWrapper.recordEvent(category: .action,
                                     method: .drop,
                                     object: .tab,
                                     value: .tabTray)
        defaultTabManager.moveTab(isPrivate: false, fromIndex: originIndex, toIndex: destinationIndex)

        let model = getTabsDisplayModel(for: tabsState.isPrivateMode, shouldScrollToTab: false)
        store.dispatch(TabPanelAction.refreshTab(model))
    }

    /// Async close single tab. If is the last tab the Tab Tray is dismissed and undo
    /// option is presented in Homepage
    ///
    /// - Parameters:
    ///   - tabUUID: UUID of the tab to be closed/removed
    /// - Returns: If is the last tab to be closed used to trigger dismissTabTray action
    private func closeTab(with tabUUID: String) async -> Bool {
        let isLastTab = defaultTabManager.normalTabs.count == 1
        await defaultTabManager.removeTab(tabUUID)
        return isLastTab
    }

    /// Close tab and trigger refresh
    /// - Parameter tabUUID: UUID of the tab to be closed/removed
    private func closeTabFromTabPanel(with tabUUID: String) {
        Task {
            let shouldDismiss = await self.closeTab(with: tabUUID)
            await self.triggerRefresh(shouldScrollToTab: false)
            if shouldDismiss {
                store.dispatch(TabTrayAction.dismissTabTray)
                store.dispatch(GeneralBrowserAction.showToast(.singleTab))
            } else {
                store.dispatch(TabPanelAction.showToast(.singleTab))
            }
        }
    }

    /// Trigger refreshTabs action after a change in `TabManager`
    @MainActor
    private func triggerRefresh(shouldScrollToTab: Bool) {
        let isPrivate = defaultTabManager.selectedTab?.isPrivate ?? false
        let model = getTabsDisplayModel(for: isPrivate, shouldScrollToTab: shouldScrollToTab)
        store.dispatch(TabPanelAction.refreshTab(model))
    }

    /// Handles undoing the close tab action, gets the backup tab from `TabManager`
    private func undoCloseTab(state: AppState) {
        // TODO: [8188] Tab actions will be updated soon to include UUID in related context object. Forthcoming.
        guard let tabsState = state.screenState(TabsPanelState.self, for: .tabsPanel, window: nil),
              let backupTab = defaultTabManager.backupCloseTab
        else { return }

        defaultTabManager.undoCloseTab(tab: backupTab.tab, position: backupTab.restorePosition)
        let model = getTabsDisplayModel(for: tabsState.isPrivateMode, shouldScrollToTab: false)
        store.dispatch(TabPanelAction.refreshTab(model))
    }

    private func closeAllTabs(state: AppState) {
        // TODO: [8188] Tab actions will be updated soon to include UUID in related context object. Forthcoming.
        guard let tabsState = state.screenState(TabsPanelState.self, for: .tabsPanel, window: nil) else { return }
        Task {
            let count = self.defaultTabManager.tabs.count
            await defaultTabManager.removeAllTabs(isPrivateMode: tabsState.isPrivateMode)

            ensureMainThread { [self] in
                let model = getTabsDisplayModel(for: tabsState.isPrivateMode, shouldScrollToTab: false)
                store.dispatch(TabPanelAction.refreshTab(model))
                store.dispatch(TabTrayAction.dismissTabTray)
                store.dispatch(GeneralBrowserAction.showToast(.allTabs(count: count)))
            }
        }
    }

    /// Handles undo close all tabs. Adds back all tabs depending on mode
    ///
    /// - Parameter isPrivateMode: if private mode is active or not
    private func undoCloseAllTabs(isPrivateMode: Bool) {
        // TODO: FXIOS-7978 Handle Undo close all tabs
        defaultTabManager.undoCloseAllTabs()
    }

    // MARK: - Inactive tabs helper

    /// Close all inactive tabs removing them from the tabs array on `TabManager`.
    /// Makes a backup of tabs to be deleted in case undo option is selected
    private func closeAllInactiveTabs(state: AppState) {
        // TODO: [8188] Tab actions will be updated soon to include UUID in related context object. Forthcoming.
        guard let tabsState = state.screenState(TabsPanelState.self, for: .tabsPanel, window: nil) else { return }
        Task {
            await defaultTabManager.removeAllInactiveTabs()
            store.dispatch(TabPanelAction.refreshInactiveTabs([InactiveTabsModel]()))
            store.dispatch(TabPanelAction.showToast(.allInactiveTabs(count: tabsState.inactiveTabs.count)))
        }
    }

    /// Handles undo close all inactive tabs. Adding back the backup tabs saved previously
    private func undoCloseAllInactiveTabs() {
        ensureMainThread {
            self.defaultTabManager.undoCloseInactiveTabs()
            let inactiveTabs = self.refreshInactiveTabs()
            store.dispatch(TabPanelAction.refreshInactiveTabs(inactiveTabs))
        }
    }

    private func closeInactiveTab(for tabUUID: String, state: AppState) {
        // TODO: [8188] Tab actions will be updated soon to include UUID in related context object. Forthcoming.
        guard let tabsState = state.screenState(TabsPanelState.self, for: .tabsPanel, window: nil) else { return }
        Task {
            if let tabToClose = defaultTabManager.getTabForUUID(uuid: tabUUID) {
                let index = tabsState.inactiveTabs.firstIndex { $0.tabUUID == tabUUID }
                defaultTabManager.backupCloseTab = BackupCloseTab(tab: tabToClose, restorePosition: index)
            }
            await defaultTabManager.removeTab(tabUUID)

            let inactiveTabs = self.refreshInactiveTabs()
            store.dispatch(TabPanelAction.refreshInactiveTabs(inactiveTabs))
            store.dispatch(TabPanelAction.showToast(.singleInactiveTabs))
        }
    }

    private func undoCloseInactiveTab() {
        guard let backupTab = defaultTabManager.backupCloseTab else { return }

        defaultTabManager.undoCloseTab(tab: backupTab.tab, position: backupTab.restorePosition)
        let inactiveTabs = self.refreshInactiveTabs()
        store.dispatch(TabPanelAction.refreshInactiveTabs(inactiveTabs))
    }

    private func didTapLearnMoreAboutPrivate(with urlRequest: URLRequest) {
        addNewTab(with: urlRequest, isPrivate: true)
        let model = getTabsDisplayModel(for: true, shouldScrollToTab: false)
        store.dispatch(TabPanelAction.refreshTab(model))
        store.dispatch(TabTrayAction.dismissTabTray)
    }

    private func selectTab(for tabUUID: String) {
        guard let tab = defaultTabManager.getTabForUUID(uuid: tabUUID) else { return }

        defaultTabManager.selectTab(tab)
    }

    private var defaultTabManager: TabManager {
        // TODO: [FXIOS-8071] Temporary. WIP for Redux + iPad Multi-window.
        let windowManager: WindowManager = AppContainer.shared.resolve()
        return windowManager.tabManager(for: windowManager.activeWindow)
    }

    // MARK: - Tab Peek

    private func didLoadTabPeek(tabID: String) {
        let tab = defaultTabManager.getTabForUUID(uuid: tabID)
        profile.places.isBookmarked(url: tab?.url?.absoluteString ?? "") >>== { isBookmarked in
            var canBeSaved = true
            if isBookmarked || (tab?.urlIsTooLong ?? false) || (tab?.isFxHomeTab ?? false) {
                canBeSaved = false
            }
            let browserProfile = self.profile as? BrowserProfile
            browserProfile?.tabs.getClientGUIDs { (result, error) in
                let model = TabPeekModel(canTabBeSaved: canBeSaved,
                                         isSyncEnabled: !(result?.isEmpty ?? true),
                                         screenshot: tab?.screenshot ?? UIImage(),
                                         accessiblityLabel: tab?.webView?.accessibilityLabel ?? "")
                store.dispatch(TabPeekAction.loadTabPeek(tabPeekModel: model))
            }
        }
    }

    private func addToBookmarks(with tabID: String) {
        guard let tab = defaultTabManager.getTabForUUID(uuid: tabID),
              let url = tab.url?.absoluteString, !url.isEmpty
        else { return }

        var title = (tab.tabState.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title = url
        }
        let shareItem = ShareItem(url: url, title: title)
        // Add new mobile bookmark at the top of the list
        profile.places.createBookmark(parentGUID: BookmarkRoots.MobileFolderGUID,
                                      url: shareItem.url,
                                      title: shareItem.title,
                                      position: 0)

        var userData = [QuickActionInfos.tabURLKey: shareItem.url]
        if let title = shareItem.title {
            userData[QuickActionInfos.tabTitleKey] = title
        }
        QuickActionsImplementation().addDynamicApplicationShortcutItemOfType(.openLastBookmark,
                                                                             withUserData: userData,
                                                                             toApplication: .shared)

        store.dispatch(TabPanelAction.showToast(.addBookmark))

        TelemetryWrapper.recordEvent(category: .action,
                                     method: .add,
                                     object: .bookmark,
                                     value: .tabTray)
    }

    private func sendToDevice(tabID: String) {
        guard let tabToShare = defaultTabManager.getTabForUUID(uuid: tabID),
              let url = tabToShare.url
        else { return }

        store.dispatch(TabPanelAction.showShareSheet(url))
    }

    private func copyURL(tabID: String) {
        UIPasteboard.general.url = defaultTabManager.selectedTab?.canonicalURL
        store.dispatch(TabPanelAction.showToast(.copyURL))
    }

    private func tabPeekCloseTab(with tabID: String) {
        closeTabFromTabPanel(with: tabID)
    }

    private func changePanel(_ panel: TabTrayPanelType) {
        self.trackPanelChange(panel)
        let isPrivate = panel == TabTrayPanelType.privateTabs
        let tabState = self.getTabsDisplayModel(for: isPrivate, shouldScrollToTab: false)
        if panel != .syncedTabs {
            store.dispatch(TabPanelAction.didLoadTabPanel(tabState))
        }
    }

    private func trackPanelChange(_ panel: TabTrayPanelType) {
        switch panel {
        case .tabs:
            TelemetryWrapper.recordEvent(
                category: .action,
                method: .tap,
                object: .privateBrowsingButton,
                extras: ["is-private": false.description])
        case .privateTabs:
            TelemetryWrapper.recordEvent(
                category: .action,
                method: .tap,
                object: .privateBrowsingButton,
                extras: ["is-private": true.description])
        case .syncedTabs:
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .libraryPanel,
                                         value: .syncPanel,
                                         extras: nil)
        }
    }
}
