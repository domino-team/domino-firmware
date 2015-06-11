#
# Copyright (C) 2013 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=domino-pi
PKG_REFV:=2
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/domino-pi
  SECTION:=base
  CATEGORY:=domino
  TITLE:=Files for Domino Pi
# DEPENDS:=+libpthread $(INTL_DEPENDS) $(ICONV_DEPENDS) +ethtool 
  DEPENDS:=+libpthread +ethtool +blkid +libubox +iwinfo\
   +avahi-daemon +avahi-dnsconfd +avahi-utils +block-mount +curl +samba36-server \
   +gnupg +hotplug2 +iw +jshn +kmod-crypto-aes +kmod-crypto-arc4 +kmod-crypto-core +kmod-crypto-hash +kmod-crypto-manager \
   +kmod-fs-ext4 +kmod-fs-ntfs +kmod-fs-vfat +kmod-fs-ext4 +ntfs-3g +kmod-fs-hfs +kmod-fs-hfsplus +kmod-fs-reiserfs +kmod-fuse +kmod-loop\
   +kmod-gpio-button-hotplug +kmod-i2c-core +kmod-leds-gpio +kmod-ledtrig-default-on +kmod-ledtrig-netdev +kmod-ledtrig-timer +kmod-ledtrig-usbdev +kmod-lib-crc-ccitt +kmod-lib-crc16\
   +kmod-nls-cp437 +kmod-nls-iso8859-1 +kmod-nls-utf8 +alljoyn\
   +kmod-usb-storage +kmod-usb-uhci +kmod-usb2 +kmod-usb-ohci \
   +kmod-usb-net +kmod-usb-cdc-ether +kmod-usb-net-rndis \
   +kmod-usb-serial +kmod-usb-serial-cp210x +kmod-usb-serial-option +kmod-usb-serial-wwan +kmod-usb-acm +usb-modeswitch +usb-modeswitch-data \
   +comgt +chat\
   +luci +luci-i18n-english +luci-lib-json +luci-lib-nixio \
   +rng-tools +uhttpd-mod-lua +uhttpd-mod-tls +uhttpd-mod-ubus \
   +usbutils +wget \
   +kmod-video-core +kmod-video-uvc +kmod-video-gspca-core +kmod-video-gspca-zc3xx +kmod-video-gspca-sonixb ++kmod-video-gspca-sonixj \
   +@BUSYBOX_CUSTOM +@BUSYBOX_CONFIG_UNICODE_SUPPORT \
   +@BUSYBOX_CONFIG_UNICODE_COMBINING_WCHARS +@BUSYBOX_CONFIG_UNICODE_WIDE_WCHARS +@BUSYBOX_CONFIG_UNICODE_BIDI_SUPPORT +@BUSYBOX_CONFIG_UNICODE_NEUTRAL_TABLE +@BUSYBOX_CONFIG_UNICODE_PRESERVE_BROKEN  \
   +@BUSYBOX_CONFIG_FEATURE_WGET_TIMEOUT +@BUSYBOX_CONFIG_FUSER +@BUSYBOX_CONFIG_IPCRM +@BUSYBOX_CONFIG_IPCS \
   +@BUSYBOX_CONFIG_FEATURE_FLOAT_SLEEP
   #+@BUSYBOX_CONFIG_SUBST_WCHAR=63 +@BUSYBOX_CONFIG_LAST_SUPPORT_WCHAR=195101 \

endef

define Build/Prepare
	
endef

define Build/Compile
	# NOOP
endef

define Build/Configure
endef

define Package/domino-pi/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/lib
	$(CP) -fr ./files/* $(1)/
	$(INSTALL_DIR) $(1)/www/cgi-bin
	chmod +x $(1)/etc/rc.button/*
	chmod +x $(1)/etc/init.d/*
	echo "built=$(shell date)" > $(1)/etc/domino/domino-release
endef

$(eval $(call BuildPackage,domino-pi))
