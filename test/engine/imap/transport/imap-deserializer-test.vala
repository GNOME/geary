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
    }

    public override void set_up() {
        this.stream = new MemoryInputStream();
        this.deser = new Deserializer(ID, this.stream);
    }

    public override void tear_down() {
        this.deser.stop_async.begin((obj, ret) => { async_complete(ret); });
        async_result();
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
