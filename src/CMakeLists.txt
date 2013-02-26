# Geary build script
# Copyright 2011-2012 Yorba Foundation

set(COMMON_SRC
common/common-arrays.vala
common/common-async.vala
common/common-international.vala
common/common-yorba-application.vala
)

set(ENGINE_SRC
engine/abstract/geary-abstract-account.vala
engine/abstract/geary-abstract-folder.vala

engine/api/geary-account.vala
engine/api/geary-account-information.vala
engine/api/geary-attachment.vala
engine/api/geary-composed-email.vala
engine/api/geary-contact.vala
engine/api/geary-contact-importance.vala
engine/api/geary-contact-store.vala
engine/api/geary-conversation.vala
engine/api/geary-conversation-monitor.vala
engine/api/geary-credentials.vala
engine/api/geary-credentials-mediator.vala
engine/api/geary-email-flag.vala
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
engine/api/geary-service-provider.vala
engine/api/geary-special-folder-type.vala

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

engine/imap/api/imap-account.vala
engine/imap/api/imap-email-flags.vala
engine/imap/api/imap-email-identifier.vala
engine/imap/api/imap-email-properties.vala
engine/imap/api/imap-folder-properties.vala
engine/imap/api/imap-folder.vala
engine/imap/command/imap-command-response.vala
engine/imap/command/imap-commands.vala
engine/imap/command/imap-command.vala
engine/imap/command/imap-fetch-command.vala
engine/imap/decoders/imap-capabilities.vala
engine/imap/decoders/imap-capability-results.vala
engine/imap/decoders/imap-command-results.vala
engine/imap/decoders/imap-fetch-data-decoder.vala
engine/imap/decoders/imap-fetch-results.vala
engine/imap/decoders/imap-list-results.vala
engine/imap/decoders/imap-select-examine-results.vala
engine/imap/decoders/imap-status-results.vala
engine/imap/imap-error.vala
engine/imap/message/imap-data-format.vala
engine/imap/message/imap-fetch-data-type.vala
engine/imap/message/imap-fetch-body-data-type.vala
engine/imap/message/imap-flag.vala
engine/imap/message/imap-mailbox-parameter.vala
engine/imap/message/imap-message-data.vala
engine/imap/message/imap-message-set.vala
engine/imap/message/imap-parameter.vala
engine/imap/message/imap-tag.vala
engine/imap/response/imap-continuation-response.vala
engine/imap/response/imap-response-code-type.vala
engine/imap/response/imap-response-code.vala
engine/imap/response/imap-server-data-type.vala
engine/imap/response/imap-server-data.vala
engine/imap/response/imap-server-response.vala
engine/imap/response/imap-status-data-type.vala
engine/imap/response/imap-status-response.vala
engine/imap/response/imap-status.vala
engine/imap/response/imap-unsolicited-server-data.vala
engine/imap/transport/imap-client-connection.vala
engine/imap/transport/imap-client-session-manager.vala
engine/imap/transport/imap-client-session.vala
engine/imap/transport/imap-deserializer.vala
engine/imap/transport/imap-mailbox.vala
engine/imap/transport/imap-serializable.vala
engine/imap/transport/imap-serializer.vala

engine/imap-db/imap-db-account.vala
engine/imap-db/imap-db-contact.vala
engine/imap-db/imap-db-database.vala
engine/imap-db/imap-db-folder.vala
engine/imap-db/imap-db-message-addresses.vala
engine/imap-db/imap-db-message-row.vala
engine/imap-db/outbox/smtp-outbox-email-identifier.vala
engine/imap-db/outbox/smtp-outbox-email-properties.vala
engine/imap-db/outbox/smtp-outbox-folder.vala
engine/imap-db/outbox/smtp-outbox-folder-properties.vala
engine/imap-db/outbox/smtp-outbox-folder-root.vala

engine/imap-engine/imap-engine.vala
engine/imap-engine/imap-engine-account-synchronizer.vala
engine/imap-engine/imap-engine-batch-operations.vala
engine/imap-engine/imap-engine-email-flag-watcher.vala
engine/imap-engine/imap-engine-email-prefetcher.vala
engine/imap-engine/imap-engine-generic-account.vala
engine/imap-engine/imap-engine-generic-all-mail-folder.vala
engine/imap-engine/imap-engine-generic-folder.vala
engine/imap-engine/imap-engine-generic-sent-mail-folder.vala
engine/imap-engine/imap-engine-generic-trash-folder.vala
engine/imap-engine/imap-engine-receive-replay-operation.vala
engine/imap-engine/imap-engine-replay-operation.vala
engine/imap-engine/imap-engine-replay-queue.vala
engine/imap-engine/imap-engine-send-replay-operation.vala
engine/imap-engine/gmail/imap-engine-gmail-account.vala
engine/imap-engine/gmail/imap-engine-gmail-folder.vala
engine/imap-engine/other/imap-engine-other-account.vala
engine/imap-engine/other/imap-engine-other-folder.vala
engine/imap-engine/replay-ops/imap-engine-copy-email.vala
engine/imap-engine/replay-ops/imap-engine-expunge-email.vala
engine/imap-engine/replay-ops/imap-engine-fetch-email.vala
engine/imap-engine/replay-ops/imap-engine-list-email.vala
engine/imap-engine/replay-ops/imap-engine-list-email-by-id.vala
engine/imap-engine/replay-ops/imap-engine-list-email-by-sparse-id.vala
engine/imap-engine/replay-ops/imap-engine-mark-email.vala
engine/imap-engine/replay-ops/imap-engine-move-email.vala
engine/imap-engine/replay-ops/imap-engine-replay-append.vala
engine/imap-engine/replay-ops/imap-engine-replay-disconnect.vala
engine/imap-engine/replay-ops/imap-engine-replay-removal.vala
engine/imap-engine/yahoo/imap-engine-yahoo-account.vala
engine/imap-engine/yahoo/imap-engine-yahoo-folder.vala

engine/nonblocking/nonblocking-abstract-semaphore.vala
engine/nonblocking/nonblocking-batch.vala
engine/nonblocking/nonblocking-mailbox.vala
engine/nonblocking/nonblocking-mutex.vala
engine/nonblocking/nonblocking-reporting-semaphore.vala
engine/nonblocking/nonblocking-variants.vala

engine/rfc822/rfc822.vala
engine/rfc822/rfc822-error.vala
engine/rfc822/rfc822-gmime-filter-flowed.vala
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
engine/util/util-interfaces.vala
engine/util/util-memory.vala
engine/util/util-numeric.vala
engine/util/util-reference-semantics.vala
engine/util/util-scheduler.vala
engine/util/util-singleton.vala
engine/util/util-stream.vala
engine/util/util-string.vala
engine/util/util-trillian.vala
)

set(CLIENT_SRC
client/geary-application.vala
client/geary-args.vala
client/geary-config.vala
client/geary-controller.vala
client/gnome-keyring-mediator.vala
client/main.vala

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

client/composer/composer-window.vala
client/composer/contact-entry-completion.vala
client/composer/email-entry.vala
client/composer/webview-edit-fixer.vala

client/dialogs/alert-dialog.vala
client/dialogs/password-dialog.vala
client/dialogs/preferences-dialog.vala

client/folder-list/folder-list-account-branch.vala
client/folder-list/folder-list-folder-entry.vala
client/folder-list/folder-list-tree.vala
client/folder-list/folder-list-inboxes-branch.vala
client/folder-list/folder-list-inbox-folder-entry.vala
client/folder-list/folder-list-special-grouping.vala

client/models/conversation-list-store.vala

client/notification/libindicate.vala
client/notification/libmessagingmenu.vala
client/notification/new-messages-indicator.vala
client/notification/new-messages-monitor.vala
client/notification/notification-bubble.vala
client/notification/null-indicator.vala
client/notification/unity-launcher.vala

client/sidebar/sidebar-branch.vala
client/sidebar/sidebar-common.vala
client/sidebar/sidebar-entry.vala
client/sidebar/sidebar-tree.vala

client/ui/folder-menu.vala
client/ui/icon-factory.vala
client/ui/main-toolbar.vala
client/ui/main-window.vala

client/util/util-date.vala
client/util/util-email.vala
client/util/util-files.vala
client/util/util-gravatar.vala
client/util/util-gtk.vala
client/util/util-webkit.vala

client/views/formatted-conversation-data.vala
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
ensure_vala_version("0.17.4" MINIMUM)
include(ValaPrecompile)

# Packages
if (LIBINDICATE_FOUND)
    message(STATUS "Unity indicate support: ON")
    set(EXTRA_CLIENT_PKG_CONFIG
        ${EXTRA_CLIENT_PKG_CONFIG}
        indicate-0.7
    )
    
    set(EXTRA_CLIENT_PACKAGES
        ${EXTRA_CLIENT_PACKAGES}
        Dbusmenu-0.4
        Indicate-0.7
    )
    
    set(EXTRA_VALA_OPTIONS
        ${EXTRA_VALA_OPTIONS}
        -D HAVE_LIBINDICATE
    )
else ()
    message(STATUS "Unity indicate support: OFF")
endif ()

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

if (LIBGRANITE_FOUND)
    message(STATUS "Granite support: ON")
    set(EXTRA_CLIENT_PKG_CONFIG
        ${EXTRA_CLIENT_PKG_CONFIG}
        granite
    )
    
    set(EXTRA_CLIENT_PACKAGES
        ${EXTRA_CLIENT_PACKAGES}
        granite
    )
    
    set(EXTRA_VALA_OPTIONS
        ${EXTRA_VALA_OPTIONS}
        -D HAVE_LIBGRANITE
    )
else ()
    message(STATUS "Granite support: OFF")
endif ()

set(TARGET_GLIB 2.32)

pkg_check_modules(DEPS REQUIRED
    gthread-2.0
    glib-2.0>=${TARGET_GLIB}.0
    gio-2.0>=2.28.0
    gtk+-3.0>=3.4.0
    gee-1.0>=0.6.0
    unique-3.0>=3.0.0
    libnotify>=0.7.5
    libcanberra>=0.28
    sqlite3>=3.7.4
    gmime-2.6>=2.6.0
    gnome-keyring-1>=3.2.2
    webkitgtk-3.0>=1.8.0
    ${EXTRA_CLIENT_PKG_CONFIG}
)

set(ENGINE_PACKAGES
    glib-2.0 gee-1.0 gio-2.0 gmime-2.6 unique-3.0 posix sqlite3
)

set(CLIENT_PACKAGES
    gtk+-3.0 gnome-keyring-1 WebKit-3.0 libnotify libcanberra ${EXTRA_CLIENT_PACKAGES}
)

set(CONSOLE_PACKAGES
    gtk+-3.0
)

set(DBUSSERVICE_PACKAGES
    gee-1.0 glib-2.0
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

set(LIB_PATHS ${DEPS_LIBRARY_DIRS})
link_directories(${LIB_PATHS})
add_definitions(${CFLAGS})

set(VALAC_OPTIONS
    --vapidir=${CMAKE_SOURCE_DIR}/bindings/vapi
    --metadatadir=${CMAKE_SOURCE_DIR}/bindings/metadata
    --girdir=${CMAKE_SOURCE_DIR}/bindings/gir
    --target-glib=${TARGET_GLIB}
    --thread
    --enable-checking
    --debug
    --fatal-warnings
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
target_link_libraries(geary-static ${DEPS_LIBRARIES} gthread-2.0)

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
target_link_libraries(geary ${DEPS_LIBRARIES} gthread-2.0 geary-static)
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
add_schemas(geary ${GSETTINGS_DIR})

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

# DBus Service
#################################################
vala_precompile(DBUS_VALA_C gearyd
    ${DBUSSERVICE_SRC}
PACKAGES
    ${DBUSSERVICE_PACKAGES}
    ${ENGINE_PACKAGES}
CUSTOM_VAPIS
    "${CMAKE_BINARY_DIR}/src/geary-static.vapi"
OPTIONS
    ${VALAC_OPTIONS}
    --vapidir=${CMAKE_BINARY_DIR}/src
)

add_executable(gearyd ${DBUS_VALA_C})
target_link_libraries(gearyd ${DEPS_LIBRARIES} gthread-2.0 geary-static)
add_custom_command(
    TARGET
        gearyd
    POST_BUILD
    COMMAND 
        ${CMAKE_COMMAND} -E copy gearyd ${CMAKE_BINARY_DIR}/
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
        gearyd
)

