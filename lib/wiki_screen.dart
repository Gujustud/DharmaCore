import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'drawer_behavior.dart';
import 'list_toolbar_widgets.dart';
import 'pocketbase_service.dart';
import 'ui_breakpoints.dart';
import 'wiki_edit_screen.dart';
import 'wiki_page_utils.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';

class WikiScreen extends StatefulWidget {
  const WikiScreen({super.key});

  @override
  State<WikiScreen> createState() => _WikiScreenState();
}

class _WikiScreenState extends State<WikiScreen> with AutoOpenDrawerMixin {
  final _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<RecordModel> _pages = [];
  bool _loading = true;
  String? _selectedId;
  String _query = '';
  /// Page ids whose children are shown in the left tree.
  final Set<String> _expandedIds = {};
  /// When true (wide layout only), hide the page tree so the reader is wider.
  bool _treeCollapsed = false;

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  bool get _canEdit => AuthService.instance.canEditWiki;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _ensureExpandedFor(String? pageId) {
    if (pageId == null) return;
    _expandedIds.addAll(wikiAncestorIds(_pages, pageId));
  }

  void _expandRootsWithChildren() {
    final children = wikiChildrenMap(_pages);
    for (final root in children[null] ?? const <RecordModel>[]) {
      if ((children[root.id] ?? const []).isNotEmpty) {
        _expandedIds.add(root.id);
      }
    }
  }

  Future<void> _load({String? keepId}) async {
    setState(() => _loading = true);
    try {
      final records = await PocketBaseService().pb.collection('wiki_pages').getFullList(
        sort: 'sort_order,title',
      );
      if (!mounted) return;
      final id = keepId ?? _selectedId;
      final still = records.any((p) => p.id == id);
      setState(() {
        _pages = List<RecordModel>.from(records);
        _selectedId = still ? id : (records.isEmpty ? null : records.first.id);
        _expandRootsWithChildren();
        _ensureExpandedFor(_selectedId);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading wiki: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  RecordModel? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final p in _pages) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _openEditor({RecordModel? page, String? parentId}) async {
    if (!_canEdit) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WikiEditScreen(
          page: page,
          defaultParentId: parentId,
          allPages: _pages,
        ),
      ),
    );
    if (changed == true) await _load(keepId: page?.id ?? _selectedId);
  }

  Future<void> _delete(RecordModel page) async {
    final kids = wikiChildrenMap(_pages)[page.id] ?? [];
    if (kids.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delete or move child pages first.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete page?'),
        content: Text('Delete “${wikiTitle(page)}”? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PocketBaseService().pb.collection('wiki_pages').delete(page.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildToolbar({
    required bool stacked,
    bool showHidePages = false,
  }) {
    final search = InventoryListSearchField(
      controller: _searchController,
      hintText: 'Search titles and page text',
      onChanged: (v) => setState(() {
        _query = v;
        if (v.trim().isNotEmpty) {
          for (final p in _pages) {
            if (wikiMatchesQuery(p, v)) {
              _expandedIds.addAll(wikiAncestorIds(_pages, p.id));
            }
          }
        }
      }),
    );
    final actions = <Widget>[
      if (showHidePages)
        IconButton(
          tooltip: 'Hide pages',
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _treeCollapsed = true),
          icon: const Icon(Icons.view_sidebar_outlined, size: 22),
        ),
      if (_canEdit) ...[
        InventoryListActionButton(
          label: 'New page',
          onPressed: () => _openEditor(parentId: _selectedId),
        ),
        InventoryListActionButton(
          label: 'Edit',
          icon: Icons.edit_outlined,
          onPressed:
              _selected == null ? null : () => _openEditor(page: _selected),
        ),
      ],
    ];

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 8, children: actions),
          ],
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: search),
        for (final action in actions) ...[
          const SizedBox(width: 12),
          action,
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selected;
    final width = MediaQuery.sizeOf(context).width;
    final isNarrow = width < 700;
    // Same master/detail breakpoint + flex as Purchases / Material.
    final usePanel = width >= kWorkspaceWideBreakpointPx;
    final panelOpen = _selectedId != null;

    final listColumn = workspaceContentFrame(
      Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: _buildToolbar(
              stacked: isNarrow || (usePanel && panelOpen),
              showHidePages: usePanel && panelOpen && !_treeCollapsed,
            ),
          ),
          if (AuthService.instance.isWikiReadonly)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Your account is wiki read-only.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _pages.isEmpty
                    ? Center(
                        child: Text(
                          _canEdit
                              ? 'No wiki pages yet.\nTap New page to add a section (Team, Tooling, Docs, …).'
                              : 'No wiki pages yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : _treePane(),
          ),
        ],
      ),
      maxWidth: usePanel && panelOpen
          ? kWorkspacePanelContentMaxWidth
          : kWorkspaceContentMaxWidth,
    );

    Widget body;
    if (usePanel && panelOpen) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_treeCollapsed) Expanded(flex: 3, child: listColumn),
          Expanded(
            flex: _treeCollapsed ? 1 : 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: _treeCollapsed
                    ? null
                    : Border(
                        left: BorderSide(color: scheme.outlineVariant),
                      ),
              ),
              child: _readerPane(
                selected,
                showPagesButton: _treeCollapsed,
              ),
            ),
          ),
        ],
      );
    } else if (!usePanel && panelOpen) {
      body = Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _selectedId = null),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Pages'),
            ),
          ),
          Expanded(child: _readerPane(selected)),
        ],
      );
    } else {
      body = listColumn;
    }

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Wiki'),
        leading: workspaceMenuLeading(context),
      ),
      body: body,
    );
  }

  Widget _treePane() {
    final visible = wikiVisibleIds(_pages, _query);
    final children = wikiChildrenMap(_pages);
    final roots = (children[null] ?? []).where((p) => visible.contains(p.id)).toList();

    if (roots.isEmpty) {
      return Center(
        child: Text(
          'No matching pages.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final root in roots) ..._treeTiles(root, children, visible, 0),
      ],
    );
  }

  List<Widget> _treeTiles(
    RecordModel page,
    Map<String?, List<RecordModel>> children,
    Set<String> visible,
    int depth,
  ) {
    final kids = (children[page.id] ?? []).where((c) => visible.contains(c.id)).toList();
    final selected = page.id == _selectedId;
    final hasKids = kids.isNotEmpty;
    final expanded = _expandedIds.contains(page.id) || _query.trim().isNotEmpty;
    final titleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: depth == 0 ? FontWeight.w600 : FontWeight.w400,
        );

    return [
      ListTile(
        selected: selected,
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.only(left: 4.0 + depth * 12.0, right: 4),
        minLeadingWidth: 28,
        leading: hasKids
            ? IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: expanded ? 'Collapse' : 'Expand',
                icon: Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                ),
                onPressed: () {
                  setState(() {
                    if (_expandedIds.contains(page.id)) {
                      _expandedIds.remove(page.id);
                    } else {
                      _expandedIds.add(page.id);
                    }
                  });
                },
              )
            : const SizedBox(width: 28),
        title: Text(
          wikiTitle(page),
          style: titleStyle,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => setState(() {
          _selectedId = page.id;
          _ensureExpandedFor(page.id);
        }),
        trailing: _canEdit
            ? PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 18,
                onSelected: (v) {
                  if (v == 'child') _openEditor(parentId: page.id);
                  if (v == 'edit') _openEditor(page: page);
                  if (v == 'delete') _delete(page);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'child', child: Text('Add child page')),
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              )
            : null,
      ),
      if (hasKids && expanded)
        for (final c in kids) ..._treeTiles(c, children, visible, depth + 1),
    ];
  }

  Widget _readerPane(
    RecordModel? page, {
    bool showPagesButton = false,
  }) {
    if (page == null) {
      return const Center(child: Text('Select a page.'));
    }
    final pb = PocketBaseService().pb;
    final attachments = wikiAttachmentNames(page);
    final editedBy = wikiUpdatedByLabel(page);
    final when = wikiUpdatedLabel(page);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showPagesButton) ...[
              IconButton(
                tooltip: 'Show pages',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => setState(() => _treeCollapsed = false),
                icon: const Icon(Icons.view_sidebar_outlined, size: 22),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                wikiTitle(page),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        wikiBodyWithTables(
          context,
          wikiBody(page),
          canEditTables: _canEdit,
        ),
        if (attachments.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('Attachments', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in attachments)
                ActionChip(
                  avatar: Icon(
                    name.toLowerCase().endsWith('.pdf')
                        ? Icons.picture_as_pdf
                        : Icons.image,
                    size: 18,
                  ),
                  label: Text(name),
                  onPressed: () async {
                    final url = pb.files.getUrl(page, name).toString();
                    final uri = Uri.tryParse(url);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
            ],
          ),
        ],
        if (editedBy.isNotEmpty || when.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            [
              if (editedBy.isNotEmpty) 'Last edit by $editedBy',
              if (when.isNotEmpty) when,
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}
