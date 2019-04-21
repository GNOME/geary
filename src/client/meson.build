# Geary client
geary_client_vala_sources = files(
  'application/application-avatar-store.vala',
  'application/application-certificate-manager.vala',
  'application/application-command.vala',
  'application/application-contact-store.vala',
  'application/application-contact.vala',
  'application/application-controller.vala',
  'application/application-startup-manager.vala',
  'application/geary-application.vala',
  'application/geary-config.vala',
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

  'components/client-web-view.vala',
  'components/components-inspector.vala',
  'components/components-placeholder-pane.vala',
  'components/components-validator.vala',
  'components/count-badge.vala',
  'components/folder-popover.vala',
  'components/icon-factory.vala',
  'components/main-toolbar.vala',
  'components/main-window.vala',
  'components/main-window-info-bar.vala',
  'components/monitored-progress-bar.vala',
  'components/monitored-spinner.vala',
  'components/search-bar.vala',
  'components/status-bar.vala',
  'components/stock.vala',

  'composer/composer-box.vala',
  'composer/composer-container.vala',
  'composer/composer-embed.vala',
  'composer/composer-headerbar.vala',
  'composer/composer-link-popover.vala',
  'composer/composer-web-view.vala',
  'composer/composer-widget.vala',
  'composer/composer-window.vala',
  'composer/contact-entry-completion.vala',
  'composer/contact-list-store.vala',
  'composer/contact-list-store-cache.vala',
  'composer/email-entry.vala',
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
  'dialogs/preferences-dialog.vala',
  'dialogs/upgrade-dialog.vala',

  'folder-list/folder-list-abstract-folder-entry.vala',
  'folder-list/folder-list-account-branch.vala',
  'folder-list/folder-list-folder-entry.vala',
  'folder-list/folder-list-tree.vala',
  'folder-list/folder-list-inboxes-branch.vala',
  'folder-list/folder-list-inbox-folder-entry.vala',
  'folder-list/folder-list-search-branch.vala',
  'folder-list/folder-list-special-grouping.vala',

  'notification/notification-desktop.vala',
  'notification/in-app-notification.vala',
  'notification/libmessagingmenu.vala',
  'notification/new-messages-indicator.vala',
  'notification/new-messages-monitor.vala',
  'notification/null-indicator.vala',
  'notification/unity-launcher.vala',

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
  'util/util-migrate.vala',
  'util/util-webkit.vala',
)

geary_client_sources = [
  geary_client_vala_sources,
  geary_resources # Included here so valac can check them
]

geary_client_dependencies = [
  libmath,
  enchant,
  folks,
  gck,
  gcr,
  gee,
  gio,
  goa,
  gtk,
  json_glib,
  libcanberra,
  libhandy,
  libsecret,
  libsoup,
  gmime,
  libxml,
  posix,
  webkit2gtk,
  geary_engine_dep,
]

geary_client_vala_options = geary_vala_options

if libmessagingmenu_dep.found()
  geary_client_dependencies += libmessagingmenu
  geary_client_vala_options += ['-D', 'HAVE_LIBMESSAGINGMENU']
endif
if libunity.found()
  geary_client_dependencies += libunity
  geary_client_vala_options += ['-D', 'HAVE_LIBUNITY']
endif

geary_client_lib = static_library('geary-client',
  geary_client_sources,
  dependencies: geary_client_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_client_vala_options,
  c_args: geary_c_options,
)

geary_client_dep = declare_dependency(
  link_with: geary_client_lib,
  include_directories: include_directories('.'),
)
