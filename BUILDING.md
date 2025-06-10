Building and running Geary
==========================

Geary uses the [Meson](http://mesonbuild.com) and
[Ninja](https://ninja-build.org) build systems. You will need these
and a number of other development libraries installed to build
Geary. See the Dependencies section below for a list of packages to
install.

Building, running, tests and documentation
------------------------------------------

To build Geary, run the following commands from the top-level
directory of the source code repository:

```
meson build
ninja -C build
```

Once built, Geary can be run directly from the build directory without
being installed:

```
./build/src/geary
```

Note that certain desktop integration (such as being listed in an
application menu) requires full installation to work correctly.

To run the unit tests, use the Meson `test` command:

```
meson test -C build
```

API documentation will be built if `valadoc` is installed.

Consult the Meson documentation for information about configuring the
build, installing, and so on.

Build profiles
--------------

Geary can be built using a number of different build profiles, which
determine things like the application id, the location of stored data,
the name of the application, icon and other visual elements.

These can be set at build configuration time using the Meson `setup`
and `configure` commands, using the standard `-Dprofile=…` option. See
the `profile` option in `meson_options.txt` for the current list of
supported types.

Maintainers must use the `release` build profile when packaging Geary,
otherwise when run it will use branding and data locations intended
for development only.

Note that setting the profile does not alter such things as compiler
options, use the standard Meson `--buildtype` argument for that.

Consult the Meson documentation for more information about configuring
options.

Dependencies
------------

Building Geary requires the following major libraries and tools:

 * GTK 3
 * WebKitGTK (Specifically the API 4.1 variant)
 * SQLite 3
 * Vala

See the `meson.build` file in the top-level directory for the complete
list of required dependencies and minimum versions.

Geary requires SQLite is built with both FTS3 and FTS5 support. Ensure
`--enable-fts5`, `-DSQLITE_ENABLE_FTS3` and
`-DSQLITE_ENABLE_FTS3_PARENTHESIS` are passed to the SQLite configure
script.

All required libraries and tools are available from major Linux
distribution's package repositories:

Installing dependencies on Fedora
---------------------------------

Install them by running this command:

```
sudo dnf install meson vala desktop-file-utils enchant2-devel \
    folks-devel gcr3-devel glib2-devel gmime30-devel \
    gnome-online-accounts-devel gspell-devel gsound-devel \
    gtk3-devel iso-codes-devel itstool json-glib-devel \
    libgee-devel libhandy1-devel \
    libpeas-devel libsecret-devel libicu-devel libstemmer-devel \
    libunwind-devel libxml2-devel libytnef-devel sqlite-devel \
    webkitgtk4.1-devel
```

Installing dependencies on Ubuntu/Debian
----------------------------------------

Install them by running this command:

```
sudo apt-get install meson build-essential valac \
    desktop-file-utils iso-codes gettext itstool \
    libenchant-2-dev libfolks-dev \
    libgcr-3-dev libgee-0.8-dev libglib2.0-dev libgmime-3.0-dev \
    libgoa-1.0-dev libgspell-1-dev libgsound-dev libgtk-3-dev \
    libjson-glib-dev libhandy-1-dev libicu-dev libpeas-dev \
    libsecret-1-dev libsqlite3-dev libstemmer-dev libunwind-dev \
    libwebkit2gtk-4.1-dev libxml2-dev libytnef0-dev
```

And for Ubuntu Messaging Menu integration:

```
sudo apt-get install libmessaging-menu-dev
```

Updating DarkReader plugin
--------------------------

We're using [DarkReader API](https://github.com/darkreader/darkreader) for dark mode.

To update it, download latest version from CDN and save as ui/darkreader.js

 - [unpkg](https://unpkg.com/darkreader/)
 - [jsDelivr](https://www.jsdelivr.com/package/npm/darkreader)


```sh
curl https://cdn.jsdelivr.net/npm/darkreader/darkreader.js --output ui/darkreader.js
```

---
Copyright © 2016 Software Freedom Conservancy Inc.
Copyright © 2018-2020 Michael Gratton <mike@vee.net>
