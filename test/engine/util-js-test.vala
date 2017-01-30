/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.JS.Test : Gee.TestCase {

    public Test() {
        base("Geary.JS.Test");
        add_test("escape_string", escape_string);
    }

    public void escape_string() {
        print("\ndata: %s\n", Geary.JS.escape_string("\n"));
        assert(Geary.JS.escape_string("\n") == """\n""");
        assert(Geary.JS.escape_string("\r") == """\r""");
        assert(Geary.JS.escape_string("\t") == """\t""");
        assert(Geary.JS.escape_string("\'") == """\'""");
        assert(Geary.JS.escape_string("\"") == """\"""");

        assert(Geary.JS.escape_string("something…\n") == """something…\n""");
    }
}
