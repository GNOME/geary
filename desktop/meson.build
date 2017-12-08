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
  i18n.merge_file(
    input: 'geary-attach.contract.desktop.in',
    output: 'geary-attach.contract',
    type: 'desktop',
    po_dir: po_dir,
    install: true,
    install_dir: join_paths(datadir, 'contractor')
  )

  install_data('geary-attach',
    install_dir: bindir,
  )
endif

# GSettings schemas
geary_compiled_schema = gnome.compile_schemas() # Always compile, even if necessary. Makes sure it's valid.
install_data('org.gnome.Geary.gschema.xml',
  install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
