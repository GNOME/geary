#
# Desktop files
#

desktop_output = []
desktop_conf = configuration_data()
desktop_conf.set('appid', geary_id)

desktop_file = i18n.merge_file(
  input: configure_file(
    input: 'org.gnome.Geary.desktop.in.in',
    output: 'org.gnome.Geary.desktop.in',
    configuration: desktop_conf
  ),
  output: '@0@.desktop'.format(geary_id),
  type: 'desktop',
  po_dir: po_dir,
  install: true,
  install_dir: join_paths(data_dir, 'applications')
)
desktop_output += desktop_file

autostart_file = i18n.merge_file(
  input: configure_file(
    input: 'geary-autostart.desktop.in.in',
    output: 'geary-autostart.desktop.in',
    configuration: desktop_conf
  ),
  output: 'geary-autostart.desktop',
  type: 'desktop',
  po_dir: po_dir,
  install: true,
  install_dir: join_paths(data_dir, 'applications')
)
desktop_output += autostart_file

foreach desktop_file: desktop_output
  if desktop_file_validate.found()
    test(
      'desktop-file-validate',
      desktop_file_validate,
      args: [ desktop_file.full_path() ],
      depends: [
        desktop_file,
      ]
    )
  endif
endforeach

#
# Metainfo file
#

metainfo_file = 'org.gnome.Geary.metainfo.xml'

metainfo_merged = i18n.merge_file(
  input: configure_file(
    input: metainfo_file + '.in.in',
    output: metainfo_file + '.in',
    configuration: desktop_conf
  ),
  output: '@0@.metainfo.xml'.format(geary_id),
  type: 'xml',
  po_dir: po_dir,
  install: true,
  install_dir: join_paths(data_dir, 'metainfo')
)

if appstreamcli.found()
  test(
    metainfo_file + '-validate',
    appstreamcli,
    args: [
      'validate', '--no-net', '--explain', metainfo_merged.full_path()
    ],
    depends: [
      metainfo_merged,
    ]
  )
endif

#
# Contractor file (Elementary OS)
#

if get_option('contractor').enabled()
  # Call msgfmt manually since gettext won't otherwise translate the
  # Description field. See merge req !50.
  msgfmt = find_program('msgfmt')

  custom_target('geary-attach-contract',
    input: 'geary-attach.contract.desktop.in',
    output: 'geary-attach.contract',
    command: [msgfmt, '--desktop', '--keyword=Description', '--template', '@INPUT@', '-d', po_dir, '-o', '@OUTPUT@'],
    install: true,
    install_dir: join_paths(data_dir, 'contractor')
  )

  install_data('geary-attach',
    install_dir: bin_dir,
  )
endif

# GSettings schemas.
#
# Compile since it makes sure the schema is valid and is used for both
# running the client locally and for tests.
#
# Note the use of depend_files here is a kludge to ensure that the
# schema is re-compiled if the source changes. This is not supported
# by Meson but it works, so request for official support has been
# added, see: https://github.com/mesonbuild/meson/issues/2770
geary_compiled_schema = gnome.compile_schemas(
  depend_files: files('org.gnome.Geary.gschema.xml'),
)
install_data('org.gnome.Geary.gschema.xml',
  install_dir: join_paths(data_dir, 'glib-2.0', 'schemas'),
)

#
# DBus services
#

service_conf = configuration_data()
service_conf.set('bindir', bin_dir)
service_conf.set('appid', geary_id)

configure_file(
  input: 'org.gnome.Geary.service.in',
  output: '@0@.service'.format(geary_id),
  configuration: service_conf,
  install: true,
  install_dir: dbus_services_dir
)
