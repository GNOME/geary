# Custom VAPIs
# NOTE: We can't directly use the dependencies returned by dependency() for
# webkit2gtk (and the web extensions), since Meson then adds the packages from
# the system directories. Since there might be conflicts with our custom VAPI's,
# we need to glue pieces together. We satisfy GCC by looking up the relevant
# include directories and we please the linker by using cc.find_library()


girdir = gobject_introspection.get_pkgconfig_variable('girdir')
webkit2gtk_include = include_directories(
  webkit2gtk_dep.get_pkgconfig_variable('includedir') + '/webkitgtk-4.0'
)

javascriptcoregtk = declare_dependency(
  dependencies: [
    javascriptcoregtk_lib,
    javascriptcoregtk_vapi
  ],
  include_directories: webkit2gtk_include
)

webkit2gtk_vapi = gnome.generate_vapi('webkit2gtk-4.8',
  sources: join_paths(girdir, 'WebKit2-4.0.gir'),
  vapi_dirs: vapi_dir,
  metadata_dirs: metadata_dir,
  packages: [
    'gtk+-3.0',
    'libsoup-2.4',
    'javascriptcore-4.0',
  ],
)

webkit2gtk = declare_dependency(
  dependencies: [
    cc.find_library('webkit2gtk-4.0'),
    glib,
    gtk,
    javascriptcoregtk,
    libsoup,
    webkit2gtk_vapi
  ],
  include_directories: webkit2gtk_include
)


webkit2gtk_web_extension_vapi = gnome.generate_vapi('webkit2gtk-web-extension-4.0',
  sources: [
    join_paths(girdir, 'WebKit2WebExtension-4.0.gir'),
    join_paths('metadata', 'WebKit2WebExtension-4.0-custom.vala'),
  ],
  vapi_dirs: [vapi_dir, meson.current_build_dir()],
  metadata_dirs: metadata_dir,
  packages: [
    'gtk+-3.0',
    'libsoup-2.4',
    'javascriptcore-4.0',
  ],
)

webkit2gtk_web_extension = declare_dependency(
  dependencies: [
    cc.find_library('webkit2gtk-4.0'),
    glib,
    gtk,
    javascriptcoregtk,
    libsoup,
    webkit2gtk_web_extension_vapi,
  ],
  include_directories: webkit2gtk_include
)
