# Geary build script
# Copyright 2011-2013 Yorba Foundation

set(COMMON_SRC
common/common-arrays.vala
common/common-async.vala
common/common-international.vala
common/common-yorba-application.vala
)

set(ENGINE_SRC
engine/abstract/geary-abstract-account.vala
engine/abstract/geary-abstract-folder.vala
engine/abstract/geary-abstract-local-folder.vala

engine/api/geary-account.vala
engine/api/geary-account-information.vala
engine/api/geary-aggregated-folder-properties.vala
engine/api/geary-attachment.vala
engine/api/geary-base-object.vala
engine/api/geary-composed-email.vala
engine/api/geary-contact.vala
engine/api/geary-contact-flags.vala
engine/api/geary-contact-importance.vala
engine/api/geary-contact-store.vala
engine/api/geary-credentials.vala
engine/api/geary-credentials-mediator.vala
engine/api/geary-email-flags.vala
engine/api/geary-email-identifier.vala
engine/api/geary-email-properties.vala
engine/api/geary-email.vala
engine/api/geary-endpoint.vala
engine/api/geary-engine-error.vala
engine/api/geary-engine.vala
engine/api/geary-folder.vala
engine/api/geary-folder-path.vala
engine/api/geary-folder-properties.vala
engine/api/geary-folder-supports-archive.vala
engine/api/geary-folder-supports-copy.vala
engine/api/geary-folder-supports-create.vala
engine/api/geary-folder-supports-mark.vala
engine/api/geary-folder-supports-move.vala
engine/api/geary-folder-supports-remove.vala
engine/api/geary-logging.vala
engine/api/geary-named-flag.vala
engine/api/geary-named-flags.vala
engine/api/geary-progress-monitor.vala
engine/api/geary-search-folder.vala
engine/api/geary-service-provider.vala
engine/api/geary-special-folder-type.vala

engine/app/app-conversation.vala
engine/app/app-conversation-monitor.vala
engine/app/app-email-store.vala

engine/app/conversation-monitor/app-append-operation.vala
engine/app/conversation-monitor/app-conversation-operation-queue.vala
engine/app/conversation-monitor/app-conversation-operation.vala
engine/app/conversation-monitor/app-conversation-set.vala
engine/app/conversation-monitor/app-external-append-operation.vala
engine/app/conversation-monitor/app-fill-window-operation.vala
engine/app/conversation-monitor/app-local-load-operation.vala
engine/app/conversation-monitor/app-local-search-operation.vala
engine/app/conversation-monitor/app-remove-operation.vala
engine/app/conversation-monitor/app-reseed-operation.vala
engine/app/conversation-monitor/app-terminate-operation.vala

engine/app/email-store/app-async-folder-operation.vala
engine/app/email-store/app-copy-operation.vala
engine/app/email-store/app-fetch-operation.vala
engine/app/email-store/app-list-operation.vala
engine/app/email-store/app-mark-operation.vala

engine/common/common-message-data.vala

engine/db/db.vala
engine/db/db-connection.vala
engine/db/db-context.vala
engine/db/db-database.vala
engine/db/db-database-error.vala
engine/db/db-result.vala
engine/db/db-statement.vala
engine/db/db-synchronous-mode.vala
engine/db/db-transaction-async-job.vala
engine/db/db-transaction-outcome.vala
engine/db/db-transaction-type.vala
engine/db/db-versioned-database.vala

engine/imap/imap.vala
engine/imap/imap-error.vala
engine/imap/api/imap-account.vala
engine/imap/api/imap-email-flags.vala
engine/imap/api/imap-email-properties.vala
engine/imap/api/imap-folder-properties.vala
engine/imap/api/imap-folder.vala
engine/imap/api/imap-folder-root.vala
engine/imap/command/imap-append-command.vala
engine/imap/command/imap-capability-command.vala
engine/imap/command/imap-close-command.vala
engine/imap/command/imap-command.vala
engine/imap/command/imap-compress-command.vala
engine/imap/command/imap-copy-command.vala
engine/imap/command/imap-examine-command.vala
engine/imap/command/imap-expunge-command.vala
engine/imap/command/imap-fetch-command.vala
engine/imap/command/imap-id-command.vala
engine/imap/command/imap-idle-command.vala
engine/imap/command/imap-list-command.vala
engine/imap/command/imap-login-command.vala
engine/imap/command/imap-logout-command.vala
engine/imap/command/imap-message-set.vala
engine/imap/command/imap-noop-command.vala
engine/imap/command/imap-search-command.vala
engine/imap/command/imap-search-criteria.vala
engine/imap/command/imap-search-criterion.vala
engine/imap/command/imap-select-command.vala
engine/imap/command/imap-starttls-command.vala
engine/imap/command/imap-status-command.vala
engine/imap/command/imap-store-command.vala
engine/imap/message/imap-data-format.vala
engine/imap/message/imap-envelope.vala
engine/imap/message/imap-fetch-body-data-specifier.vala
engine/imap/message/imap-fetch-data-specifier.vala
engine/imap/message/imap-flag.vala
engine/imap/message/imap-flags.vala
engine/imap/message/imap-internal-date.vala
engine/imap/message/imap-mailbox-specifier.vala
engine/imap/message/imap-mailbox-parameter.vala
engine/imap/message/imap-message-data.vala
engine/imap/message/imap-message-flag.vala
engine/imap/message/imap-message-flags.vala
engine/imap/message/imap-sequence-number.vala
engine/imap/message/imap-status-data-type.vala
engine/imap/message/imap-tag.vala
engine/imap/message/imap-uid.vala
engine/imap/message/imap-uid-validity.vala
engine/imap/parameter/imap-atom-parameter.vala
engine/imap/parameter/imap-list-parameter.vala
engine/imap/parameter/imap-literal-parameter.vala
engine/imap/parameter/imap-nil-parameter.vala
engine/imap/parameter/imap-number-parameter.vala
engine/imap/parameter/imap-parameter.vala
engine/imap/parameter/imap-quoted-string-parameter.vala
engine/imap/parameter/imap-root-parameters.vala
engine/imap/parameter/imap-string-parameter.vala
engine/imap/parameter/imap-unquoted-string-parameter.vala
engine/imap/response/imap-capabilities.vala
engine/imap/response/imap-continuation-response.vala
engine/imap/response/imap-fetch-data-decoder.vala
engine/imap/response/imap-fetched-data.vala
engine/imap/response/imap-mailbox-attribute.vala
engine/imap/response/imap-mailbox-attributes.vala
engine/imap/response/imap-mailbox-information.vala
engine/imap/response/imap-response-code.vala
engine/imap/response/imap-response-code-type.vala
engine/imap/response/imap-server-data.vala
engine/imap/response/imap-server-data-type.vala
engine/imap/response/imap-server-response.vala
engine/imap/response/imap-status.vala
engine/imap/response/imap-status-data.vala
engine/imap/response/imap-status-response.vala
engine/imap/transport/imap-client-connection.vala
engine/imap/transport/imap-client-session-manager.vala
engine/imap/transport/imap-client-session.vala
engine/imap/transport/imap-deserializer.vala
engine/imap/transport/imap-serializer.vala

engine/imap-db/imap-db-account.vala
engine/imap-db/imap-db-attachment.vala
engine/imap-db/imap-db-contact.vala
engine/imap-db/imap-db-database.vala
engine/imap-db/imap-db-email-identifier.vala
engine/imap-db/imap-db-folder.vala
engine/imap-db/imap-db-message-addresses.vala
engine/imap-db/imap-db-message-row.vala
engine/imap-db/imap-db-search-email-identifier.vala
engine/imap-db/outbox/smtp-outbox-email-identifier.vala
engine/imap-db/outbox/smtp-outbox-email-properties.vala
engine/imap-db/outbox/smtp-outbox-folder.vala
engine/imap-db/outbox/smtp-outbox-folder-properties.vala
engine/imap-db/outbox/smtp-outbox-folder-root.vala

engine/imap-engine/imap-engine.vala
engine/imap-engine/imap-engine-account-synchronizer.vala
engine/imap-engine/imap-engine-batch-operations.vala
engine/imap-engine/imap-engine-contact-store.vala
engine/imap-engine/imap-engine-email-flag-watcher.vala
engine/imap-engine/imap-engine-email-prefetcher.vala
engine/imap-engine/imap-engine-generic-account.vala
engine/imap-engine/imap-engine-generic-all-mail-folder.vala
engine/imap-engine/imap-engine-generic-drafts-folder.vala
engine/imap-engine/imap-engine-generic-folder.vala
engine/imap-engine/imap-engine-generic-sent-mail-folder.vala
engine/imap-engine/imap-engine-generic-trash-folder.vala
engine/imap-engine/imap-engine-receive-replay-operation.vala
engine/imap-engine/imap-engine-replay-operation.vala
engine/imap-engine/imap-engine-replay-queue.vala
engine/imap-engine/imap-engine-send-replay-operation.vala
engine/imap-engine/gmail/imap-engine-gmail-account.vala
engine/imap-engine/gmail/imap-engine-gmail-folder.vala
engine/imap-engine/gmail/imap-engine-gmail-search-folder.vala
engine/imap-engine/other/imap-engine-other-account.vala
engine/imap-engine/other/imap-engine-other-folder.vala
engine/imap-engine/outlook/imap-engine-outlook-account.vala
engine/imap-engine/outlook/imap-engine-outlook-folder.vala
engine/imap-engine/replay-ops/imap-engine-abstract-list-email.vala
engine/imap-engine/replay-ops/imap-engine-copy-email.vala
engine/imap-engine/replay-ops/imap-engine-create-email.vala
engine/imap-engine/replay-ops/imap-engine-fetch-email.vala
engine/imap-engine/replay-ops/imap-engine-list-email-by-id.vala
engine/imap-engine/replay-ops/imap-engine-list-email-by-sparse-id.vala
engine/imap-engine/replay-ops/imap-engine-mark-email.vala
engine/imap-engine/replay-ops/imap-engine-move-email.vala
engine/imap-engine/replay-ops/imap-engine-remove-email.vala
engine/imap-engine/replay-ops/imap-engine-replay-append.vala
engine/imap-engine/replay-ops/imap-engine-replay-disconnect.vala
engine/imap-engine/replay-ops/imap-engine-replay-removal.vala
engine/imap-engine/replay-ops/imap-engine-server-search-email.vala
engine/imap-engine/yahoo/imap-engine-yahoo-account.vala
engine/imap-engine/yahoo/imap-engine-yahoo-folder.vala

engine/memory/memory-buffer.vala
engine/memory/memory-byte-buffer.vala
engine/memory/memory-empty-buffer.vala
engine/memory/memory-file-buffer.vala
engine/memory/memory-growable-buffer.vala
engine/memory/memory-string-buffer.vala
engine/memory/memory-unowned-byte-array-buffer.vala
engine/memory/memory-unowned-bytes-buffer.vala
engine/memory/memory-unowned-string-buffer.vala

engine/nonblocking/nonblocking-abstract-semaphore.vala
engine/nonblocking/nonblocking-batch.vala
engine/nonblocking/nonblocking-concurrent.vala
engine/nonblocking/nonblocking-counting-semaphore.vala
engine/nonblocking/nonblocking-error.vala
engine/nonblocking/nonblocking-mailbox.vala
engine/nonblocking/nonblocking-mutex.vala
engine/nonblocking/nonblocking-reporting-semaphore.vala
engine/nonblocking/nonblocking-variants.vala

engine/rfc822/rfc822.vala
engine/rfc822/rfc822-error.vala
engine/rfc822/rfc822-gmime-filter-flowed.vala
engine/rfc822/rfc822-gmime-filter-blockquotes.vala
engine/rfc822/rfc822-gmime-filter-plain.vala
engine/rfc822/rfc822-mailbox-addresses.vala
engine/rfc822/rfc822-mailbox-address.vala
engine/rfc822/rfc822-message.vala
engine/rfc822/rfc822-message-data.vala
engine/rfc822/rfc822-utils.vala

engine/smtp/smtp-abstract-authenticator.vala
engine/smtp/smtp-authenticator.vala
engine/smtp/smtp-capabilities.vala
engine/smtp/smtp-client-connection.vala
engine/smtp/smtp-client-session.vala
engine/smtp/smtp-command.vala
engine/smtp/smtp-data-format.vala
engine/smtp/smtp-error.vala
engine/smtp/smtp-greeting.vala
engine/smtp/smtp-login-authenticator.vala
engine/smtp/smtp-plain-authenticator.vala
engine/smtp/smtp-request.vala
engine/smtp/smtp-response.vala
engine/smtp/smtp-response-code.vala
engine/smtp/smtp-response-line.vala

engine/state/state-machine-descriptor.vala
engine/state/state-machine.vala
engine/state/state-mapping.vala

engine/util/util-collection.vala
engine/util/util-converter.vala
engine/util/util-files.vala
engine/util/util-generic-capabilities.vala
engine/util/util-html.vala
engine/util/util-imap-utf7.vala
engine/util/util-inet.vala
engine/util/util-numeric.vala
engine/util/util-object.vala
engine/util/util-reference-semantics.vala
engine/util/util-scheduler.vala
engine/util/util-single-item.vala
engine/util/util-stream.vala
engine/util/util-string.vala
engine/util/util-synchronization.vala
engine/util/util-time.vala
engine/util/util-trillian.vala
)

set(CLIENT_SRC
client/geary-application.vala
client/geary-args.vala
client/geary-config.vala
client/geary-controller.vala
client/main.vala
client/secret-mediator.vala

client/accounts/account-dialog.vala
client/accounts/account-dialog-account-list-pane.vala
client/accounts/account-dialog-add-edit-pane.vala
client/accounts/account-dialog-pane.vala
client/accounts/account-dialog-remove-confirm-pane.vala
client/accounts/account-dialog-remove-fail-pane.vala
client/accounts/account-dialog-spinner-pane.vala
client/accounts/account-spinner-page.vala
client/accounts/add-edit-page.vala
client/accounts/login-dialog.vala

client/composer/composer-toolbar.vala
client/composer/composer-window.vala
client/composer/contact-entry-completion.vala
client/composer/contact-list-store.vala
client/composer/email-entry.vala
client/composer/webview-edit-fixer.vala

client/dialogs/alert-dialog.vala
client/dialogs/attachment-dialog.vala
client/dialogs/password-dialog.vala
client/dialogs/preferences-dialog.vala
client/dialogs/upgrade-dialog.vala

client/folder-list/folder-list-abstract-folder-entry.vala
client/folder-list/folder-list-account-branch.vala
client/folder-list/folder-list-folder-entry.vala
client/folder-list/folder-list-tree.vala
client/folder-list/folder-list-inboxes-branch.vala
client/folder-list/folder-list-inbox-folder-entry.vala
client/folder-list/folder-list-search-branch.vala
client/folder-list/folder-list-special-grouping.vala

client/models/conversation-list-store.vala

client/notification/libmessagingmenu.vala
client/notification/libnotify.vala
client/notification/new-messages-indicator.vala
client/notification/new-messages-monitor.vala
client/notification/null-indicator.vala
client/notification/unity-launcher.vala

client/sidebar/sidebar-branch.vala
client/sidebar/sidebar-common.vala
client/sidebar/sidebar-count-cell-renderer.vala
client/sidebar/sidebar-entry.vala
client/sidebar/sidebar-tree.vala

client/ui/count-badge.vala
client/ui/folder-menu.vala
client/ui/icon-factory.vala
client/ui/main-toolbar.vala
client/ui/main-window.vala
client/ui/monitored-progress-bar.vala
client/ui/monitored-spinner.vala
client/ui/pill-toolbar.vala
client/ui/status-bar.vala
client/ui/stock.vala

client/util/util-date.vala
client/util/util-email.vala
client/util/util-files.vala
client/util/util-gravatar.vala
client/util/util-gtk.vala
client/util/util-webkit.vala

client/views/formatted-conversation-data.vala
client/views/conversation-find-bar.vala
client/views/conversation-list-cell-renderer.vala
client/views/conversation-list-view.vala
client/views/conversation-viewer.vala
client/views/conversation-web-view.vala
)

set(CONSOLE_SRC
console/main.vala
)

set(MAILER_SRC
mailer/main.vala
)

set(DBUSSERVICE_SRC
dbusservice/controller.vala
dbusservice/database.vala
dbusservice/dbus-conversation.vala
dbusservice/dbus-conversations.vala
dbusservice/dbus-email.vala
dbusservice/main.vala
)

# Vala
find_package(Vala REQUIRED)
include(ValaVersion)
ensure_vala_version("0.20.1" MINIMUM)
include(ValaPrecompile)

# Packages
if (LIBMESSAGINGMENU_FOUND)
    message(STATUS "Unity messaging menu support: ON")
    set(EXTRA_CLIENT_PKG_CONFIG
        ${EXTRA_CLIENT_PKG_CONFIG}
        messaging-menu
    )
    
    set(EXTRA_CLIENT_PACKAGES
        ${EXTRA_CLIENT_PACKAGES}
        MessagingMenu-1.0
    )
    
    set(EXTRA_VALA_OPTIONS
        ${EXTRA_VALA_OPTIONS}
        -D HAVE_LIBMESSAGINGMENU
    )
else ()
    message(STATUS "Unity messaging menu support: OFF")
endif ()

if (LIBUNITY_FOUND)
    message(STATUS "Unity launcher support: ON")
    set(EXTRA_CLIENT_PKG_CONFIG
        ${EXTRA_CLIENT_PKG_CONFIG}
        unity
    )
    
    set(EXTRA_CLIENT_PACKAGES
        ${EXTRA_CLIENT_PACKAGES}
        unity
    )
    
    set(EXTRA_VALA_OPTIONS
        ${EXTRA_VALA_OPTIONS}
        -D HAVE_LIBUNITY
    )
else ()
    message(STATUS "Unity launcher support: OFF")
endif ()

if (WEBKITGTK22X_FOUND)
    message(STATUS "Targeting WebKitGTK 2.2.x")
    SET(EXTRA_CLIENT_PKG_CONFIG
        ${EXTRA_CLIENT_PKG_CONFIG}
        webkitgtk-3.0>=2.2.0
    )
    
    SET(WEBKITGTK_METADATA_DIR
        webkitgtk-2.2
    )
else ()
    message(STATUS "Targeting WebKitGTK 1.10.0 to 2.0.4")
    SET(EXTRA_CLIENT_PKG_CONFIG
        ${EXTRA_CLIENT_PKG_CONFIG}
        webkitgtk-3.0>=1.10.0
        webkitgtk-3.0<=2.0.4
    )
    
    SET(WEBKITGTK_METADATA_DIR
        webkitgtk-2.0
    )
endif ()

if (NO_FATAL_WARNINGS)
    message(STATUS "Vala fatal warnings: OFF")
else ()
    message(STATUS "Vala fatal warnings: ON")
    
    set (EXTRA_VALA_OPTIONS
        ${EXTRA_VALA_OPTIONS}
        --fatal-warnings
    )
endif ()

set(TARGET_GLIB 2.32)

pkg_check_modules(DEPS REQUIRED
    gthread-2.0
    glib-2.0>=${TARGET_GLIB}.0
    gio-2.0>=2.28.0
    gtk+-3.0>=3.6.0
    gee-0.8>=0.8.5
    unique-3.0>=3.0.0
    libnotify>=0.7.5
    libcanberra>=0.28
    sqlite3>=3.7.4
    gmime-2.6>=2.6.0
    libsecret-1>=0.11
    libxml-2.0>=2.7.8
    ${EXTRA_CLIENT_PKG_CONFIG}
)

set(ENGINE_PACKAGES
    glib-2.0 gee-0.8 gio-2.0 gmime-2.6 unique-3.0 posix sqlite3 libxml-2.0
)

set(CLIENT_PACKAGES
    gtk+-3.0 libsecret-1 WebKit-3.0 libnotify libcanberra ${EXTRA_CLIENT_PACKAGES}
)

set(CONSOLE_PACKAGES
    gtk+-3.0
)

set(DBUSSERVICE_PACKAGES
    gee-0.8 glib-2.0
)

set(GSETTINGS_DIR ${CMAKE_SOURCE_DIR}/desktop)

set(CFLAGS 
    ${DEPS_CFLAGS}
    ${DEPS_CFLAGS_OTHER}
    -D_VERSION=\"${VERSION}\"
    -D_INSTALL_PREFIX=\"${CMAKE_INSTALL_PREFIX}\"
    -D_SOURCE_ROOT_DIR=\"${CMAKE_SOURCE_DIR}\"
    -D_GSETTINGS_DIR=\"${CMAKE_BINARY_DIR}/gsettings\"
    -DGETTEXT_PACKAGE=\"${GETTEXT_PACKAGE}\"
    -DLANGUAGE_SUPPORT_DIRECTORY=\"${LANGUAGE_SUPPORT_DIRECTORY}\"
    -g
)

if (NOT DEBUG)
    set(CFLAGS
        ${CFLAGS}
        -O2
    )    
endif ()

if (REF_TRACKING)
    message(STATUS "Reference tracking: ON")
    set(EXTRA_VALA_OPTIONS
        ${EXTRA_VALA_OPTIONS}
        --define=REF_TRACKING
    )
else ()
    message(STATUS "Reference tracking: OFF")
endif ()

set(LIB_PATHS ${DEPS_LIBRARY_DIRS})
link_directories(${LIB_PATHS})
add_definitions(${CFLAGS})

set(VALAC_OPTIONS
    --vapidir=${CMAKE_SOURCE_DIR}/bindings/vapi
    --metadatadir=${CMAKE_SOURCE_DIR}/bindings/metadata
    --metadatadir=${CMAKE_SOURCE_DIR}/bindings/metadata/${WEBKITGTK_METADATA_DIR}
    --target-glib=${TARGET_GLIB}
    --thread
    --enable-checking
    --debug
    --enable-deprecated
    ${EXTRA_VALA_OPTIONS}
)

# Engine (static library used for building)
#################################################
vala_precompile(ENGINE_VALA_C geary-static
    ${ENGINE_SRC}
    ${COMMON_SRC}
PACKAGES
    ${CONSOLE_PACKAGES}
    ${ENGINE_PACKAGES}
GENERATE_VAPI
    geary-static
OPTIONS
    ${VALAC_OPTIONS}
)

add_library(geary-static STATIC ${ENGINE_VALA_C})
target_link_libraries(geary-static ${DEPS_LIBRARIES} sqlite3-unicodesn gthread-2.0)

# Geary client app
#################################################
vala_precompile(GEARY_VALA_C geary
    ${CLIENT_SRC}
PACKAGES
    ${CLIENT_PACKAGES}
    ${ENGINE_PACKAGES}
CUSTOM_VAPIS
    "${CMAKE_BINARY_DIR}/src/geary-static.vapi"
OPTIONS
    ${VALAC_OPTIONS}
    --vapidir=${CMAKE_BINARY_DIR}/src
)

add_executable(geary ${GEARY_VALA_C})
target_link_libraries(geary m ${DEPS_LIBRARIES} gthread-2.0 geary-static)
install(TARGETS geary RUNTIME DESTINATION bin)
add_custom_command(
    TARGET
        geary
    POST_BUILD
    COMMAND 
        ${CMAKE_COMMAND} -E copy geary ${CMAKE_BINARY_DIR}/
)

# GSettings
# This needs to be here and not in desktop/CMakeLists.txt in order for Geary to run in the build
# directory
include(GSettings)
add_schemas(geary ${GSETTINGS_DIR} ${CMAKE_INSTALL_PREFIX})

IF (XGETTEXT_FOUND)
    MESSAGE("Creating POT file")
    GETTEXT_CREATE_POT(${GETTEXT_PACKAGE}.pot OPTION ${XGETTEXT_OPTIONS} SRC ${CLIENT_SRC} ${ENGINE_SRC} ${COMMON_SRC} GLADE ${GLADE_FILES})
ELSE ()
    message(STATUS "xgettext not found")
ENDIF()

# Console app
#################################################
vala_precompile(CONSOLE_VALA_C geary-console
    ${CONSOLE_SRC}
PACKAGES
    ${CONSOLE_PACKAGES}
    ${ENGINE_PACKAGES}
CUSTOM_VAPIS
    "${CMAKE_BINARY_DIR}/src/geary-static.vapi"
OPTIONS
    ${VALAC_OPTIONS}
    --vapidir=${CMAKE_BINARY_DIR}/src
)

add_executable(geary-console ${CONSOLE_VALA_C})
target_link_libraries(geary-console ${DEPS_LIBRARIES} gthread-2.0 geary-static)
add_custom_command(
    TARGET
        geary-console
    POST_BUILD
    COMMAND 
        ${CMAKE_COMMAND} -E copy geary-console ${CMAKE_BINARY_DIR}/
)

# Mailer app
#################################################
vala_precompile(MAILER_VALA_C geary-mailer
    ${MAILER_SRC}
PACKAGES
    ${ENGINE_PACKAGES}
CUSTOM_VAPIS
    "${CMAKE_BINARY_DIR}/src/geary-static.vapi"
OPTIONS
    ${VALAC_OPTIONS}
    --vapidir=${CMAKE_BINARY_DIR}/src
)

add_executable(geary-mailer ${MAILER_VALA_C})
target_link_libraries(geary-mailer ${DEPS_LIBRARIES} gthread-2.0 geary-static)
add_custom_command(
    TARGET
        geary-mailer
    POST_BUILD
    COMMAND 
        ${CMAKE_COMMAND} -E copy geary-mailer ${CMAKE_BINARY_DIR}/
)

# Valadoc
#################################################
foreach(pkg ${ENGINE_PACKAGES})
    list(APPEND valadoc_pkg_opts "--pkg=${pkg}")
endforeach(pkg ${ENGINE_PACKAGES})

include(FindValadoc)
add_custom_target(
    valadoc
    WORKING_DIRECTORY
        ${CMAKE_SOURCE_DIR}/src
    COMMAND
        ${VALADOC_EXECUTABLE} --force --no-protected -b ${CMAKE_CURRENT_SOURCE_DIR} -o ${CMAKE_SOURCE_DIR}/valadoc --package-name=geary --package-version=${VERSION} ${ENGINE_SRC} ${valadoc_pkg_opts} --vapidir=${CMAKE_SOURCE_DIR}/bindings/vapi
)

## Make clean: remove copied files
##################################################
set_property(
    DIRECTORY ..
    APPEND
    PROPERTY ADDITIONAL_MAKE_CLEAN_FILES
        geary
        geary-console
        geary-mailer
)

add_subdirectory(sqlite3-unicodesn)
