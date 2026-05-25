#!/usr/bin/bash
set -o pipefail

# Variables for common paths
LDAP_CONFIG_PATH="/etc/ldap/slapd.d/cn=config"
SCHEMA_PATH="$LDAP_CONFIG_PATH/cn=schema"
MDB_LDIF="$LDAP_CONFIG_PATH/olcDatabase={1}mdb.ldif"
MDB_LDIF_BAK="$MDB_LDIF.bak"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Stop OpenLDAP server
log "Stopping OpenLDAP server"
systemctl stop slapd.service || { log "Failed to stop OpenLDAP server"; exit 1; }

# Remove nis.ldif from schema
log "Removing nis.ldif from schema"
rm "$SCHEMA_PATH/cn={2}nis.ldif" || { log "Failed to remove nis.ldif"; exit 1; }

# Reorganize schema
log "Reorganizing schema"
mv $SCHEMA_PATH/cn=\{{3,2}\}inetorgperson.ldif || { log "Failed to reorganize inetorgperson.ldif"; exit 1; }

# Backup database config
log "Backing up database configuration"
cp "$MDB_LDIF" "$MDB_LDIF_BAK" || { log "Failed to backup database configuration"; exit 1; }

# Modify database config
log "Modifying database configuration"
sed -i '/^olcAccess: {1}/s/^/#/' "$MDB_LDIF"
sed -i '/^olcDbIndex: member/s/^/#/' "$MDB_LDIF"

# Recalculate CRC32 checksum
log "Recalculating CRC32 checksum"
cat $MDB_LDIF | sed '/^#/d' > "$MDB_LDIF.crc"
sed -i "s/^# CRC32 .*/# CRC32 $(crc32 $MDB_LDIF.crc)/" "$MDB_LDIF" ; rm "$MDB_LDIF.crc"

# Restart OpenLDAP server
log "Restarting OpenLDAP server"
systemctl start slapd.service || { log "Failed to start OpenLDAP server"; exit 1; }

# Add rfc2307bis schema
log "Adding rfc2307bis schema"
schema2ldif /etc/ldap/schema/rfc2307bis.schema | ldapadd -Q -Y EXTERNAL -H ldapi:/// || { log "Failed to add rfc2307bis schema"; exit 1; }

# Stop OpenLDAP server
log "Stopping OpenLDAP server again"
systemctl stop slapd.service || { log "Failed to stop OpenLDAP server"; exit 1; }

# Reorganize schema again
log "Reorganizing schema again"
mv $SCHEMA_PATH/cn=\{{2,3}\}inetorgperson.ldif || { log "Failed to reorganize inetorgperson.ldif"; exit 1; }
mv $SCHEMA_PATH/cn=\{{3,2}\}rfc2307bis.ldif || { log "Failed to reorganize rfc2307bis.ldif"; exit 1; }

# Restore old database configuration
log "Restoring old database configuration"
mv "$MDB_LDIF_BAK" "$MDB_LDIF" || { log "Failed to restore database configuration"; exit 1; }
chown openldap: "$MDB_LDIF" || { log "Failed to change ownership of database configuration"; exit 1; }

# Restart OpenLDAP server
log "Restarting OpenLDAP server"
systemctl start slapd.service || { log "Failed to start OpenLDAP server"; exit 1; }

log "Script completed successfully"
