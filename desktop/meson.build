foreach desktop_file: [ 'org.gnome.Geary.desktop', 'geary-autostart.desktop' ]
  i18n.merge_file(
    input: desktop_file + '.in',
    output: desktop_file,
    type: 'desktop',
    po_dir: po_dir,
    install: true,
    install_dir: join_paths(datadir, 'applications')
  )
endforeach

# The appdata file
i18n.merge_file(
  input: 'org.gnome.Geary.appdata.xml.in',
  output: 'org.gnome.Geary.appdata.xml',
  type: 'xml',
  po_dir: po_dir,
  install: true,
  install_dir: join_paths(datadir, 'metainfo')
)

# Contractor file (Elementary OS)
if install_contractor_file

  msgfmt = find_program('msgfmt')

  custom_target(
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
