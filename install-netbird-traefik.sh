#!/bin/bash

set -e

# Configuration
NETBIRD_DOMAIN="netbird.yblis.fr"
export NETBIRD_DOMAIN
TRAEFIK_NETWORK="traefik_traefik"
TRAEFIK_CERTRESOLVER="webssl"

# Error handling functions
handle_request_command_status() {
  PARSED_RESPONSE=$1
  FUNCTION_NAME=$2
  RESPONSE=$3
  if [[ $PARSED_RESPONSE -ne 0 ]]; then
    echo "ERROR calling $FUNCTION_NAME:" $(echo "$RESPONSE" | jq -r '.message') > /dev/stderr
    exit 1
  fi
}

handle_zitadel_request_response() {
  PARSED_RESPONSE=$1
  FUNCTION_NAME=$2
  RESPONSE=$3
  if [[ $PARSED_RESPONSE == "null" ]]; then
    echo "ERROR calling $FUNCTION_NAME:" $(echo "$RESPONSE" | jq -r '.message') > /dev/stderr
    exit 1
  fi
  sleep 1
}

# Dependency checks
check_jq() {
  if ! command -v jq &> /dev/null
  then
    echo "jq is not installed or not in PATH, please install with your package manager. e.g. sudo apt install jq" > /dev/stderr
    exit 1
  fi
}

check_docker_compose() {
  if command -v docker-compose &> /dev/null
  then
      echo "docker-compose"
      return
  fi
  if docker compose --help &> /dev/null
  then
      echo "docker compose"
      return
  fi

  echo "docker-compose is not installed or not in PATH. Please follow the steps from the official guide: https://docs.docker.com/engine/install/" > /dev/stderr
  exit 1
}

# Wait functions
wait_pat() {
  PAT_PATH=$1
  set +e
  while true; do
    if [[ -f "$PAT_PATH" ]]; then
      break
    fi
    echo -n " ."
    sleep 1
  done
  echo " done"
  set -e
}

wait_api() {
    INSTANCE_URL=$1
    PAT=$2
    set +e
    counter=1
    while true; do
      FLAGS="-s"
      if [[ $counter -eq 45 ]]; then
        FLAGS="-v"
        echo ""
      fi

      curl $FLAGS --fail --connect-timeout 1 -o /dev/null "$INSTANCE_URL/auth/v1/users/me" -H "Authorization: Bearer $PAT"
      if [[ $? -eq 0 ]]; then
        break
      fi
      if [[ $counter -eq 45 ]]; then
        echo ""
        echo "Unable to connect to Zitadel for more than 45s, please check the output above, your firewall rules and container logs"
        exit 1
      fi
      echo -n " ."
      sleep 1
      counter=$((counter + 1))
    done
    echo " done"
    set -e
}

# Zitadel API functions
create_new_project() {
  INSTANCE_URL=$1
  PAT=$2
  PROJECT_NAME="NETBIRD"

  RESPONSE=$(
    curl -sS -X POST "$INSTANCE_URL/management/v1/projects" \
      -H "Authorization: Bearer $PAT" \
      -H "Content-Type: application/json" \
      -d '{"name": "'"$PROJECT_NAME"'"}'
  )
  PARSED_RESPONSE=$(echo "$RESPONSE" | jq -r '.id')
  handle_zitadel_request_response "$PARSED_RESPONSE" "create_new_project" "$RESPONSE"
  echo "$PARSED_RESPONSE"
}

create_new_application() {
  INSTANCE_URL=$1
  PAT=$2
  APPLICATION_NAME=$3
  BASE_REDIRECT_URL1=$4
  BASE_REDIRECT_URL2=$5
  LOGOUT_URL=$6
  ZITADEL_DEV_MODE=$7
  DEVICE_CODE=$8

  if [[ $DEVICE_CODE == "true" ]]; then
    GRANT_TYPES='["OIDC_GRANT_TYPE_AUTHORIZATION_CODE","OIDC_GRANT_TYPE_DEVICE_CODE","OIDC_GRANT_TYPE_REFRESH_TOKEN"]'
  else
    GRANT_TYPES='["OIDC_GRANT_TYPE_AUTHORIZATION_CODE","OIDC_GRANT_TYPE_REFRESH_TOKEN"]'
  fi

  RESPONSE=$(
    curl -sS -X POST "$INSTANCE_URL/management/v1/projects/$PROJECT_ID/apps/oidc" \
      -H "Authorization: Bearer $PAT" \
      -H "Content-Type: application/json" \
      -d '{
    "name": "'"$APPLICATION_NAME"'",
    "redirectUris": [
      "'"$BASE_REDIRECT_URL1"'",
      "'"$BASE_REDIRECT_URL2"'"
    ],
    "postLogoutRedirectUris": [
      "'"$LOGOUT_URL"'"
    ],
    "RESPONSETypes": [
      "OIDC_RESPONSE_TYPE_CODE"
    ],
    "grantTypes": '"$GRANT_TYPES"',
    "appType": "OIDC_APP_TYPE_USER_AGENT",
    "authMethodType": "OIDC_AUTH_METHOD_TYPE_NONE",
    "version": "OIDC_VERSION_1_0",
    "devMode": '"$ZITADEL_DEV_MODE"',
    "accessTokenType": "OIDC_TOKEN_TYPE_JWT",
    "accessTokenRoleAssertion": true,
    "skipNativeAppSuccessPage": true
  }'
  )

  PARSED_RESPONSE=$(echo "$RESPONSE" | jq -r '.clientId')
  handle_zitadel_request_response "$PARSED_RESPONSE" "create_new_application" "$RESPONSE"
  echo "$PARSED_RESPONSE"
}

create_service_user() {
  INSTANCE_URL=$1
  PAT=$2

  RESPONSE=$(
    curl -sS -X POST "$INSTANCE_URL/management/v1/users/machine" \
      -H "Authorization: Bearer $PAT" \
      -H "Content-Type: application/json" \
      -d '{
            "userName": "netbird-service-account",
            "name": "Netbird Service Account",
            "description": "Netbird Service Account for IDP management",
            "accessTokenType": "ACCESS_TOKEN_TYPE_JWT"
      }'
  )
  PARSED_RESPONSE=$(echo "$RESPONSE" | jq -r '.userId')
  handle_zitadel_request_response "$PARSED_RESPONSE" "create_service_user" "$RESPONSE"
  echo "$PARSED_RESPONSE"
}

create_service_user_secret() {
  INSTANCE_URL=$1
  PAT=$2
  USER_ID=$3

  RESPONSE=$(
    curl -sS -X PUT "$INSTANCE_URL/management/v1/users/$USER_ID/secret" \
      -H "Authorization: Bearer $PAT" \
      -H "Content-Type: application/json" \
      -d '{}'
  )
  SERVICE_USER_CLIENT_ID=$(echo "$RESPONSE" | jq -r '.clientId')
  handle_zitadel_request_response "$SERVICE_USER_CLIENT_ID" "create_service_user_secret_id" "$RESPONSE"
  SERVICE_USER_CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.clientSecret')
  handle_zitadel_request_response "$SERVICE_USER_CLIENT_SECRET" "create_service_user_secret" "$RESPONSE"
}

add_organization_user_manager() {
  INSTANCE_URL=$1
  PAT=$2
  USER_ID=$3

  RESPONSE=$(
    curl -sS -X POST "$INSTANCE_URL/management/v1/orgs/me/members" \
      -H "Authorization: Bearer $PAT" \
      -H "Content-Type: application/json" \
      -d '{
            "userId": "'"$USER_ID"'",
            "roles": [
              "ORG_USER_MANAGER"
            ]
      }'
  )
  PARSED_RESPONSE=$(echo "$RESPONSE" | jq -r '.details.creationDate')
  handle_zitadel_request_response "$PARSED_RESPONSE" "add_organization_user_manager" "$RESPONSE"
  echo "$PARSED_RESPONSE"
}

create_admin_user() {
    INSTANCE_URL=$1
    PAT=$2
    USERNAME=$3
    PASSWORD=$4
    RESPONSE=$(
        curl -sS -X POST "$INSTANCE_URL/management/v1/users/human/_import" \
          -H "Authorization: Bearer $PAT" \
          -H "Content-Type: application/json" \
          -d '{
                "userName": "'"$USERNAME"'",
                "profile": {
                  "firstName": "Zitadel",
                  "lastName": "Admin"
                },
                "email": {
                  "email": "'"$USERNAME"'",
                  "isEmailVerified": true
                },
                "password": "'"$PASSWORD"'",
                "passwordChangeRequired": true
          }'
      )
      PARSED_RESPONSE=$(echo "$RESPONSE" | jq -r '.userId')
      handle_zitadel_request_response "$PARSED_RESPONSE" "create_admin_user" "$RESPONSE"
      echo "$PARSED_RESPONSE"
}

add_instance_admin() {
  INSTANCE_URL=$1
  PAT=$2
  USER_ID=$3

  RESPONSE=$(
    curl -sS -X POST "$INSTANCE_URL/admin/v1/members" \
      -H "Authorization: Bearer $PAT" \
      -H "Content-Type: application/json" \
      -d '{
            "userId": "'"$USER_ID"'",
            "roles": [
              "IAM_OWNER"
            ]
      }'
  )
  PARSED_RESPONSE=$(echo "$RESPONSE" | jq -r '.details.creationDate')
  handle_zitadel_request_response "$PARSED_RESPONSE" "add_instance_admin" "$RESPONSE"
  echo "$PARSED_RESPONSE"
}

delete_auto_service_user() {
  INSTANCE_URL=$1
  PAT=$2

  RESPONSE=$(
    curl -sS -X GET "$INSTANCE_URL/auth/v1/users/me" \
      -H "Authorization: Bearer $PAT" \
      -H "Content-Type: application/json" \
  )
  USER_ID=$(echo "$RESPONSE" | jq -r '.user.id')
  handle_zitadel_request_response "$USER_ID" "delete_auto_service_user_get_user" "$RESPONSE"

  RESPONSE=$(
      curl -sS -X DELETE "$INSTANCE_URL/admin/v1/members/$USER_ID" \
        -H "Authorization: Bearer $PAT" \
        -H "Content-Type: application/json" \
  )
  PARSED_RESPONSE=$(echo "$RESPONSE" | jq -r '.details.changeDate')
  handle_zitadel_request_response "$PARSED_RESPONSE" "delete_auto_service_user_remove_instance_permissions" "$RESPONSE"

  RESPONSE=$(
      curl -sS -X DELETE "$INSTANCE_URL/management/v1/orgs/me/members/$USER_ID" \
        -H "Authorization: Bearer $PAT" \
        -H "Content-Type: application/json" \
  )
  PARSED_RESPONSE=$(echo "$RESPONSE" | jq -r '.details.changeDate')
  handle_zitadel_request_response "$PARSED_RESPONSE" "delete_auto_service_user_remove_org_permissions" "$RESPONSE"
  echo "$PARSED_RESPONSE"
}

# Get external IP for TURN server
get_turn_external_ip() {
  TURN_EXTERNAL_IP_CONFIG="#external-ip="
  IP=$(curl -s -4 https://jsonip.com | jq -r '.ip')
  if [[ "x-$IP" != "x-" ]]; then
    TURN_EXTERNAL_IP_CONFIG="external-ip=$IP"
  fi
  echo "$TURN_EXTERNAL_IP_CONFIG"
}

# Main initialization function
main() {
  echo "Initializing NetBird with Traefik..."

  # Check dependencies
  check_jq
  DOCKER_COMPOSE_COMMAND=$(check_docker_compose)

  # Check if files already exist
  if [ -f zitadel.env ]; then
    echo "Generated files already exist, if you want to reinitialize the environment, please remove them first."
    echo "You can use the following commands:"
    echo "  $DOCKER_COMPOSE_COMMAND down --volumes # to remove all containers and volumes"
    echo "  rm -f docker-compose.yml zitadel.env zdb.env dashboard.env management.json relay.env turnserver.conf machinekey/zitadel-admin-sa.token"
    echo "Be aware that this will remove all data from the database, and you will have to reconfigure the dashboard."
    exit 1
  fi

  # Generate passwords and secrets
  ZITADEL_MASTERKEY="$(openssl rand -base64 32 | head -c 32)"
  POSTGRES_ROOT_PASSWORD="$(openssl rand -base64 32 | sed 's/=//g')@"
  POSTGRES_ZITADEL_PASSWORD="$(openssl rand -base64 32 | sed 's/=//g')@"
  TURN_PASSWORD=$(openssl rand -base64 32 | sed 's/=//g')
  NETBIRD_RELAY_AUTH_SECRET=$(openssl rand -base64 32 | sed 's/=//g')
  ZITADEL_ADMIN_USERNAME="admin@$NETBIRD_DOMAIN"
  ZITADEL_ADMIN_PASSWORD="$(openssl rand -base64 32 | sed 's/=//g')@"
  TURN_EXTERNAL_IP_CONFIG=$(get_turn_external_ip)

  if [[ "$OSTYPE" == "darwin"* ]]; then
      ZIDATE_TOKEN_EXPIRATION_DATE=$(date -u -v+30M "+%Y-%m-%dT%H:%M:%SZ")
  else
      ZIDATE_TOKEN_EXPIRATION_DATE=$(date -u -d "+30 minutes" "+%Y-%m-%dT%H:%M:%SZ")
  fi

  echo "Generating configuration files..."

  # Generate zitadel.env
  cat > zitadel.env <<EOF
ZITADEL_LOG_LEVEL=debug
ZITADEL_MASTERKEY=$ZITADEL_MASTERKEY
ZITADEL_EXTERNALSECURE=true
ZITADEL_TLS_ENABLED=false
ZITADEL_EXTERNALPORT=443
ZITADEL_EXTERNALDOMAIN=$NETBIRD_DOMAIN
ZITADEL_FIRSTINSTANCE_PATPATH=/machinekey/zitadel-admin-sa.token
ZITADEL_FIRSTINSTANCE_ORG_MACHINE_MACHINE_USERNAME=zitadel-admin-sa
ZITADEL_FIRSTINSTANCE_ORG_MACHINE_MACHINE_NAME=Admin
ZITADEL_FIRSTINSTANCE_ORG_MACHINE_PAT_SCOPES=openid
ZITADEL_FIRSTINSTANCE_ORG_MACHINE_PAT_EXPIRATIONDATE=$ZIDATE_TOKEN_EXPIRATION_DATE
ZITADEL_DATABASE_POSTGRES_HOST=zdb
ZITADEL_DATABASE_POSTGRES_PORT=5432
ZITADEL_DATABASE_POSTGRES_DATABASE=zitadel
ZITADEL_DATABASE_POSTGRES_USER_USERNAME=zitadel
ZITADEL_DATABASE_POSTGRES_USER_PASSWORD=$POSTGRES_ZITADEL_PASSWORD
ZITADEL_DATABASE_POSTGRES_USER_SSL_MODE=disable
ZITADEL_DATABASE_POSTGRES_ADMIN_USERNAME=root
ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD=$POSTGRES_ROOT_PASSWORD
ZITADEL_DATABASE_POSTGRES_ADMIN_SSL_MODE=disable
NETBIRD_DOMAIN=$NETBIRD_DOMAIN
EOF

  # Generate zdb.env
  cat > zdb.env <<EOF
POSTGRES_USER=root
POSTGRES_PASSWORD=$POSTGRES_ROOT_PASSWORD
EOF

  # Generate turnserver.conf
  cat > turnserver.conf <<EOF
listening-port=3478
$TURN_EXTERNAL_IP_CONFIG
tls-listening-port=5349
min-port=49152
max-port=65535
fingerprint
lt-cred-mech
user=self:$TURN_PASSWORD
realm=wiretrustee.com
cert=/etc/coturn/certs/cert.pem
pkey=/etc/coturn/private/privkey.pem
log-file=stdout
no-software-attribute
pidfile="/var/tmp/turnserver.pid"
no-cli
EOF

  # Generate relay.env
  cat > relay.env <<EOF
NB_LOG_LEVEL=info
NB_LISTEN_ADDRESS=:33080
NB_EXPOSED_ADDRESS=rels://$NETBIRD_DOMAIN:443/relay
NB_AUTH_SECRET=$NETBIRD_RELAY_AUTH_SECRET
NETBIRD_DOMAIN=$NETBIRD_DOMAIN
EOF



  # Create temporary empty files
  echo "" > dashboard.env
  echo "" > management.json

  # Generate docker-compose.yml
  cat > docker-compose.yml <<'EOF'
services:
  # UI dashboard
  dashboard:
    image: netbirdio/dashboard:latest
    restart: unless-stopped
    networks: 
      - netbird
      - traefik_traefik
    env_file:
      - ./dashboard.env
    labels:
      - traefik.enable=true
      - traefik.docker.network=traefik_traefik
      - traefik.http.services.netbird-dashboard.loadbalancer.server.port=80
      - traefik.http.routers.netbird-dashboard.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`)
      - traefik.http.routers.netbird-dashboard.entrypoints=https
      - traefik.http.routers.netbird-dashboard.tls=true
      - traefik.http.routers.netbird-dashboard.tls.certresolver=NETBIRD_TRAEFIK_SSL
      - traefik.http.routers.netbird-dashboard.priority=50
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

  # Signal
  signal:
    image: netbirdio/signal:latest
    restart: unless-stopped
    networks: 
      - netbird
      - traefik_traefik
    labels:
      - traefik.enable=true
      - traefik.docker.network=traefik_traefik
      - traefik.http.services.netbird-signal.loadbalancer.server.port=10000
      - traefik.http.services.netbird-signal.loadbalancer.server.scheme=h2c
      - traefik.http.routers.netbird-signal.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`) && PathPrefix(`/signalexchange.SignalExchange/`)
      - traefik.http.routers.netbird-signal.entrypoints=https
      - traefik.http.routers.netbird-signal.tls=true
      - traefik.http.routers.netbird-signal.tls.certresolver=NETBIRD_TRAEFIK_SSL
      - traefik.http.routers.netbird-signal.priority=200
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

  # Relay
  relay:
    image: netbirdio/relay:latest
    restart: unless-stopped
    networks: 
      - netbird
      - traefik_traefik
    env_file:
      - ./relay.env
    labels:
      - traefik.enable=true
      - traefik.docker.network=traefik_traefik
      - traefik.http.services.netbird-relay.loadbalancer.server.port=33080
      - traefik.http.routers.netbird-relay.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`) && PathPrefix(`/relay`)
      - traefik.http.routers.netbird-relay.entrypoints=https
      - traefik.http.routers.netbird-relay.tls=true
      - traefik.http.routers.netbird-relay.tls.certresolver=NETBIRD_TRAEFIK_SSL
      - traefik.http.routers.netbird-relay.priority=200
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

  # Management
  management:
    image: netbirdio/management:latest
    restart: unless-stopped
    networks: 
      - netbird
      - traefik_traefik
    volumes:
      - netbird_management:/var/lib/netbird
      - ./management.json:/etc/netbird/management.json
    command: [
      "--port", "80",
      "--log-file", "console",
      "--log-level", "info",
      "--disable-anonymous-metrics=false",
      "--single-account-mode-domain=netbird.selfhosted",
      "--dns-domain=netbird.selfhosted",
      "--idp-sign-key-refresh-enabled"
    ]
    labels:
      - traefik.enable=true
      - traefik.docker.network=traefik_traefik
      - traefik.http.services.netbird-management.loadbalancer.server.port=80
      - traefik.http.services.netbird-management-grpc.loadbalancer.server.port=80
      - traefik.http.services.netbird-management-grpc.loadbalancer.server.scheme=h2c
      # REST API
      - traefik.http.routers.netbird-api.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`) && PathPrefix(`/api`)
      - traefik.http.routers.netbird-api.entrypoints=https
      - traefik.http.routers.netbird-api.service=netbird-management
      - traefik.http.routers.netbird-api.tls=true
      - traefik.http.routers.netbird-api.tls.certresolver=NETBIRD_TRAEFIK_SSL
      - traefik.http.routers.netbird-api.priority=200
      # gRPC
      - traefik.http.routers.netbird-management-grpc.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`) && PathPrefix(`/management.ManagementService/`)
      - traefik.http.routers.netbird-management-grpc.entrypoints=https
      - traefik.http.routers.netbird-management-grpc.service=netbird-management-grpc
      - traefik.http.routers.netbird-management-grpc.tls=true
      - traefik.http.routers.netbird-management-grpc.tls.certresolver=NETBIRD_TRAEFIK_SSL
      - traefik.http.routers.netbird-management-grpc.priority=200
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

  # Coturn
  coturn:
    image: coturn/coturn
    restart: unless-stopped
    volumes:
      - ./turnserver.conf:/etc/turnserver.conf:ro
    network_mode: host
    command:
      - -c /etc/turnserver.conf
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

  # Zitadel - identity provider
  zitadel:
    restart: 'always'
    image: 'ghcr.io/zitadel/zitadel:v2.64.1'
    command: 'start-from-init --masterkeyFromEnv --tlsMode external'
    env_file:
      - ./zitadel.env
    depends_on:
      zdb:
        condition: 'service_healthy'
    volumes:
      - ./machinekey:/machinekey
      - netbird_zitadel_certs:/zdb-certs:ro
    networks: 
      - netbird
      - traefik_traefik
    labels:
      - traefik.enable=true
      - traefik.docker.network=traefik_traefik
      - traefik.http.services.zitadel.loadbalancer.server.port=8080
      # OIDC wellknown
      - traefik.http.routers.zitadel-wellknown.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`) && PathPrefix(`/.well-known`)
      - traefik.http.routers.zitadel-wellknown.entrypoints=https
      - traefik.http.routers.zitadel-wellknown.service=zitadel
      - traefik.http.routers.zitadel-wellknown.priority=300
      - traefik.http.routers.zitadel-wellknown.tls=true
      - traefik.http.routers.zitadel-wellknown.tls.certresolver=NETBIRD_TRAEFIK_SSL
      # OAuth
      - traefik.http.routers.zitadel-oauth.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`) && PathPrefix(`/oauth`)
      - traefik.http.routers.zitadel-oauth.entrypoints=https
      - traefik.http.routers.zitadel-oauth.service=zitadel
      - traefik.http.routers.zitadel-oauth.priority=300
      - traefik.http.routers.zitadel-oauth.tls=true
      - traefik.http.routers.zitadel-oauth.tls.certresolver=NETBIRD_TRAEFIK_SSL
      # OIDC
      - traefik.http.routers.zitadel-oidc.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`) && PathPrefix(`/oidc`)
      - traefik.http.routers.zitadel-oidc.entrypoints=https
      - traefik.http.routers.zitadel-oidc.service=zitadel
      - traefik.http.routers.zitadel-oidc.priority=300
      - traefik.http.routers.zitadel-oidc.tls=true
      - traefik.http.routers.zitadel-oidc.tls.certresolver=NETBIRD_TRAEFIK_SSL
      # UI Console
      - traefik.http.routers.zitadel-ui.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`) && PathPrefix(`/ui`)
      - traefik.http.routers.zitadel-ui.entrypoints=https
      - traefik.http.routers.zitadel-ui.service=zitadel
      - traefik.http.routers.zitadel-ui.priority=300
      - traefik.http.routers.zitadel-ui.tls=true
      - traefik.http.routers.zitadel-ui.tls.certresolver=NETBIRD_TRAEFIK_SSL
      # Device flow
      - traefik.http.routers.zitadel-device.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`) && PathPrefix(`/device`)
      - traefik.http.routers.zitadel-device.entrypoints=https
      - traefik.http.routers.zitadel-device.service=zitadel
      - traefik.http.routers.zitadel-device.priority=300
      - traefik.http.routers.zitadel-device.tls=true
      - traefik.http.routers.zitadel-device.tls.certresolver=NETBIRD_TRAEFIK_SSL
      # Management API
      - traefik.http.routers.zitadel-mgmt.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`) && PathPrefix(`/management/v1`)
      - traefik.http.routers.zitadel-mgmt.entrypoints=https
      - traefik.http.routers.zitadel-mgmt.service=zitadel
      - traefik.http.routers.zitadel-mgmt.priority=300
      - traefik.http.routers.zitadel-mgmt.tls=true
      - traefik.http.routers.zitadel-mgmt.tls.certresolver=NETBIRD_TRAEFIK_SSL
      # Auth API
      - traefik.http.routers.zitadel-auth.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`) && PathPrefix(`/auth/v1`)
      - traefik.http.routers.zitadel-auth.entrypoints=https
      - traefik.http.routers.zitadel-auth.service=zitadel
      - traefik.http.routers.zitadel-auth.priority=300
      - traefik.http.routers.zitadel-auth.tls=true
      - traefik.http.routers.zitadel-auth.tls.certresolver=NETBIRD_TRAEFIK_SSL
      # Admin API
      - traefik.http.routers.zitadel-admin.rule=Host(`NETBIRD_DOMAIN_PLACEHOLDER`) && PathPrefix(`/admin/v1`)
      - traefik.http.routers.zitadel-admin.entrypoints=https
      - traefik.http.routers.zitadel-admin.service=zitadel
      - traefik.http.routers.zitadel-admin.priority=300
      - traefik.http.routers.zitadel-admin.tls=true
      - traefik.http.routers.zitadel-admin.tls.certresolver=NETBIRD_TRAEFIK_SSL
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

  # Postgres for Zitadel
  zdb:
    restart: 'always'
    networks: [netbird]
    image: 'postgres:16-alpine'
    env_file:
      - ./zdb.env
    volumes:
      - netbird_zdb_data:/var/lib/postgresql/data:rw
    healthcheck:
      test: ["CMD-SHELL", "pg_isready", "-d", "db_prod"]
      interval: 5s
      timeout: 60s
      retries: 10
      start_period: 5s
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

volumes:
  netbird_zdb_data:
  netbird_management:
  netbird_zitadel_certs:

networks:
  netbird:
    driver: bridge
  traefik_traefik:
    external: true
EOF
sed -i "s/NETBIRD_DOMAIN_PLACEHOLDER/${NETBIRD_DOMAIN}/g" docker-compose.yml
sed -i "s/NETBIRD_TRAEFIK_SSL/${TRAEFIK_CERTRESOLVER}/g" docker-compose.yml

  # Create machinekey directory
  mkdir -p machinekey
  chmod 777 machinekey

  echo "Starting database..."
  $DOCKER_COMPOSE_COMMAND up -d zdb

  echo "Waiting for database to be ready..."
  sleep 30

  echo "Starting Zitadel..."
  $DOCKER_COMPOSE_COMMAND up -d zitadel

  echo "Waiting for Zitadel to initialize..."
  sleep 60

  # Configuration automatique de Zitadel
  echo "Configuring Zitadel applications..."

  INSTANCE_URL="https://$NETBIRD_DOMAIN"
  TOKEN_PATH=./machinekey/zitadel-admin-sa.token

  echo -n "Waiting for Zitadel's PAT to be created "
  wait_pat "$TOKEN_PATH"

  echo "Reading Zitadel PAT"
  PAT=$(cat $TOKEN_PATH)
  if [ "$PAT" = "null" ]; then
    echo "Failed getting Zitadel PAT"
    exit 1
  fi

  echo -n "Waiting for Zitadel to become ready "
  wait_api "$INSTANCE_URL" "$PAT"

  # Create project
  echo "Creating Zitadel project"
  PROJECT_ID=$(create_new_project "$INSTANCE_URL" "$PAT")

  # Create applications
  echo "Creating Dashboard application"
  DASHBOARD_APPLICATION_CLIENT_ID=$(create_new_application "$INSTANCE_URL" "$PAT" "Dashboard" "https://$NETBIRD_DOMAIN/nb-auth" "https://$NETBIRD_DOMAIN/nb-silent-auth" "https://$NETBIRD_DOMAIN/" "false" "false")

  echo "Creating CLI application"
  CLI_APPLICATION_CLIENT_ID=$(create_new_application "$INSTANCE_URL" "$PAT" "Cli" "http://localhost:53000/" "http://localhost:54000/" "http://localhost:53000/" "true" "true")

  # Create service user
  echo "Creating service user"
  MACHINE_USER_ID=$(create_service_user "$INSTANCE_URL" "$PAT")
  create_service_user_secret "$INSTANCE_URL" "$PAT" "$MACHINE_USER_ID"
  add_organization_user_manager "$INSTANCE_URL" "$PAT" "$MACHINE_USER_ID"

  # Create admin user
  echo "Creating admin user"
  HUMAN_USER_ID=$(create_admin_user "$INSTANCE_URL" "$PAT" "$ZITADEL_ADMIN_USERNAME" "$ZITADEL_ADMIN_PASSWORD")
  add_instance_admin "$INSTANCE_URL" "$PAT" "$HUMAN_USER_ID"

  # Clean up auto service user
  echo "Cleaning up auto service user"
  DATE=$(delete_auto_service_user "$INSTANCE_URL" "$PAT")
  if [ "$DATE" = "null" ]; then
      echo "Failed deleting auto service user"
      echo "Please remove it manually"
  fi

  # Generate NetBird configuration
  echo "Generating NetBird configuration..."

  # dashboard.env
  cat > dashboard.env <<EOF
NETBIRD_MGMT_API_ENDPOINT=https://$NETBIRD_DOMAIN
NETBIRD_MGMT_GRPC_API_ENDPOINT=https://$NETBIRD_DOMAIN
AUTH_AUDIENCE=$DASHBOARD_APPLICATION_CLIENT_ID
AUTH_CLIENT_ID=$DASHBOARD_APPLICATION_CLIENT_ID
AUTH_AUTHORITY=https://$NETBIRD_DOMAIN
USE_AUTH0=false
AUTH_SUPPORTED_SCOPES=openid profile email offline_access
AUTH_REDIRECT_URI=/nb-auth
AUTH_SILENT_REDIRECT_URI=/nb-silent-auth
NGINX_SSL_PORT=443
LETSENCRYPT_DOMAIN=none
NETBIRD_DOMAIN=$NETBIRD_DOMAIN
EOF

  # management.json
  cat > management.json <<EOF
{
    "Stuns": [
        {
            "Proto": "udp",
            "URI": "stun:$NETBIRD_DOMAIN:3478"
        }
    ],
    "TURNConfig": {
        "Turns": [
            {
                "Proto": "udp",
                "URI": "turn:$NETBIRD_DOMAIN:3478",
                "Username": "self",
                "Password": "$TURN_PASSWORD"
            }
        ],
        "TimeBasedCredentials": false
    },
    "Relay": {
        "Addresses": ["rels://$NETBIRD_DOMAIN:443/relay"],
        "CredentialsTTL": "24h",
        "Secret": "$NETBIRD_RELAY_AUTH_SECRET"
    },
    "Signal": {
        "Proto": "https",
        "URI": "$NETBIRD_DOMAIN:443"
    },
    "HttpConfig": {
        "AuthIssuer": "https://$NETBIRD_DOMAIN",
        "AuthAudience": "$DASHBOARD_APPLICATION_CLIENT_ID",
        "OIDCConfigEndpoint":"https://$NETBIRD_DOMAIN/.well-known/openid-configuration"
    },
    "IdpManagerConfig": {
        "ManagerType": "zitadel",
        "ClientConfig": {
            "Issuer": "https://$NETBIRD_DOMAIN",
            "TokenEndpoint": "https://$NETBIRD_DOMAIN/oauth/v2/token",
            "ClientID": "$SERVICE_USER_CLIENT_ID",
            "ClientSecret": "$SERVICE_USER_CLIENT_SECRET",
            "GrantType": "client_credentials"
        },
        "ExtraConfig": {
            "ManagementEndpoint": "https://$NETBIRD_DOMAIN/management/v1"
        }
    },
    "DeviceAuthorizationFlow": {
        "Provider": "hosted",
        "ProviderConfig": {
            "Audience": "$CLI_APPLICATION_CLIENT_ID",
            "ClientID": "$CLI_APPLICATION_CLIENT_ID",
            "Scope": "openid"
        }
    },
    "PKCEAuthorizationFlow": {
        "ProviderConfig": {
            "Audience": "$CLI_APPLICATION_CLIENT_ID",
            "ClientID": "$CLI_APPLICATION_CLIENT_ID",
            "Scope": "openid profile email offline_access",
            "RedirectURLs": ["http://localhost:53000/","http://localhost:54000/"]
        }
    }
}
EOF

  echo "Starting all NetBird services..."
  $DOCKER_COMPOSE_COMMAND up -d

  echo -e "\nDone!\n"
  echo "You can access the NetBird dashboard at https://$NETBIRD_DOMAIN"
  echo "Login with the following credentials:"
  echo "Username: $ZITADEL_ADMIN_USERNAME" | tee .env
  echo "Password: $ZITADEL_ADMIN_PASSWORD" | tee -a .env
  echo "URL: https://$NETBIRD_DOMAIN" | tee -a .env
  echo ""
  echo "Zitadel console: https://$NETBIRD_DOMAIN/ui/console"
  echo ""
  echo "Note: The admin password will require changing on first login."
}

# Execute main function
main "$@"
