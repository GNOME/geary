/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.TlsNegotiationMethodTest : TestCase {


    public TlsNegotiationMethodTest() {
        base("Geary.TlsNegotiationMethodTest");
        add_test("to_value", to_value);
        add_test("for_value", for_value);
    }

    public void to_value() throws GLib.Error {
        assert_equal(TlsNegotiationMethod.START_TLS.to_value(), "start-tls");
    }

    public void for_value() throws GLib.Error {
        assert_equal(
            TlsNegotiationMethod.for_value("start-tls").to_string(),
            TlsNegotiationMethod.START_TLS.to_string(),
            "start-tls"
        );
        assert_equal(
            TlsNegotiationMethod.for_value("Start-TLS").to_string(),
            TlsNegotiationMethod.START_TLS.to_string(),
            "Start-TLS"
        );
    }

}