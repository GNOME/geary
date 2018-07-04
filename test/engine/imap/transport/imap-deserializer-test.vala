/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.DeserializerTest : Gee.TestCase {


    protected enum Expect { MESSAGE, EOS, DESER_FAIL; }

    private const string ID = "test";
    private const string EOL = "\r\n";

    private Deserializer? deser = null;
    private MemoryInputStream? stream = null;


    public DeserializerTest() {
        base("Geary.Imap.DeserializerTest");
        add_test("test_gmail_greeting", test_gmail_greeting);
        add_test("test_cyrus_2_4_greeting", test_cyrus_2_4_greeting);
        add_test("test_aliyun_greeting", test_aliyun_greeting);

        add_test("test_invalid_atom_prefix", test_invalid_atom_prefix);

        add_test("test_gmail_flags", test_gmail_flags);
        add_test("test_gmail_permanent_flags", test_gmail_permanent_flags);
        add_test("test_cyrus_flags", test_cyrus_flags);

        add_test("test_runin_special_flag", test_runin_special_flag);
        add_test("test_invalid_flag_prefix", test_invalid_flag_prefix);

        add_test("test_instant_eos", test_instant_eos);
        add_test("test_bye_eos", test_bye_eos);
    }

    public override void set_up() {
        this.stream = new MemoryInputStream();
        this.deser = new Deserializer(ID, this.stream);
    }

    public override void tear_down() {
        this.deser.stop_async.begin((obj, ret) => { async_complete(ret); });
        async_result();
    }

    public void test_gmail_greeting() {
        string greeting = "* OK Gimap ready for requests from 115.187.245.46 c194mb399904375ivc";
        this.stream.add_data(greeting.data, g_free);
        this.stream.add_data(EOL.data, g_free);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == greeting);
    }

    public void test_cyrus_2_4_greeting() {
        string greeting = "* OK [CAPABILITY IMAP4rev1 LITERAL+ ID ENABLE AUTH=PLAIN SASL-IR] mogul Cyrus IMAP v2.4.12-Debian-2.4.12-2 server ready";
        this.stream.add_data(greeting.data, g_free);
        this.stream.add_data(EOL.data, g_free);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == greeting);
    }

    public void test_aliyun_greeting() {
        string greeting = "* OK AliYun IMAP Server Ready(10.147.40.164)";
        string parsed = "* OK AliYun IMAP Server Ready (10.147.40.164)";
        this.stream.add_data(greeting.data, g_free);
        this.stream.add_data(EOL.data, g_free);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == parsed);
    }

    public void test_invalid_atom_prefix() {
        string flags = """* OK %atom""";
        this.stream.add_data(flags.data, g_free);
        this.stream.add_data(EOL.data, g_free);

        this.process.begin(Expect.DESER_FAIL, (obj, ret) => { async_complete(ret); });
        this.process.end(async_result());
    }

    public void test_gmail_flags() {
        string flags = """* FLAGS (\Answered \Flagged \Draft \Deleted \Seen $NotPhishing $Phishing)""";
        this.stream.add_data(flags.data, g_free);
        this.stream.add_data(EOL.data, g_free);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == flags);
    }

    public void test_gmail_permanent_flags() {
        string flags = """* OK [PERMANENTFLAGS (\Answered \Flagged \Draft \Deleted \Seen $NotPhishing $Phishing \*)] Flags permitted.""";
        this.stream.add_data(flags.data, g_free);
        this.stream.add_data(EOL.data, g_free);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == flags);
    }

    public void test_cyrus_flags() {
        string flags = """* 2934 FETCH (FLAGS (\Answered \Seen $Quuxo::Spam::Trained) UID 3041)""";
        this.stream.add_data(flags.data, g_free);
        this.stream.add_data(EOL.data, g_free);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == flags);
    }

    public void test_runin_special_flag() {
        // since we must terminate a special flag upon receiving the
        // '*', the following atom will be treated as a run-on but
        // distinct atom.
        string flags = """* OK \*atom""";
        string expected = """* OK \* atom""";
        this.stream.add_data(flags.data, g_free);
        this.stream.add_data(EOL.data, g_free);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == expected);
    }

    public void test_invalid_flag_prefix() {
        string flags = """* OK \%atom""";
        this.stream.add_data(flags.data, g_free);
        this.stream.add_data(EOL.data, g_free);

        this.process.begin(Expect.DESER_FAIL, (obj, ret) => { async_complete(ret); });
        this.process.end(async_result());
    }

    public void test_instant_eos() {
        this.process.begin(Expect.EOS, (obj, ret) => { async_complete(ret); });
        this.process.end(async_result());
        assert(this.deser.is_halted());
    }

    public void test_bye_eos() {
        string bye = """* OK bye""";
        this.stream.add_data(bye.data, g_free);

        bool eos = false;
        this.deser.eos.connect(() => { eos = true; });

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());
        assert(message.to_string() == bye);
        assert(eos);
        assert(this.deser.is_halted());
    }

    protected async RootParameters? process(Expect expected) {
        RootParameters? message = null;
        bool eos = false;
        bool deserialize_failure = false;
        bool receive_failure = false;
        size_t bytes_received = 0;

        this.deser.parameters_ready.connect((param) => { message = param; });
        this.deser.bytes_received.connect((count) => { bytes_received += count; });
        this.deser.eos.connect((param) => { eos = true; });
        this.deser.deserialize_failure.connect(() => { deserialize_failure = true; });
        this.deser.receive_failure.connect((err) => { receive_failure = true;});

        this.deser.start_async.begin();
        while (message == null && !receive_failure && !eos && !deserialize_failure) {
            this.main_loop.iteration(true);
        }

        switch (expected) {
        case Expect.MESSAGE:
            assert(message != null);
            assert(bytes_received > 0);
            assert(!eos);
            assert(!deserialize_failure);
            assert(!receive_failure);
            break;

        case Expect.EOS:
            assert(message == null);
            assert(eos);
            assert(!deserialize_failure);
            assert(!receive_failure);
            break;

        case Expect.DESER_FAIL:
            assert(message == null);
            assert(!eos);
            assert(deserialize_failure);
            assert(!receive_failure);
            break;

        default:
            assert_not_reached();
        }

        // Process any remaining async tasks the deserializer might
        // have left over.
        while (this.main_loop.pending()) {
            this.main_loop.iteration(true);
        }

        return message;
    }

}
