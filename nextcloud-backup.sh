#!/bin/bash
# Backup nextcloud to remote storage via ssh
# Preconditions: rsync, ssmtp, ssh,
#   key-based login to remote host via ssh


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~ Configuration                 ~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
MONTHROTATE=monthrotate
RSYNCCONF=(--delete)
SSH="/usr/bin/ssh"; LN="/bin/ln"; ECHO="/bin/echo"
DATE="/bin/date"; MAIL="ssmtp"
RSYNC="/usr/bin/rsync"; LAST="last";

SOURCES=()
TARGET=""

MAILRECEIVER=""
MAILSENDER=""
MAILSUBJECT="Nextcloud Backup SUCCESS"

SSHUSER=""
SSHHOST=""
SSHPORT=22

DBHOST=""
DBUSER=""
DBPASSWORD=""
DATABASE=""
DBBACKUPFOLDER=""
DBBACKUPFILE="$DBBACKUPFOLDER/nextcloud-db-backup.bak"

# variables have to be set via external configuration file
. ./nextcloud-backup.config

INC="--link-dest=$TARGET/$LAST"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~ Initializaion stuff  ~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~
LOG=$0.log
$ECHO "$($DATE) - Starting backup procedure..." > $LOG

if [ "${TARGET:${#TARGET}-1:1}" != "/" ]; then
  TARGET=$TARGET/
fi

if [ -z "$MONTHROTATE" ]; then
  TODAY=$($DATE +%y%m%d)
else
  TODAY=$($DATE +%d)
fi


function rsync_command() {
  $ECHO "$RSYNC -e \"$1\" $2 \"$3\" $4 \"$5\" $INC " >> $LOG
  $RSYNC -e "$1" $2 "$3" $4 "$5" $INC >> $LOG 2>&1
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~ Dump database to local directory. Later this folder   ~~
# ~~ will be rsync-ed to remote backup storage             ~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
$ECHO "" >>$LOG
$ECHO "$($DATE) - Performing DB-Dump to $DBBACKUPFILE..." >>$LOG
$ECHO "mysqldump --lock-tables -h $DBHOST  -u $DBUSER --password=*****  --databases $DATABASE" >>$LOG
if mysqldump --skip-comments --lock-tables -h $DBHOST  -u $DBUSER  --password=$DBPASSWORD  --databases $DATABASE 2>>$LOG  >"$DBBACKUPFILE"
then
    $ECHO -e "mysqldump successfully finished" >> $LOG
else
    $ECHO -e "mysqldump failed" >> $LOG
fi


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~ Perform backup via ssh of SOURCE folders and the folder  ~~
# ~~ containing the db dump created previously                ~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
$ECHO "" >>$LOG
$ECHO "$($DATE) - Performing backup of folders..." >>$LOG
if [ "$SSHUSER" ] && [ "$SSHPORT" ] && [ "SSHHOST" ]; then
  S="$SSH -p $SSHPORT -l $SSHUSER";

  #use -c for the db dump to avoid it is copied each time (rsync must not consider file's creation date)
  rsync_command "$S" "-avRc" "$DBBACKUPFOLDER" "${RSYNCCONF[@]}" "$SSHHOST:$TARGET$TODAY"
  for SOURCE in "${SOURCES[@]}"
    do
      rsync_command "$S" "-avR" "$SOURCE" "${RSYNCCONF[@]}" "$SSHHOST:$TARGET$TODAY"
      if [ $? -ne 0 ]; then
        ERROR=1
      fi
  done

  $ECHO "$SSH -p $SSHPORT -l $SSHUSER $SSHHOST $LN -nsf $TARGET$TODAY $TARGET$LAST" >> $LOG
  $SSH -p $SSHPORT -l $SSHUSER $SSHHOST "$LN -nsf \"$TARGET\"$TODAY \"$TARGET\"$LAST" >> $LOG 2>&1
  if [ $? -ne 0 ]; then
    ERROR=1
  fi
fi

$ECHO "" >>$LOG
$ECHO "$($DATE) - Backup procedure finished." >>$LOG


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~ Inform about status of the backup via email  ~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
if [ -n "$MAILRECEIVER" ] && [ -n "$MAILSENDER" ]; then
  if [ $ERROR ];then
    MAILSUBJECT="Nextcloud Backup ERROR $LOG"
  fi
  {
    echo To: $MAILRECEIVER
    echo From: $MAILSENDER
    echo Subject: $MAILSUBJECT
    echo
    cat  $LOG
  } | ssmtp $MAILRECEIVER
fi

