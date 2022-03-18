# Build source configuration
config_h_dir = include_directories('.')

conf = configuration_data()
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf.set_quoted('G_LOG_DOMAIN', meson.project_name())
conf.set_quoted('_APP_ID', geary_id)
conf.set_quoted('_BUILD_ROOT_DIR', meson.project_build_root())
conf.set_quoted('_GSETTINGS_DIR', meson.project_build_root() / 'desktop')
conf.set_quoted('_INSTALL_PREFIX', geary_prefix)
conf.set_quoted('_ISO_CODE_3166_XML', iso_3166_xml)
conf.set_quoted('_ISO_CODE_639_XML', iso_639_xml)
conf.set_quoted('_LANGUAGE_SUPPORT_DIRECTORY', locale_dir)
conf.set_quoted('_NAME_SUFFIX', name_suffix)
conf.set_quoted('_PLUGINS_DIR', plugins_dir)
conf.set_quoted('_PROFILE', profile)
conf.set_quoted('_REVNO', revno)
conf.set_quoted('_SOURCE_ROOT_DIR', meson.project_source_root())
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
vala_defines = []

if get_option('ref_tracking').enabled()
  vala_defines += [ '--define=REF_TRACKING' ]
endif

if gmime.version().version_compare('<=3.2.7')
  vala_defines += [ '--define=GMIME_STREAM_WRITE_STRING' ]
endif

geary_vala_args += vala_defines

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
]

subdir('engine')
subdir('client')
subdir('console')
subdir('mailer')

web_process_sources = files(
  'client/web-process/web-process-extension.vala',
  'client/util/util-js.vala',
)

# Web process extension library
web_process = library('geary-web-process',
  web_process_sources,
  dependencies: [
    engine_dep,
    gee,
    gmime,
    webkit2gtk_web_extension,
  ],
  include_directories: config_h_dir,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
  install: true,
  install_dir: web_extensions_dir
)

# Now finally, make the geary executable
bin_sources = files(
  'client' / 'application' / 'main.vala',
)

bin_sources += [
  geary_compiled_schema,
  geary_resources # Included here so they show up in the executable.
]
bin_dependencies = [
  folks,
  gdk,
  client_dep,
  engine_dep,
  gee,
  gmime,
  goa,
  gtk,
  javascriptcoregtk,
  libhandy,
  libmath,
  libpeas,
  webkit2gtk,
]

bin = executable('geary',
  bin_sources,
  dependencies: bin_dependencies,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
  install: true,
  install_rpath: client_lib_dir,
)

valadoc_dependencies = [
  cairo,
  enchant,
  folks,
  gcr,
  gdk,
  gee,
  gio,
  glib,
  gmime,
  goa,
  gspell,
  gtk,
  javascriptcoregtk,
  json_glib,
  libhandy,
  libpeas,
  libsecret,
  libxml,
  sqlite,
  webkit2gtk
]

valadoc_vapi_dirs = [
  vapi_dir,
  meson.current_build_dir()
]
if libhandy_vapi != ''
  valadoc_vapi_dirs += libhandy_vapi
endif

# Hopefully Meson will get baked-in valadoc support, so we don't have
# to resort to these kinds of hacks any more. See
# https://github.com/mesonbuild/meson/issues/894

valadoc_dep_args = []
foreach dep : valadoc_dependencies
  valadoc_dep_args += '--pkg'
  if dep != libhandy
    valadoc_dep_args += dep.name()
  else
    valadoc_dep_args += 'libhandy-1'
  endif
endforeach
valadoc_dep_args += [ '--pkg', 'icu-uc' ]
valadoc_dep_args += [ '--pkg', 'libstemmer' ]
valadoc_dep_args += [ '--pkg', 'posix' ]

valadoc_vapidir_args = []
foreach dir : valadoc_vapi_dirs
  valadoc_vapidir_args += '--vapidir=@0@'.format(dir)
endforeach

if valadoc.found()
  docs = custom_target('valadoc',
    build_by_default: true,
    depends: [client_lib, engine_lib],
    input: client_vala_sources + engine_sources,
    output: 'valadoc',
    command: [ valadoc,
      '--verbose',
      '--force',
      '--internal',
      '--package-name=@0@'.format(meson.project_name()),
      '--package-version=@0@'.format(meson.project_version()),
      '-b', meson.current_source_dir(),
      '-o', '@OUTPUT@',
    ] + vala_defines + valadoc_dep_args + valadoc_vapidir_args + [
      '@INPUT@'
    ]
  )
endif
