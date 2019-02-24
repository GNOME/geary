project('geary', [ 'vala', 'c' ],
  version: '3.32-dev',
  license: 'LGPL2.1+',
  meson_version: '>= 0.43',
)

gnome = import('gnome')
i18n = import('i18n')

# Option
install_contractor_file = get_option('contractor')
iso_639_xml = get_option('iso_639_xml')
iso_3166_xml = get_option('iso_3166_xml')
reference_tracking = get_option('ref_tracking')
poodle = get_option('poodle')
enable_valadoc = get_option('valadoc')

# Some variables
cc = meson.get_compiler('c')
valac = meson.get_compiler('vala')
config_h_dir = include_directories('.')
geary_prefix = get_option('prefix')
bindir = join_paths(geary_prefix, get_option('bindir'))
datadir = join_paths(geary_prefix, get_option('datadir'))
libdir = join_paths(geary_prefix, get_option('libdir'))
locale_dir = join_paths(geary_prefix, get_option('localedir'))
po_dir = join_paths(meson.source_root(), 'po')
vapi_dir = join_paths(meson.source_root(), 'bindings', 'vapi')
metadata_dir = join_paths(meson.source_root(), 'bindings', 'metadata')
web_extensions_dir = join_paths(libdir, 'geary', 'web-extensions')

# Make sure Meson can find our custom VAPI's
add_project_arguments([
    '--vapidir', vapi_dir,
    '--metadatadir', metadata_dir,
  ],
  language: 'vala'
)

#
# Required libraries and other dependencies
#

target_glib = '2.54' # Also passed to valac, so don't include a point rev
target_gtk = '3.22.26'
target_webkit = '2.20'

# Primary deps
glib = dependency('glib-2.0', version: '>=' + target_glib)
gmime = dependency('gmime-2.6', version: '>= 2.6.17')
gtk = dependency('gtk+-3.0', version: '>=' + target_gtk)
sqlite = dependency('sqlite3', version: '>= 3.12')
webkit2gtk = dependency('webkit2gtk-4.0', version: '>=' + target_webkit)

# Secondary deps - keep sorted alphabetically
enchant = dependency('enchant-2', version: '>=2.1', required: false) # see below
gck = dependency('gck-1')
gcr = dependency('gcr-3', version: '>= 3.10.1')
gdk = dependency('gdk-3.0', version: '>=' + target_gtk)
gee = dependency('gee-0.8', version: '>= 0.8.5')
gio = dependency('gio-2.0', version: '>=' + target_glib)
goa = dependency('goa-1.0')
gthread = dependency('gthread-2.0', version: '>=' + target_glib)
iso_codes = dependency('iso-codes')
javascriptcoregtk = dependency('javascriptcoregtk-4.0', version: '>=' + target_webkit)
json_glib = dependency('json-glib-1.0', version: '>= 1.0')
libcanberra = dependency('libcanberra', version: '>= 0.28')
libmath = cc.find_library('m')
libnotify = dependency('libnotify', version: '>= 0.7.5')
libsecret = dependency('libsecret-1', version: '>= 0.11')
libsoup = dependency('libsoup-2.4', version: '>= 2.48')
libunwind_dep = dependency(
  'libunwind', version: '>= 1.1', required: not get_option('libunwind_optional')
)
libunwind_generic_dep = dependency(
  'libunwind-generic', version: '>= 1.1', required: not get_option('libunwind_optional')
)
libxml = dependency('libxml-2.0', version: '>= 2.7.8')
posix = valac.find_library('posix')
webkit2gtk_web_extension = dependency('webkit2gtk-web-extension-4.0', version: '>=' + target_webkit)

# Can currently use either Enchant 1 or 2
if not enchant.found()
  enchant = dependency('enchant', version: '>=1.6')
endif

if libunwind_dep.found()
  # Libunwind system dependencies above ensures appropriate versions,
  # but this declared depencency is what we actually build against so we
  # can include the custom VAPI correctly. We need to add unwind_lib to
  # the search path for these so Flatpak builds can find the C lib.
  unwind_lib = libunwind_dep.get_pkgconfig_variable('libdir')
  libunwind = declare_dependency(
     dependencies: [
       valac.find_library('libunwind', dirs: [vapi_dir, unwind_lib]),
       cc.find_library('libunwind', dirs: unwind_lib),
       cc.find_library('libunwind-generic', dirs: unwind_lib)
     ],
   )
endif

# Optional dependencies
appstream_util = find_program('appstream-util', required: false)
desktop_file_validate = find_program('desktop-file-validate', required: false)
libunity = dependency('unity', version: '>= 5.12.0', required: false)
libmessagingmenu = meson.get_compiler('c').find_library('libmessaging-menu', required: false)

# Ensure SQLite was built correctly
if not cc.has_header_symbol('sqlite3.h', 'SQLITE_DBCONFIG_ENABLE_FTS3_TOKENIZER', dependencies: sqlite)
  error('SQLite3 is missing FTS3 tokenizer support. Please compile it with -DSQLITE_ENABLE_FTS3.\n'
        + 'See https://bugzilla.gnome.org/show_bug.cgi?id=763203 for details.')
endif

#
# Build glue
#

if enable_valadoc
  valadoc = find_program('valadoc')
endif

# Language detection
iso_codes_dir = join_paths(iso_codes.get_pkgconfig_variable('prefix'), 'share', 'xml', 'iso-codes')
if iso_639_xml == ''
  iso_639_xml = join_paths(iso_codes_dir, 'iso_639.xml')
endif
if iso_3166_xml == ''
  iso_3166_xml = join_paths(iso_codes_dir, 'iso_3166.xml')
endif
files(iso_639_xml, iso_3166_xml) # Check to make sure these exist

# Configuration
conf = configuration_data()
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf.set_quoted('G_LOG_DOMAIN', meson.project_name())
conf.set_quoted('PACKAGE_NAME', meson.project_name())
conf.set_quoted('PACKAGE_STRING', '@0@-@1@'.format(meson.project_name(), meson.project_version()))
conf.set_quoted('PACKAGE_VERSION', meson.project_version())
conf.set_quoted('_BUILD_ROOT_DIR', meson.build_root())
conf.set_quoted('_SOURCE_ROOT_DIR', meson.source_root())
conf.set_quoted('_GSETTINGS_DIR', join_paths(meson.build_root(), 'desktop'))
conf.set_quoted('_INSTALL_PREFIX', geary_prefix)
conf.set_quoted('_WEB_EXTENSIONS_DIR', web_extensions_dir)
conf.set_quoted('LANGUAGE_SUPPORT_DIRECTORY', locale_dir)
conf.set_quoted('ISO_CODE_639_XML', iso_639_xml)
conf.set_quoted('ISO_CODE_3166_XML', iso_3166_xml)
conf.set('HAVE_LIBMESSAGINGMENU', libmessagingmenu.found())
conf.set('HAVE_LIBUNITY', libunity.found())
conf.set('HAVE_FTS3_TOKENIZE', true)
conf.set('VERSION', meson.project_version())
conf.set('GCR_API_SUBJECT_TO_CHANGE', true)
configure_file(output: 'config.h', configuration: conf)

# Post-install scripts
meson.add_install_script(join_paths('build-aux', 'post_install.py'))

# Subfolders
subdir('desktop')
subdir('help')
subdir('icons')
subdir('po')
subdir('sql')
subdir('ui')
subdir('src')
subdir('test')
