import AppKit
import PanelFeature
import SettingsFeature

extension PanelContentView {
    func setup() {
        sidebarTable.onEscape = { [weak self] in self?.handleEscape() }
        sidebarTable.onFind = { [weak self] in self?.focusSearchField() }
        sidebarTable.onReturn = { [weak self] in self?.openSavedLocation(nil) }
        fileTable.onEscape = { [weak self] in self?.handleEscape() }
        fileTable.onFind = { [weak self] in self?.focusSearchField() }
        fileTable.onReturn = { [weak self] in self?.openSelection() }
        fileTable.onSpace = { [weak self] in self?.toggleQuickLookFromKeyboard() }
        fileTable.onDelete = { [weak self] in self?.trashSelection() }
        fileTable.onContextRow = { [weak self] row in
            guard let self else {
                return
            }
            model.select(index: row)
            contextItemURL = row.flatMap { index in
                model.items.indices.contains(index) ? model.items[index].url : nil
            }
        }
        sidebarTable.onContextRow = { [weak self] row in
            guard let self else {
                return
            }
            contextSidebarItem = row.flatMap { index in
                let items = sidebarDataSource.visibleItems
                return items.indices.contains(index) ? items[index] : nil
            }
        }
        focusView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(focusView)

        let splitView = NSSplitView()
        self.splitView = splitView
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitView)

        let sidebarScroll = NSScrollView()
        sidebarScrollView = sidebarScroll
        sidebarScroll.borderType = .noBorder
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.drawsBackground = false
        sidebarScroll.documentView = sidebarTable
        configureSidebarTable()

        let sidebarSurface = NSVisualEffectView()
        sidebarSurface.material = .sidebar
        sidebarSurface.blendingMode = .withinWindow
        sidebarSurface.state = .followsWindowActiveState
        sidebarTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        sidebarTitleLabel.textColor = .secondaryLabelColor
        sidebarTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addFavoriteButton.title = "Add Favorite…"
        addFavoriteButton.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: nil
        )
        addFavoriteButton.imagePosition = .imageLeading
        addFavoriteButton.bezelStyle = .rounded
        addFavoriteButton.controlSize = .small
        addFavoriteButton.target = self
        addFavoriteButton.action = #selector(addSavedLocation(_:))
        addFavoriteButton.setAccessibilityIdentifier("pathshelf.favorite.add")
        addFavoriteButton.setAccessibilityLabel("Add Favorite")
        addFavoriteButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarSurface.addSubview(sidebarTitleLabel)
        sidebarSurface.addSubview(sidebarScroll)
        sidebarSurface.addSubview(addFavoriteButton)
        NSLayoutConstraint.activate([
            sidebarTitleLabel.leadingAnchor.constraint(equalTo: sidebarSurface.leadingAnchor, constant: 12),
            sidebarTitleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: sidebarSurface.trailingAnchor,
                constant: -12
            ),
            sidebarTitleLabel.topAnchor.constraint(equalTo: sidebarSurface.topAnchor, constant: 10),
            sidebarScroll.leadingAnchor.constraint(equalTo: sidebarSurface.leadingAnchor),
            sidebarScroll.trailingAnchor.constraint(equalTo: sidebarSurface.trailingAnchor),
            sidebarScroll.topAnchor.constraint(equalTo: sidebarTitleLabel.bottomAnchor, constant: 6),
            sidebarScroll.bottomAnchor.constraint(equalTo: addFavoriteButton.topAnchor, constant: -6),
            addFavoriteButton.leadingAnchor.constraint(
                equalTo: sidebarSurface.leadingAnchor,
                constant: 12
            ),
            addFavoriteButton.trailingAnchor.constraint(
                equalTo: sidebarSurface.trailingAnchor,
                constant: -12
            ),
            addFavoriteButton.bottomAnchor.constraint(
                equalTo: sidebarSurface.bottomAnchor,
                constant: -8
            ),
            addFavoriteButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        splitView.addArrangedSubview(sidebarSurface)
        let preferredSidebarWidth = sidebarSurface.widthAnchor.constraint(equalToConstant: 210)
        preferredSidebarWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            sidebarSurface.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            sidebarSurface.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            preferredSidebarWidth
        ])

        let fileScroll = NSScrollView()
        fileScrollView = fileScroll
        fileScroll.borderType = .noBorder
        fileScroll.hasVerticalScroller = true
        fileScroll.drawsBackground = true
        fileScroll.backgroundColor = .controlBackgroundColor
        fileScroll.documentView = fileTable
        configureFileTable()
        let fileSurface = SemanticSurfaceView(kind: .fileList)
        let searchBar = SemanticSurfaceView(kind: .footer)
        searchBarView = searchBar
        searchField.placeholderString = "Filter current folder"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.target = self
        searchField.action = #selector(filterCurrentDirectory(_:))
        searchField.toolTip = "Filter filenames in the current folder (Command-F)"
        searchField.setAccessibilityLabel("Filter current folder")
        searchField.setAccessibilityIdentifier("pathshelf.filter.current-folder")
        searchField.onEscape = { [weak self] in self?.handleEscape() }
        let searchSeparator = NSBox()
        searchSeparator.boxType = .separator
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchSeparator.translatesAutoresizingMaskIntoConstraints = false
        searchBar.addSubview(searchField)
        searchBar.addSubview(searchSeparator)
        fileScroll.translatesAutoresizingMaskIntoConstraints = false
        browserStateView.translatesAutoresizingMaskIntoConstraints = false
        fileSurface.addSubview(searchBar)
        fileSurface.addSubview(fileScroll)
        fileSurface.addSubview(browserStateView)
        let preferredSearchWidth = searchField.widthAnchor.constraint(equalToConstant: 320)
        preferredSearchWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: fileSurface.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: fileSurface.trailingAnchor),
            searchBar.topAnchor.constraint(equalTo: fileSurface.topAnchor),
            searchBar.heightAnchor.constraint(equalToConstant: VisualMetrics.searchBarHeight),
            searchField.leadingAnchor.constraint(
                equalTo: searchBar.leadingAnchor,
                constant: VisualMetrics.panelHorizontalInset
            ),
            searchField.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            searchField.trailingAnchor.constraint(
                lessThanOrEqualTo: searchBar.trailingAnchor,
                constant: -VisualMetrics.panelHorizontalInset
            ),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            preferredSearchWidth,
            searchSeparator.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor),
            searchSeparator.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor),
            searchSeparator.bottomAnchor.constraint(equalTo: searchBar.bottomAnchor),
            fileScroll.leadingAnchor.constraint(equalTo: fileSurface.leadingAnchor),
            fileScroll.trailingAnchor.constraint(equalTo: fileSurface.trailingAnchor),
            fileScroll.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            fileScroll.bottomAnchor.constraint(equalTo: fileSurface.bottomAnchor),
            browserStateView.leadingAnchor.constraint(equalTo: fileSurface.leadingAnchor),
            browserStateView.trailingAnchor.constraint(equalTo: fileSurface.trailingAnchor),
            browserStateView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            browserStateView.bottomAnchor.constraint(equalTo: fileSurface.bottomAnchor)
        ])
        splitView.addArrangedSubview(fileSurface)
        fileSurface.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        pathControl.pathStyle = .standard
        pathControl.isEditable = false
        pathControl.target = self
        pathControl.action = #selector(openPathComponent(_:))
        pathControl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathControl.pathContextMenuProvider = { [weak self] url in
            self?.makePathComponentMenu(for: url)
        }

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.alignment = .right
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        pathControl.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        let bottomBar = SemanticSurfaceView(kind: .footer)
        bottomBarView = bottomBar
        bottomBar.addSubview(pathControl)
        bottomBar.addSubview(statusLabel)
        let bottomBarSeparator = NSBox()
        bottomBarSeparator.boxType = .separator
        bottomBarSeparator.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(bottomBarSeparator)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBar)

        NSLayoutConstraint.activate([
            focusView.leadingAnchor.constraint(equalTo: leadingAnchor),
            focusView.trailingAnchor.constraint(equalTo: trailingAnchor),
            focusView.topAnchor.constraint(equalTo: topAnchor),
            focusView.bottomAnchor.constraint(equalTo: bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: VisualMetrics.pathBarHeight),
            bottomBarSeparator.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            bottomBarSeparator.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            bottomBarSeparator.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            pathControl.leadingAnchor.constraint(
                equalTo: bottomBar.leadingAnchor,
                constant: VisualMetrics.panelHorizontalInset
            ),
            pathControl.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            pathControl.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -10),
            statusLabel.trailingAnchor.constraint(
                equalTo: bottomBar.trailingAnchor,
                constant: -VisualMetrics.panelHorizontalInset
            ),
            statusLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor)
        ])
        refreshTables()
    }

    var layoutDiagnostics: String {
        layoutSubtreeIfNeeded()
        let firstCellExists = fileTable.numberOfRows > 0
            && fileTable.view(atColumn: 0, row: 0, makeIfNecessary: true) != nil
        return [
            "content=\(frameDescription(frame))",
            "pathBar=\(frameDescription(bottomBarView?.frame ?? .zero))",
            "searchBar=\(frameDescription(searchBarView?.frame ?? .zero))",
            "searchField=\(frameDescription(searchField.frame))",
            "split=\(frameDescription(splitView?.frame ?? .zero))",
            "sidebarScroll=\(frameDescription(sidebarScrollView?.frame ?? .zero))",
            "fileScroll=\(frameDescription(fileScrollView?.frame ?? .zero))",
            "fileTable=\(frameDescription(fileTable.frame))",
            "rows=\(fileTable.numberOfRows)",
            "firstCell=\(firstCellExists)"
        ].joined(separator: " ")
    }

    var isLayoutReady: Bool {
        layoutSubtreeIfNeeded()
        guard let bottomBarView, let searchBarView, let fileScrollView, let splitView else {
            return false
        }
        return bounds.intersects(bottomBarView.frame)
            && searchBarView.frame.height >= 24
            && searchField.frame.width >= 240
            && fileScrollView.frame.width >= 320
            && fileScrollView.frame.height >= 320
            && splitView.frame.height >= 320
            && (fileTable.numberOfRows == 0
                || fileTable.view(atColumn: 0, row: 0, makeIfNecessary: true) != nil)
    }

    @objc func filterCurrentDirectory(_ sender: NSSearchField) {
        applyFilterQuery(sender.stringValue)
    }

    func applyFilterQuery(_ query: String) {
        searchField.stringValue = query
        model.setFilterQuery(query)
        refreshTablesAndThumbnails()
    }

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
    }

    func handleEscape() {
        guard model.filterQuery.isEmpty == false else {
            onEscape()
            return
        }
        applyFilterQuery("")
    }

    private func frameDescription(_ frame: CGRect) -> String {
        String(
            format: "%.0f,%.0f,%.0f,%.0f",
            frame.origin.x,
            frame.origin.y,
            frame.width,
            frame.height
        )
    }

    @objc func openPathComponent(_ sender: NSPathControl) {
        guard let url = sender.clickedPathItem?.url else {
            return
        }
        Task { [weak self] in
            await self?.model.navigateToPathBarLocation(url)
            self?.refreshTablesAndThumbnails()
        }
    }
    private func configureSidebarTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("saved"))
        column.title = "Favorites"
        sidebarTable.addTableColumn(column)
        sidebarTable.dataSource = sidebarDataSource
        sidebarTable.delegate = sidebarDataSource
        sidebarDataSource.attach(to: sidebarTable)
        sidebarDataSource.onDrop = { [weak self] payload, row, operation in
            self?.handleFavoriteDrop(payload: payload, row: row, operation: operation) ?? false
        }
        sidebarTable.headerView = nil
        sidebarTable.rowHeight = 28
        sidebarTable.intercellSpacing = .zero
        sidebarTable.backgroundColor = .clear
        sidebarTable.style = .sourceList
        sidebarTable.target = self
        sidebarTable.doubleAction = #selector(openSavedLocation(_:))
        sidebarTable.contextMenuProvider = { [weak self] row in
            guard let self else {
                return nil
            }
            let items = sidebarDataSource.visibleItems
            let item = row.flatMap { items.indices.contains($0) ? items[$0] : nil }
            return makeFavoriteContextMenu(for: item)
        }
        sidebarTable.registerForDraggedTypes([.favoriteSidebarItem])
        sidebarTable.setDraggingSourceOperationMask(.move, forLocal: true)
    }

    private func configureFileTable() {
        fileTable.usesAlternatingRowBackgroundColors = false
        fileTable.rowHeight = 28
        fileTable.intercellSpacing = NSSize(width: 0, height: 1)
        fileTable.dataSource = fileDataSource
        fileTable.delegate = fileDataSource
        fileDataSource.onSortColumn = { [weak self] identifier in
            self?.sortByColumn(identifier)
        }
        fileDataSource.onDrop = { [weak self] urls, move in
            self?.copyOrMoveDroppedURLs(urls, move: move)
        }
        fileDataSource.explicitMoveSignal = {
            NSApp.currentEvent?.modifierFlags.contains(.control) == true
        }
        fileTable.target = self
        fileTable.doubleAction = #selector(openClickedFile(_:))
        fileTable.menu = makeActionsMenu()
        fileTable.toolTip = "Drop copies; hold Control to move."
        fileTable.registerForDraggedTypes([.fileURL])
        fileTable.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        applyVisibleColumns()
    }

    private func applyVisibleColumns() {
        fileTable.tableColumns.forEach(fileTable.removeTableColumn)
        fileTable.addTableColumn(makeColumn(identifier: "name", title: "Name", width: 320))

        let settings = (try? settingsStore.load()) ?? .default
        let columnDefinitions: [(FileDetailColumn, String, String, CGFloat)] = [
            (.modified, "metadata", "Modified", 170),
            (.kind, "kind", "Kind", 110),
            (.size, "size", "Size", 100),
            (.created, "created", "Created", 170),
            (.availability, "availability", "Availability", 130)
        ]
        for (preference, identifier, title, width) in columnDefinitions
        where settings.visibleDetailColumns.contains(preference) {
            fileTable.addTableColumn(makeColumn(identifier: identifier, title: title, width: width))
        }
        updateSortIndicator()
    }

    private func makeColumn(identifier: String, title: String, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = identifier == "name" ? 180 : 80
        return column
    }

    private func sortByColumn(_ identifier: String) {
        let nextOrder: FileSortOrder
        switch identifier {
        case "name":
            nextOrder = model.sortOrder == .nameAscending ? .nameDescending : .nameAscending
        case "metadata":
            nextOrder = model.sortOrder == .modifiedNewest ? .modifiedOldest : .modifiedNewest
        case "kind":
            nextOrder = .kindThenName
        case "size":
            nextOrder = model.sortOrder == .sizeLargest ? .sizeSmallest : .sizeLargest
        case "created":
            nextOrder = model.sortOrder == .createdNewest ? .createdOldest : .createdNewest
        case "availability":
            nextOrder = .availabilityThenName
        default:
            return
        }
        model.setSortOrder(nextOrder)
        refreshTables()
        updateSortIndicator()
    }

    private func updateSortIndicator() {
        for column in fileTable.tableColumns {
            fileTable.setIndicatorImage(nil, in: column)
        }
        let (identifier, ascending): (String, Bool)
        switch model.sortOrder {
        case .nameAscending:
            (identifier, ascending) = ("name", true)
        case .nameDescending:
            (identifier, ascending) = ("name", false)
        case .kindThenName:
            (identifier, ascending) = ("kind", true)
        case .modifiedNewest:
            (identifier, ascending) = ("metadata", false)
        case .modifiedOldest:
            (identifier, ascending) = ("metadata", true)
        case .sizeLargest:
            (identifier, ascending) = ("size", false)
        case .sizeSmallest:
            (identifier, ascending) = ("size", true)
        case .createdNewest:
            (identifier, ascending) = ("created", false)
        case .createdOldest:
            (identifier, ascending) = ("created", true)
        case .availabilityThenName:
            (identifier, ascending) = ("availability", true)
        }
        guard let column = fileTable.tableColumn(
            withIdentifier: NSUserInterfaceItemIdentifier(identifier)
        ) else {
            return
        }
        fileTable.highlightedTableColumn = column
        fileTable.setIndicatorImage(
            NSImage(
                systemSymbolName: ascending ? "chevron.up" : "chevron.down",
                accessibilityDescription: ascending ? "Ascending" : "Descending"
            ),
            in: column
        )
    }
}
