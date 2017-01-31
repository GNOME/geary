/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

int main(string[] args) {
    // POODLE SSLv3: This disables SSLv3 inside of GnuTLS preventing the exploit described at:
    // http://googleonlinesecurity.blogspot.co.uk/2014/10/this-poodle-bites-exploiting-ssl-30.html
    // Although it's extremely unlikely Geary presents an open attack vector (because Javascript
    // must be enabled in WebKit), it still makes sense to disable this version of SSL.  See more
    // at https://bugzilla.gnome.org/show_bug.cgi?id=738633
    //
    // This *must* be done before any threads are created, as their copy of the envvars is not
    // updated with this call.  overwrite is set to false to allow the user to override the priority
    // string if they need to.
    //
    // Packages can disable this fix with the --disable-poodle-ssl3 configure option.
#if !DISABLE_POODLE
    Environment.set_variable("G_TLS_GNUTLS_PRIORITY", "NORMAL:%COMPAT:%LATEST_RECORD_VERSION:!VERS-SSL3.0", false);
#endif

    // Disable WebKit2 accelerated compositing here while we can't
    // depend on there being an API to do it. AC isn't appropriate
    // since Geary is likely to be doing anything that requires
    // acceleration, and it is costs a lot in terms of performance
    // and memory:
    // https://lists.webkit.org/pipermail/webkit-gtk/2016-November/002863.html
    Environment.set_variable("WEBKIT_DISABLE_COMPOSITING_MODE", "1", true);

    GearyApplication app = new GearyApplication();

    int ec = app.run(args);

#if REF_TRACKING
    Geary.BaseObject.dump_refs(stdout);
#endif

    return ec;
}

