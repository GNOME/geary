namespace WebKit {
    namespace DOM {
        [CCode (cheader_filename="webkit/webkit.h", type_id="webkit_dom_event_target_get_type()")]
        public interface EventTarget {
            public abstract bool add_event_listener(string event_name, GLib.Callback handler, bool use_capture, GLib.Object? object);
            public abstract bool remove_event_listener(string event_name, GLib.Callback handler, bool use_capture);
        }
    }
}

