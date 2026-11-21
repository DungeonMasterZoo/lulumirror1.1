mirrordisk=$(cat /code/build/mirrordiskuuid)
mkdir -p /code/build/mirror-backup
dd if=$mirrordisk of=/code/build/mirror-backup/disk.img bs=4096 status=progress
