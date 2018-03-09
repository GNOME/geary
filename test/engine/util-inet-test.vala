/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Inet.Test : TestCase {

    public Test() {
        base("Geary.Inet.Test");
        add_test("is_valid_display_host_dns", is_valid_display_host_dns);
        add_test("is_valid_display_host_ipv4", is_valid_display_host_ipv4);
        add_test("is_valid_display_host_ipv6", is_valid_display_host_ipv6);
    }

    public void is_valid_display_host_dns() throws Error {
        assert(is_valid_display_host("foo"));
        assert(is_valid_display_host("Foo"));
        assert(is_valid_display_host("Ƒoo"));
        assert(is_valid_display_host("2oo"));
        assert(is_valid_display_host("foo."));
        assert(is_valid_display_host("foo.bar"));
        assert(is_valid_display_host("foo.bar."));
        assert(is_valid_display_host("foo-bar"));

        assert(!is_valid_display_host(""));
        assert(!is_valid_display_host(" "));
        assert(!is_valid_display_host(" foo"));
        assert(!is_valid_display_host(" foo "));
        assert(!is_valid_display_host("foo bar"));
        assert(!is_valid_display_host("-foo"));
        assert(!is_valid_display_host("foo-"));
    }

    public void is_valid_display_host_ipv4() throws Error {
        assert(is_valid_display_host("123.123.123.123"));
        assert(is_valid_display_host("127.0.0.1"));

        // These are valid host names
        //assert(!is_valid_display_host("123"));
        //assert(!is_valid_display_host("123.123"));
        //assert(!is_valid_display_host("123.123.123"));
        //assert(is_valid_display_host("666.123.123.123"));
    }

    public void is_valid_display_host_ipv6() throws Error {
        assert(is_valid_display_host("FEDC:BA98:7654:3210:FEDC:BA98:7654:3210"));
        assert(is_valid_display_host("1080:0:0:0:8:800:200C:4171"));
        assert(is_valid_display_host("3ffe:2a00:100:7031::1"));
        assert(is_valid_display_host("1080::8:800:200C:417A"));
        assert(is_valid_display_host("::1"));
        assert(is_valid_display_host("::192.9.5.5"));
        assert(is_valid_display_host("::FFFF:129.144.52.38"));
        assert(is_valid_display_host("2010:836B:4179::836B:4179"));

        assert(!is_valid_display_host("1200::AB00:1234::2552:7777:1313"));
        assert(!is_valid_display_host("1200:0000:AB00:1234:O000:2552:7777:1313"));
    }

}
