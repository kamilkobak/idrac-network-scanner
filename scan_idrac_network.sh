#!/bin/bash

# iDRAC Network Scanner - Open Source (GPL License)
# Author: Kamil Kobak 
# Purpose: Network discovery and inventory for Dell iDRAC servers via SNMP
# GitHub: https://github.com/kamilkobak/idrac-network-scanner
# Version: 1.1

# Configuration variables
SHOW_ALL=${1:-0}                # 0 = show all hosts (default), 1 = show only idrac hosts
NETWORK="172.16.3"              # Base network /24 (e.g. 192.16.3)
SNMP_COMMUNITY="public"         # SNMP community string
SNMP_TIMEOUT=2                  # SNMP timeout for response/retry (seconds)
PING_TIMEOUT=1                  # Ping timeout (seconds)
DB_FILE="idrac_inventory.db"    # SQLite database file
OID_HOSTNAME="1.3.6.1.2.1.1.5.0"           # sysName (hostname)
OID_FQDN="1.3.6.1.4.1.674.10892.5.1.3.1.0" # Dell systemFQDN
OID_SERVICETAG="1.3.6.1.4.1.674.10892.5.1.3.2.0" # Dell Service Tag

# SNMP parsing function (handles empty strings "", errors, cleans OID/raw)
parse_snmp() {
    local raw_output="$1"
    
    if echo "${raw_output}" | grep -q "No Such Object\|Timeout\|No Such Instance"; then
        echo "-"
        return
    fi
    
    local value=$(echo "${raw_output}" | sed 's/.*STRING: "\(.*\)".*/\1/; t; d')
    
    if [[ -z "${value}" ]]; then
        echo "-"
    else
        echo "${value}"
    fi
}

# Check required tools
missing_tools=()
command -v sqlite3 >/dev/null 2>&1 || missing_tools+=("sqlite3: sudo apt install sqlite3")
command -v ping >/dev/null 2>&1 || missing_tools+=("ping: sudo apt install iputils-ping")
command -v snmpget >/dev/null 2>&1 || missing_tools+=("snmpget: sudo apt install snmp")

if [[ ${#missing_tools[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools:"
    printf '  %s\n' "${missing_tools[@]}"
    exit 1
fi

# Initialize SQLite database with indexes
sqlite3 "${DB_FILE}" "
CREATE TABLE IF NOT EXISTS idrac_inventory (
    timestamp TEXT,
    ip TEXT PRIMARY KEY,
    hostname TEXT,
    fqdn TEXT,
    servicetag TEXT
);
CREATE TABLE IF NOT EXISTS idrac_inventory_old AS 
SELECT * FROM idrac_inventory WHERE 1=0;
CREATE INDEX IF NOT EXISTS idx_ip ON idrac_inventory(ip);
"

# Backup previous data before scan
sqlite3 "${DB_FILE}" "INSERT INTO idrac_inventory_old SELECT * FROM idrac_inventory;"

# Current scan header
echo "=== CURRENT SCAN ($(date '+%Y-%m-%d %H:%M:%S')) ==="
printf "%-15s %-25s %-40s %-15s\n" "IP" "Hostname" "FQDN" "Service Tag"
printf "%s\n" "---------------------------------------------------------------------------------------------------------------"

# Network scan and data collection
declare -a current_data
for i in {1..254}; do
    local_ip="${NETWORK}.${i}"
    
    if ping -c1 -W"${PING_TIMEOUT}" "${local_ip}" &>/dev/null; then
        
        raw_hostname=$(snmpget -v2c -c "${SNMP_COMMUNITY}" -t"${SNMP_TIMEOUT}" "${local_ip}" "${OID_HOSTNAME}" 2>/dev/null)
        hostname=$(parse_snmp "${raw_hostname}")
        
        raw_fqdn=$(snmpget -v2c -c "${SNMP_COMMUNITY}" -t"${SNMP_TIMEOUT}" "${local_ip}" "${OID_FQDN}" 2>/dev/null)
        fqdn=$(parse_snmp "${raw_fqdn}")
        
        raw_tag=$(snmpget -v2c -c "${SNMP_COMMUNITY}" -t"${SNMP_TIMEOUT}" "${local_ip}" "${OID_SERVICETAG}" 2>/dev/null)
        servicetag=$(parse_snmp "${raw_tag}")
        
	if [[ "${SHOW_ALL}" == "1" ]]; then
	    if [[ "${hostname}" != "-" && -n "${hostname}" ]]; then
	        printf "%-15s %-25s %-40s %-15s\n" "${local_ip}" "${hostname}" "${fqdn}" "${servicetag}"
                timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	        current_data+=("${timestamp}|${local_ip}|${hostname}|${fqdn}|${servicetag}")
	    fi
	else
	    printf "%-15s %-25s %-40s %-15s\n" "${local_ip}" "${hostname}" "${fqdn}" "${servicetag}"
	fi
    fi
done

# Save to SQLite (safe parsing with proper quoting)
for row in "${current_data[@]}"; do
    IFS='|' read -r ts ip hn fqdn tag <<< "${row}"
    sqlite3 "${DB_FILE}" "INSERT OR REPLACE INTO idrac_inventory 
                          (timestamp, ip, hostname, fqdn, servicetag)
                          VALUES ('${ts}', '${ip}', '${hn}', '${fqdn}', '${tag}');"
done

# Current summary
total_servers=$(sqlite3 "${DB_FILE}" "SELECT COUNT(*) FROM idrac_inventory;")
echo "Total iDRAC servers found: ${total_servers}"

# Changes report (NEW/CHANGED/REMOVED)
echo ""
echo "=== CHANGES SINCE LAST SCAN ==="
sqlite3 "${DB_FILE}" -header -separator ' | ' "
WITH changes AS (
    -- NEW servers
    SELECT 'NEW' as change, n.ip, n.hostname, n.fqdn, n.servicetag 
    FROM idrac_inventory n LEFT JOIN idrac_inventory_old o ON n.ip=o.ip 
    WHERE o.ip IS NULL
    
    UNION ALL
    
    -- CHANGED (hostname/fqdn/servicetag)
    SELECT 'CHANGED' as change, n.ip, 
           n.hostname||' -> '||COALESCE(o.hostname,n.hostname) as hostname,
           n.fqdn||' -> '||COALESCE(o.fqdn,n.fqdn) as fqdn,
           COALESCE(n.servicetag||' -> '||o.servicetag, n.servicetag) as servicetag
    FROM idrac_inventory n JOIN idrac_inventory_old o ON n.ip=o.ip 
    WHERE n.hostname != o.hostname OR n.fqdn != o.fqdn OR n.servicetag != o.servicetag
    
    UNION ALL
    
    -- REMOVED/OFFLINE servers
    SELECT 'REMOVED' as change, o.ip, o.hostname, o.fqdn, o.servicetag
    FROM idrac_inventory_old o LEFT JOIN idrac_inventory n ON o.ip=n.ip 
    WHERE n.ip IS NULL
)
SELECT * FROM changes ORDER BY change, ip;
"

echo ""
echo "✅ Inventory saved to ${DB_FILE}"
echo "📊 Run again to track changes (cron-ready)"



