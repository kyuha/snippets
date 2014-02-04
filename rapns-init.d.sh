#! /bin/sh

# RAPNS
# Maintainer: @randx
# Authors: rovanion.luckey@gmail.com, @randx
# App Version: 6.0

### BEGIN INIT INFO
# Provides:          gitlab
# Required-Start:    $local_fs $remote_fs $network $syslog redis-server
# Required-Stop:     $local_fs $remote_fs $network $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: GitLab git repository management
# Description:       GitLab git repository management
### END INIT INFO


###
# DO NOT EDIT THIS FILE!
# This file will be overwritten on update.
# Instead add/change your variables in /etc/default/gitlab
# An example defaults file can be found in lib/support/init.d/gitlab.default.example
###


### Environment variables
RAILS_ENV="production"

# Script variable names should be lower-case not to conflict with
# internal /bin/sh variables such as PATH, EDITOR or SHELL.
app_user="bukalapak"
app_root="/home/$app_user/current"
pid_path="$app_root/tmp/pids"
rapns_pid_path="$pid_path/rapns.pid"

# Read configuration variable file if it is present
test -f /etc/default/rapns && . /etc/default/rapns

# Switch to the app_user if it is not he/she who is running the script.
if [ "$USER" != "$app_user" ]; then
  sudo -u "$app_user" -H -i $0 "$@"; exit;
fi

# Switch to the gitlab path, exit on failure.
if ! cd "$app_root" ; then
 echo "Failed to cd into $app_root, exiting!";  exit 1
fi


### Init Script functions

## Gets the pids from the files
check_pids(){
  if ! mkdir -p "$pid_path"; then
    echo "Could not create the path $pid_path needed to store the pids."
    exit 1
  fi
  # If there exists a file which should hold the value of the Rapns pid: read it.
  if [ -f "$rapns_pid_path" ]; then
    rpid=$(cat "$rapns_pid_path")
  else
    rpid=0
  fi
}

## Called when we have started the two processes and are waiting for their pid files.
wait_for_pids(){
  # We are sleeping a bit here mostly because sidekiq is slow at writing it's pid
  i=0;
  while [ ! -f $rapns_pid_path ]; do
    sleep 0.1;
    i=$((i+1))
    if [ $((i%10)) = 0 ]; then
      echo -n "."
    elif [ $((i)) = 301 ]; then
      echo "Waited 30s for the processes to write their pids, something probably went wrong."
      exit 1;
    fi
  done
  echo
}

# We use the pids in so many parts of the script it makes sense to always check them.
# Only after start() is run should the pids change. Sidekiq sets it's own pid.
check_pids


## Checks whether the different parts of the service are already running or not.
check_status(){
  check_pids
  # If the web server is running kill -0 $wpid returns true, or rather 0.
  # Checks of *_status should only check for == 0 or != 0, never anything else.
  if [ $rpid -ne 0 ]; then
    kill -0 "$rpid" 2>/dev/null
    rapns_status="$?"
  else
    rapns_status="-1"
  fi

}

## Check for stale pids and remove them if necessary.
check_stale_pids(){
  check_status
  # If there is a pid it is something else than 0, the service is running if
  # *_status is == 0.
  if [ "$rpid" != "0" -a "$rapns_status" != "0" ]; then
    echo "Removing stale Rapns pid. This is most likely caused by the web server crashing the last time it ran."
    if ! rm "$rapns_pid_path"; then
      echo "Unable to remove stale pid, exiting."
      exit 1
    fi
  fi
}

## If no parts of the service is running, bail out.
exit_if_not_running(){
  check_stale_pids
  if [ "$rapns_status" != "0" ]; then
    echo "Rapns is not running."
    exit
  fi
}

## Starts Unicorn and Sidekiq if they're not running.
start() {
  check_stale_pids

  if [ "$rapns_status" != "0" ]; then
    echo -n "Starting Rapns"
  fi

  # Then check if the service is running. If it is: don't start again.
  if [ "$rapns_status" = "0" ]; then
    echo "The Rapns already running with pid $rpid, not restarting."
  else
    # Start the web server
    RAILS_ENV=$RAILS_ENV bundle exec rapns $RAILS_ENV -p $rapns_pid_path
  fi

  # Wait for the pids to be planted
  wait_for_pids
  # Finally check the status to tell wether or not GitLab is running
  print_status
}

## Asks the Unicorn and the Sidekiq if they would be so kind as to stop, if not kills them.
stop() {
  exit_if_not_running

  if [ "$rapns_status" = "0" ]; then
    echo -n "Shutting Rapns"
  fi

  # If the Unicorn web server is running, tell it to stop;
  if [ "$rapns_status" = "0" ]; then
    kill -INT $rpid
  fi

  # If something needs to be stopped, lets wait for it to stop. Never use SIGKILL in a script.
  while [ "$rapns_status" = "0" ]; do
    sleep 1
    check_status
    printf "."
    if [ "$rapns_status" != "0" ]; then
      printf "\n"
      break
    fi
  done

  sleep 1
  # Cleaning up unused pids
  rm "$rapns_pid_path" 2>/dev/null

  print_status
}

## Prints the status of GitLab and it's components.
print_status() {
  check_status
  if [ "$rapns_status" = "0" ]; then
    echo "The Rapns with pid $rpid is running."
  else
    printf "The Rapns is \033[31mnot running\033[0m.\n"
  fi
}

## Restarts Sidekiq and Unicorn.
restart(){
  check_status
  if [ "$rapns_status" = "0" ]; then
    stop
  fi
  start
}


### Finally the input handling.

case "$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    restart
    ;;
  status)
    print_status
    exit $gitlab_status
    ;;
  *)
    echo "Usage: service rapns {start|stop|restart|status}"
    exit 1
    ;;
esac

exit
