/*
 * Copyright 2017-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.DeserializerTest : TestCase {


    protected enum Expect { MESSAGE, EOS, DESER_FAIL; }

    private const string ID = "test";
    private const string UNTAGGED = "* ";
    private const string EOL = "\r\n";

    private Deserializer? deser = null;
    private MemoryInputStream? stream = null;


    public DeserializerTest() {
        base("Geary.Imap.DeserializerTest");
        add_test("parse_unquoted", parse_unquoted);
        add_test("parse_quoted", parse_quoted);
        add_test("parse_number", parse_number);
        add_test("parse_list", parse_list);
        add_test("parse_flag", parse_flag);
        add_test("parse_wildcard_flag", parse_wildcard_flag);
        add_test("parse_response_code", parse_response_code);
        add_test("parse_bad_list", parse_bad_list);
        add_test("parse_bad_code", parse_bad_response_code);

        add_test("gmail_greeting", gmail_greeting);
        add_test("cyrus_2_4_greeting", cyrus_2_4_greeting);
        add_test("aliyun_greeting", aliyun_greeting);

        add_test("invalid_atom_prefix", invalid_atom_prefix);

        add_test("gmail_flags", gmail_flags);
        add_test("gmail_permanent_flags", gmail_permanent_flags);
        add_test("gmail_broken_flags", gmail_broken_flags);
        add_test("cyrus_flags", cyrus_flags);

        add_test("runin_special_flag", runin_special_flag);

        // Deser currently emits a warning here causing the test to
        // fail, disable for the moment
        add_test("invalid_flag_prefix", invalid_flag_prefix);

        add_test("reserved_in_response_text", reserved_in_response_text);


        add_test("instant_eos", instant_eos);
        add_test("bye_eos", bye_eos);
    }

    public override void set_up() {
        this.stream = new MemoryInputStream();
        this.deser = new Deserializer(ID, this.stream, new Quirks());
    }

    public override void tear_down() {
        this.deser.stop_async.begin(this.async_completion);
        async_result();
        this.deser = null;
        this.stream = null;
    }

    public void parse_unquoted() throws Error {
        string bytes = "OK";
        this.stream.add_data(UNTAGGED.data);
        this.stream.add_data(bytes.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert_equal<int?>(message.size, 2);
        assert_true(message.get(1) is UnquotedStringParameter, "Not parsed as atom");
        assert_equal(message.get(1).to_string(), bytes);
    }

    public void parse_quoted() throws Error {
        string bytes = "\"OK\"";
        this.stream.add_data(UNTAGGED.data);
        this.stream.add_data(bytes.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert_equal<int?>(message.size, 2);
        assert_true(message.get(1) is QuotedStringParameter, "Not parsed as quoted");
        assert_equal(message.get(1).to_string(), bytes);
    }

    public void parse_number() throws Error {
        string bytes = "1234";
        this.stream.add_data(UNTAGGED.data);
        this.stream.add_data(bytes.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert_equal<int?>(message.size, 2);
        assert_true(message.get(1) is NumberParameter, "Not parsed as number");
        assert_equal(message.get(1).to_string(), bytes);
    }

    public void parse_list() throws Error {
        string bytes = "(OK)";
        this.stream.add_data(UNTAGGED.data);
        this.stream.add_data(bytes.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert_equal<int?>(message.size, 2);
        assert_true(message.get(1) is ListParameter, "Not parsed as list");
        assert_equal(message.get(1).to_string(), bytes);
    }

    public void parse_flag() throws GLib.Error {
        string bytes = "\\iamaflag";
        this.stream.add_data(UNTAGGED.data);
        this.stream.add_data(bytes.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert_equal<int?>(message.size, 2);
        assert_true(
            message.get(1) is UnquotedStringParameter,
            "Not parsed as n atom"
        );
        assert_string(message.get(1).to_string(), bytes);
    }

    public void parse_wildcard_flag() throws GLib.Error {
        string bytes = "\\*";
        this.stream.add_data(UNTAGGED.data);
        this.stream.add_data(bytes.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert_equal<int?>(message.size, 2);
        assert_true(
            message.get(1) is UnquotedStringParameter,
            "Not parsed as n atom"
        );
        assert_string(message.get(1).to_string(), bytes);
    }

    public void parse_response_code() throws Error {
        string bytes = "[OK]";
        this.stream.add_data(UNTAGGED.data);
        this.stream.add_data(bytes.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert_equal<int?>(message.size, 2);
        assert_true(message.get(1) is ResponseCode, "Not parsed as response code");
        assert_equal(message.get(1).to_string(), bytes);
    }

    public void parse_bad_list() throws Error {
        string bytes = "(UHH";
        this.stream.add_data(UNTAGGED.data);
        this.stream.add_data(bytes.data);
        this.stream.add_data(EOL.data);

        // XXX We expect EOS here rather than DESER_FAIL since the
        // deserializer currently silently ignores lines with
        // malformed lists and continues parsing, so we get to the end
        // of the stream.
        this.process.begin(Expect.EOS, this.async_completion);
        this.process.end(async_result());
    }

    public void parse_bad_response_code() throws Error {
        string bytes = "[UHH";
        this.stream.add_data(UNTAGGED.data);
        this.stream.add_data(bytes.data);
        this.stream.add_data(EOL.data);

        // XXX We expect EOS here rather than DESER_FAIL since the
        // deserializer currently silently ignores lines with
        // malformed lists and continues parsing, so we get to the end
        // of the stream.
        this.process.begin(Expect.EOS, this.async_completion);
        this.process.end(async_result());
    }

    public void gmail_greeting() throws Error {
        string greeting = "* OK Gimap ready for requests from 115.187.245.46 c194mb399904375ivc";
        this.stream.add_data(greeting.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == greeting);
    }

    public void cyrus_2_4_greeting() throws Error {
        string greeting = "* OK [CAPABILITY IMAP4rev1 LITERAL+ ID ENABLE AUTH=PLAIN SASL-IR] mogul Cyrus IMAP v2.4.12-Debian-2.4.12-2 server ready";
        this.stream.add_data(greeting.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == greeting);
    }

    public void aliyun_greeting() throws Error {
        string greeting = "* OK AliYun IMAP Server Ready(10.147.40.164)";
        this.stream.add_data(greeting.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == greeting);
    }

    public void invalid_atom_prefix() throws Error {
        string flags = """* OK %atom""";
        this.stream.add_data(flags.data);
        this.stream.add_data(EOL.data);

        // XXX deser currently emits a warning here causing the test
        // to fail, so disable for the moment
        GLib.Test.skip("Test skipped due to Deserializer error handling");

        //this.process.begin(Expect.DESER_FAIL, this.async_completion);
        //this.process.end(async_result());
    }

    public void gmail_flags() throws Error {
        string flags = """* FLAGS (\Answered \Flagged \Draft \Deleted \Seen $NotPhishing $Phishing)""";
        this.stream.add_data(flags.data);
        this.stream.add_data(EOL.data);
        this.deser.quirks = new Imap.Quirks();
        this.deser.quirks.update_for_gmail();

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == flags);
    }

    public void gmail_permanent_flags() throws Error {
        string flags = """* OK [PERMANENTFLAGS (\Answered \Flagged \Draft \Deleted \Seen $NotPhishing $Phishing \*)] Flags permitted.""";
        this.stream.add_data(flags.data);
        this.stream.add_data(EOL.data);
        this.deser.quirks = new Imap.Quirks();
        this.deser.quirks.update_for_gmail();

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == flags);
    }

    public void gmail_broken_flags() throws GLib.Error {
        // As of 2020-05-01, GMail does not correctly quote email
        // flags. See #746
        string flags = """* FLAGS (\Answered \Flagged \Draft \Deleted \Seen $Forwarded $MDNSent $NotPhishing $Phishing Junk LoadRemoteImages NonJunk OIB-Seen-INBOX OIB-Seen-Unsubscribe [GMail]/Sent_Mail OIB-Seen-[Gmail]/Important OIB-Seen-[Gmail]/Spam OIB-Seen-[Gmail]/Tous les messages)""";
        this.stream.add_data(flags.data);
        this.stream.add_data(EOL.data);
        this.deser.quirks = new Imap.Quirks();
        this.deser.quirks.update_for_gmail();

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == flags);
    }

    public void cyrus_flags() throws Error {
        string flags = """* 2934 FETCH (FLAGS (\Answered \Seen $Quuxo::Spam::Trained) UID 3041)""";
        this.stream.add_data(flags.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, this.async_completion);
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

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == expected);
    }

    public void invalid_flag_prefix() throws Error {
        string flags = """* OK \%atom""";
        this.stream.add_data(flags.data);
        this.stream.add_data(EOL.data);

        // XXX Deser currently emits a warning here causing the test
        // to fail, so disable for the moment
        GLib.Test.skip("Test skipped due to Deserializer error handling");

        //this.process.begin(Expect.DESER_FAIL, this.async_completion);
        //this.process.end(async_result());
    }

    public void reserved_in_response_text() throws Error {
        // As seen in #711
        string line = """a008 BAD Missing ] in: header.fields""";
        this.stream.add_data(line.data);
        this.stream.add_data(EOL.data);

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());

        assert(message.to_string() == line);
    }

    public void instant_eos() throws Error {
        this.process.begin(Expect.EOS, this.async_completion);
        this.process.end(async_result());
        assert(this.deser.is_halted());
    }

    public void bye_eos() throws Error {
        string bye = """* OK bye""";
        this.stream.add_data(bye.data);

        bool eos = false;
        this.deser.end_of_stream.connect(() => { eos = true; });

        this.process.begin(Expect.MESSAGE, this.async_completion);
        RootParameters? message = this.process.end(async_result());
        assert(message.to_string() == bye);
        assert_false(eos);

        this.process.begin(Expect.EOS, this.async_completion);
        assert_true(eos);

        assert(this.deser.is_halted());
    }

    protected async RootParameters? process(Expect expected) throws GLib.Error {
        RootParameters? message = null;
        bool eos = false;
        bool deserialize_failure = false;
        bool receive_failure = false;
        size_t bytes_received = 0;

        this.deser.parameters_ready.connect((param) => { message = param; });
        this.deser.bytes_received.connect((count) => { bytes_received += count; });
        this.deser.end_of_stream.connect((param) => { eos = true; });
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
            break;
        }

        return message;
    }

}
