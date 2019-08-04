/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Util.JS.Test : TestCase {

    public Test() {
        base("Util.JS.Test");
        add_test("escape_string", escape_string);
    }

    public void escape_string() throws Error {
        assert(Util.JS.escape_string("\n") == """\n""");
        assert(Util.JS.escape_string("\r") == """\r""");
        assert(Util.JS.escape_string("\t") == """\t""");
        assert(Util.JS.escape_string("\'") == """\'""");
        assert(Util.JS.escape_string("\"") == """\"""");

        assert(Util.JS.escape_string("something…\n") == """something…\n""");
    }
}
