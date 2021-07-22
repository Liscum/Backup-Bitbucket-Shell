# Backup-Bitbucket-Shell

This repository contains 2 shell scripts to backup an entire Bitbucket workspace locally. One script is for Linux in general and the other is for Synology. 

The scripts will send an e-mail in case the git commands encounters an errors during cloning the repositories. The package I used to send mails on Linux is Mailutils and as it is not installed by default on Synology I made a specific version for Synology using the already installed mail function of PHP.

This script backups all the repositories of the given workspace and save it as "myRepo.git" to the desired location. It works by using "git clone --mirror myRepo".
To make the script faster I used parallelization for the backup as it considerably reduce the backup time (5 mins for 90 repos (~9go) instead of 35 mins).

The script will also clean up all backups older than what is specified in the "keep_time" variable, so no need to worry about cleaning old backups.

# Requirements

* Linux version : curl, git and mailutils

* Synology version : curl and git (can be installed via the package center)


# Usage

The Bitbucket user, password and workspace need to be set in the script to run it.

`./bb_backup_linux.sh`

`./bb_backup_synology.sh`



