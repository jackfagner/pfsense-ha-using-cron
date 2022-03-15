# pfsense-ha-using-cron
Cron script for monitoring high availability services when relayd was removed from pfSense


Sample usange:
1. Upload pfsense_load_balancer_server1.sh and aliastools.php to /root/loadbalancer/
2. Change the settings in pfsense_load_balancer_server1.sh
3. Create a crontab job (using cron plugin) and run this script every minute: /root/loadbalancer/pfsense_load_balancer_server1.sh
