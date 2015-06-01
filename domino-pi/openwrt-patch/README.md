This is the patches to add a build target in OpenWrt BB1407.

1. Download Openwrt
----------------
```
git clone git://git.openwrt.org/14.07/openwrt.git openwrt-domino
cd openwrt-domino
```

2. Add Domino target patch
----------------------------
First you need to create a folder with name "patches" in openwrt root and copy domino.patch and series to this foder. Then use 'quilt' to apply the patch
```
mkdir patches
cp domino.patch series ./patches
quilt push -a
./scripts/feeds update -a
./scripts/feeds install -a
```

3. Compile
run 
```
make menuconfig
```
Choose "Domino Wifi for things" as compile target, then run
```
make
```

Please be noted the above steps will build a minimum firmware for Domino Pi board. If you need more features, refer to Domino Documentations. 