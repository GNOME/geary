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

geary_test_engine_sources = [
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
  'engine/db/db-database-test.vala',
  'engine/db/db-versioned-database-test.vala',
  'engine/imap/command/imap-create-command-test.vala',
  'engine/imap/command/imap-fetch-command-test.vala',
  'engine/imap/message/imap-data-format-test.vala',
  'engine/imap/message/imap-mailbox-specifier-test.vala',
  'engine/imap/parameter/imap-list-parameter-test.vala',
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

  geary_test_engine_resources
]

geary_test_client_sources = [
  'test-case.vala',
  'test-client.vala',

  'client/accounts/accounts-manager-test.vala',
  'client/application/application-client-test.vala',
  'client/application/application-configuration-test.vala',
  'client/components/client-web-view-test.vala',
  'client/components/client-web-view-test-case.vala',
  'client/components/components-validator-test.vala',
  'client/composer/composer-web-view-test.vala',
  'client/util/util-avatar-test.vala',
  'client/util/util-cache-test.vala',
  'client/util/util-email-test.vala',
  'client/util/util-js-test.vala',

  'js/client-page-state-test.vala',
  'js/composer-page-state-test.vala',
  'js/conversation-page-state-test.vala',

  geary_compiled_schema,
  geary_resources
]

geary_test_integration_sources = [
  'test-case.vala',
  'test-integration.vala',

  'integration/imap/client-session.vala',
  'integration/smtp/client-session.vala',
]

# Engine tests

geary_test_engine_dependencies = [
  geary_engine_internal_dep,
  vala_unit_dep,
]
geary_test_engine_dependencies += geary_engine_dependencies

geary_test_engine_vala_args = geary_vala_args

if get_option('tnef-support')
  geary_test_engine_dependencies += libytnef
  geary_test_engine_vala_args += [
    '-D', 'WITH_TNEF_SUPPORT'
  ]
endif

geary_test_engine_bin = executable('test-engine',
  geary_test_engine_sources + libmock_sources,
  dependencies: geary_test_engine_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_test_engine_vala_args,
  c_args: geary_c_args,
)

# Client tests

geary_test_client_dependencies = [
  geary_client_dep,
  vala_unit_dep,
]
geary_test_client_dependencies += geary_client_dependencies

geary_test_client_bin = executable('test-client',
  geary_test_client_sources + libmock_sources,
  dependencies: geary_test_client_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
)

# Integration tests

geary_test_integration_bin = executable('test-integration',
  geary_test_integration_sources,
  dependencies: [
    geary_engine_dep,
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

test('engine-tests', geary_test_engine_bin)
test('client-tests', geary_test_client_bin)
