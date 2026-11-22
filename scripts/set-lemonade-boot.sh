mirrordisk=$(cat /code/build/mirrordiskuuid)
cat > /tmp/config-env.txt <<EOF
bootdelay=2
baudrate=115200
ethprime=FEC
loadaddr=0x40480000
splashpos=m,m
splashimage=0x50000000
fdt_high=0xffffffffffffffff
initrd_high=0xffffffffffffffff
bootcmd=mmc dev 2; fatload mmc 2:4 0x40800000 /boot.scr; source 0x40800000
EOF
/code/build/uboot-nxp/tools/mkenvimage -s 4096 -o /code/build/set-lemonade-boot.bin /tmp/config-env.txt
dd if=/code/build/set-lemonade-boot.bin of=$mirrordisk bs=4096 seek=1024 count=1 conv=notrunc
