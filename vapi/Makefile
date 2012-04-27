# NOTE: The dependencies in this file require vapigen and vala-gen-introspect to be installed,
# which are not default in a standard Vala installation.

GMIME_FILES := \
	gmime-2.6/gmime-2.6.defines \
	gmime-2.6/gmime-2.6.files \
	gmime-2.6/gmime-2.6.metadata \
	gmime-2.6/gmime-2.6.namespace \
	gmime-2.6/gmime-2.6-custom.vala

all: gmime-2.6.vapi

.PHONY: clean
clean:
	rm gmime-2.6.vapi gmime-2.6/gmime-2.6.gi

gmime-2.6/gmime-2.6.gi: $(GMIME_FILES)
	vala-gen-introspect gmime-2.6 gmime-2.6

gmime-2.6.vapi: gmime-2.6/gmime-2.6.gi
	vapigen --pkg=glib-2.0 --pkg=gio-2.0 --library gmime-2.6 gmime-2.6/gmime-2.6.gi gmime-2.6/gmime-2.6-custom.vala

