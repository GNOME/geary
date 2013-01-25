/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.FetchedData : Object {
    public MessageNumber msg_num { get; private set; }
    public Gee.Map<FetchDataType, MessageData> map { get; private set;
        default = new Gee.HashMap<FetchDataType, MessageData>(); }
    public Gee.List<Memory.AbstractBuffer> body_data { get; private set;
        default = new Gee.ArrayList<Memory.AbstractBuffer>(); }
    
    public FetchedData(MessageNumber msg_num) {
        this.msg_num = msg_num;
    }
    
    public static FetchedData decode(ServerData server_data) throws ImapError {
        if (!server_data.get_as_string(2).equals_ci(FetchCommand.NAME))
            throw new ImapError.PARSE_ERROR("Not FETCH data: %s", server_data.to_string());
        
        FetchedData fetched_data = new FetchedData(new MessageNumber(data.get_as_string(1).as_int()));
        
        // walk the list for each returned fetch data item, which is paired by its data item name
        // and the structured data itself
        ListParameter list = server_data.get_as_list(3);
        for (int ctr = 0; ctr < list.get_count(); ctr += 2) {
            StringParameter data_item_param = list.get_as_string(ctr);
            
            // watch for truncated lists, which indicate an empty return value
            bool has_value = (ctr < (list.get_count() - 1));
            
            if (FetchBodyDataType.is_fetch_body(data_item_param)) {
                // FETCH body data items are merely a literal of all requested fields formatted
                // in RFC822 header format ... watch for empty return values and NIL
                if (has_value)
                    fetched_data.body_data.add(list.get_as_empty_literal(ctr + 1).get_buffer());
                else
                    fetched_data.body_data.add(Memory.EmptyBuffer.instance);
            } else {
                FetchDataType data_item = FetchDataType.decode(data_item_param.value);
                FetchDataDecoder? decoder = data_item.get_decoder();
                if (decoder == null) {
                    debug("Unable to decode fetch response for \"%s\": No decoder available",
                        data_item.to_string());
                    
                    continue;
                }
                
                // watch for empty return values
                if (has_value)
                    fetched_data.set_data(data_item, decoder.decode(list.get_required(ctr + 1)));
                else
                    fetched_data.set_data(data_item, decoder.decode(NilParameter.instance));
            }
        }
        
        return fetched_data;
    }
}

