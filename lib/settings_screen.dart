import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'pocketbase_service.dart';
import 'category_management_screen.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';
import 'tool_import_config_screen.dart'; // NEW
import 'quote_management_settings_screen.dart';
import 'email_ingest_settings_screen.dart';
import 'app_theme.dart';
import 'theme_controller.dart';
import 'drawer_behavior.dart';
import 'drawer_data_cache.dart';
import 'idle_logout_listener.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with AutoOpenDrawerMixin {
  bool _isLoading = true;
  bool _showAllInventoryInMenu = true;
  bool _showToolDetailsInList = true;
  bool _useCategoryButtons = false;
  bool _enableToolImport = false; // NEW
  bool _darkMode = false;
  AppSkin _skin = AppSkin.graphite;
  bool _keepDrawerOpen = DrawerDataCache.keepDrawerOpen;
  String? _settingsId;
  String? _shopSettingsId;
  final _autoLogoutMinutes = TextEditingController();
  bool _savingAutoLogout = false;

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _darkMode = ThemeController.instance.themeMode.value == ThemeMode.dark;
    _skin = ThemeController.instance.skin.value;
  }

  @override
  void dispose() {
    _autoLogoutMinutes.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final pbService = PocketBaseService();
      final results = await Future.wait([
        pbService.getAppSettings(),
        pbService.getShopSettings(),
      ]);
      final settings = results[0];
      final shop = results[1];
      final logoutRaw = (shop.data['auto_logout_minutes'] as num?)?.toInt() ?? 0;
      setState(() {
        _settingsId = settings.id;
        _shopSettingsId = shop.id;
        _showAllInventoryInMenu = settings.data['show_all_inventory_in_menu'] ?? true;
        _showToolDetailsInList = settings.data['show_tool_details_in_list'] ?? true;
        _useCategoryButtons = settings.data['use_category_buttons'] ?? false;
        _enableToolImport = settings.data['enable_tool_import'] ?? false; // NEW
        _keepDrawerOpen = DrawerDataCache.readKeepDrawerOpen(settings);
        _autoLogoutMinutes.text = logoutRaw < 0 ? '0' : '$logoutRaw';
        _isLoading = false;
      });

      // Keep in-memory drawer cache in sync so new behavior applies immediately
      DrawerDataCache.keepDrawerOpen = _keepDrawerOpen;
      DrawerDataCache.notifyKeepDrawerOpenListeners();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateShowAllInventory(bool value) async {
    if (_settingsId == null) return;

    try {
      final pbService = PocketBaseService();
      await pbService.updateAppSettings(
        settingsId: _settingsId!,
        showAllInventoryInMenu: value,
        showToolDetailsInList: _showToolDetailsInList,
        useCategoryButtons: _useCategoryButtons,
        enableToolImport: _enableToolImport,
        keepDrawerOpen: _keepDrawerOpen,
      );

      setState(() {
        _showAllInventoryInMenu = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value 
              ? '"All Inventory" will appear in menu' 
              : '"All Inventory" hidden from menu'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating setting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateShowToolDetails(bool value) async {
    if (_settingsId == null) return;

    try {
      final pbService = PocketBaseService();
      await pbService.updateAppSettings(
        settingsId: _settingsId!,
        showAllInventoryInMenu: _showAllInventoryInMenu,
        showToolDetailsInList: value,
        useCategoryButtons: _useCategoryButtons,
        enableToolImport: _enableToolImport,
        keepDrawerOpen: _keepDrawerOpen,
      );

      setState(() {
        _showToolDetailsInList = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value 
              ? 'Tool details will show in inventory lists' 
              : 'Tool details hidden from inventory lists'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating setting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateUseCategoryButtons(bool value) async {
    if (_settingsId == null) return;

    try {
      final pbService = PocketBaseService();
      await pbService.updateAppSettings(
        settingsId: _settingsId!,
        showAllInventoryInMenu: _showAllInventoryInMenu,
        showToolDetailsInList: _showToolDetailsInList,
        useCategoryButtons: value,
        enableToolImport: _enableToolImport,
        keepDrawerOpen: _keepDrawerOpen,
      );

      setState(() {
        _useCategoryButtons = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value 
              ? 'Category selection will show as buttons' 
              : 'Category selection will show as dropdown'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating setting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // NEW: Update tool import setting
  Future<void> _updateEnableToolImport(bool value) async {
    if (_settingsId == null) return;

    try {
      final pbService = PocketBaseService();
      await pbService.updateAppSettings(
        settingsId: _settingsId!,
        showAllInventoryInMenu: _showAllInventoryInMenu,
        showToolDetailsInList: _showToolDetailsInList,
        useCategoryButtons: _useCategoryButtons,
        enableToolImport: value,
        keepDrawerOpen: _keepDrawerOpen,
      );

      setState(() {
        _enableToolImport = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value 
              ? 'Auto tool import enabled' 
              : 'Auto tool import disabled'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating setting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveAutoLogout() async {
    if (_shopSettingsId == null) return;

    final parsed = int.tryParse(_autoLogoutMinutes.text.trim());
    final minutes = parsed == null || parsed < 0 ? 0 : parsed;

    setState(() => _savingAutoLogout = true);
    try {
      await PocketBaseService().updateShopSettings(_shopSettingsId!, {
        'auto_logout_minutes': minutes,
      });
      _autoLogoutMinutes.text = '$minutes';
      IdleLogoutPolicy.instance.notifyChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              minutes == 0
                  ? 'Auto-logout disabled'
                  : 'Auto-logout set to $minutes minute${minutes == 1 ? '' : 's'}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving session setting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAutoLogout = false);
    }
  }

  Future<void> _updateKeepDrawerOpen(bool value) async {
    if (_settingsId == null) return;

    final previous = _keepDrawerOpen;
    // Optimistic: rebuild this screen and any mounted WorkspaceScaffold (dashboard).
    setState(() => _keepDrawerOpen = value);
    DrawerDataCache.keepDrawerOpen = value;
    DrawerDataCache.notifyKeepDrawerOpenListeners();

    try {
      final pbService = PocketBaseService();
      await pbService.updateAppSettings(
        settingsId: _settingsId!,
        showAllInventoryInMenu: _showAllInventoryInMenu,
        showToolDetailsInList: _showToolDetailsInList,
        useCategoryButtons: _useCategoryButtons,
        enableToolImport: _enableToolImport,
        keepDrawerOpen: value,
      );

      // PB silently drops unknown fields — confirm the value actually stuck.
      final settings = await pbService.getAppSettings();
      final persisted = DrawerDataCache.readKeepDrawerOpen(settings);
      if (persisted != value) {
        if (!mounted) return;
        setState(() => _keepDrawerOpen = previous);
        DrawerDataCache.keepDrawerOpen = previous;
        DrawerDataCache.notifyKeepDrawerOpenListeners();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save "keep side menu open". Check that app_settings '
              'has boolean keep_drawer_open and your user can update that record.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 8),
          ),
        );
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Side menu will stay open on desktop'
                  : 'Side menu will auto-hide on desktop',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _keepDrawerOpen = previous);
      DrawerDataCache.keepDrawerOpen = previous;
      DrawerDataCache.notifyKeepDrawerOpenListeners();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating setting: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickSkin() async {
    final selected = await showModalBottomSheet<AppSkin>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Choose skin',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              for (final option in AppSkin.values)
                ListTile(
                  leading: Icon(
                    _skin == option
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(option.label),
                  subtitle: Text(option.subtitle),
                  onTap: () => Navigator.pop(context, option),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected == null || selected == _skin) return;
    setState(() => _skin = selected);
    await ThemeController.instance.setSkin(selected);
  }

  @override
  Widget build(BuildContext context) {
    final bodyContent = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
                // Inventory Management Section
                const Text(
                  'INVENTORY MANAGEMENT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.category, color: Colors.blue),
                        title: const Text('Manage Categories & Subcategories'),
                        subtitle: const Text('Add, edit, or delete categories and subcategories'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CategoryManagementScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.inventory, color: Colors.blue),
                        title: const Text('Show "All Inventory" in menu'),
                        subtitle: const Text('Display all items menu option in drawer'),
                        value: _showAllInventoryInMenu,
                        onChanged: _updateShowAllInventory,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'SESSION',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Auto-logout after inactivity',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Automatically sign out after a period with no activity. Set to 0 to disable.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            SizedBox(
                              width: 120,
                              child: TextField(
                                controller: _autoLogoutMinutes,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Minutes',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                enabled: !_savingAutoLogout,
                                onSubmitted: (_) => _saveAutoLogout(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(
                              onPressed: _savingAutoLogout ? null : _saveAutoLogout,
                              child: _savingAutoLogout
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Save'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (!AuthService.instance.isJobsOnly) ...[
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text(
                      'QUOTE MANAGEMENT',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.request_quote, color: Colors.blue),
                      title: const Text('Quote defaults & rates'),
                      subtitle: const Text(
                        'Markups, hourly rates, and exchange rate',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const QuoteManagementSettingsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text(
                      'PURCHASE EMAIL INGEST',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.mail_outline, color: Colors.blue),
                      title: const Text('Email purchase ingest'),
                      subtitle: const Text(
                        'Gmail poll, vendors, review drafts on Purchases',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const EmailIngestSettingsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Display Preferences Section
                const Text(
                  'DISPLAY PREFERENCES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.dark_mode, color: Colors.blue),
                        title: const Text('Dark mode'),
                        value: _darkMode,
                        onChanged: (value) async {
                          setState(() {
                            _darkMode = value;
                          });
                          await ThemeController.instance.setDarkMode(value);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.menu_open, color: Colors.blue),
                        title: const Text('Keep side menu open on desktop'),
                        subtitle: const Text('On large screens, open the menu by default'),
                        value: _keepDrawerOpen,
                        onChanged: _updateKeepDrawerOpen,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.info_outline, color: Colors.blue),
                        title: const Text('Show tool details in inventory lists'),
                        subtitle: const Text('Display diameter, flutes, and length info'),
                        value: _showToolDetailsInList,
                        onChanged: _updateShowToolDetails,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.apps, color: Colors.blue),
                        title: const Text('Use buttons for category selection'),
                        subtitle: const Text('Show categories as buttons instead of dropdown'),
                        value: _useCategoryButtons,
                        onChanged: _updateUseCategoryButtons,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          Icons.palette,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: const Text('Skin'),
                        subtitle: Text('${_skin.label} — ${_skin.subtitle}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _pickSkin,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Data Management Section
                const Text(
                  'DATA MANAGEMENT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      // NEW: Auto Tool Import
                      SwitchListTile(
                        secondary: const Icon(Icons.cloud_download, color: Colors.blue),
                        title: const Text('Enable Auto Tool Import'),
                        subtitle: const Text('Import tool specs from vendor websites'),
                        value: _enableToolImport,
                        onChanged: _updateEnableToolImport,
                      ),
                      // NEW: Show config option only when enabled
                      if (_enableToolImport) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.settings, color: Colors.blue),
                          title: const Text('Configure Tool Import'),
                          subtitle: const Text('Manage vendors and import settings'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ToolImportConfigScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.backup, color: Colors.grey),
                        title: const Text('Backup & Restore'),
                        subtitle: const Text('Coming soon'),
                        enabled: false,
                        trailing: const Icon(Icons.chevron_right),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.sync, color: Colors.grey),
                        title: const Text('Sync Settings'),
                        subtitle: const Text('Coming soon'),
                        enabled: false,
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              ],
            );

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: workspaceMenuLeading(context),
      ),
      body: bodyContent,
    );
  }
}
