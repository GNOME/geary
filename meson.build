project('geary', [ 'vala', 'c' ],
  version: '46.0',
  license: 'LGPL2.1+',
  meson_version: '>= 0.59',
)

# Determine the type of build
profile = get_option('profile')
appid_suffix = ''
name_suffix = ''
if profile == 'auto'
  if run_command('[', '-d', '.git', ']', check: false).returncode() == 0
    profile = 'development'
  else
    error('No build profile specified, see BUILDING.md')
  endif
endif

if profile == 'development'
  appid_suffix = '.Devel'
elif profile == 'beta'
  appid_suffix = '.Beta'
  name_suffix = ' (Beta)'
elif profile != 'release'
  error('Unknown build profile specified, see BUILDING.md')
endif

# Configurable install dirs
geary_prefix = get_option('prefix')
bin_dir = geary_prefix / get_option('bindir')
data_dir = geary_prefix / get_option('datadir')
lib_dir = geary_prefix / get_option('libdir')
locale_dir = geary_prefix / get_option('localedir')

# Source dirs
metadata_dir = meson.project_source_root() / 'bindings'/ 'metadata'
po_dir = meson.project_source_root() / 'po'
vapi_dir = meson.project_source_root() / 'bindings' / 'vapi'

# Compiler configuration
add_project_arguments([
    # Make sure Meson can find custom VAPIs
    '--vapidir', vapi_dir,
    '--metadatadir', metadata_dir,
  ],
  language: 'vala'
)
cc = meson.get_compiler('c')
valac = meson.get_compiler('vala')

#
# Required libraries and other dependencies
#

target_glib = '2.68'
target_gtk = '3.24.24'
target_vala = '0.48.18'
target_webkit = '2.30'

if not valac.version().version_compare('>=' + target_vala)
  error('Vala does not meet minimum required version: ' + target_vala)
endif

# Primary deps
glib = dependency('glib-2.0', version: '>=' + target_glib)
gmime = dependency('gmime-3.0', version: '>= 3.2.4')
gtk = dependency('gtk+-3.0', version: '>=' + target_gtk)
sqlite = dependency('sqlite3', version: '>= 3.24')
webkit2gtk = dependency('webkit2gtk-4.1', version: '>=' + target_webkit)

# Secondary deps - keep sorted alphabetically
cairo = dependency('cairo')
enchant = dependency('enchant-2', version: '>=2.1')
folks = dependency('folks', version: '>=0.11')
gck = dependency('gck-1')
gcr = dependency('gcr-3', version: '>= 3.10.1')
gdk = dependency('gdk-3.0', version: '>=' + target_gtk)
gee = dependency('gee-0.8', version: '>= 0.8.5')
gio = dependency('gio-2.0', version: '>=' + target_glib)
goa = dependency('goa-1.0')
gsound = dependency('gsound')
gspell = dependency('gspell-1')
gthread = dependency('gthread-2.0', version: '>=' + target_glib)
icu_uc = dependency('icu-uc', version: '>=60')
iso_codes = dependency('iso-codes')
javascriptcoregtk = dependency('javascriptcoregtk-4.1', version: '>=' + target_webkit)
json_glib = dependency('json-glib-1.0', version: '>= 1.0')
libhandy = dependency('libhandy-1', version: '>= 1.6', required: false)
libmath = cc.find_library('m')
libpeas = dependency('libpeas-1.0', version: '>= 1.24.0')
libsecret = dependency('libsecret-1', version: '>= 0.11')
libsoup = dependency('libsoup-3.0')
libstemmer_dep = cc.find_library('stemmer')
libunwind_dep = dependency(
  'libunwind', version: '>= 1.1', required: get_option('libunwind')
)
libunwind_generic_dep = dependency(
  'libunwind-generic', version: '>= 1.1', required: get_option('libunwind')
)
libxml = dependency('libxml-2.0', version: '>= 2.7.8')
libytnef = dependency('libytnef', version: '>= 1.9.3', required: get_option('tnef'))
posix = valac.find_library('posix')
webkit2gtk_web_extension = dependency('webkit2gtk-web-extension-4.1', version: '>=' + target_webkit)

# System dependencies above ensures appropriate versions for the
# following libraries, but the declared dependency is what we actually
# build against so we can include the custom VAPI correctly.

icu_uc = declare_dependency(
  dependencies: [
    valac.find_library('icu-uc', dirs: [vapi_dir]),
    cc.find_library('icuuc'),
  ],
)

if libunwind_dep.found()
  # We need to add native lib to the search path for these so Flatpak
  # builds can find it.
  unwind_lib = libunwind_dep.get_variable(pkgconfig: 'libdir')
  libunwind = declare_dependency(
     dependencies: [
       valac.find_library('libunwind', dirs: [vapi_dir, unwind_lib]),
       cc.find_library('libunwind', dirs: unwind_lib),
       cc.find_library('libunwind-generic', dirs: unwind_lib)
     ],
   )
endif

libstemmer = declare_dependency(
  dependencies: [
    valac.find_library('libstemmer', dirs: [vapi_dir]),
    libstemmer_dep,
  ],
)

# Required until libhandy 1.2.1 is GA
libhandy_vapi = ''
if not libhandy.found()
  libhandy_project = subproject(
    'libhandy',
    default_options: [
      'examples=false',
      'package_subdir=geary',
      'tests=false',
    ]
  )
  libhandy = declare_dependency(
    dependencies: [
      libhandy_project.get_variable('libhandy_dep'),
      libhandy_project.get_variable('libhandy_vapi')
    ]
  )
  libhandy_vapi = meson.project_build_root() / 'subprojects' / 'libhandy' / 'src'
endif

# Optional dependencies
appstreamcli = find_program('appstreamcli', required: false)
desktop_file_validate = find_program('desktop-file-validate', required: false)
libmessagingmenu_dep = dependency('messaging-menu', version: '>= 12.10', required: false)

#
# Internal build configuration
#

# Build variables
geary_id = 'org.gnome.Geary@0@'.format(appid_suffix)
geary_version = meson.project_version()
revno = get_option('revno')
if revno == ''
  revno = run_command('build-aux/git_version.py', check: false).stdout().strip()
endif

gnome = import('gnome')
i18n = import('i18n')

# Static install dirs
dbus_services_dir = data_dir / 'dbus-1' / 'services'
client_lib_dir = lib_dir / 'geary'
plugins_dir = client_lib_dir / 'plugins'
web_extensions_dir = client_lib_dir / 'web-extensions'

# Ensure SQLite was built correctly
if not cc.has_header_symbol('sqlite3.h', 'SQLITE_DBCONFIG_ENABLE_FTS3_TOKENIZER', dependencies: sqlite)
  error('SQLite3 was not built with FTS3 support. See BUILDING.md for details.')
endif
if not cc.has_header_symbol('sqlite3.h', 'Fts5ExtensionApi', dependencies: sqlite)
  error('SQLite3 was not built with FTS5 support. See BUILDING.md for details.')
endif

#
# Build glue
#

valadoc = find_program('valadoc', required: get_option('valadoc'))

vala_unit_proj = subproject(
  'vala-unit',
  default_options: [
    'install=false',
    'valadoc=@0@'.format(valadoc.found())
  ]
)
vala_unit_dep = vala_unit_proj.get_variable('vala_unit_dep')

# Language detection

iso_codes_dir = iso_codes.get_variable(pkgconfig: 'prefix')/'share'/'xml'/'iso-codes'

iso_639_xml = get_option('iso_639_xml')
if iso_639_xml == ''
  iso_639_xml = iso_codes_dir / 'iso_639.xml'
endif

iso_3166_xml = get_option('iso_3166_xml')
if iso_3166_xml == ''
  iso_3166_xml = iso_codes_dir / 'iso_3166.xml'
endif

files(iso_639_xml, iso_3166_xml) # Check to make sure these exist

# Make sure the locale C.UTF-8 is installed on the system

c_utf8_check = run_command('locale', '-a', check: true).stdout()
have_c_utf8 = 'C.utf8' in c_utf8_check.split('\n')

if not have_c_utf8
  warning('C.utf8 locale not available on this system.')
endif

# Post-install script
gnome.post_install(
  gtk_update_icon_cache: true,
  glib_compile_schemas: true,
  update_desktop_database: true,
)

# Subfolders
subdir('desktop')
subdir('help')
subdir('icons')
subdir('po')
subdir('sql')
subdir('ui')
subdir('src')
subdir('test')
