#
# Desktop files
#

desktop_src = [
  'org.gnome.Geary.desktop',
  'geary-autostart.desktop'
]

foreach desktop_file: desktop_src
  desktop_merged = i18n.merge_file(
    input: desktop_file + '.in',
    output: desktop_file,
    type: 'desktop',
    po_dir: po_dir,
    install: true,
    install_dir: join_paths(datadir, 'applications')
  )
  if desktop_file_validate.found()
    test(
      desktop_file + '-validate',
      desktop_file_validate,
      args: [ desktop_merged.full_path() ]
    )
  endif
endforeach

#
# Appdata file
#

appdata_file = 'org.gnome.Geary.appdata.xml'

appdata_merged = i18n.merge_file(
  input: appdata_file + '.in',
  output: appdata_file,
  type: 'xml',
  po_dir: po_dir,
  install: true,
  install_dir: join_paths(datadir, 'metainfo')
)

if appstream_util.found()
  test(
    appdata_file + '-validate',
    appstream_util,
    args: [
      'validate-relax', '--nonet', appdata_merged.full_path()
    ]
  )
endif

#
# Contractor file (Elementary OS)
#

if install_contractor_file
  # Call msgfmt manually since gettext won't otherwise translate the
  # Description field. See merge req !50.
  msgfmt = find_program('msgfmt')

  custom_target('geary-attach-contract',
    input: 'geary-attach.contract.desktop.in',
    output: 'geary-attach.contract',
    command: [msgfmt, '--desktop', '--keyword=Description', '--template', '@INPUT@', '-d', po_dir, '-o', '@OUTPUT@'],
    install: true,
    install_dir: join_paths(datadir, 'contractor')
  )

  install_data('geary-attach',
    install_dir: bindir,
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
  install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)

#
# DBus services
#

service_conf = configuration_data()
service_conf.set('bindir', bindir)

configure_file(
  input: 'org.gnome.Geary.service.in',
  output: 'org.gnome.Geary.service',
  configuration: service_conf,
  install: true,
  install_dir: dbus_services_dir
)
