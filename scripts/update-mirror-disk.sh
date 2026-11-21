for i in /sys/block/*; do grep -q UMS ${i}/device/model 2>/dev/null && echo $i | sed -e 's:/sys/block:/dev:'; done > /code/build/mirrordiskuuid
cat /code/build/mirrordiskuuid
