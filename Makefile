# Makefile for ACPI daemon
TOPDIR = $(shell pwd)

# our build config file
BUILD_CONFIG = $(TOPDIR)/BUILD_CONFIG

# project version
PRJ_VERSION = 2.0.5
PRJ_REVISION = 1

# assign build options default values
# Use '?=' variable assignment so ENV variables can be used.

DEBUG ?= 0			# boolean
STATIC ?= 0			# option: 0=no, 1=yes, 2=partial
PROFILE ?= 0			# boolean
ENABLE_MCEDB ?= 0		# boolean (currently not checked in)
ENABLE_DBUS ?= 0		# boolean
ENABLE_FAKE_DEV_MCELOG ?= 0	# boolean
CHECK_FOR_NON_POLL_KERNELS ?= 0 # boolean

# include the generic rules
include $(TOPDIR)/Makerules.mk

# assign any flags variables
# Use '+=' variable assignment so ENV variables can be used.

DEFS += -D_GNU_SOURCE
CWARNS += -Wundef -Wshadow -Wno-strict-aliasing
CPPFLAGS += -DENABLE_MCEDB=$(ENABLE_MCEDB)
CPPFLAGS += -DENABLE_DBUS=$(ENABLE_DBUS)
CPPFLAGS += -DENABLE_FAKE_DEV_MCELOG=$(ENABLE_FAKE_DEV_MCELOG)
CPPFLAGS += -DCHECK_FOR_NON_POLL_KERNELS=$(CHECK_FOR_NON_POLL_KERNELS)
ifneq "$(strip $(ENABLE_MCEDB))" "0"
LIBS += -ldb
endif
ifneq "$(strip $(ENABLE_DBUS))" "0"
CFLAGS += $(shell pkg-config --cflags dbus-1 dbus-glib-1)
LIBS += $(shell pkg-config --libs dbus-1 dbus-glib-1) -lpcre
endif
RPM_ARCH += $(shell uname -m)

PREFIX = /usr/local
BINDIR = $(PREFIX)/bin
SBINDIR = $(PREFIX)/sbin
MAN8DIR = $(PREFIX)/share/man/man8

SBIN_PROGS = mced
BIN_PROGS = mce_listen mce_decode
TEST_PROGS = mcelog_faker
PROGS = $(SBIN_PROGS) $(BIN_PROGS) $(TEST_PROGS)

mced_SRCS = mced.c rules.c util.c ud_socket.c cmdline.c
ifneq "$(strip $(ENABLE_DBUS))" "0"
mced_SRCS += dbus.c dbus_asv.c
endif
mced_OBJS = $(mced_SRCS:.c=.o)

mce_listen_SRCS = mce_listen.c util.c ud_socket.c cmdline.c
ifneq "$(strip $(ENABLE_DBUS))" "0"
mce_listen_SRCS += dbus_asv.c
endif
mce_listen_OBJS = $(mce_listen_SRCS:.c=.o)

mce_decode_SRCS = mce_decode.c
mce_decode_OBJS = $(mce_decode_SRCS:.c=.o)

mcelog_faker_SRCS = mcelog_faker.c
mcelog_faker_OBJS = $(mcelog_faker_SRCS:.c=.o)

MAN8 = mced.8 mce_listen.8
MAN8GZ = $(MAN8:.8=.8.gz)

#
# Our rules
#

all: $(PROGS)

mced: $(mced_OBJS)
	$(CC) -o $@ $(mced_OBJS) $(LDFLAGS) $(LDLIBS)

auto.dbus_client.h: dbus_interface.xml
	dbus-binding-tool \
	    --prefix=mced_gobject \
	    --mode=glib-client \
	    --output=$@ \
	    $<

auto.dbus_server.h: dbus_interface.xml
	dbus-binding-tool \
	    --prefix=mced_gobject \
	    --mode=glib-server \
	    --output=$@ \
	    $<

mce_listen: $(mce_listen_OBJS)
	$(CC) -o $@ $(mce_listen_OBJS) $(LDFLAGS) $(LDLIBS)

mcelog_faker: $(mcelog_faker_OBJS)
	$(CC) -o $@ $(mcelog_faker_OBJS) $(LDFLAGS)

man: $(MAN8)
	for a in $^; do gzip -f -9 -c $$a > $$a.gz; done

install: $(PROGS) man
	mkdir -p $(SBINDIR)
	mkdir -p $(BINDIR)
	install -m 750 mced $(SBINDIR)
	install -m 755 mce_listen $(BINDIR)
	mkdir -p $(MAN8DIR)
	install -m 644 $(MAN8GZ) $(MAN8DIR)

DISTTMP=/tmp
dist:
	rm -rf $(DISTTMP)/mcedaemon-$(PRJ_VERSION)
	mkdir -p $(DISTTMP)/mcedaemon-$(PRJ_VERSION)
	cp -a * $(DISTTMP)/mcedaemon-$(PRJ_VERSION)
	find $(DISTTMP)/mcedaemon-$(PRJ_VERSION) -type d -name .svn | xargs rm -rf
	make -C $(DISTTMP)/mcedaemon-$(PRJ_VERSION) distclean
	tar -C $(DISTTMP) -zcvf mcedaemon-$(PRJ_VERSION).tar.gz mcedaemon-$(PRJ_VERSION)
	rm -rf $(DISTTMP)/mcedaemon-$(PRJ_VERSION)

clean:
	$(RM) $(PROGS) $(MAN8GZ) *.o auto.*

RPMROOT=$(DISTTMP)/mcedaemon-rpm-$(PRJ_VERSION)
rpm: dist
	rm -rf $(RPMROOT)
	mkdir -p $(RPMROOT)/SOURCES/
	cp mcedaemon-$(PRJ_VERSION).tar.gz $(RPMROOT)/SOURCES/
	rpmbuild -bb --define='_topdir $(RPMROOT)' \
		--define='version $(PRJ_VERSION)' --define='revision $(PRJ_REVISION)' ./mced.spec
	mv $(RPMROOT)/RPMS/$(RPM_ARCH)/mcedaemon-$(PRJ_VERSION)-$(PRJ_REVISION).$(RPM_ARCH).rpm ./
	rm -rf $(RPMROOT)

DEBROOT=$(DISTTMP)/mcedaemon-deb-$(PRJ_VERSION)
debian: dist
	rm -rf $(DEBROOT)
	mkdir -p $(DEBROOT)
	cp mcedaemon-$(PRJ_VERSION).tar.gz $(DEBROOT)/
	tar -C $(DEBROOT) -xvf mcedaemon-$(PRJ_VERSION).tar.gz
	make -C $(DEBROOT)/mcedaemon-$(PRJ_VERSION) STATIC=1
	cd $(DEBROOT)/mcedaemon-$(PRJ_VERSION) && ./make_deb.sh $(PRJ_VERSION) $(PRJ_REVISION)
	cp $(DEBROOT)/mcedaemon-$(PRJ_VERSION)/mcedaemon_$(PRJ_VERSION)*.deb ./
	rm -rf $(DEBROOT)

distclean:
	$(RM) .depend
	$(RM) $(BUILD_CONFIG)

.depend: $(mced_SRCS) $(mce_listen_SRCS)
