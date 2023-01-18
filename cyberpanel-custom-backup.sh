#!/bin/bash
# manual: https://community.cyberpanel.net/t/cyberpanel-command-line-interface/30683

function require_root {
	if [[ $(id -u "$(whoami)") -ne 0 ]];then
		echo "You are $(whoami)"
		echo "Require root"
		exit
	fi
}

function require_cyberpanel {
	if [[ -z $(which cyberpanel) ]];then
		echo "Only work for CyberPanel"
		exit
	fi
}

function require_ncftp {
	if [[ -z $(which ncftpput) ]];then
		# install ncftp
		apt-get install ncftp
	fi
}

function init_vars {
	BACKUP=/backup
	RETENTION=7
	BACKUPDIR=$BACKUP/$(date +%F)
}

function init_backupdir {
	if [[ ! -d "$BACKUPDIR" ]];then
		mkdir -p "$BACKUPDIR"
	fi
}

function backup_homedir {
	mkdir -p "$BACKUPDIR"/website/
	tar -cvzf "$BACKUPDIR"/website/"$WEBSITE".tar.gz /home/"$WEBSITE"
}

function backup_mysql {
	mkdir -p "$BACKUPDIR"/mysql/"$WEBSITE"
	cyberpanel listDatabasesPretty --databaseWebsite "$WEBSITE"|awk '{print $4}'|sed "s/Database//g"|sort|while read -r SQL;do 
		if [[ -n "$SQL" ]];then
			mysqlcheck -r "$SQL";
			mysqldump "$SQL" > "$BACKUPDIR"/mysql/"$WEBSITE"/"$SQL".sql;
		fi
	done
}

function backup_dnszone {
	mkdir -p "$BACKUPDIR"/dnszone/
	mysql -Bse "use cyberpanel;select name,type,ttl,content from records;"|grep "$WEBSITE" > "$BACKUPDIR"/dnszone/"$WEBSITE".db
}

function ftp_upload {
	if [[ -f /root/.netrc ]];then
		FTPUSERNAME=$(awk '/login/ {print $2}' /root/.netrc)
		FTPPASSWORD=$(awk '/password/ {print $2}' /root/.netrc)
		FTPHOSTNAME=$(awk '/machine/ {print $2}' /root/.netrc)
		if [[ -n $FTPUSERNAME ]] && [[ -n $FTPPASSWORD ]] && [[ -n $FTPHOSTNAME ]];then
			ncftpput -R -v -u "$FTPUSERNAME" -p "$FTPPASSWORD" "$FTPHOSTNAME" . "$BACKUPDIR"
		fi
	else
		echo "/root/.netrc not found"
		echo "echo 'machine [FTP Hostname]' > /root/.netrc"
		echo "echo 'login [FTP Username]' >> /root/.netrc"
		echo "echo 'password [FTP Password]' >> /root/.netrc"
		echo "Whitelist Passive Port Range 49152:65534"
	fi
}

function total_backup {
	TOTAL_BACKUP=$(find $BACKUP -name "[0-9][0-9][0-9][0-9]\-[0-9][0-9]\-[0-9][0-9]" -type d|wc -l)
}

function retention_backup {
	if [[ "$TOTAL_BACKUP" -gt "$RETENTION" ]];then
		TOTALDEL=$(( "$RETENTION" - "$TOTAL_BACKUP" ))
		find "$BACKUP" -name "[0-9][0-9][0-9][0-9]\-[0-9][0-9]\-[0-9][0-9]" -type d|sort|head -n "$TOTALDEL"|while read -r DELBACKUP;do
			if [[ -d "$DELBACKUP" ]];then
				rm -rf "$DELBACKUP";
			fi
		done
fi
}

# main program

# requirement check
require_root
require_cyberpanel
require_ncftp

init_vars
init_backupdir
cyberpanel listWebsitesPretty|awk '/Active/ {print $4}'|while read -r WEBSITE;do echo "$WEBSITE";
	backup_homedir
	backup_mysql
	backup_dnszone
done

total_backup
retention_backup
ftp_upload
