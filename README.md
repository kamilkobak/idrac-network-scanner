# iDRAC Network Scanner

**Open source** script for automatic network scanning and inventory of **Dell iDRAC** servers using SNMP v2c (public community).

## 🎯 **Purpose**
- Automatic discovery of Dell servers in local network (/24)
- Collects: **IP, Hostname, FQDN, Service Tag**
- Change history in **SQLite** (new/changed/offline servers)

## ✨ **Features**
- ✅ Ping + SNMP scan (only responsive iDRAC)
- ✅ **SQLite DB** with scan history
- ✅ **Change report** (NEW/CHANGED/REMOVED)
- ✅ Zero external dependencies (sqlite3, ping, snmp standard)
- ✅ Clean output (no OID errors)

## 📋 **Requirements**
```bash
# Debian/Ubuntu
sudo apt install iputils-ping snmp sqlite3

# RHEL/CentOS
sudo yum install iputils net-snmp-utils sqlite
```

🚀 Usage

```bash
git clone https://github.com/kamilkobak/idrac-network-scanner
cd cd idrac-network-scanner/
chmod +x scan_idrac_network.sh
./scan_idrac_network.sh
```
Example output:

```text
=== CURRENT SCAN (2026-01-30 15:00) ===
IP              Hostname             FQDN                           Service Tag    
----------------------------------------------------------------------------------
192.16.3.2      idrac-PF-MASTER   PF_MASTER                   AXXXXX1        
192.16.3.3      idrac-PF-SLAVE    PF_SLAVE                    AXXXXX2        
192.16.3.18     node1             node1.exm.lab               AXXXXX3        


=== CHANGES SINCE LAST SCAN ===
change  ip            hostname                    fqdn                               servicetag
NEW     192.16.3.18   node1                       node1.exm.lab                      AXXXXX1
REMOVED 192.16.3.9    node2                       node2.exm.lab                      AXXXXX2

Data saved to idrac_inventory.db
```


⚙️ Configuration

Edit variables at the top of the script:

```bash
NETWORK="192.16.3"        # Network /24
SNMPCOMMUNITY="public"    # SNMP community
TIMEOUT=2                 # SNMP timeout (s)
```
🗄️ SQLite Database

```text
idrac_inventory.db:
├── idrac_inventory    (current data)
└── idrac_inventory_old (previous scan backup)
```
Queries:

```bash
# All servers
sqlite3 idrac_inventory.db "SELECT * FROM idrac_inventory ORDER BY ip"

# IP history
sqlite3 idrac_inventory.db "SELECT timestamp,hostname FROM idrac_inventory WHERE ip='192.16.3.2'"
```
🤖 Automation (cron)

```bash
# Daily at 2:00 AM, logs + CSV
0 2 * * * /path/to/scan_idrac_network.sh >> /var/log/idrac_scan.log 2>&1

# With CSV export
./scan_idrac_network.sh | tee -a idrac_inventory_$(date +%Y%m%d).csv
```
🔍 Troubleshooting

```text
# iDRAC SNMP disabled?
snmpwalk -v2c -c public 192.16.3.X 1 | head

# Single test
snmpget -v2c -c public 192.16.3.2 1.3.6.1.2.1.1.5.0
```
iDRAC web: iDRAC Settings → Services → SNMP Agent → Enable


📄 License: GPL-3.0 license.
🙌 Author: Kamil Kobak
🐧Open Source > Everything 


