project(
  'vala-unit',
  [ 'vala', 'c' ],
  version: '1.0',
  license: 'LGPL2.1+',
  meson_version: '>= 0.50',
)

enable_install = get_option('install')
enable_valadoc = get_option('valadoc')

add_project_arguments(
  [
    '--abi-stability',
    '--enable-checking',
    '--enable-experimental-non-null',
    '--fatal-warnings',
    '--nostdpkg'
  ],
  language: 'vala'
)

target_vala = '0.44'
target_glib = '2.62'

if not meson.get_compiler('vala').version().version_compare('>=' + target_vala)
  error('Vala does not meet minimum required version: ' + target_vala)
endif

gee = dependency('gee-0.8')
gio = dependency('gio-2.0')
glib = dependency('glib-2.0', version: '>=' + target_glib)
gobject = dependency('gobject-2.0')

g_ir_compiler = find_program('g-ir-compiler')
if enable_valadoc
  valadoc = find_program('valadoc')
endif

dependencies = [
  gee,
  gio,
  glib,
  gobject
]

lib_sources = files(
  'src/async-result-waiter.vala',
  'src/collection-assertions.vala',
  'src/expected-call.vala',
  'src/mock-object.vala',
  'src/test-adaptor.vala',
  'src/test-assertions.vala',
  'src/test-case.vala',
)

test_sources = files(
  'test/collection-assertions.vala',
  'test/test-assertions.vala',
  'test/test-driver.vala',
)

package_name = 'ValaUnit'
package_version = '1.0'
package_full = '@0@-@1@'.format(package_name, package_version)
package_vapi = '@0@-@1@'.format(meson.project_name(), package_version)
package_gir = package_full + '.gir'

vala_unit_lib = library(
  meson.project_name(),
  lib_sources,
  dependencies: dependencies,
  # Ensure we always get debug symbols.
  override_options : [
    'debug=true',
    'strip=false',
  ],
  vala_vapi: package_vapi + '.vapi',
  vala_gir: package_gir,
  install: enable_install,
  install_dir: [true, true, true, true]
)

vala_unit_dep = declare_dependency(
  link_with : vala_unit_lib,
  include_directories: include_directories('.')
)

custom_target(
  meson.project_name() + '-typelib',
  command: [
    g_ir_compiler,
    '--output', '@OUTPUT@',
    meson.current_build_dir() / package_gir,
  ],
  output: [package_full + '.typelib'],
  depends: vala_unit_lib,
  install: enable_install,
  install_dir: get_option('libdir') / 'girepository-1.0'
)

if enable_valadoc
  # Hopefully Meson will get baked-in valadoc support, so we don't have
  # to do this any more. https://github.com/mesonbuild/meson/issues/894
  valadoc_dep_args = []
  foreach dep : dependencies
    valadoc_dep_args += '--pkg'
    valadoc_dep_args += dep.name()
  endforeach

  docs = custom_target(
    'valadoc',
    build_by_default: true,
    depends: [vala_unit_lib],
    input: lib_sources,
    output: 'valadoc',
    command: [
      valadoc,
      '--verbose',
      '--force',
      '--fatal-warnings',
      '--package-name=@0@'.format(package_vapi),
      '--package-version=@0@'.format(meson.project_version()),
      '-b', meson.current_source_dir(),
      '-o', '@OUTPUT@',
      '@INPUT@',
    ] + valadoc_dep_args
  )

  if enable_install
    install_subdir(
      meson.current_build_dir() / 'valadoc',
      install_dir: get_option('datadir') / 'doc' / 'vala-unit' / 'valadoc'
    )
  endif
endif

test_driver = executable(
  'test-driver',
  test_sources,
  dependencies: dependencies + [ vala_unit_dep ],
  # Always do a plain debug build to avoid compiler optimsations that
  # might render testing invalid, and to ensure we get debug symbols.
  # Ensure we always get debug symbols.
  override_options : [
    'debug=true',
    'optimization=0',
    'strip=false',
  ],
)

test('tests', test_driver)
