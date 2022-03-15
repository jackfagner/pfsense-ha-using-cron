#!/bin/sh

# SCRIPT VERSION
#  2022-01-05

START_TIME=`date +%s`

# SETTINGS

# If test mode is set to "true", no changes will be made to aliases
TEST_MODE=true

# Logging
LOG_TO_FILE=false
LOG_PATH="/root/loadbalancer/logs_server1"
MAX_LOGFILES_TO_KEEP=60
LOG_ERRORS="$LOG_PATH/important.log"

# Notifications
SMS_NUMBERS="0044123456789"
NOTIFY_URL="https://sample-service.sample-push-notification.com/send-text"

# Max time (seconds) the script will run (usually less than 60 sec if using cron)
# Set to cron interval (60) minus SLEEP_BETWEEN_REQ (5)
MAX_RUNTIME=55

# Max number of failed requests before switching over to secondary server
MAX_FAILURES=3

# Number of successful requests (in a row) before returning to primary server
REQUIRED_SUCCESSFUL=3

# URL to be checking (primary server)
CHECK_HOST_PRIMARY=server1.domain.com
CHECK_IP_PRIMARY=10.1.1.101
CHECK_PORT_PRIMARY=443
CHECK_URL_PRIMARY="https://$CHECK_HOST_PRIMARY"
# URL to check before switching to secondary
CHECK_HOST_SECONDARY=server2.domain.com
CHECK_IP_SECONDARY=10.1.1.102
CHECK_PORT_SECONDARY=443
CHECK_URL_SECONDARY="https://$CHECK_HOST_SECONDARY"

# CARP IP check (public IP used by this service)
CARP_IP=142.250.74.142

# Return code to consider successful
SUCCESS_RETURN_CODE_PRIMARY=200
SUCCESS_RETURN_CODE_SECONDARY=200

# Alias settings
ALIAS_NAME=WebFarmInternalIP
PRIMARY_SERVER=10.1.1.101
SECONDARY_SERVER=10.1.1.102
ALIASTOOLS_PATH=/root/loadbalancer/aliastools.php

# Sleep between requests
SLEEP_BETWEEN_REQ=5


# VARIABLES (do not change)
NO_OF_FAILURES=0
NO_OF_SUCCESSFUL=0
RUN_TIME=0
CARP_MODE=UNKNOWN
CURRENT_ALIAS_IP=0.0.0.0
CURRENT_LOG_FILE=""

# FUNCTIONS

CHECK_PRIMARY_SERVER() {
    LOGMSG "Checking server"
    LAST_RETURN_CODE=`curl -I -4 --resolve "$CHECK_HOST_PRIMARY:$CHECK_PORT_PRIMARY:$CHECK_IP_PRIMARY" --connect-timeout 5 --max-time 10 "$CHECK_URL_PRIMARY" 2>/dev/null | head -n 1 | cut -d" " -f2`
    if [ "$LAST_RETURN_CODE" = "$SUCCESS_RETURN_CODE_PRIMARY" ]; then
        LOGMSG "Success"
        NO_OF_SUCCESSFUL=`expr $NO_OF_SUCCESSFUL + 1`
    else
        LOGMSG "ERROR! Last return code: $LAST_RETURN_CODE"
        NO_OF_FAILURES=`expr $NO_OF_FAILURES + 1`
        NO_OF_SUCCESSFUL=0 # Reset
    fi
}

VERIFY_SECONDARY_SERVER() {
    LOGMSG "Verifying secondary server"
    RETURN_CODE_SECONDARY=`curl -I -4 --resolve "$CHECK_HOST_SECONDARY:$CHECK_PORT_SECONDARY:$CHECK_IP_SECONDARY" --connect-timeout 5 --max-time 10 "$CHECK_URL_SECONDARY" 2>/dev/null | head -n 1 | cut -d" " -f2`
    if [ "$RETURN_CODE_SECONDARY" = "$SUCCESS_RETURN_CODE_SECONDARY" ]; then
        SECONDARY_SERVER_LIVE=true
    else
        LOGERR "ERROR! Secondary return code: $RETURN_CODE_SECONDARY"
        SECONDARY_SERVER_LIVE=false
    fi
}

UPDATE_RUNTIME() {
    RUN_TIME=`expr $(date +%s) - $START_TIME`
}

ASSERT_MAX_RUNTIME() {
    UPDATE_RUNTIME
    if [ $RUN_TIME -ge $MAX_RUNTIME ]; then
        LOGERR "The script has been running for $RUN_TIME seconds. Exiting"
        exit 2
    fi
}

CHECK_SCRIPT_RUNNING() {
    PROCESS_BASE_NAME=`basename "$0"`
    RUNNING_INSTANCE=`pgrep -f "$PROCESS_BASE_NAME"`
    if [ ! -z "$RUNNING_INSTANCE" ]; then
		LOGERR "ERROR: Script is already running. Waiting"
		while [ ! -z "$RUNNING_INSTANCE" ]; do
			sleep 1
			ASSERT_MAX_RUNTIME
			RUNNING_INSTANCE=`pgrep -f "$PROCESS_BASE_NAME"`
		done
    fi
}

CHECK_CARP_MASTER() {
    CARP_MODE=`ifconfig | grep " $(ifconfig | grep "$CARP_IP " | grep -Eo "vhid [0-9]+") " | grep -Eo "MASTER|BACKUP"`
    if [ "$CARP_MODE" = "MASTER" ]; then
        LOGMSG "CARP mode is: ${CARP_MODE}"
    elif [ "$CARP_MODE" = "" ]; then
        LOGERR "Unable to determine CARP mode for ${CARP_IP}. Exiting"
        exit 1
    else
        LOGMSG "Current CARP mode for $CARP_IP is: ${CARP_MODE}. Exiting"
        exit 1
    fi
}

CHECK_ALIAS_IP() {
    CURRENT_ALIAS_IP=`$ALIASTOOLS_PATH get $ALIAS_NAME`
    if [ "$CURRENT_ALIAS_IP" = "$PRIMARY_SERVER" ]; then
		LOGMSG "Alias $ALIAS_NAME is pointing to primary server ($PRIMARY_SERVER)"
    elif [ "$CURRENT_ALIAS_IP" = "$SECONDARY_SERVER" ]; then
		LOGMSG "N.B! Alias $ALIAS_NAME is pointing to secondary server ($SECONDARY_SERVER)"
    else
        LOGERR "WARNING! Alias $ALIAS_NAME is pointing to unknown IP: ${CURRENT_ALIAS_IP}. Exiting"
        exit 3
    fi
}

RESET_VARIABLES() {
    NO_OF_FAILURES=0
    NO_OF_SUCCESSFUL=0
    if [ "$TEST_MODE" != "true" ]; then
        CHECK_ALIAS_IP
    fi
}

FORCE_TO_PRIMARY() {
    LOGERR "Forcing alias $ALIAS_NAME to primary server: $PRIMARY_SERVER"
    CHECK_CARP_MASTER
    if [ "$TEST_MODE" != "true" ]; then
        $ALIASTOOLS_PATH set $ALIAS_NAME $PRIMARY_SERVER
        NOTIFY "WEBFARM: Primary server $PRIMARY_SERVER is back online. Moving traffic back to primary server."
    fi
    CURRENT_ALIAS_IP=$PRIMARY_SERVER # Assume it all went well?
}

FORCE_TO_SECONDARY() {
    LOGERR "Forcing alias $ALIAS_NAME to secondary server: $SECONDARY_SERVER"
    CHECK_CARP_MASTER
    VERIFY_SECONDARY_SERVER
    if [ "$SECONDARY_SERVER_LIVE" != "true" ]; then
		LOGERR "ERROR! Secondary server is not responding. Leaving alias unchanged."
		NOTIFY "WEBFARM: Warning! Both primary and secondary server are offline. Unable to move traffic to any working server."
    elif [ "$TEST_MODE" != "true" ]; then
        $ALIASTOOLS_PATH set $ALIAS_NAME $SECONDARY_SERVER
        NOTIFY "WEBFARM: Primary server $PRIMARY_SERVER is offline. Moving traffic to secondary server ${SECONDARY_SERVER}."
    fi
    CURRENT_ALIAS_IP=$SECONDARY_SERVER # Assume it all went well?
}

SETUP_LOGGING() {
    if [ "$LOG_TO_FILE" = "true" ]; then
        DELETE_OLD_LOGFILES
        READABLE_DATE=`date -j -r "$START_TIME" +%Y-%m-%d_%H-%M-%S`
        CURRENT_LOG_FILE="${LOG_PATH}/log_$READABLE_DATE.log"
        #exec > ${CURRENT_LOG_FILE}
    else
		CURRENT_LOG_FILE=""
    fi
}

DELETE_OLD_LOGFILES() {
    ls -tp ${LOG_PATH}/log_*.log | grep -v '/$' | tail -n +${MAX_LOGFILES_TO_KEEP} | xargs -I {} rm -- {}
}

LOGMSG() {
	echo "$1"
	if [ ! -z "$CURRENT_LOG_FILE" ]; then
		echo "$(date -j +%Y-%m-%d_%H-%M-%S) - $1" >> $CURRENT_LOG_FILE
	fi
}

LOGERR() {
	LOGMSG "$1"
	if [ ! -z "$LOG_ERRORS" ]; then
		echo "$(date -j +%Y-%m-%d_%H-%M-%S) - $1" >> $LOG_ERRORS
	fi
	# Notify?
	# NOTIFY "$1"
}

NOTIFY() {
	if [ ! -z "$NOTIFY_URL" ]; then
		curl -s -4 -o /dev/null --connect-timeout 10 --max-time 20 --data-urlencode "destination=$SMS_NUMBERS" --data-urlencode "text=$1" "$NOTIFY_URL" 2>/dev/null
	fi
}

# ACTUAL CODE

# Log to file
SETUP_LOGGING

LOGMSG "Starting up"

# Check if script is already running
CHECK_SCRIPT_RUNNING

# Check that we are CARP master
CHECK_CARP_MASTER

# Check if alias is pointed to primary or secondary server
CHECK_ALIAS_IP

UPDATE_RUNTIME
while [ $RUN_TIME -lt $MAX_RUNTIME ]; do
    CHECK_PRIMARY_SERVER

    if [ $NO_OF_FAILURES -ge $MAX_FAILURES ] && [ "$CURRENT_ALIAS_IP" = "$PRIMARY_SERVER" ]; then
        FORCE_TO_SECONDARY
        RESET_VARIABLES
    elif [ $NO_OF_SUCCESSFUL -ge $REQUIRED_SUCCESSFUL ] && [ "$CURRENT_ALIAS_IP" != "$PRIMARY_SERVER" ]; then
        FORCE_TO_PRIMARY
        RESET_VARIABLES
    fi

    # Sleep if we are not aleady overdue
    UPDATE_RUNTIME
    if [ $RUN_TIME -lt $MAX_RUNTIME ]; then
        sleep $SLEEP_BETWEEN_REQ
    fi

    UPDATE_RUNTIME
done

LOGMSG "Script is done for now. Exiting"

exit 0

