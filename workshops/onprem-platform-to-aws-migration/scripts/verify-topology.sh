#!/usr/bin/env bash
# Proves the central migration hazard in ivozprovider: the platform's own database is its
# service registry, and some of those address columns describe third-party endpoints.
#
# Loads schema/initial.sql into a throwaway MariaDB container and queries it. No AWS, no
# application build, no credentials. Runtime ~90s (first run pulls the image).
#
# Usage: ./verify-topology.sh [path-to-ivozprovider-clone]
set -euo pipefail

REPO="${1:-$HOME/repos/ivozprovider}"
NAME="ivoz-topology-check"
DB_IMAGE="mariadb:10.8"

SQL_DUMP="$REPO/schema/initial.sql"
[ -f "$SQL_DUMP" ] || { echo "not found: $SQL_DUMP (pass the ivozprovider clone path)" >&2; exit 1; }

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "==> starting $DB_IMAGE and loading schema/initial.sql"
docker run -d --name "$NAME" \
  -e MYSQL_ROOT_PASSWORD=changeme \
  -e MYSQL_DATABASE=ivozprovider \
  -v "$SQL_DUMP:/docker-entrypoint-initdb.d/initial.sql:ro" \
  "$DB_IMAGE" >/dev/null

q() { docker exec "$NAME" mariadb -uroot -pchangeme ivozprovider -e "$1" 2>/dev/null; }

for _ in $(seq 1 80); do
  if q "SELECT 1" >/dev/null 2>&1 && [ "$(q "SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema='ivozprovider'" | tail -1)" -gt 150 ]; then
    break
  fi
  sleep 3
done

echo
echo "==> schema loaded"
q "SELECT table_type, COUNT(*) AS count FROM information_schema.tables
   WHERE table_schema='ivozprovider' GROUP BY table_type;"

echo
echo "==> the platform's node topology, as stored in its own database"
q "SELECT 'ApplicationServers' AS source, CONVERT(ip USING utf8mb4) AS value,
          CONVERT(name USING utf8mb4) AS label FROM ApplicationServers
   UNION ALL SELECT 'ProxyUsers',     CONVERT(ip USING utf8mb4), CONVERT(name USING utf8mb4) FROM ProxyUsers
   UNION ALL SELECT 'ProxyTrunks',    CONVERT(ip USING utf8mb4), CONVERT(name USING utf8mb4) FROM ProxyTrunks
   UNION ALL SELECT 'kam_dispatcher', CONVERT(destination USING utf8mb4), CONVERT(description USING utf8mb4) FROM kam_dispatcher
   UNION ALL SELECT 'kam_rtpengine',  CONVERT(url USING utf8mb4), CONVERT(description USING utf8mb4) FROM kam_rtpengine;"

echo
echo "==> every column holding an address or endpoint"
echo "    (ours = must be re-addressed; theirs = a carrier or customer trusts this value)"
q "SELECT CONCAT(table_name,'.',column_name) AS column_ref,
          CASE
            WHEN table_name IN ('ApplicationServers','ProxyUsers','ProxyTrunks',
                                'kam_dispatcher','kam_rtpengine','WebPortals') THEN 'ours'
            WHEN table_name IN ('CarrierServers','DDIProviderAddresses','Friends',
                                'ResidentialDevices','RetailAccounts','Companies',
                                'kam_trusted','kam_users_address','kam_trunks_address',
                                'kam_trunks_lcr_gateways','BannedAddresses') THEN 'theirs'
            ELSE '-'
          END AS owner
   FROM information_schema.columns
   WHERE table_schema='ivozprovider'
     AND (column_name LIKE '%ip' OR column_name LIKE 'ip%'
          OR column_name IN ('destination','url','src_ip','ip_addr'))
     AND column_name <> 'strip'
   ORDER BY owner DESC, table_name;"

cat <<'NOTE'

==> what this means for the migration
    - Node identity is data, not configuration: profiles/proxy/etc/kamailio/autoconf renders
      listeners.cfg from ProxyUsers/ProxyTrunks rows at install time.
      => autoscaling requires either stable per-node addresses (EIP/ENI) or a registrar that
         maintains these rows from instance/task lifecycle events.
    - Rows marked "theirs" are addresses that carriers and customer devices are configured to
      trust (SIP ACLs, IP filters).
      => changing public IPs is a commercial coordination exercise, not just a Terraform change.
NOTE
