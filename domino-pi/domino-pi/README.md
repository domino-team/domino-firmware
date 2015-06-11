# GL.iNet OpenWrt package #


### What is this package ###

* This this the source code of GL.iNet CGI and Web
* Version 2.0

### How to compile ###

* Download openwrt source tree to your local directory, e.g. openwrt/trunk
* Put rootfile/* to your openwrt/trunk/files/
* Put other files to your openwrt path, e.g. openwrt/trunk/package
* Put all files folder to your openwrt/trunk/ (files not in the source yet)
* run `make defconfig`
* run `make menuconfig` to select the packages
* select 'GL.iNet' in the Target Profile 
* select 'gl-inet -> gl-inet' package, this will automatically select all dependencies 


### Who do I talk to? ###

* alzhao@gl-inet.com