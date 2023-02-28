
plugin_name = 'mail-merge'

plugin_src = files(
  plugin_name + '.vala'
)
plugin_data = plugin_name + plugin_data_suffix
plugin_dest = plugins_dir / plugin_name

lib_src = files(
  'mail-merge-folder.vala',
  'mail-merge-csv.vala',
  'mail-merge-processor.vala',
)

test_src = files(
  'mail-merge-test-processor.vala',
  'mail-merge-test-reader.vala',
  'mail-merge-test.vala'
)

lib = static_library(
  'util',
  sources: lib_src,
  dependencies: plugin_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_vala_args,
  c_args: plugin_c_args,
  install: false
)

plugin = shared_module(
  plugin_name,
  sources: plugin_src,
  dependencies: plugin_dependencies,
  link_with: lib,
  include_directories: config_h_dir,
  vala_args: geary_vala_args,
  c_args: plugin_c_args,
  install: true,
  install_dir: plugin_dest,
  install_rpath: client_lib_dir
)

custom_target(
  plugin_data,
  input: files(plugin_data + plugin_data_src_suffix),
  output: plugin_data,
  command: msgfmt_plugin_cmd,
  install: true,
  install_dir: plugin_dest
)

plugin_test = executable(
  'plugin-test',
  test_src,
  dependencies: plugin_dependencies + [ vala_unit_dep ],
  link_with: lib,
  include_directories: config_h_dir,
  vala_args: geary_vala_args,
  c_args: plugin_c_args,
  install: false
)

test(plugin_name + '-test', plugin_test)
