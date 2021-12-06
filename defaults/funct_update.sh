function update_repo() {
  PARAM1=$1
  echo "Downloading repo from s3" | tee -a ${LOGS}
  mkdir -p ${HOME}/solidrust.net/defaults
  case ${PARAM1} in
  game | gameserver)
    echo "Sync repo for game server"
    mkdir -p ${HOME}/solidrust.net/servers ${HOME}/solidrust.net/defaults
    aws s3 sync --delete \
      --exclude "web/*" \
      --exclude "defaults/web/*" \
      --exclude "defaults/database/*" \
      --exclude "servers/web/*" \
      --exclude "servers/data/*" \
      --exclude "servers/radio/*" \
      ${S3_REPO} ${HOME}/solidrust.net | tee -a ${LOGS}
    echo "Setting execution bits" | tee -a ${LOGS}
    chmod +x ${HOME}/solidrust.net/defaults/*.sh
    cp ${HOME}/solidrust.net/build.txt ${GAME_ROOT}/
    ;;
  web | webserver)
    echo "Sync repo for website server"
    mkdir -p ${HOME}/solidrust.net/web ${HOME}/solidrust.net/defaults ${HOME}/solidrust.net/servers
    export GAME_ROOT="${HOME}/solidrust.net/web"
    aws s3 sync --size-only --delete \
      --exclude "web/maps/*" \
      --exclude "defaults/oxide/*" \
      --exclude "defaults/database/*" \
      --exclude "servers/data/*" \
      --exclude "servers/radio/*" \
      ${S3_REPO} ${HOME}/solidrust.net | tee -a ${LOGS}
    echo "Setting execution bits" | tee -a ${LOGS}
    chmod +x ${HOME}/solidrust.net/defaults/*.sh
    chmod +x ${HOME}/solidrust.net/defaults/web/*.sh
    ;;
  data | database)
    echo "Sync repo for database server"
    mkdir -p ${HOME}/solidrust.net
    aws s3 sync --delete ${S3_REPO} ${HOME}/solidrust.net \
    --exclude 'defaults/oxide/*' \
    --exclude 'defaults/web/*' \
    --exclude 'web/*' \
    --exclude 'servers/*' \
    --include 'servers/data/*' | grep -v ".git" | tee -a ${LOGS}
    echo "Setting execution bits" | tee -a ${LOGS}
    chmod +x ${HOME}/solidrust.net/defaults/database/*.sh
    ;;
  *)
    echo "Performing full repository sync"
    mkdir -p ${HOME}/solidrust.net
    aws s3 sync --delete ${S3_REPO} ${HOME}/solidrust.net | grep -v ".git" | tee -a ${LOGS}
    echo "Setting execution bits" | tee -a ${LOGS}
    chmod +x ${HOME}/solidrust.net/defaults/database/*.sh
    chmod +x ${HOME}/solidrust.net/defaults/web/*.sh
    chmod +x ${HOME}/solidrust.net/defaults/*.sh
    ;;
  esac
  echo "Current build: $(cat ${HOME}/solidrust.net/build.txt | head -n 2)"
}

function update_mods() {
  # Sync global Oxide data defaults 
  OXIDE=(
    oxide/data/BetterLoot/LootTables.json
    oxide/data/Kits/Kits.json
    oxide/data/FancyDrop.json
    oxide/data/BetterChat.json
    oxide/data/CompoundOptions.json
    oxide/data/death.png
    oxide/data/hit.png
    oxide/data/GuardedCrate.json
    oxide/data/CustomChatCommands.json
  )
  echo "=> Updating plugin data" | tee -a ${LOGS}
  mkdir -p "${GAME_ROOT}/oxide/data/BetterLoot" "${GAME_ROOT}/oxide/data/Kits"
  for data in ${OXIDE[@]}; do
    echo " - $data" | tee -a ${LOGS}
    rsync "${SERVER_GLOBAL}/$data" "${GAME_ROOT}/$data" | tee -a ${LOGS}
    if [[ -f "${SERVER_CUSTOM}/$data" ]]; then
      rsync "${SERVER_CUSTOM}/$data" "${GAME_ROOT}/$data" | tee -a ${LOGS}
    fi
  done
  echo " - oxide/data/copypaste" | tee -a ${LOGS}
  mkdir -p "${GAME_ROOT}/oxide/data/copypaste"
  rsync -r "${SERVER_GLOBAL}/oxide/data/copypaste/" "${GAME_ROOT}/oxide/data/copypaste" | tee -a ${LOGS}
  if [[ -d "${SERVER_CUSTOM}/oxide/data/copypaste" ]]; then
    rsync -r "${SERVER_CUSTOM}/oxide/data/copypaste/" "${GAME_ROOT}/oxide/data/copypaste" | tee -a ${LOGS}
  fi
  echo " - oxide/data/RaidableBases" | tee -a ${LOGS}
  mkdir -p "${GAME_ROOT}/oxide/data/RaidableBases"
  rsync -ra --delete "${SERVER_GLOBAL}/oxide/data/RaidableBases/" "${GAME_ROOT}/oxide/data/RaidableBases" | tee -a ${LOGS}
  if [[ -d "${SERVER_CUSTOM}/oxide/data/RaidableBases" ]]; then
    rsync -r "${SERVER_CUSTOM}/oxide/data/RaidableBases/" "${GAME_ROOT}/oxide/data/RaidableBases" | tee -a ${LOGS}
  fi
  # Sync global Oxide config defaults
  echo "=> Updating plugin configurations" | tee -a ${LOGS}
  mkdir -p "${GAME_ROOT}/oxide/config" | tee -a ${LOGS}
  echo " - sync ${SERVER_GLOBAL}/oxide/config/ to ${GAME_ROOT}/oxide/config" | tee -a ${LOGS}
  rsync -r "${SERVER_GLOBAL}/oxide/config/" "${GAME_ROOT}/oxide/config" | tee -a ${LOGS}
  # Sync server-specific Oxide config overrides
  echo " - sync ${SERVER_CUSTOM}/oxide/config/ to ${GAME_ROOT}/oxide/config" | tee -a ${LOGS}
  rsync -r "${SERVER_CUSTOM}/oxide/config/" "${GAME_ROOT}/oxide/config" | tee -a ${LOGS}
  # Merge global default, SRT Custom and other server-specific plugins into a single build
  rm -rf ${BUILD_ROOT}
  mkdir -p "${BUILD_ROOT}/oxide/plugins"
  echo "=> Updating Oxide plugins" | tee -a ${LOGS}
  rsync -ra --delete "${SERVER_GLOBAL}/oxide/plugins/" "${BUILD_ROOT}/oxide/plugins" | tee -a ${LOGS}
  rsync -ra "${SERVER_GLOBAL}/oxide/custom/" "${BUILD_ROOT}/oxide/plugins" | tee -a ${LOGS}
  rsync -ra "${SERVER_CUSTOM}/oxide/plugins/" "${BUILD_ROOT}/oxide/plugins" | tee -a ${LOGS}
  # Push customized plugins into the game root
  rsync -ra --delete "${BUILD_ROOT}/oxide/plugins/" "${GAME_ROOT}/oxide/plugins" | tee -a ${LOGS}
  rm -rf ${BUILD_ROOT}
  # Update plugin language and wording overrides
  LANG=(
    oxide/lang/en/Kits.json
    oxide/lang/en/Welcomer.json
    oxide/lang/en/Dance.json
    oxide/lang/ru/Dance.json
  )
  echo "=> Updating plugin language data" | tee -a ${LOGS}
  mkdir -p "${GAME_ROOT}/oxide/lang/en" "${GAME_ROOT}/oxide/lang/ru"
  for data in ${LANG[@]}; do
    echo " - $data" | tee -a ${LOGS}
    rsync "${SERVER_GLOBAL}/$data" "${GAME_ROOT}/$data" | tee -a ${LOGS}
    if [[ -f "${SERVER_CUSTOM}/$data" ]]; then
      rsync "${SERVER_CUSTOM}/$data" "${GAME_ROOT}/$data" | tee -a ${LOGS}
    fi
  done
  echo "=> loading dormant plugins" | tee -a ${LOGS}
  ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "o.load *" | tee -a ${LOGS}
  tail -n 24 "${GAME_ROOT}/RustDedicated.log"
}

function update_configs() {
  echo "=> Update Rust Server configs" | tee -a ${LOGS}
  mkdir -p ${GAME_ROOT}/server/solidrust/cfg | tee -a ${LOGS}
  rm ${GAME_ROOT}/server/solidrust/cfg/serverauto.cfg ## TODO, conditional, only if file exists
  rsync -a ${SERVER_CUSTOM}/server/solidrust/cfg/server.cfg ${GAME_ROOT}/server/solidrust/cfg/server.cfg | tee -a ${LOGS}
  rsync -a ${SERVER_GLOBAL}/cfg/users.cfg ${GAME_ROOT}/server/solidrust/cfg/users.cfg | tee -a ${LOGS}
  rsync -a ${SERVER_CUSTOM}/server/solidrust/cfg/users.cfg ${GAME_ROOT}/server/solidrust/cfg/users.cfg | tee -a ${LOGS}
  rsync -a ${SERVER_GLOBAL}/cfg/bans.cfg ${GAME_ROOT}/server/solidrust/cfg/bans.cfg | tee -a ${LOGS}
}

function update_maps() {
  echo "=> Update Rust custom maps configs" | tee -a ${LOGS}
  aws s3 sync --size-only --delete ${S3_WEB}/maps ${HOME}/solidrust.net/web/maps | tee -a ${LOGS}
}

function update_radio() {
  echo "=> Update Rust custom radio station" | tee -a ${LOGS}
  aws s3 sync --size-only --delete ${S3_RADIO} /var/www/radio | tee -a ${LOGS}
}

function update_server() {
  echo "=> Updating server: ${GAME_ROOT}" | tee -a ${LOGS}
  echo " - Buffing-up Debian Distribution..." | tee -a ${LOGS}
  sudo apt update | tee -a ${LOGS}
  sudo apt -y dist-upgrade | tee -a ${LOGS}
  # TODO: output a message to reboot if kernel or initrd was updated
  echo "=> Validating installed Steam components..." | tee -a ${LOGS}
  /usr/games/steamcmd +login anonymous +force_install_dir ${GAME_ROOT}/ +app_update 258550 validate +quit | tee -a ${LOGS}
  # Update RCON CLI tool
  echo " - No rcon found here, downloading it..." | tee -a ${LOGS}
  LATEST_RCON=$(curl https://github.com/gorcon/rcon-cli/releases | grep "/releases/tag" | head -n 1 | awk -F "v" '{ print $2 }' | rev | cut -c3- | rev)
  wget https://github.com/gorcon/rcon-cli/releases/download/v${LATEST_RCON}/rcon-${LATEST_RCON}-amd64_linux.tar.gz
  tar xzvf rcon-${LATEST_RCON}-amd64_linux.tar.gz
  mv rcon-${LATEST_RCON}-amd64_linux/rcon ${GAME_ROOT}/rcon
  rm -rf rcon-${LATEST_RCON}-amd64_linux*
  # Update uMod (Oxide) libraries
  echo "=> Updating uMod..." | tee -a ${LOGS}
  cd ${GAME_ROOT}
  wget https://umod.org/games/rust/download/develop -O \
    Oxide.Rust.zip &&
    unzip -o Oxide.Rust.zip &&
    rm Oxide.Rust.zip | tee -a ${LOGS}
  # Update Discord integrations
  echo "=> Downloading discord binary..." | tee -a ${LOGS}
  wget https://umod.org/extensions/discord/download -O \
    ${GAME_ROOT}/RustDedicated_Data/Managed/Oxide.Ext.Discord.dll | tee -a ${LOGS}
  # Update RustEdit libraries
  echo "=> Downloading RustEdit.io binary..." | tee -a ${LOGS}
  wget https://github.com/k1lly0u/Oxide.Ext.RustEdit/raw/master/Oxide.Ext.RustEdit.dll -O \
    ${GAME_ROOT}/RustDedicated_Data/Managed/Oxide.Ext.RustEdit.dll | tee -a ${LOGS}
  #echo "=> Downloading Rust:IO binary..." | tee -a ${LOGS}
  #wget http://playrust.io/latest -O \
  #    ${GAME_ROOT}/RustDedicated_Data/Managed/Oxide.Ext.RustIO.dll | tee -a ${LOGS}
}

function update_umod() {
  echo "Currently Disabled. This method causes conflicts now that we use custom plugins from many sources."
  #    echo "=> Download fresh plugins from uMod" | tee -a ${LOGS}
  #    cd ${GAME_ROOT}/oxide/plugins
  #    plugins=$(ls -1 *.cs)
  #    for plugin in ${plugins[@]}; do
  #        echo " - Attempting to replace $plugin from umod" | tee -a ${LOGS}
  #        wget "https://umod.org/plugins/$plugin" -O $plugin | tee -a ${LOGS}
  #        sleep 3 | tee -a ${LOGS}
  #    done
}

function update_permissions() {
  echo "=> Updating plugin permissions" | tee -a ${LOGS}
  echo " - \"o.load *\"" | tee -a ${LOGS}
  ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "o.load *" | tee -a ${LOGS}
  sleep 5
  for perm in ${DEFAULT_PERMS[@]}; do
    echo " - \"o.grant default $perm\""
    ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "o.grant group default $perm" | tee -a ${LOGS}
    sleep 5
  done
  echo "=> Reload permissions sync" | tee -a ${LOGS}

  ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "o.reload PermissionGroupSync" | tee -a ${LOGS}
}

function update_map_api() {
  echo "Updating Map API data" | tee -a ${LOGS}
  ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "rma_regenerate" | tee -a ${LOGS}
  sleep 10
  echo "Uploading Map to Imgur" | tee -a ${LOGS}
  ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "rma_upload default 1800 1 1" | tee -a ${LOGS}
  sleep 10
  IMGUR_URL=$(tail -n 1000 ${GAME_ROOT}/RustDedicated.log | grep "imgur.com" | tail -n 1 | awk '{print $4}')
  echo "Successfully uploaded: ${IMGUR_URL}" | tee -a ${LOGS}
  wget ${IMGUR_URL} -O ${GAME_ROOT}/oxide/data/LustyMap/current.jpg
  echo "Installed new map graphic: ${GAME_ROOT}/oxide/data/LustyMap/current.jpg" | tee -a ${LOGS}
  echo "Uploading to S3" | tee -a ${LOGS}
  aws s3 cp ${GAME_ROOT}/oxide/data/LustyMap/current.jpg ${S3_WEB}/maps/${HOSTNAME}.jpg
  ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "o.reload LustyMap" | tee -a ${LOGS}
}

# Default Game permissions
DEFAULT_PERMS=(
  vehicledeployedlocks.codelock.duosub
  vehicledeployedlocks.codelock.solosub
  vehicledeployedlocks.keylock.duosub
  vehicledeployedlocks.keylock.solosub
  skins.use
  craftchassis.2
  removertool.normal
  baserepair.use
  autolock.use
  backpacks.gui
  backpacks.use
  kits.defaultspawn
  bank.use
  bgrade.all
  vehicledeployedlocks.codelock.allvehicles
  vehicledeployedlocks.keylock.allvehicles
  carlockui.use.codelock
  carturrets.limit.2
  carturrets.allmodules
  trade.use
  trade.accept
  carturrets.deploy.command
  carturrets.deploy.inventory
  nteleportation.home
  nteleportation.deletehome
  nteleportation.homehomes
  nteleportation.importhomes
  nteleportation.radiushome
  nteleportation.tpr
  nteleportation.tpb
  nteleportation.tphome
  nteleportation.tptown
  nteleportation.tpoutpost
  nteleportation.tpbandit
  nteleportation.wipehomes
  securitylights.use
  vehiclevendoroptions.ownership.allvehicles
  autodoors.use
  automaticauthorization.use
  barrelpoints.default
  itemskinrandomizer.use
  itemskinrandomizer.reskin
  instantcraft.use
  furnacesplitter.use
  realistictorch.use
  raidalarm.use
  clearrepair.use
  treeplanter.use
  farmtools.clone
  farmtools.clone.all
  farmtools.harvest.all
  turretloadouts.autoauth
  turretloadouts.autotoggle
  turretloadouts.manage
  turretloadouts.manage.custom
  heal.self
  heal.player
  blueprintshare.toggle
  blueprintshare.share
  blueprintshare.use
  recyclerspeed.use
  dance.use
  securitycameras.use
  simpletime.use
  chute.allowed
  buildinggrades.use
  buildinggrades.up.all
  buildinggrades.down.all
  spawnmini.mini
  customgenetics.use
  spawnmini.nomini
  spawnmini.fmini
  signartist.url
  signartist.text
  signartist.restore
  signartist.raw
  signartist.restoreall
  fishing.allowed
  fishing.makepole
  optimalburn.use
  dronepilot.create
  dronelights.searchlight.autodeploy
  dronelights.searchlight.move
  fuelgauge.allow
  phonesplus.use
  privatemessages.allow
  quicksmelt.use
  quicksort.use
  quicksort.lootall
  quicksort.autolootall
  unwound.canuse
  quicksmelt.use
  craftsman.leveling.melee
  craftsman.leveling.ranged
  craftsman.leveling.clothing
  sleep.allow
  autocode.use
  autocode.try
  autobaseupgrade.use
  carcommander.use
  carcommander.canspawn
  carcommander.canbuild
  extendedrecycler.use
  statistics.use
  bounty.use
  Kits.default
  buildingworkbench.use
  iteminspector.use
  betterrootcombiners.use
  payforelectricity.use
  bloodtrail.allow
  patrolboat.builder
  localize.use
  vehiclevendoroptions.ownership.allvehicles
  crafts.use
  instantmixingtable.use
)

echo "SRT Update Functions initialized" | tee -a ${LOGS}
