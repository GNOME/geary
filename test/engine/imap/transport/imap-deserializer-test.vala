/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.DeserializerTest : TestCase {


    protected enum Expect { MESSAGE, EOS, DESER_FAIL; }

    private const string ID = "test";
    private const string EOL = "\r\n";

    private Deserializer? deser = null;
    private MemoryInputStream? stream = null;


    public DeserializerTest() {
        base("Geary.Imap.DeserializerTest");
        add_test("gmail_greeting", gmail_greeting);
        add_test("cyrus_2_4_greeting", cyrus_2_4_greeting);
        add_test("aliyun_greeting", aliyun_greeting);

        add_test("invalid_atom_prefix", invalid_atom_prefix);

        add_test("gmail_flags", gmail_flags);
        add_test("gmail_permanent_flags", gmail_permanent_flags);
        add_test("cyrus_flags", cyrus_flags);

        add_test("runin_special_flag", runin_special_flag);
        add_test("invalid_flag_prefix", invalid_flag_prefix);

        add_test("instant_eos", instant_eos);
        add_test("bye_eos", bye_eos);
    }

    public override void set_up() {
        this.stream = new MemoryInputStream();
        this.deser = new Deserializer(ID, this.stream);
    }

    public override void tear_down() {
        this.deser.stop_async.begin((obj, ret) => { async_complete(ret); });
        async_result();
    }

    public void gmail_greeting() throws Error {
        string greeting = "* OK Gimap ready for requests from 115.187.245.46 c194mb399904375ivc";
        this.stream.add_data(greeting.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == greeting);
    }

    public void cyrus_2_4_greeting() throws Error {
        string greeting = "* OK [CAPABILITY IMAP4rev1 LITERAL+ ID ENABLE AUTH=PLAIN SASL-IR] mogul Cyrus IMAP v2.4.12-Debian-2.4.12-2 server ready";
        this.stream.add_data(greeting.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == greeting);
    }

    public void aliyun_greeting() throws Error {
        string greeting = "* OK AliYun IMAP Server Ready(10.147.40.164)";
        string parsed = "* OK AliYun IMAP Server Ready (10.147.40.164)";
        this.stream.add_data(greeting.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == parsed);
    }

    public void invalid_atom_prefix() throws Error {
        string flags = """* OK %atom""";
        this.stream.add_data(flags.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.DESER_FAIL, (obj, ret) => { async_complete(ret); });
        this.process.end(async_result());
    }

    public void gmail_flags() throws Error {
        string flags = """* FLAGS (\Answered \Flagged \Draft \Deleted \Seen $NotPhishing $Phishing)""";
        this.stream.add_data(flags.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == flags);
    }

    public void gmail_permanent_flags() throws Error {
        string flags = """* OK [PERMANENTFLAGS (\Answered \Flagged \Draft \Deleted \Seen $NotPhishing $Phishing \*)] Flags permitted.""";
        this.stream.add_data(flags.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == flags);
    }

    public void cyrus_flags() throws Error {
        string flags = """* 2934 FETCH (FLAGS (\Answered \Seen $Quuxo::Spam::Trained) UID 3041)""";
        this.stream.add_data(flags.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == flags);
    }

    public void runin_special_flag() throws Error {
        // since we must terminate a special flag upon receiving the
        // '*', the following atom will be treated as a run-on but
        // distinct atom.
        string flags = """* OK \*atom""";
        string expected = """* OK \* atom""";
        this.stream.add_data(flags.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, (obj, ret) => { async_complete(ret); });
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == expected);
    }

    public void invalid_flag_prefix() throws Error {
        string flags = """* OK \%atom""";
        this.stream.add_data(flags.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.DESER_FAIL, (obj, ret) => { async_complete(ret); });
        this.process.end(async_result());
    }

    public void instant_eos() throws Error {
        this.process.begin(Expect.EOS, (obj, ret) => { async_complete(ret); });
        this.process.end(async_result());
        assert(this.deser.is_halted());
    }

    public void bye_eos() throws Error {
        string bye = """* OK bye""";
        this.stream.add_data(bye.data);

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

        return message;
    }

}
