#
# Makefile for Atheros tools.
#

ifneq ($(strip $(TOOLPREFIX)),)
CROSS:=$(TOOLPREFIX)
endif

#CC=$(CROSS)mips-openwrt-linux-uclibc-gcc

#CC=$(CROSS)gcc
STRIP           =$(CROSS)strip

ifeq ($(strip ${ATH_WASP_I2S}),1)
EXTRA_CFLAGS += -DWASP
endif

ALL=	athplay i2sconf

all:	${ALL}

athplay: athplay.c
	${CC} ${EXTRA_CFLAGS} -o athplay athplay.c

i2sconf: i2sconf.c
	${CC} -o i2sconf i2sconf.c

clean: 
	rm -f ${ALL} 
