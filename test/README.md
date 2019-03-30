
Automated Test Infrastructure
=============================

Geary currently supports three types of automated tests:

 * Engine unit tests
 * Client (GTK and JavaScript) unit tests
 * Server integration tests

Unit tests
----------

Unit tests test individual functions, in general avoid doing any I/O
so they are fast, and can be run automatically.

The engine and client unit tests are hooked up to the Meson build, so
you can use Meson's test infrastructure to build and run them. These
are run automatically as part of the Gitlab CI process and if you use
the development Makefile, you can execute them locally by simply
calling:

    make test

The engine tests can be run headless (i.e. without an X11 or Wayland
session), but the client tests require a functioning display since
they execute GTK code.

Integration tests
-----------------

Integration tests run Geary's network code against actual servers, to
ensure that the code also works in the real world.

The integration tests are built by default, but not currently hooked
up to Meson and are not automatically run by Gitlab CI, since they
require multiple working servers, network connection to the servers,
and login credentials.

You can run them manually however against any server you have a test
account on, using the following form:

    build/test/test-integration PROTOCOL PROVIDER [HOSTNAME] LOGIN PASSWORD

For example, to test against GMail's IMAP service:

    build/test/test-integration imap gmail test@gmail.com p455w04d

If `PROVIDER` is `other`, then `HOSTNAME` is required.

The easiest way to test against a number of different servers at the
moment is to create a test account for each, then write a shell script
or similar to execute the tests against each in turn.
