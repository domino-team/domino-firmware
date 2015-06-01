#
# Copyright (C) 2013 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=domino-athplay
PKG_REFV:=2
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/domino-athplay
  SECTION:=base
  CATEGORY:=domino
  TITLE:=Athplayer for Domino IIS board
 DEPENDS:=+libpthread $(INTL_DEPENDS) $(ICONV_DEPENDS)

endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

MAKE_FLAGS += CFLAGS="$(TARGET_CFLAGS) -Wall"

define Package/domino-athplay/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN)  $(PKG_BUILD_DIR)/athplay $(1)/usr/bin
	$(INSTALL_BIN)  $(PKG_BUILD_DIR)/i2sconf $(1)/usr/bin
endef

$(eval $(call BuildPackage,domino-athplay))
