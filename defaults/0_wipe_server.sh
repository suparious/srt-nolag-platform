#!/bin/bash
## Install on:
# - Game Server
#
## crontab example:
#      M H    D ? Y
#echo "0 0    * * *   ${USER}  /bin/sh -c ${HOME}/solidrust.net/defaults/99_wipe_server.sh" | sudo tee -a /etc/crontab

case "$1" in
    now | fast )
        echo "performing a Quick Wipe"
        initialize
        update_config
        wipe_map
        change_seed
        update_ip
        update_rust
        start_rust
        ;;
    *)
        echo "performing a Standard Wipe"
        initialize
        notification
        backup
        update_config
        wipe_map
        change_seed
        update_ip
        update_rust
        start_rust
        update_map_api
        ;;
esac

initialize {
    source ${HOME}/solidrust.net/defaults/env_vars.sh
    me=$(basename -- "$0")
    echo "====> Starting ${me}: ${LOG_DATE}" | tee -a ${LOGS}
}

notification() {
    echo "Notifying players with 1 hour warning" | tee -a ${LOGS}
    ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "restart 3600 \"Scheduled map wipe is about to begin.\""
    sleep 3590
    echo "Backing-up server to local disk" | tee -a ${LOGS}
    ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "server.writecfg"
    sleep 1
    ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "server.save"
    sleep 5
    ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "server.backup"
    sleep 4
}

backup() {
    echo "Uploading backup to s3" | tee -a ${LOGS}
    CONTENTS=(
        oxide
        server
        backup
    )
    
    for folder in ${CONTENTS[@]}; do
        echo "sync ${GAME_ROOT}/$folder to ${S3_BACKUPS}/servers/${HOSTNAME}/$folder" | tee -a ${LOGS}
        aws s3 sync --quiet --delete ${GAME_ROOT}/$folder ${S3_BACKUPS}/servers/${HOSTNAME}/$folder | tee -a ${LOGS}
        sleep 1
    done
}

update_config() {
    /bin/sh -c ${HOME}/solidrust.net/defaults/40_sync_oxide_mods.sh
    /bin/sh -c ${HOME}/solidrust.net/defaults/44_sync_server_config.sh
    # update repo
    echo "Downloading repo from s3" | tee -a ${LOGS}
    aws s3 sync --only-show-errors --delete ${S3_BACKUPS}/repo ${HOME}/solidrust.net | tee -a ${LOGS}
    # Pull global env vars
    echo "Reloading global environment variables" | tee -a ${LOGS}
    source ${HOME}/solidrust.net/defaults/env_vars.sh
    
    # Update Rust server config
    echo "Update Rust Server configs" | tee -a ${LOGS}
    mkdir -p ${GAME_ROOT}/server/solidrust/cfg | tee -a ${LOGS}
    rsync -a ${SERVER_CUSTOM}/server/solidrust/cfg/server.cfg ${GAME_ROOT}/server/solidrust/cfg/server.cfg | tee -a ${LOGS}
    rsync -a ${SERVER_GLOBAL}/cfg/users.cfg ${GAME_ROOT}/server/solidrust/cfg/users.cfg | tee -a ${LOGS}
    rsync -a ${SERVER_GLOBAL}/cfg/bans.cfg ${GAME_ROOT}/server/solidrust/cfg/bans.cfg | tee -a ${LOGS}
    echo "Update custom maps" | tee -a ${LOGS}
    aws s3 sync ${S3_WEB}/maps ${GAME_ROOT}/server/solidrust | tee -a ${LOGS}
}

wipe_map() {
    echo "Wipe out old Procedural maps and related data" | tee -a ${LOGS}
    rm -rf ${GAME_ROOT}/server/solidrust/proceduralmap.*
}

change_seed() {
    export SEED=$(shuf -i 1-2147483648 -n 1)
    echo "New Map Seed generated: ${SEED}" | tee -a ${LOGS}
    echo ${SEED} > ${GAME_ROOT}/server.seed
    sed -i "/server.seed/d" ${GAME_ROOT}/server/solidrust/cfg/server.cfg
    echo "server.seed \"${SEED}\"" >> ${GAME_ROOT}/server/solidrust/cfg/server.cfg
    echo "Installed new map seed to ${GAME_ROOT}/server/solidrust/cfg/server.cfg" | tee -a ${LOGS}
}

update_ip() {
    export IP=$(curl -s http://whatismyip.akamai.com/)
    echo ${IP} > ${GAME_ROOT}/app.publicip
    sed -i "/app.publicip/d" ${GAME_ROOT}/server/solidrust/cfg/server.cfg
    echo "Updating public IP to: \"${IP}\" " | tee -a ${LOGS}
    echo "app.publicip \"${IP}\"" >> ${GAME_ROOT}/server/solidrust/cfg/server.cfg
}

update_rust() {
    echo "Update game service and integrations" | tee -a ${LOGS}
    /bin/sh -c ${HOME}/solidrust.net/defaults/update_rust_service.sh
}

start_rust() {
    echo "Start RustDedicated game service" | tee -a ${LOGS}
    /bin/sh -c ${HOME}/solidrust.net/defaults/solidrust.sh &
    echo "Delaying for about 8mins while service loads" | tee -a ${LOGS}
    sleep 500
    echo "Should be ready for action" | tee -a ${LOGS}
}

update_map_api() {
    echo "Updating Map API data" | tee -a ${LOGS}
    ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "rma_regenerate" | tee -a ${LOGS}
    sleep 10
    echo "Uploading Map to Imgur" | tee -a ${LOGS}
    ${GAME_ROOT}/rcon --log ${LOGS} --config ${RCON_CFG} "rma_upload default 2000 1 1" | tee -a ${LOGS}
    sleep 10
    IMGUR_URL=$(tail -n 1000 ${GAME_ROOT}/RustDedicated.log | grep "imgur.com" | tail -n 1 | awk '{print $4}')
    echo "Successfully uploaded: ${IMGUR_URL}" | tee -a ${LOGS}
    echo "Uploading to S3"
    wget ${IMGUR_URL} -O ${GAME_ROOT}/${HOSTNAME}.jpg
    aws s3 cp ${GAME_ROOT}/${HOSTNAME}.jpg ${S3_WEB}/maps/
}

echo "Finished ${me}"   | tee -a ${LOGS}
exit 0