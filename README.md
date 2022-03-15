# pfsense-ha-using-cron
Cron script for monitoring high availability services when relayd was removed from pfSense


Assumption:
1. One primary server and one secondary
2. The service availability is monitored using HTTPS requests
3. pfSense is setup in a HA enviorment using CARP IP

Sample usage:
1. Upload pfsense_load_balancer_server1.sh and aliastools.php to /root/loadbalancer/
2. Change the settings in pfsense_load_balancer_server1.sh
3. Create a crontab job (using cron plugin) and run this script every minute: /root/loadbalancer/pfsense_load_balancer_server1.sh
4. Run the same script on all your pfSense firewalls (CARP masters and slaves). The script will only run if the current pfSense machine is CARP master

You can use this solution in an active-active HA setup, where you have two internal web servers hostings different sites. By duplicating the pfsense_load_balancer_server1.sh and running two scripts (pfsense_load_balancer_server1.sh and pfsense_load_balancer_server2.sh) on each pfSense server you can move all HTTPS traffic to the working web server if either of the internal web servers fail.
