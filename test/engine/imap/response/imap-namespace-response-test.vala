/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.NamespaceResponseTest : Gee.TestCase {


    public NamespaceResponseTest() {
        base("Geary.Imap.NamespaceResponseTest");
        add_test("test_minimal", test_minimal);
        add_test("test_complete", test_complete);
        add_test("test_cyrus", test_cyrus);
        add_test("test_anonymous", test_anonymous);
    }

    public void test_minimal() {
        // * NAMESPACE NIL NIL NIL
        try {
            ServerData data = newNamespaceServerData(null, null, null);

            NamespaceResponse response = NamespaceResponse.decode(data);
            assert(response.personal == null);
            assert(response.user == null);
            assert(response.shared == null);
        } catch (Error err) {
            assert_not_reached();
        }
    }

    public void test_complete() {
        // * NAMESPACE (("" "/")) (("~" "/")) (("#shared/" "/")
        ListParameter personal = new ListParameter();
        personal.add(newNamespace("", "/"));
        ListParameter user = new ListParameter();
        user.add(newNamespace("~", "/"));
        ListParameter shared = new ListParameter();
        shared.add(newNamespace("#shared/", "/"));
        try {
            ServerData data = newNamespaceServerData(personal, user, shared);

            NamespaceResponse response = NamespaceResponse.decode(data);
            assert(response.personal != null);
            assert(response.personal.size == 1);
            assert(response.personal[0].prefix == "");
            assert(response.personal[0].delim == "/");

            assert(response.user != null);
            assert(response.user.size == 1);
            assert(response.user[0].prefix == "~");
            assert(response.user[0].delim == "/");

            assert(response.shared != null);
            assert(response.shared.size == 1);
            assert(response.shared[0].prefix == "#shared/");
            assert(response.shared[0].delim == "/");
        } catch (Error err) {
            assert_not_reached();
        }
    }

    public void test_cyrus() {
        // * NAMESPACE (("INBOX." ".")) NIL (("" "."))
        ListParameter personal = new ListParameter();
        personal.add(newNamespace("INBOX.", "."));
        ListParameter shared = new ListParameter();
        shared.add(newNamespace("", "."));
        try {
            ServerData data = newNamespaceServerData(personal, null, shared);

            NamespaceResponse response = NamespaceResponse.decode(data);
            assert(response.personal != null);
            assert(response.personal[0].prefix == "INBOX.");
            assert(response.personal[0].delim == ".");
            assert(response.user == null);
            assert(response.shared != null);
            assert(response.shared.size == 1);
            assert(response.shared[0].prefix == "");
            assert(response.shared[0].delim == ".");
        } catch (Error err) {
            assert_not_reached();
        }
    }

    public void test_anonymous() {
        // * NAMESPACE NIL NIL (("" "."))
        ListParameter shared = new ListParameter();
        shared.add(newNamespace("", ","));
        try {
            ServerData data = newNamespaceServerData(null, null, shared);

            NamespaceResponse response = NamespaceResponse.decode(data);
            assert(response.personal == null);
            assert(response.user == null);
            assert(response.shared != null);
            assert(response.shared.size == 1);
            assert(response.shared[0].prefix == "");
            assert(response.shared[0].delim == ",");
        } catch (Error err) {
            assert_not_reached();
        }
    }

    private ServerData newNamespaceServerData(ListParameter? personal,
                                              ListParameter? users,
                                              ListParameter? shared)
    throws Error {
        RootParameters root = new RootParameters();
        root.add(new UnquotedStringParameter("*"));
        root.add(new AtomParameter("namespace"));
        // Vala's ternary op support is all like :'(
        if (personal == null)
            root.add(NilParameter.instance);
        else
            root.add(personal);

        if (users == null)
            root.add(NilParameter.instance);
        else
            root.add(users);

        if (shared == null)
            root.add(NilParameter.instance);
        else
            root.add(shared);

        return new ServerData.migrate(root);
    }

    private ListParameter newNamespace(string prefix, string? delim) {
        ListParameter ns = new ListParameter();
        ns.add(new QuotedStringParameter(prefix));
        ns.add(delim == null ? (Parameter) NilParameter.instance : new QuotedStringParameter(delim));
        return ns;
    }
}
