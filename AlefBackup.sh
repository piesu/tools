#!/bin/bash
# AlefBackup 
# made by Pies
# script uses rsync

# TODO:
# - allow to be over ssh both source and destination
# - allow rsync overs ssh tunel
# - check if backup is running, don't start second
# - check left space on disk - use readlink, mount, df
# - generate raports for sending

# Changelog:
#
# 0.3.8.3:
#  - added list of acceptable error codes that will mean backup ended successful
#    (like error 24 - some files vanished during copying. Pretty normal for mail servers)
#
# 0.3.8.2:
#  - added --checksum - for every file will be run md5sum
#
# 0.3.8.1:
#  - last link isn't changed if backup wasn't succesful
#  - backup isn't added to daily etc files if wasn't successful

VERSION='v0.3.8.3'

usage()
{
echo "AlefBackup $VERSION 
 made by Pies
 script uses rsync

Usage: backup [OPTION] source destination

Options:
 -h, --help       print this help info
 -q, --quiet      don't output anything
 -s, --ssh        let source be accessible by ssh
                  ssh server must be configured in ~/.ssh/config
                  access must by possible by keys
 -d, --dry-run    dry run, do nothing, show everything
 -v, --verbose    show everything
 -n, --new        create new dir for backups
"
exit
}

new()
{

show "Creating place for backups"
if [[ ! -e $dst ]] ; then
  mkdir $dst
fi

if [[ ! -e $dst/last ]] ; then 
  mkdir $dst/empty
  ln -s $dst/empty $dst/last
  touch $dst/empty.log
  ln -s $dst/empty.log $dst/last.log
fi

if [[ ! -e $dst/rules ]]
then
  echo "# Please enter what should be backuped and what shouldn't
#
# start line with \"+\" to add directory/files to backup and \"-\" to remove
" >> "$dst/rules"
fi

if [[ ! -e $dst/config ]]
then
  echo "# Config file for AlefBackup
#
# Default config will made:
# - 14 backups from last 14 days (1 each day)
# - 12 backups from last 12 months (1 each 30 days)
# -  4 backups from last 4 years (1 each 365 days)

# there should be no more then #n of daily backups (Default 14)
daily_num=14

# daily backups should be made no before end of #n days (Default 1)
daily_freq=1


# there should be no more then #n of monthly backups (Default 12)
monthly_num=12

# monthly backups should be made no before end of #n days (Default 30)
monthly_freq=30

# there should be no more then #n of yearly backups (Default 4)
yearly_num=4
# yearly backups should be made no before end of #n days (Default 365)
yearly_freq=365

" >> "$dst/config"
fi



editor "$dst/rules"
editor "$dst/config"

show "Dirs created, first backup is starting"

}

# Filter for quiet runs
show()
{
if [[ ! $quiet ]]
  then
  echo $1
fi
}



backup()
{

if [[ $ssh = true ]]
  then
  src="-e ssh $src"
#  if [[ "`echo $src | grep -v \":\"`" ]]
#    then
#    src="$src:/"
#  fi
fi

acceptable_errors="24"

BACKUP_DIR=${dst%/}

rules=${BACKUP_DIR}/rules
date=`date +%Y-%m-%d_%H%M`

date_clear=`echo $date |sed -e 's/[-_]//g'`
daily_clear=`tail -n1 ${BACKUP_DIR}/daily | sed -e 's/[-_]//g'`
monthly_clear=`tail -n1 ${BACKUP_DIR}/monthly | sed -e 's/[-_]//g'`
yearly_clear=`tail -n1 ${BACKUP_DIR}/yearly | sed -e 's/[-_]//g'`

if [[ `date -d "$daily_freq days ago"  +%Y%m%d9999` -gt $daily_clear ]]
then
  daily_on=true
else
  daily_on=false
fi

if [[ `date -d "$monthly_freq days ago"  +%Y%m%d9999` -gt $monthly_clear ]]
then
  monthly_on=true
else
  monthly_on=false
fi

if [[ `date -d "$yearly_freq days ago"  +%Y%m%d9999` -gt $yearly_clear ]]
then
  yearly_on=true
else
  yearly_on=false
fi

if ! $yearly_on && ! $monthly_on && ! $daily_on 
then
 show "This isn't time for any backup!"
 return 
fi

if [[ ! $dry ]]
then
  backup=${BACKUP_DIR}/$date
  mkdir $backup
  show "Created dir $backup" 
  last=${BACKUP_DIR}/last
else
  backup=${BACKUP_DIR}
  last=${BACKUP_DIR}/last
fi

show "Backuping..."
attributes="--archive --human-readable --delete --include-from $rules --link-dest=$last"

# don't check only time and size, let rsync md5sum every file
attributes="--checksum $attributes"

if [[ $dry ]]
then
  attributes="$attributes --dry-run --verbose"
else
  attributes="$attributes --log-file=${backup}.log"
fi

if [[ $verbose ]] && [[ ! $dry ]]
then
  attributes="$attributes --verbose"
fi

rsync $attributes $src $backup
success=$?

real_success=$success

# some errors are acceptable
for k in $acceptable_errors; 
do 
 if [[ $k -eq $success ]]; 
 then 
  success=0; 
 fi; 
done;


if [[ ! $dry ]] && [[ $success == 0 ]]
then
  rm $last
  ln -s $backup $last
  rm $last.log
  ln -s $backup.log $last.log
  if $daily_on 
  then
    echo $date >> $daily
    show "$date >> $daily"
  fi
  if $monthly_on 
  then
    echo $date >> $monthly
    show "$date >> $monthly"
  fi
  if $yearly_on 
  then
    echo $date >> $yearly
    show "$date >> $yearly"
  fi
fi 

if [[ ! $dry ]] && [[ $success != 0 ]]
then
  echo "$date error $success" >> $failed
fi


show "Everything done, be happy with your new backup!"
}

delete_old()
{

if [[ $daily_num -gt 0 ]]
then      
  num_of_daily=`wc -l $daily |cut -f1 -d' '`


  if [[ $num_of_daily -gt $daily_num ]]
  then
    head $daily -n $(( $num_of_daily - $daily_num )) | while read old ;
    do
      if ! grep $old $monthly > /dev/null
      then
        if ! grep $old $yearly > /dev/null
        then
          rm -rf ${dst%/}/$old
          echo "rm -rf ${dst%/}/$old"
        fi
      fi
    tail $daily -n $daily_num > $daily.tmp
    rm $daily
    mv $daily.tmp $daily
    done
 
  fi
fi

if [[ $monthly_num -gt 0 ]]
then
  num_of_monthly=`wc -l $monthly |cut -f1 -d' '`

  if [[ $num_of_monthly -gt $monthly_num ]]
  then
    head $monthly -n $(( $num_of_monthly - $monthly_num )) | while read old ;
    do
      if ! grep $old $daily > /dev/null
      then
        if ! grep $old $yearly > /dev/null
        then
          rm -rf ${dst%/}/$old
          echo "rm -rf ${dst%/}/$old"
        fi
      fi
    done
    tail $monthly -n $monthly_num > $monthly.tmp
    rm $monthly
    mv $monthly.tmp $monthly
  fi
fi

if [[ $yearly_num -gt 0 ]]
then
  num_of_yearly=`wc -l $yearly |cut -f1 -d' '`

  if [[ $num_of_yearly -gt $yearly_num ]]
  then
    head $yearly -n $(( $num_of_yearly - $yearly_num )) | while read old ;
    do
      if ! grep $old $daily > /dev/null
      then
        if ! grep $old $monthly > /dev/null
        then
          rm -rf ${dst%/}/$old
          echo "rm -rf ${dst%/}/$old"
        fi
      fi
    done
    tail $yearly -n $yearly_num > $yearly.tmp
    rm $yearly
    mv $yearly.tmp $yearly

  fi
fi

}

config()
{

if [[ ! $config ]]
then 
  config=${dst%/}/config
  source $config
fi

if [[ ! $failed ]]
then 
  failed=${dst%/}/failed
fi


daily=${dst%/}/daily

if [[ ! $daily_num ]]
then
  daily_num=0
fi

if [[ ! $daily_freq ]]
then
  daily_freq=0
fi

monthly=${dst%/}/monthly

if [[ ! $monthly_num ]]
then 
 monthly_num=0
fi

if [[ ! $monthly_freq ]]
then 
 monthly_freq=30
fi

yearly=${dst%/}/yearly

if [[ ! $yearly_num ]]
then 
 yearly_num=0
fi

if [[ ! $yearly_freq ]]
then 
 yearly_freq=365
fi

}


# If run without arguments, then show help
if [[ $# = 0 ]]
then 
  usage
fi  


debug()
{
echo "ssh=$ssh"
echo "quiet=$quiet"
echo "dry=$dry"
echo "verbose=$verbose"
echo "src=$src"
echo "dst=$dst"


}



tmp=`getopt -o hsqdvn --long help,quiet,ssh,dry-run,verbose,new \
     -n 'AlefBackup' -- "$@"`
eval set -- "$tmp"
tmp=''

while true ; do
  case "$1" in
    -h|--help)  usage ; exit ;;
    -s|--ssh)   ssh=true ; shift ;;
    -q|--quiet) quiet=true ; shift ;;
    -d|--dry-run) dry=true ; shift ;;
    -v|--verbose) verbose=true ; shift ;;
    -n|--new)     new=true ; shift ;;
   --) shift ; break ;;
    *) usage ; exit ;;
  esac
done

if [[ "$1" ]]
then 
  src="$1" 
  shift 
else 
  echo "You have to specify source of backup" 
  exit 1
fi

if [[ "$1" ]]
then 
  case "$1" in
    /*) dst=$1 ;;
    *) dst=`pwd`/$1 ;;
  esac
  shift 
else 
  echo "You have to specify destination of backup" 
  exit 1
fi

if [[ "$1" ]]
then
  echo "Too much arguments!"
  exit 1
fi

if [[ $new ]]
then
  new
fi

config
backup
delete_old
