/* javascriptcore-4.0.vapi. */

[CCode (cprefix = "JS", gir_namespace = "JavaScriptCore", gir_version = "4.0", lower_case_cprefix = "JS_", cheader_filename = "JavaScriptCore/JavaScript.h")]
namespace JS {

	[CCode (cname = "JSGlobalContextRef")]
    [SimpleType]
	public struct GlobalContext {
	}

	[CCode (cname = "JSValueRef")]
    [SimpleType]
	public struct Value {
	}
}
