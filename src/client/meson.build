# Geary client

geary_client_vala_sources = files(
  'application/application-attachment-manager.vala',
  'application/application-avatar-store.vala',
  'application/application-certificate-manager.vala',
  'application/application-client.vala',
  'application/application-command.vala',
  'application/application-configuration.vala',
  'application/application-contact-store.vala',
  'application/application-contact.vala',
  'application/application-controller.vala',
  'application/application-email-store-factory.vala',
  'application/application-folder-context.vala',
  'application/application-folder-store-factory.vala',
  'application/application-main-window.vala',
  'application/application-notification-context.vala',
  'application/application-plugin-manager.vala',
  'application/application-startup-manager.vala',
  'application/goa-mediator.vala',
  'application/secret-mediator.vala',

  'accounts/accounts-editor.vala',
  'accounts/accounts-editor-add-pane.vala',
  'accounts/accounts-editor-edit-pane.vala',
  'accounts/accounts-editor-list-pane.vala',
  'accounts/accounts-editor-remove-pane.vala',
  'accounts/accounts-editor-row.vala',
  'accounts/accounts-editor-servers-pane.vala',
  'accounts/accounts-signature-web-view.vala',
  'accounts/accounts-manager.vala',

  'client-action.vala',

  'components/client-web-view.vala',
  'components/components-attachment-pane.vala',
  'components/components-entry-undo.vala',
  'components/components-info-bar-stack.vala',
  'components/components-info-bar.vala',
  'components/components-inspector.vala',
  'components/components-in-app-notification.vala',
  'components/components-inspector-error-view.vala',
  'components/components-inspector-log-view.vala',
  'components/components-inspector-system-view.vala',
  'components/components-placeholder-pane.vala',
  'components/components-preferences-window.vala',
  'components/components-problem-report-info-bar.vala',
  'components/components-reflow-box.c',
  'components/components-search-bar.vala',
  'components/components-validator.vala',
  'components/count-badge.vala',
  'components/folder-popover.vala',
  'components/icon-factory.vala',
  'components/main-toolbar.vala',
  'components/monitored-progress-bar.vala',
  'components/monitored-spinner.vala',
  'components/status-bar.vala',
  'components/stock.vala',

  'composer/composer-box.vala',
  'composer/composer-container.vala',
  'composer/composer-email-entry.vala',
  'composer/composer-embed.vala',
  'composer/composer-headerbar.vala',
  'composer/composer-link-popover.vala',
  'composer/composer-web-view.vala',
  'composer/composer-widget.vala',
  'composer/composer-window.vala',
  'composer/contact-entry-completion.vala',
  'composer/spell-check-popover.vala',

  'conversation-list/conversation-list-cell-renderer.vala',
  'conversation-list/conversation-list-store.vala',
  'conversation-list/conversation-list-view.vala',
  'conversation-list/formatted-conversation-data.vala',

  'conversation-viewer/conversation-contact-popover.vala',
  'conversation-viewer/conversation-email.vala',
  'conversation-viewer/conversation-list-box.vala',
  'conversation-viewer/conversation-message.vala',
  'conversation-viewer/conversation-viewer.vala',
  'conversation-viewer/conversation-web-view.vala',

  'dialogs/alert-dialog.vala',
  'dialogs/attachment-dialog.vala',
  'dialogs/certificate-warning-dialog.vala',
  'dialogs/dialogs-problem-details-dialog.vala',
  'dialogs/password-dialog.vala',
  'dialogs/upgrade-dialog.vala',

  'folder-list/folder-list-abstract-folder-entry.vala',
  'folder-list/folder-list-account-branch.vala',
  'folder-list/folder-list-folder-entry.vala',
  'folder-list/folder-list-tree.vala',
  'folder-list/folder-list-inboxes-branch.vala',
  'folder-list/folder-list-inbox-folder-entry.vala',
  'folder-list/folder-list-search-branch.vala',
  'folder-list/folder-list-special-grouping.vala',

  'plugin/plugin-account.vala',
  'plugin/plugin-application.vala',
  'plugin/plugin-button.vala',
  'plugin/plugin-contact-store.vala',
  'plugin/plugin-email-store.vala',
  'plugin/plugin-email.vala',
  'plugin/plugin-error.vala',
  'plugin/plugin-folder-extension.vala',
  'plugin/plugin-folder-store.vala',
  'plugin/plugin-folder.vala',
  'plugin/plugin-info-bar.vala',
  'plugin/plugin-notification-extension.vala',
  'plugin/plugin-plugin-base.vala',
  'plugin/plugin-trusted-extension.vala',

  'sidebar/sidebar-branch.vala',
  'sidebar/sidebar-common.vala',
  'sidebar/sidebar-count-cell-renderer.vala',
  'sidebar/sidebar-entry.vala',
  'sidebar/sidebar-tree.vala',

  'util/util-avatar.vala',
  'util/util-cache.vala',
  'util/util-date.vala',
  'util/util-email.vala',
  'util/util-files.vala',
  'util/util-gio.vala',
  'util/util-gtk.vala',
  'util/util-international.vala',
  'util/util-js.vala',
  'util/util-migrate.vala',
)

geary_client_sources = [
  geary_client_vala_sources,
  geary_resources # Included here so valac can check them
]

geary_client_dependencies = [
  enchant,
  folks,
  gck,
  gcr,
  geary_engine_dep,
  gee,
  gio,
  gmime,
  goa,
  gspell,
  gtk,
  javascriptcoregtk,
  json_glib,
  libhandy,
  libmath,
  libpeas,
  libpeas_gtk,
  libsecret,
  libsoup,
  libxml,
  posix,
  webkit2gtk,
]

geary_client_vala_args = geary_vala_args

# Enable shared shecondary process if available.
# See issues #558 and #559
webkit_version = webkit2gtk.version().split('.')
if webkit_version[0].to_int() <= 2 and webkit_version[1].to_int() <= 24
  message('Enabling WebKitGTK shared process model')
  geary_client_vala_args += [
    '-D', 'HAS_WEBKIT_SHARED_PROC'
  ]
endif

# Main client application library
geary_client_lib = static_library('geary-client',
  geary_client_sources,
  dependencies: geary_client_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_client_vala_args,
  c_args: geary_c_args,
)

geary_client_dep = declare_dependency(
  link_with: geary_client_lib,
  include_directories: include_directories('.'),
)

subdir('plugin')
