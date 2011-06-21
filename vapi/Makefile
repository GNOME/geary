# NOTE: The dependencies in this file require vapigen and vala-gen-introspect to be installed,
# which are not default in a standard Vala installation.

GMIME_FILES := \
	gmime-2.4/gmime-2.4.defines \
	gmime-2.4/gmime-2.4.files \
	gmime-2.4/gmime-2.4.metadata \
	gmime-2.4/gmime-2.4.namespace \
	gmime-2.4/gmime-2.4-custom.vala

all: gmime-2.4.vapi

.PHONY: clean
clean:
	rm gmime-2.4.vapi gmime-2.4/gmime-2.4.gi

gmime-2.4/gmime-2.4.gi: $(GMIME_FILES)
	vala-gen-introspect gmime-2.4 gmime-2.4

gmime-2.4.vapi: gmime-2.4/gmime-2.4.gi
	vapigen --pkg=glib-2.0 --pkg=gio-2.0 --library gmime-2.4 gmime-2.4/gmime-2.4.gi gmime-2.4/gmime-2.4-custom.vala

