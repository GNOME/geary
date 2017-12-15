project('geary', [ 'vala', 'c' ],
  version: '0.13-dev',
  license: 'LGPL2.1+',
  meson_version: '>= 0.41',
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
datadir = join_paths(geary_prefix, get_option('datadir'))
libdir = join_paths(geary_prefix, get_option('libdir'))
locale_dir = join_paths(geary_prefix, get_option('localedir'))
po_dir = join_paths(meson.source_root(), 'po')
vapi_dir = join_paths(meson.source_root(), 'bindings', 'vapi')
metadata_dir = join_paths(meson.source_root(), 'bindings', 'metadata')

# Make sure Meson can find our custom VAPI's
add_project_arguments([
    '--vapidir', vapi_dir,
    '--metadatadir', metadata_dir,
  ],
  language: 'vala'
)

# Dependencies
target_glib = '2.44' # Also passed to valac, so don't include a point rev
target_gtk = '3.22.0'
target_webkit = '2.16'

posix = valac.find_library('posix')
libmath = cc.find_library('m')
glib = dependency('glib-2.0', version: '>=' + target_glib)
gthread = dependency('gthread-2.0', version: '>=' + target_glib)
gio = dependency('gio-2.0', version: '>=' + target_glib)
gtk = dependency('gtk+-3.0', version: '>=' + target_gtk)
gdk = dependency('gdk-3.0', version: '>=' + target_gtk)
libsoup = dependency('libsoup-2.4', version: '>= 2.48')
gee = dependency('gee-0.8', version: '>= 0.8.5')
libnotify = dependency('libnotify', version: '>= 0.7.5')
libcanberra = dependency('libcanberra', version: '>= 0.28')
sqlite = dependency('sqlite3', version: '>= 3.7.4')
gmime = dependency('gmime-2.6', version: '>= 2.6.17')
libsecret = dependency('libsecret-1', version: '>= 0.11')
libxml = dependency('libxml-2.0', version: '>= 2.7.8')
gcr = dependency('gcr-3', version: '>= 3.10.1')
gobject_introspection = dependency('gobject-introspection-1.0')
webkit2gtk_dep = dependency('webkit2gtk-4.0', version: '>=' + target_webkit)
webkit2gtk_web_extension_dep = dependency('webkit2gtk-web-extension-4.0', version: '>=' + target_webkit)
javascriptcoregtk_lib = cc.find_library('javascriptcoregtk-4.0', version: '>=' + target_webkit)
javascriptcoregtk_vapi = valac.find_library('javascriptcore-4.0', dirs: vapi_dir)
enchant = dependency('enchant', version: '>= 1.6')
libunwind = declare_dependency(
  dependencies: [
    dependency('libunwind', version: '>= 1.1'),
    cc.find_library('libunwind-' + target_machine.cpu_family()),
  ],
)

libunity = dependency('unity', version: '>= 5.12.0', required: false)
libmessagingmenu = meson.get_compiler('c').find_library('libmessaging-menu', required: false)
sqlite = dependency('sqlite3')
if sqlite.version().version_compare('>= 3.12')
  if not cc.has_header_symbol('sqlite3.h', 'SQLITE_DBCONFIG_ENABLE_FTS3_TOKENIZER')
    error('SQLite3 is missing FTS3 tokenizer support. Please compile it with -DSQLITE_ENABLE_FTS3.\n'
           + 'See https://bugzilla.gnome.org/show_bug.cgi?id=763203 for details.')
  endif
else
  # detect that the current sqlite3 library has FTS3 support (at run time)
  runtime_fts3_check = cc.compiles('''
    #include <sqlite3.h>
    #include <stdlib.h>
    int main() {
        sqlite3 *db;
        char tmpfile[] = "sqliteXXXXXX";
        mkstemp(tmpfile);
        if (sqlite3_open(tmpfile, &db) == SQLITE_OK) {
            return sqlite3_exec(db, "CREATE VIRTUAL TABLE mail USING fts3(subject, body);", 0, 0, 0);
        }
        return -1;
    }
  ''', dependencies: sqlite)
  if not runtime_fts3_check
    if sqlite.version().version_compare('< 3.11')
      error('SQLite3 is missing FTS3 support. Please compile it with -DSQLITE_ENABLE_FTS3.')
    else
      error('SQLite3 is missing FTS3 tokenizer support. Please compile it with -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_TOKENIZER.')
    endif
  endif
endif

if enable_valadoc
  valadoc = find_program('valadoc')
endif

# This will provide our custom dependencies, such as webkit2gtk
subdir('bindings')

# Language detection
iso_codes_dir = join_paths('/', 'usr', 'share', 'xml', 'iso-codes')
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
