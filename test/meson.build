subdir('data')

# Mock classes should be compiled into a stand-alone test lib for
# re-use by both client and engine test suites, but we can't since
# that would depend on geary-engine.vapi, and the engine test sute
# needs to depend geary-engine_internal.vapi, which leads to duplicate
# symbols when linking. So just duplicate the sources in both.
libmock_sources = [
  'mock/mock-account.vala',
  'mock/mock-contact-store.vala',
  'mock/mock-client-service.vala',
  'mock/mock-credentials-mediator.vala',
  'mock/mock-email-identifier.vala',
  'mock/mock-email-properties.vala',
  'mock/mock-folder.vala',
  'mock/mock-folder-properties.vala',
  'mock/mock-search-query.vala',
]

test_engine_sources = [
  'test-case.vala',
  'test-server.vala',
  'test-engine.vala',

  'engine/common/common-contact-harvester-mock.vala',

  'engine/api/geary-account-information-test.vala',
  'engine/api/geary-attachment-test.vala',
  'engine/api/geary-composed-email-test.vala',
  'engine/api/geary-email-test.vala',
  'engine/api/geary-engine-test.vala',
  'engine/api/geary-folder-path-test.vala',
  'engine/api/geary-service-information-test.vala',
  'engine/app/app-conversation-test.vala',
  'engine/app/app-conversation-monitor-test.vala',
  'engine/app/app-conversation-set-test.vala',
  'engine/common/common-contact-store-impl-test.vala',
  'engine/common/common-contact-harvester-test.vala',
  'engine/common/common-fts-search-query-test.vala',
  'engine/db/db-database-test.vala',
  'engine/db/db-versioned-database-test.vala',
  'engine/imap/command/imap-create-command-test.vala',
  'engine/imap/command/imap-fetch-command-test.vala',
  'engine/imap/message/imap-data-format-test.vala',
  'engine/imap/message/imap-mailbox-specifier-test.vala',
  'engine/imap/parameter/imap-list-parameter-test.vala',
  'engine/imap/response/imap-fetch-data-decoder-test.vala',
  'engine/imap/response/imap-namespace-response-test.vala',
  'engine/imap/transport/imap-client-connection-test.vala',
  'engine/imap/transport/imap-client-session-test.vala',
  'engine/imap/transport/imap-deserializer-test.vala',
  'engine/imap-db/imap-db-account-test.vala',
  'engine/imap-db/imap-db-attachment-test.vala',
  'engine/imap-db/imap-db-database-test.vala',
  'engine/imap-db/imap-db-email-identifier-test.vala',
  'engine/imap-db/imap-db-folder-test.vala',
  'engine/imap-engine/account-processor-test.vala',
  'engine/imap-engine/imap-engine-generic-account-test.vala',
  'engine/mime/mime-content-type-test.vala',
  'engine/outbox/outbox-email-identifier-test.vala',
  'engine/rfc822/rfc822-mailbox-address-test.vala',
  'engine/rfc822/rfc822-mailbox-addresses-test.vala',
  'engine/rfc822/rfc822-message-test.vala',
  'engine/rfc822/rfc822-message-data-test.vala',
  'engine/rfc822/rfc822-part-test.vala',
  'engine/rfc822/rfc822-utils-test.vala',
  'engine/util-ascii-test.vala',
  'engine/util-config-file-test.vala',
  'engine/util-html-test.vala',
  'engine/util-idle-manager-test.vala',
  'engine/util-inet-test.vala',
  'engine/util-string-test.vala',
  'engine/util-timeout-manager-test.vala',

  test_engine_resources
]

test_client_sources = [
  'test-case.vala',
  'test-client.vala',

  'client/accounts/accounts-manager-test.vala',
  'client/application/application-certificate-manager-test.vala',
  'client/application/application-client-test.vala',
  'client/application/application-configuration-test.vala',
  'client/components/components-validator-test.vala',
  'client/components/components-web-view-test-case.vala',
  'client/components/components-web-view-test.vala',
  'client/composer/composer-web-view-test.vala',
  'client/composer/composer-widget-test.vala',
  'client/util/util-cache-test.vala',
  'client/util/util-email-test.vala',
  'client/util/util-js-test.vala',

  'js/components-page-state-test.vala',
  'js/composer-page-state-test.vala',
  'js/conversation-page-state-test.vala',

  geary_compiled_schema,
  geary_resources
]

test_js_sources = [
  'test-case.vala',
  'test-js.vala',

  'client/components/components-web-view-test-case.vala',

  'js/components-page-state-test.vala',
  'js/composer-page-state-test.vala',
  'js/conversation-page-state-test.vala',

  geary_compiled_schema,
  geary_resources
]

test_integration_sources = [
  'test-case.vala',
  'test-integration.vala',

  'integration/imap/client-session.vala',
  'integration/smtp/client-session.vala',
]

# Engine tests

test_engine_dependencies = [
  engine_internal_dep,
  vala_unit_dep,
]
test_engine_dependencies += engine_dependencies

test_engine_vala_args = geary_vala_args

if libytnef.found()
  test_engine_dependencies += libytnef
  test_engine_vala_args += [
    '-D', 'WITH_TNEF_SUPPORT'
  ]
endif

test_engine_bin = executable('test-engine',
  test_engine_sources + libmock_sources,
  dependencies: test_engine_dependencies,
  include_directories: config_h_dir,
  vala_args: test_engine_vala_args,
  c_args: geary_c_args,
)

# Client tests

test_client_dependencies = [
  client_internal_dep,
  vala_unit_dep,
]
test_client_dependencies += client_dependencies

test_client_bin = executable('test-client',
  test_client_sources + libmock_sources,
  dependencies: test_client_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
  build_rpath: client_build_dir,
)

test_js_dependencies = [
  client_internal_dep,
  vala_unit_dep,
]
test_js_dependencies += client_dependencies

test_js_bin = executable('test-js',
  test_js_sources + libmock_sources,
  dependencies: test_js_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
  build_rpath: client_build_dir,
)

# Integration tests

test_integration_bin = executable('test-integration',
  test_integration_sources,
  dependencies: [
    engine_dep,
    gee,
    gio,
    gmime,
    vala_unit_dep,
    webkit2gtk,
  ],
  include_directories: config_h_dir,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
)

test(
  'engine-tests',
  test_engine_bin,
  depends: [ engine_lib ]
)
test(
  'client-tests',
  test_client_bin,
  depends: [ client_lib, web_process ]
)
test(
  'js-tests',
  test_js_bin,
  depends: [ client_lib, web_process ]
)
