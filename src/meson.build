# Build source configuration
config_h_dir = include_directories('.')

conf = configuration_data()
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf.set_quoted('G_LOG_DOMAIN', meson.project_name())
conf.set_quoted('_APP_ID', geary_id)
conf.set_quoted('_BUILD_ROOT_DIR', meson.build_root())
conf.set_quoted('_GSETTINGS_DIR', join_paths(meson.build_root(), 'desktop'))
conf.set_quoted('_INSTALL_PREFIX', geary_prefix)
conf.set_quoted('_ISO_CODE_3166_XML', iso_3166_xml)
conf.set_quoted('_ISO_CODE_639_XML', iso_639_xml)
conf.set_quoted('_LANGUAGE_SUPPORT_DIRECTORY', locale_dir)
conf.set_quoted('_NAME_SUFFIX', name_suffix)
conf.set_quoted('_PLUGINS_DIR', plugins_dir)
conf.set_quoted('_PROFILE', profile)
conf.set_quoted('_REVNO', revno)
conf.set_quoted('_SOURCE_ROOT_DIR', meson.source_root())
conf.set_quoted('_VERSION', geary_version)
conf.set_quoted('_WEB_EXTENSIONS_DIR', web_extensions_dir)
configure_file(output: 'config.h', configuration: conf)

# Common valac options
geary_vala_args = [
  '--abi-stability',
  '--enable-checking',
]

# Symbols for valac's preprocessor must be defined as compiler args,
# not in the code or in config.h
if reference_tracking
  geary_vala_args += [ '--define=REF_TRACKING' ]
endif
if not poodle
  geary_vala_args += [ '--define=DISABLE_POODLE' ]
endif

# Common cc options
geary_c_args = [
  '-include', 'config.h',
  # Enable GLib structured logging
  '-DG_LOG_USE_STRUCTURED',
  # Select libunwind's optimised, local-only backtrace unwiding. See
  # libunwind(3).
  '-DUNW_LOCAL_ONLY',
  # None of these kids want to hang out unless you are cool enough
  '-DGCK_API_SUBJECT_TO_CHANGE',
  '-DGCR_API_SUBJECT_TO_CHANGE',
  '-DGOA_API_IS_SUBJECT_TO_CHANGE',
  '-DHANDY_USE_UNSTABLE_API',
]

subdir('sqlite3-unicodesn')
subdir('engine')
subdir('client')
subdir('console')
subdir('mailer')

geary_web_process_sources = files(
  'client/web-process/web-process-extension.vala',
  'client/util/util-js.vala',
)

# Web process extension library
geary_web_process = library('geary-web-process',
  geary_web_process_sources,
  dependencies: [
    geary_engine_dep,
    gee,
    gmime,
    webkit2gtk_web_extension,
  ],
  include_directories: config_h_dir,
  vala_args: geary_client_vala_args,
  c_args: geary_c_args,
  install: true,
  install_dir: web_extensions_dir
)

# Now finally, make the geary executable
geary_bin_sources = files(
  join_paths('client', 'application', 'main.vala'),
)

geary_bin_sources += [
  geary_compiled_schema,
  geary_resources # Included here so they show up in the executable.
]
geary_bin_dependencies = [
  folks,
  gdk,
  geary_client_dep,
  geary_engine_dep,
  gee,
  gmime,
  goa,
  gtk,
  javascriptcoregtk,
  libhandy,
  libmath,
  libpeas,
  libsoup,
  webkit2gtk,
]

geary_bin = executable('geary',
  geary_bin_sources,
  dependencies: geary_bin_dependencies,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
  install: true,
)

if enable_valadoc
  geary_docs = custom_target('valadoc',
    build_by_default: true,
    depends: geary_engine_lib,
    input: geary_engine_sources,
    output: 'valadoc',
    command: [ valadoc,
      '--verbose',
      '--force',
      '--internal',
      '--package-name=@0@'.format(meson.project_name()),
      '--package-version=@0@'.format(meson.project_version()),
      '-b', meson.current_source_dir(),
      '-o', '@OUTPUT@',
      '--vapidir=@0@'.format(vapi_dir),
      '--vapidir=@0@'.format(meson.current_build_dir()),
      # Hopefully, Meson gets baked-in valadoc support, so we don't
      # have to do this (see https://github.com/mesonbuild/meson/issues/894)
      '--pkg', 'glib-2.0',
      '--pkg', 'gio-2.0',
      '--pkg', 'gee-0.8',
      '--pkg', 'sqlite3',
      '--pkg', 'gmime-3.0',
      '--pkg', 'javascriptcoregtk-4.0',
      '--pkg', 'libxml-2.0',
      '--pkg', 'libunwind',
      '@INPUT@',
    ]
  )
endif
