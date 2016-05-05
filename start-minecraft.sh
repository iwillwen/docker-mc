#!/bin/bash

#umask 002
export HOME=/data

if [ ! -e /data/eula.txt ]; then
  if [ "$EULA" != "" ]; then
    echo "# Generated via Docker on $(date)" > eula.txt
    echo "eula=$EULA" >> eula.txt
  else
    echo ""
    echo "Please accept the Minecraft EULA at"
    echo "  https://account.mojang.com/documents/minecraft_eula"
    echo "by adding the following immediately after 'docker run':"
    echo "  -e EULA=TRUE"
    echo ""
    exit 1
  fi
fi

echo "Checking version information."
case "X$VERSION" in
  X|XLATEST|Xlatest)
    VANILLA_VERSION=`curl -sSL http://78rc4m.com1.z0.glb.clouddn.com/mc/versions.json | jq -r '.latest.release'`
  ;;
  XSNAPSHOT|Xsnapshot)
    VANILLA_VERSION=`curl -sSL http://78rc4m.com1.z0.glb.clouddn.com/mc/versions.json | jq -r '.latest.snapshot'`
  ;;
  X[1-9]*)
    VANILLA_VERSION=$VERSION
  ;;
  *)
    VANILLA_VERSION=`curl -sSL http://78rc4m.com1.z0.glb.clouddn.com/mc/versions.json | jq -r '.latest.release'`
  ;;
esac

cd /data

function buildSpigotFromSource {
  echo "Building Spigot $VANILLA_VERSION from source, might take a while, get some coffee"
  mkdir /data/temp
  cd /data/temp
  wget -q -P /data/temp https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar && \
    java -jar /data/temp/BuildTools.jar --rev $VANILLA_VERSION 2>&1 |tee /data/spigot_build.log| while read l; do echo -n .; done; echo "done"
  mv spigot-*.jar /data/spigot_server.jar
  mv craftbukkit-*.jar /data/craftbukkit_server.jar
  echo "Cleaning up"
  rm -rf /data/temp
  cd /data
}

function downloadSpigot {
  case "$TYPE" in
    *BUKKIT|*bukkit)
      match="Craftbukkit $VANILLA_VERSION"
      ;;
    *)
      match="Spigot $VANILLA_VERSION"
      ;;
  esac

  curl -o /tmp/versions -sSL https://getspigot.org/api/getversions
  status=$?
  if [ $status != 0 ]; then
    echo "ERROR: failed to access Spigot versions (curl error code was $status)"
    exit 3
  fi
  downloadUrl=$(cat /tmp/versions | jq -r ".[] | select(.version == \"$match\") | .downloadUrl")
  if [[ -n $downloadUrl ]]; then
    echo "Downloading $match"
    wget -q -O $SERVER "$downloadUrl"
    status=$?
    if [ $status != 0 ]; then
      echo "ERROR: failed to download from $downloadUrl due to (error code was $status)"
      exit 3
    fi
  else
    echo "ERROR: Version $VANILLA_VERSION is not supported for $TYPE"
    echo "       Refer to http://getspigot.org for supported versions"
    exit 2
  fi
}

function installForge {
  TYPE=FORGE
  norm=$VANILLA_VERSION

  echo "Checking Forge version information."
  case $FORGEVERSION in
    RECOMMENDED)
      curl -o /tmp/forge.json -sSL http://files.minecraftforge.net/maven/net/minecraftforge/forge/promotions_slim.json
      FORGE_VERSION=$(cat /tmp/forge.json | jq -r ".promos[\"$norm-recommended\"]")
      if [ $FORGE_VERSION = null ]; then
        FORGE_VERSION=$(cat /tmp/forge.json | jq -r ".promos[\"$norm-latest\"]")
        if [ $FORGE_VERSION = null ]; then
          echo "ERROR: Version $FORGE_VERSION is not supported by Forge"
          echo "       Refer to http://files.minecraftforge.net/ for supported versions"
          exit 2
        fi
      fi
      ;;

    *)
      FORGE_VERSION=$FORGEVERSION
      ;;
  esac

  # URL format changed for 1.7.10 from 10.13.2.1300
  sorted=$((echo $FORGE_VERSION; echo 10.13.2.1300) | sort -V | head -1)
  if [[ $norm == '1.7.10' && $sorted == '10.13.2.1300' ]]; then
      # if $FORGEVERSION >= 10.13.2.1300
      normForgeVersion="$norm-$FORGE_VERSION-$norm"
  else
      normForgeVersion="$norm-$FORGE_VERSION"
  fi

  FORGE_INSTALLER="forge-$normForgeVersion-installer.jar"
  SERVER="forge-$normForgeVersion-universal.jar"

  if [ ! -e "$SERVER" ]; then
    echo "Downloading $FORGE_INSTALLER ..."
    wget -q http://files.minecraftforge.net/maven/net/minecraftforge/forge/$normForgeVersion/$FORGE_INSTALLER
    echo "Installing $SERVER"
    java -jar $FORGE_INSTALLER --installServer
  fi
}

function installVanilla {
  SERVER="minecraft_server.$VANILLA_VERSION.jar"

  if [ ! -e $SERVER ]; then
    echo "Downloading $SERVER ..."
    wget -q http://78rc4m.com1.z0.glb.clouddn.com/mc/$SERVER
  fi
}

echo "Checking type information."
case "$TYPE" in
  *BUKKIT|*bukkit|SPIGOT|spigot)
    case "$TYPE" in
      *BUKKIT|*bukkit)
        SERVER=craftbukkit_server.jar
        ;;
      *)
        SERVER=spigot_server.jar
        ;;
    esac

    if [ ! -f $SERVER ]; then
       if [[ "$BUILD_SPIGOT_FROM_SOURCE" = TRUE || "$BUILD_SPIGOT_FROM_SOURCE" = true || "$BUILD_FROM_SOURCE" = TRUE || "$BUILD_FROM_SOURCE" = true ]]; then
         buildSpigotFromSource
       else
         downloadSpigot
       fi
    fi
    # normalize on Spigot for operations below
    TYPE=SPIGOT
  ;;

  FORGE|forge)
    TYPE=FORGE
    installForge
  ;;

  VANILLA|vanilla)
    installVanilla
  ;;

  *)
      echo "Invalid type: '$TYPE'"
      echo "Must be: VANILLA, FORGE, SPIGOT"
      exit 1
  ;;

esac


# If supplied with a URL for a world, download it and unpack
if [[ "$WORLD" ]]; then
case "X$WORLD" in
  X[Hh][Tt][Tt][Pp]*)
    echo "Downloading world via HTTP"
    echo "$WORLD"
    wget -q -O - "$WORLD" > /data/world.zip
    echo "Unzipping word"
    unzip -q /data/world.zip
    rm -f /data/world.zip
    if [ ! -d /data/world ]; then
      echo World directory not found
      for i in /data/*/level.dat; do
        if [ -f "$i" ]; then
          d=`dirname "$i"`
          echo Renaming world directory from $d
          mv -f "$d" /data/world
        fi
      done
    fi
    if [ "$TYPE" = "SPIGOT" ]; then
      # Reorganise if a Spigot server
      echo "Moving End and Nether maps to Spigot location"
      [ -d "/data/world/DIM1" ] && mv -f "/data/world/DIM1" "/data/world_the_end"
      [ -d "/data/world/DIM-1" ] && mv -f "/data/world/DIM-1" "/data/world_nether"
    fi
    ;;
  *)
    echo "Invalid URL given for world: Must be HTTP or HTTPS and a ZIP file"
    ;;
esac
fi

# If supplied with a URL for a modpack (simple zip of jars), download it and unpack
if [[ "$MODPACK" ]]; then
case "X$MODPACK" in
  X[Hh][Tt][Tt][Pp]*[Zz][iI][pP])
    echo "Downloading mod/plugin pack via HTTP"
    echo "$MODPACK"
    wget -q -O /tmp/modpack.zip "$MODPACK"
    if [ "$TYPE" = "SPIGOT" ]; then
      mkdir -p /data/plugins
      unzip -d /data/plugins /tmp/modpack.zip
    else
      mkdir -p /data/mods
      unzip -d /data/mods /tmp/modpack.zip
    fi
    rm -f /tmp/modpack.zip
    ;;
  *)
    echo "Invalid URL given for modpack: Must be HTTP or HTTPS and a ZIP file"
    ;;
esac
fi

function setServerProp {
  local prop=$1
  local var=$2
  if [ -n "$var" ]; then
    echo "Setting $prop to $var"
    sed -i "/$prop\s*=/ c $prop=$var" /data/server.properties
  fi

}

if [ ! -e server.properties ]; then
  echo "Creating server.properties"
  cp /tmp/server.properties .

  if [ -n "$WHITELIST" ]; then
    echo "Creating whitelist"
    sed -i "/whitelist\s*=/ c whitelist=true" /data/server.properties
    sed -i "/white-list\s*=/ c white-list=true" /data/server.properties
  fi

  setServerProp "motd" "$MOTD"
  setServerProp "allow-nether" "$ALLOW_NETHER"
  setServerProp "announce-player-achievements" "$ANNOUNCE_PLAYER_ACHIEVEMENTS"
  setServerProp "enable-command-block" "$ENABLE_COMMAND_BLOCK"
  setServerProp "spawn-animals" "$SPAWN_ANIMAILS"
  setServerProp "spawn-monsters" "$SPAWN_MONSTERS"
  setServerProp "spawn-npcs" "$SPAWN_NPCS"
  setServerProp "generate-structures" "$GENERATE_STRUCTURES"
  setServerProp "spawn-npcs" "$SPAWN_NPCS"
  setServerProp "view-distance" "$VIEW_DISTANCE"
  setServerProp "hardcore" "$HARDCORE"
  setServerProp "max-build-height" "$MAX_BUILD_HEIGHT"
  setServerProp "force-gamemode" "$FORCE_GAMEMODE"
  setServerProp "hardmax-tick-timecore" "$MAX_TICK_TIME"
  setServerProp "enable-query" "$ENABLE_QUERY"
  setServerProp "query.port" "$QUERY_PORT"
  setServerProp "enable-rcon" "$ENABLE_RCON"
  setServerProp "rcon.password" "$RCON_PASSWORD"
  setServerProp "rcon.port" "$RCON_PORT"
  setServerProp "max-players" "$MAX_PLAYERS"
  setServerProp "max-world-size" "$MAX_WORLD_SIZE"
  setServerProp "level-name" "$LEVEL"
  setServerProp "level-seed" "$SEED"
  setServerProp "pvp" "$PVP"
  setServerProp "generator-settings" "$GENERATOR_SETTINGS"

  if [ -n "$LEVEL_TYPE" ]; then
    # normalize to uppercase
    LEVEL_TYPE=${LEVEL_TYPE^^}
    echo "Setting level type to $LEVEL_TYPE"
    # check for valid values and only then set
    case $LEVEL_TYPE in
      DEFAULT|FLAT|LARGEBIOMES|AMPLIFIED|CUSTOMIZED)
        sed -i "/level-type\s*=/ c level-type=$LEVEL_TYPE" /data/server.properties
        ;;
      *)
        echo "Invalid LEVEL_TYPE: $LEVEL_TYPE"
  exit 1
  ;;
    esac
  fi

  if [ -n "$DIFFICULTY" ]; then
    case $DIFFICULTY in
      peaceful|0)
        DIFFICULTY=0
        ;;
      easy|1)
        DIFFICULTY=1
        ;;
      normal|2)
        DIFFICULTY=2
        ;;
      hard|3)
        DIFFICULTY=3
        ;;
      *)
        echo "DIFFICULTY must be peaceful, easy, normal, or hard."
        exit 1
        ;;
    esac
    echo "Setting difficulty to $DIFFICULTY"
    sed -i "/difficulty\s*=/ c difficulty=$DIFFICULTY" /data/server.properties
  fi

  if [ -n "$MODE" ]; then
    echo "Setting mode"
    case ${MODE,,?} in
      0|1|2|3)
        ;;
      s*)
        MODE=0
        ;;
      c*)
        MODE=1
        ;;
      a*)
        MODE=2
        ;;
      s*)
        MODE=3
        ;;
      *)
        echo "ERROR: Invalid game mode: $MODE"
        exit 1
        ;;
    esac

    sed -i "/gamemode\s*=/ c gamemode=$MODE" /data/server.properties
  fi
fi


if [ -n "$OPS" -a ! -e ops.txt.converted ]; then
  echo "Setting ops"
  echo $OPS | awk -v RS=, '{print}' >> ops.txt
fi

if [ -n "$WHITELIST" -a ! -e white-list.txt.converted ]; then
  echo "Setting whitelist"
  echo $WHITELIST | awk -v RS=, '{print}' >> white-list.txt
fi

if [ -n "$ICON" -a ! -e server-icon.png ]; then
  echo "Using server icon from $ICON..."
  # Not sure what it is yet...call it "img"
  wget -q -O /tmp/icon.img $ICON
  specs=$(identify /tmp/icon.img | awk '{print $2,$3}')
  if [ "$specs" = "PNG 64x64" ]; then
    mv /tmp/icon.img /data/server-icon.png
  else
    echo "Converting image to 64x64 PNG..."
    convert /tmp/icon.img -resize 64x64! /data/server-icon.png
  fi
fi

# Make sure files exist to avoid errors
if [ ! -e banned-players.json ]; then
  echo '' > banned-players.json
fi
if [ ! -e banned-ips.json ]; then
  echo '' > banned-ips.json
fi

# If any modules have been provided, copy them over
[ -d /data/mods ] || mkdir /data/mods
for m in /mods/*.jar
do
  if [ -f "$m" ]; then
    echo Copying mod `basename "$m"`
    cp -f "$m" /data/mods
  fi
done
[ -d /data/config ] || mkdir /data/config
for c in /config/*
do
  if [ -f "$c" ]; then
    echo Copying configuration `basename "$c"`
    cp -rf "$c" /data/config
  fi
done

if [ "$TYPE" = "SPIGOT" ]; then
  if [ -d /plugins ]; then
    echo Copying any Bukkit plugins over
    cp -r /plugins /data
  fi
fi

# If we have a bootstrap.txt file... feed that in to the server stdin
if [ -f /data/bootstrap.txt ];
then
    exec java $JVM_OPTS -jar $SERVER < /data/bootstrap.txt
else
    exec java $JVM_OPTS -jar $SERVER
fi

exec java $JVM_OPTS -jar $SERVER
