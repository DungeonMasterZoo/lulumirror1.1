mirrordisk=$(cat /code/build/mirrordiskuuid)
dd if=$mirrordisk of=/code/build/mirror-backup/disk.img bs=4096
