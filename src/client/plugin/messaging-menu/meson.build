
plugin_name = 'messaging-menu'

if libmessagingmenu_dep.found()
  messaging_menu_dependencies = plugin_dependencies

  # The libmessagingmenu dependency in the root meson.build file
  # determines if the lib is present, but since the library uses a
  # broken name for its VAPI we have to fake it and find the C and
  # Vala libs manually
  messaging_menu_dependencies += declare_dependency(
    include_directories: include_directories(
      libmessagingmenu_dep.get_variable(pkgconfig: 'includedir')
    ),
    dependencies: [
      valac.find_library('MessagingMenu-1.0', dirs: [ '/usr/share/vala/vapi' ]),
      cc.find_library('messaging-menu'),
    ]
  )

  plugin_src = files(plugin_name + '.vala')
  plugin_data = plugin_name + plugin_data_suffix
  plugin_dest = plugins_dir / plugin_name

  shared_module(
    # Use a non-standard name for the lib since the standard one
    # conflicts with libmessagingmenu and causes linking to fail
    'unity-' + plugin_name,
    sources: plugin_src,
    dependencies: messaging_menu_dependencies,
    include_directories: config_h_dir,
    vala_args: geary_vala_args,
    c_args: plugin_c_args,
    install: true,
    install_dir: plugin_dest,
    install_rpath: client_lib_dir,
  )

  custom_target(
    plugin_data,
    input: files(plugin_data + plugin_data_src_suffix),
    output: plugin_data,
    command: msgfmt_plugin_cmd,
    install: true,
    install_dir: plugin_dest
  )
endif
