
plugin_name = 'messaging-menu'

if libmessagingmenu_dep.found()
  messaging_menu_dependencies = plugin_dependencies

  # The libmessagingmenu dependency in the root meson.build file
  # determines if the lib is present, but since the library uses a
  # broken name for its VAPI we have to fake it and find the C and
  # Vala libs manually
  messaging_menu_dependencies += declare_dependency(
    include_directories: include_directories(
      libmessagingmenu_dep.get_pkgconfig_variable('includedir')
    ),
    dependencies: [
      valac.find_library('MessagingMenu-1.0', dirs: [ '/usr/share/vala/vapi' ]),
      cc.find_library('messaging-menu'),
    ]
  )

  plugin_src = join_paths(plugin_name + '.vala')
  plugin_data = join_paths(plugin_name + '.plugin')
  plugin_dest = join_paths(plugins_dir, plugin_name)

  shared_module(
    # Use a non-standard name for the lib since the standard one
    # conflicts with libmessagingmenu and causes linking to fail
    plugin_name + '-geary',
    sources: plugin_src,
    dependencies: messaging_menu_dependencies,
    vala_args: geary_vala_options,
    c_args: plugin_cflags,
    install: true,
    install_dir: plugin_dest
  )

  i18n.merge_file(
    input: plugin_data + '.in',
    output: plugin_data,
    type: 'desktop',
    po_dir: po_dir,
    install: true,
    install_dir: plugin_dest
  )
endif
