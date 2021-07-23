#!/bin/bash

# You either need an app password for HTTPS mode or an app password and a ssh key for SSH mode (App password is needed to list all repos)
# Permissions for the app password needs to at least be "READ" on Projects and Repositories
# Require curl and git
# "Restore" git file : git clone repo.git

# Variables
backup_location="./backups"
bbuser="TO_FILL"
bbpass="TO_FILL"
workspace="TO_FILL"
mail_to="TO_FILL"

# How long to keep backups (ex: -1 month , -5 days , -2 years)
keep_time="-1 month"

# Git clone mode, HTTPS (app password) or SSH (key)
mode=https

# Changing the backup_date format will break the clean_up function
backup_date=$(date +%F_%H-%M)

# Remove backups older than $keep_time
clean_up () {
    keep_time_epoch=$(date --date="$keep_time" +%s)

    for bkp in $backup_location/*; do
        backup_name=$(basename $bkp)

        # If backup name has the following format : 0000-00-00_00-00
        if [[ "$backup_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}$ ]]; then
            formatted_date=$(sed -r 's/_/ /g; s/(.*)-/\1:/g' <<< $backup_name)
            bkp_epoch=$(date -d "$formatted_date" +%s)

            if [ -d "$bkp" ] && [ $bkp_epoch -lt $keep_time_epoch ]; then
                rm -R $bkp
            fi
        fi
    done

}

# Get every repos and their URL
bitbucket_get_urls () {

    # Get all repos URL from Bitbucket
    for page in {1..4} ; do
        curl --user $bbuser:$bbpass -s "https://api.bitbucket.org/2.0/repositories/$workspace?pagelen=100&page=$page" |tr , '\n' |tr -d '"{}[]' >> bb_url_list.tmp
    done

    # Grep only the "SSH link" or the clone URL for https
    if [ "$mode" == 'ssh' ]; then
        grep -i "git@bitbucket.org:" "bb_url_list.tmp" |cut -d" " -f3 > $backup_location/bitbucket_url_list
    elif [ "$mode" == 'https' ]; then
        grep -i " clone: href:" "bb_url_list.tmp" |cut -d" " -f4 > $backup_location/bitbucket_url_list
    fi

    rm -f bb_url_list.tmp
}

# Backup
bb_backup () {

    cd $backup_location/$backup_date

    local repos=$1
    local tmp_errors=$(mktemp --tmpdir=$temp_dir)
    local git_errors=$(mktemp --tmpdir=$temp_dir)
    local repoFolder=$(basename "$repos")

    # If the repo url contains the $workspace
    if [[ $repos =~ $bbuser ]] && [ $mode == "https" ]; then
        # Add password in URL so no prompt for it
        local repo=$(sed "0,/$bbuser/s//$bbuser:$bbpass/" <<< "$repos")
    elif [ $mode == "ssh" ]; then
        local repo=$repos
    fi

    # Cloning repos
    git clone --mirror $repo $repoFolder 2> $tmp_errors
    if [ $? -ne 0 ]; then
        cat $tmp_errors >> $git_errors
        echo -e "Error when cloning the following git repo : $repoFolder\nFull command : 'git clone --mirror $repos $repoFolder' (password removed from output)\n" >> $git_errors
    fi

    # Verify integrity
    git --git-dir $repoFolder fsck 2> $tmp_errors
    if [ $? -ne 0 ]; then
        cat $tmp_errors >> $git_errors
        echo -e "Error when verifying the following git repo : $repoFolder\nFull command : 'git --git-dir $repoFolder fsck'\n" >> $git_errors
    fi

    # If error during git commands add output to the global log
    if [ -s "$git_errors" ]; then
        cat $git_errors >> full_git_errors
    fi
}


# Script starts here
temp_dir=$(mktemp -d)
mkdir -p $backup_location/$backup_date

clean_up
bitbucket_get_urls

# If the following trigger it is either because the bbuser/bbpass/workspace are incorrect or that there are no repositories in the workspace
if [ ! -s "$backup_location/bitbucket_url_list" ]; then
    echo "No repository to backup"
    exit 1
fi

# Parallelisation of the backup function
# Number of concurrent process & number of iterations (= number of repos)
NUM_PROCS=5
NUM_ITERS=$(wc -l < $backup_location/bitbucket_url_list)

# For each repos, starts the backup of the repo in background with a maximum background job of $NUM_PROCS
for ((i=0; i<$NUM_ITERS; i++)); do
    let 'i>=NUM_PROCS' && wait -n
    bb_backup $(sed -n "$((i+1))"p $backup_location/bitbucket_url_list) &
done
wait

# If an error occured during the git clone or verify commands -> send mail to $mail_to
if [[ -s "$backup_location/$backup_date/full_git_errors" ]]; then
    subject="ERROR: Backup Bitbucket $workspace"
    message="$(cat $backup_location/$backup_date/full_git_errors)"
    /usr/bin/php -r 'mail("$mail_to","$subject","$message");'
fi

rm -rf $temp_dir
rm -f $backup_location/bitbucket_url_list $backup_location/$backup_date/full_git_errors
