#!/usr/local/bin/php-cgi -q
<?php
/*
 * aliastools
 *
 * part of pfSense (https://www.pfsense.org)
 * Copyright (c) 2010-2013 BSD Perimeter
 * Copyright (c) 2013-2016 Electric Sheep Fencing
 * Copyright (c) 2014-2021 Rubicon Communications, LLC (Netgate)
 * All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


require_once("globals.inc");
require_once("config.inc");
require_once("pfsense-utils.inc");
require_once("filter.inc");

$message = "";

if (($argc > 1) && !empty($argv[1])) {
	$message = "";
	$message = aliastools($argv[1], $argv[2], $argv[3]);
    echo $message . "\n";
} else {
	// Print usage:
	echo "usage:\n";
	echo " Set IP/FQDN entry to the Alias\n";
	echo "     " . basename($argv[0]) . " set <alias> <IP/FQDN>\n";
	echo "\n";
	echo " Get IP/FQDN entry from the Alias\n";
	echo "     " . basename($argv[0]) . " get <alias>\n";
	echo "\n";
	echo " Set example:\n";
	echo "     " . basename($argv[0]) . " set webserver 192.168.1.10\n";
	echo "\n";
	echo " Get example:\n";
	echo "     " . basename($argv[0]) . " get webserver\n";
	echo "\n";
}

function aliastools($act, $alias, $entry) {
	global $reserved_table_names, $config, $g;

	if (!in_array($act, array('get', 'set'))) {
		return "ERROR: Invalid action";
	}

	if (!is_array($config['aliases']) || !is_alias($alias) ||
	    in_array($alias, $reserved_table_names) || (alias_get_type($alias) != 'host')) {
		return "ERROR: Alias not found";
	}

	if ($act == 'set' && !is_ipaddr($entry) && !is_domain($entry)) {
		return "ERROR: Invalid host/IP";
	}

	foreach ($config['aliases']['alias'] as & $als) {
		if ($als['name'] != $alias) {
			continue;
		}
		if ($act == 'set') {
			$als['address'] = $entry;
			$als['detail'] = sprintf(gettext("Entry set %s"), date('r'));
			break;
		} elseif (($act == 'get')) {
            return $als['address'];
		} else {
			return "ERROR: Invalid action";
		}
	}
	write_config(gettext("Edited a firewall alias by aliastools."));

	$retval = 0;
    $retval |= filter_configure();

    if ($retval == 0) {
            clear_subsystem_dirty('aliases');
    }

    return "OK";
}
?>
