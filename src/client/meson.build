# Geary client
geary_client_vala_sources = files(
  'application/application-avatar-store.vala',
  'application/autostart-manager.vala',
  'application/application-command.vala',
  'application/geary-application.vala',
  'application/geary-args.vala',
  'application/geary-config.vala',
  'application/geary-controller.vala',
  'application/goa-mediator.vala',
  'application/secret-mediator.vala',

  'accounts/account-dialog.vala',
  'accounts/account-dialog-account-list-pane.vala',
  'accounts/account-dialog-add-edit-pane.vala',
  'accounts/account-dialog-edit-alternate-emails-pane.vala',
  'accounts/account-dialog-pane.vala',
  'accounts/account-dialog-remove-confirm-pane.vala',
  'accounts/account-dialog-remove-fail-pane.vala',
  'accounts/account-dialog-spinner-pane.vala',
  'accounts/account-manager.vala',
  'accounts/account-spinner-page.vala',
  'accounts/accounts-editor.vala',
  'accounts/accounts-editor-edit-pane.vala',
  'accounts/accounts-editor-list-pane.vala',
  'accounts/accounts-editor-remove-pane.vala',
  'accounts/accounts-editor-row.vala',
  'accounts/accounts-editor-servers-pane.vala',
  'accounts/add-edit-page.vala',
  'accounts/goa-service-information.vala',
  'accounts/local-service-information.vala',
  'accounts/login-dialog.vala',

  'components/client-web-view.vala',
  'components/count-badge.vala',
  'components/empty-placeholder.vala',
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

  'conversation-viewer/conversation-email.vala',
  'conversation-viewer/conversation-list-box.vala',
  'conversation-viewer/conversation-message.vala',
  'conversation-viewer/conversation-viewer.vala',
  'conversation-viewer/conversation-web-view.vala',

  'dialogs/alert-dialog.vala',
  'dialogs/attachment-dialog.vala',
  'dialogs/certificate-warning-dialog.vala',
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

  'notification/in-app-notification.vala',
  'notification/libmessagingmenu.vala',
  'notification/libnotify.vala',
  'notification/new-messages-indicator.vala',
  'notification/new-messages-monitor.vala',
  'notification/null-indicator.vala',
  'notification/unity-launcher.vala',

  'sidebar/sidebar-branch.vala',
  'sidebar/sidebar-common.vala',
  'sidebar/sidebar-count-cell-renderer.vala',
  'sidebar/sidebar-entry.vala',
  'sidebar/sidebar-tree.vala',

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
  gcr,
  gee,
  gio,
  goa,
  gtk,
  json_glib,
  libcanberra,
  libnotify,
  libsecret,
  libsoup,
  gmime,
  libxml,
  posix,
  webkit2gtk,
  geary_engine_dep,
]

if libmessagingmenu.found()
  messagingmenu_vapi = meson.get_compiler('vala').find_library(
      'MessagingMenu-1.0',
      dirs: '/usr/share/vala/vapi',
      required: true
  )
  geary_client_dependencies += libmessagingmenu
  geary_client_dependencies += messagingmenu_vapi
endif
if libunity.found()
  geary_client_dependencies += libunity
endif

geary_client_lib = static_library('geary-client',
  geary_client_sources,
  dependencies: geary_client_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_vala_options,
  c_args: geary_c_options,
)

geary_client_dep = declare_dependency(
  link_with: geary_client_lib,
  include_directories: include_directories('.'),
)
