#!/bin/sh

set -e
usermod --uid $UID minecraft
groupmod --gid $GID minecraft

chown -R minecraft:minecraft /data /start-minecraft
chmod -R g+wX /data /start-minecraft

while lsof -- /start-minecraft; do
  echo -n "."
  sleep 1
done

mkdir -p /home/minecraft
chown minecraft: /home/minecraft

echo "Switching to user 'minecraft'"
exec sudo -E -u minecraft /start-minecraft
