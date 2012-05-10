/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * FetchDataDecoder accept the result line of a FETCH response and decodes it into MessageData.
 * While they can be used standalone, they're intended to be used by FetchResults to process
 * a CommandResponse.
 *
 * Note that FetchDataDecoders are keyed off of FetchDataType; new implementations should add
 * themselves to FetchDataType.get_decoder().
 *
 * In the future FetchDataDecoder may be used to decode MessageData stored in other formats, such
 * as in a database.
 */

public abstract class Geary.Imap.FetchDataDecoder {
    public FetchDataType data_item { get; private set; }
    
    public FetchDataDecoder(FetchDataType data_item) {
        this.data_item = data_item;
    }
    
    // The default implementation determines the type of the parameter and calls the appropriate
    // virtual function; most implementations of a FetchResponseDecoder shouldn't need to override
    // this method.
    public virtual MessageData decode(Parameter param) throws ImapError {
        StringParameter? stringp = param as StringParameter;
        if (stringp != null)
            return decode_string(stringp);
        
        ListParameter? listp = param as ListParameter;
        if (listp != null)
            return decode_list(listp);
        
        LiteralParameter? literalp = param as LiteralParameter;
        if (literalp != null)
            return decode_literal(literalp);
        
        NilParameter? nilp = param as NilParameter;
        if (nilp != null)
            return decode_nil(nilp);
        
        // bad news; this means this function isn't handling a Parameter type properly
        assert_not_reached();
    }
    
    protected virtual MessageData decode_string(StringParameter param) throws ImapError {
        throw new ImapError.TYPE_ERROR("%s does not accept a string parameter", data_item.to_string());
    }
    
    protected virtual MessageData decode_list(ListParameter list) throws ImapError {
        throw new ImapError.TYPE_ERROR("%s does not accept a list parameter", data_item.to_string());
    }
    
    protected virtual MessageData decode_literal(LiteralParameter literal) throws ImapError {
        throw new ImapError.TYPE_ERROR("%s does not accept a literal parameter", data_item.to_string());
    }
    
    protected virtual MessageData decode_nil(NilParameter nil) throws ImapError {
        throw new ImapError.TYPE_ERROR("%s does not accept a nil parameter", data_item.to_string());
    }
}

public class Geary.Imap.UIDDecoder : Geary.Imap.FetchDataDecoder {
    public UIDDecoder() {
        base (FetchDataType.UID);
    }
    
    protected override MessageData decode_string(StringParameter stringp) throws ImapError {
        return new UID(stringp.as_int());
    }
}

public class Geary.Imap.MessageFlagsDecoder : Geary.Imap.FetchDataDecoder {
    public MessageFlagsDecoder() {
        base (FetchDataType.FLAGS);
    }
    
    protected override MessageData decode_list(ListParameter listp) throws ImapError {
        Gee.List<Flag> flags = new Gee.ArrayList<Flag>();
        for (int ctr = 0; ctr < listp.get_count(); ctr++)
            flags.add(new MessageFlag(listp.get_as_string(ctr).value));
        
        return new MessageFlags(flags);
    }
}

public class Geary.Imap.InternalDateDecoder : Geary.Imap.FetchDataDecoder {
    public InternalDateDecoder() {
        base (FetchDataType.INTERNALDATE);
    }
    
    protected override MessageData decode_string(StringParameter stringp) throws ImapError {
        return new InternalDate(stringp.value);
    }
}

public class Geary.Imap.RFC822SizeDecoder : Geary.Imap.FetchDataDecoder {
    public RFC822SizeDecoder() {
        base (FetchDataType.RFC822_SIZE);
    }
    
    protected override MessageData decode_string(StringParameter stringp) throws ImapError {
        return new RFC822Size(stringp.as_long());
    }
}

public class Geary.Imap.EnvelopeDecoder : Geary.Imap.FetchDataDecoder {
    public EnvelopeDecoder() {
        base (FetchDataType.ENVELOPE);
    }
    
    protected override MessageData decode_list(ListParameter listp) throws ImapError {
        StringParameter? sent = listp.get_as_nullable_string(0);
        StringParameter subject = listp.get_as_empty_string(1);
        ListParameter from = listp.get_as_empty_list(2);
        ListParameter sender = listp.get_as_empty_list(3);
        ListParameter reply_to = listp.get_as_empty_list(4);
        ListParameter? to = listp.get_as_nullable_list(5);
        ListParameter? cc = listp.get_as_nullable_list(6);
        ListParameter? bcc = listp.get_as_nullable_list(7);
        StringParameter? in_reply_to = listp.get_as_nullable_string(8);
        StringParameter? message_id = listp.get_as_nullable_string(9);
        
        // Although Message-ID is required to be returned by IMAP, it may be blank if the email
        // does not supply it (optional according to RFC822); deal with this cognitive dissonance
        if (message_id != null && String.is_empty(message_id.value))
            message_id = null;
        
        return new Envelope((sent != null) ? new Geary.RFC822.Date(sent.value) : null,
            new Geary.RFC822.Subject.decode(subject.value),
            parse_addresses(from), parse_addresses(sender), parse_addresses(reply_to),
            (to != null) ? parse_addresses(to) : null, 
            (cc != null) ? parse_addresses(cc) : null,
            (bcc != null) ? parse_addresses(bcc) : null,
            (in_reply_to != null) ? new Geary.RFC822.MessageID(in_reply_to.value) : null,
            (message_id != null) ? new Geary.RFC822.MessageID(message_id.value) : null);
    }
    
    // TODO: This doesn't handle group lists (see Johnson, p.268) -- this will throw an
    // ImapError.TYPE_ERROR if this occurs.
    private Geary.RFC822.MailboxAddresses? parse_addresses(ListParameter listp) throws ImapError {
        Gee.List<Geary.RFC822.MailboxAddress> list = new Gee.ArrayList<Geary.RFC822.MailboxAddress>();
        for (int ctr = 0; ctr < listp.get_count(); ctr++) {
            ListParameter fields = listp.get_as_empty_list(ctr);
            StringParameter? name = fields.get_as_nullable_string(0);
            StringParameter? source_route = fields.get_as_nullable_string(1);
            StringParameter mailbox = fields.get_as_empty_string(2);
            StringParameter domain = fields.get_as_empty_string(3);
            
            Geary.RFC822.MailboxAddress addr = new Geary.RFC822.MailboxAddress.imap(
                (name != null) ? name.nullable_value : null,
                (source_route != null) ? source_route.nullable_value : null,
                mailbox.value,
                domain.value);
            list.add(addr);
        }
        
        return new Geary.RFC822.MailboxAddresses(list);
    }
}

public class Geary.Imap.RFC822HeaderDecoder : Geary.Imap.FetchDataDecoder {
    public RFC822HeaderDecoder() {
        base (FetchDataType.RFC822_HEADER);
    }
    
    protected override MessageData decode_literal(LiteralParameter literalp) throws ImapError {
        return new Geary.Imap.RFC822Header(literalp.get_buffer());
    }
}

public class Geary.Imap.RFC822TextDecoder : Geary.Imap.FetchDataDecoder {
    public RFC822TextDecoder() {
        base (FetchDataType.RFC822_TEXT);
    }
    
    protected override MessageData decode_literal(LiteralParameter literalp) throws ImapError {
        return new Geary.Imap.RFC822Text(literalp.get_buffer());
    }
    
    protected override MessageData decode_nil(NilParameter nilp) throws ImapError {
        return new Geary.Imap.RFC822Text(Memory.EmptyBuffer.instance);
    }
}

public class Geary.Imap.RFC822FullDecoder : Geary.Imap.FetchDataDecoder {
    public RFC822FullDecoder() {
        base (FetchDataType.RFC822);
    }
    
    protected override MessageData decode_literal(LiteralParameter literalp) throws ImapError {
        return new Geary.Imap.RFC822Full(literalp.get_buffer());
    }
}

