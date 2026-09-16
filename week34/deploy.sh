#!/usr/bin/env bash
# Novatrix AB, vecka 34: återskapa nätverk, VM, Nginx och webbplats.
# Körs i Azure Cloud Shell (Bash) eller lokalt i Bash med Azure CLI.
set -Eeuo pipefail

RG="${RG:-rg-novatrix}"
REGION="${REGION:-swedencentral}"
VM="${VM:-vm-novatrix-web}"
VM_SIZE="${VM_SIZE:-Standard_B2ats_v2}"
VNET="${VNET:-vnet-novatrix}"
SUBNET="${SUBNET:-subnet-novatrix-web}"
PIP="${PIP:-pip-novatrix-web}"
NSG="${NSG:-nsg-novatrix-web}"
ADMIN="${ADMIN:-azureuser}"
SSH_SOURCE_CIDR="${SSH_SOURCE_CIDR:-*}"
SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-$HOME/.ssh/novatrix-key}"
SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-${SSH_PRIVATE_KEY}.pub}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SITE_FILE="$SCRIPT_DIR/index.html"

fail() { printf 'FEL: %s\n' "$*" >&2; exit 1; }
command -v az >/dev/null 2>&1 || fail 'Azure CLI (az) saknas. Använd Azure Cloud Shell med Bash.'
command -v ssh-keygen >/dev/null 2>&1 || fail 'ssh-keygen saknas.'
[[ -s "$SITE_FILE" ]] || fail "Hittar inte $SITE_FILE. Lägg deploy.sh bredvid index.html."
az account show --output none 2>/dev/null || fail 'Logga in med az login (Cloud Shell är normalt redan inloggat).'

if [[ -n "${AZURE_SUBSCRIPTION:-}" ]]; then
  az account set --subscription "$AZURE_SUBSCRIPTION"
fi
printf 'Azure-prenumeration: %s\n' "$(az account show --query name --output tsv)"
printf 'Resursgrupp: %s | Region: %s | VM: %s\n' "$RG" "$REGION" "$VM"

# VIKTIGT: ändra aldrig en befintlig VM genom att köra detta script igen.
# Cloud-init exekveras vid FÖRSTA starten, inte vid en normal omkörning.
if [[ "$(az group exists --name "$RG" --output tsv)" == true ]] &&
   az vm show --resource-group "$RG" --name "$VM" --output none 2>/dev/null; then
  fail "VM $VM finns redan i $RG. Skriptet skriver inte över eller raderar den. Läs guiden före återuppbyggnad."
fi

# Använd befintlig publik SSH-nyckel eller skapa ett EGET par lokalt i Cloud Shell.
# Ingen privatnyckel lagras i repot eller skickas till Azure.
if [[ ! -s "$SSH_PUBLIC_KEY_FILE" ]]; then
  [[ ! -e "$SSH_PRIVATE_KEY" ]] || fail "Privatnyckeln finns men publiknyckeln saknas: $SSH_PUBLIC_KEY_FILE. Ange SSH_PUBLIC_KEY_FILE."
  mkdir -p "$(dirname "$SSH_PRIVATE_KEY")"
  chmod 700 "$(dirname "$SSH_PRIVATE_KEY")"
  printf 'Skapar nytt SSH-nyckelpar på: %s (lägg ALDRIG privatnyckeln i GitHub)\n' "$SSH_PRIVATE_KEY"
  ssh-keygen -q -t rsa -b 4096 -N '' -f "$SSH_PRIVATE_KEY" -C novatrix-web
fi

TEMP_CLOUD_INIT="$(mktemp)"
TEMP_SCHEDULE="$(mktemp)"
trap 'rm -f "$TEMP_CLOUD_INIT" "$TEMP_SCHEDULE"' EXIT

# Generera cloud-init direkt från index.html. Bara EN version av webbplatsen
# behöver underhållas i GitHub. Indragningen behövs för giltig YAML.
{
  cat <<'YAML'
#cloud-config
package_update: true
packages:
  - nginx
write_files:
  - path: /opt/novatrix/index.html
    owner: root:root
    permissions: '0644'
    content: |
YAML
  sed 's/^/      /' "$SITE_FILE"
  # GitHub-filer behöver inte sluta med radbrytning. Separera ändå YAML-nycklarna.
  printf '\n'
  cat <<'YAML'
runcmd:
  - [ mkdir, -p, /var/www/html ]
  - [ cp, /opt/novatrix/index.html, /var/www/html/index.html ]
  - [ systemctl, enable, --now, nginx ]
YAML
} > "$TEMP_CLOUD_INIT"

if [[ "$(wc -c < "$TEMP_CLOUD_INIT")" -gt 60000 ]]; then
  fail 'Cloud-init-filen är för stor (Azure har gräns på 64 KiB custom data).'
fi

if [[ "$(az group exists --name "$RG" --output tsv)" != true ]]; then
  az group create --name "$RG" --location "$REGION" --output none
  printf 'Skapade resursgruppen %s.\n' "$RG"
else
  printf 'Återanvänder befintlig resursgrupp %s (raderar ingenting).\n' "$RG"
fi

if ! az network vnet show -g "$RG" -n "$VNET" -o none 2>/dev/null; then
  az network vnet create -g "$RG" -n "$VNET" -l "$REGION" \
    --address-prefixes 10.0.0.0/16 \
    --subnet-name "$SUBNET" --subnet-prefixes 10.0.0.0/24 -o none
else
  if ! az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$SUBNET" -o none 2>/dev/null; then
    az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SUBNET" \
      --address-prefixes 10.0.0.0/24 -o none
  fi
fi
printf 'VNet och subnet finns: %s / %s.\n' "$VNET" "$SUBNET"

if ! az network nsg show -g "$RG" -n "$NSG" -o none 2>/dev/null; then
  az network nsg create -g "$RG" -n "$NSG" -l "$REGION" -o none
fi

if [[ "$SSH_SOURCE_CIDR" == '*' ]]; then
  echo 'OBS: SSH (22) öppnas för alla IP-adresser. Begränsa gärna med SSH_SOURCE_CIDR=ditt.ip/32.' >&2
fi
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n allow-ssh \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "$SSH_SOURCE_CIDR" --source-port-ranges '*' \
  --destination-address-prefixes '*' --destination-port-ranges 22 -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n allow-http \
  --priority 110 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes '*' --source-port-ranges '*' \
  --destination-address-prefixes '*' --destination-port-ranges 80 -o none

if ! az network public-ip show -g "$RG" -n "$PIP" -o none 2>/dev/null; then
  az network public-ip create -g "$RG" -n "$PIP" -l "$REGION" \
    --sku Standard --allocation-method Static -o none
fi

echo 'Skapar Ubuntu-VM, Standard SSD och NIC. cloud-init installerar Nginx och publicerar index.html.'
az vm create -g "$RG" -n "$VM" -l "$REGION" \
  --image Ubuntu2404 --size "$VM_SIZE" \
  --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true \
  --admin-username "$ADMIN" --authentication-type ssh \
  --ssh-key-values "$SSH_PUBLIC_KEY_FILE" \
  --vnet-name "$VNET" --subnet "$SUBNET" \
  --public-ip-address "$PIP" --nsg "$NSG" --nsg-rule NONE \
  --storage-sku StandardSSD_LRS --os-disk-delete-option Delete \
  --nic-delete-option Delete \
  --custom-data "$TEMP_CLOUD_INIT" --output none

# Skapande via CLI kan ha andra diagnostikstandardvärden än portalens vy.
az vm boot-diagnostics disable -g "$RG" -n "$VM" -o none

# Samma automatiska avstängning som i portalen: 20:00 svensk tid.
# API-resursen stöder tidszon; az vm auto-shutdown använder annars UTC som default.
VM_ID="$(az vm show -g "$RG" -n "$VM" --query id -o tsv)"
cat > "$TEMP_SCHEDULE" <<JSON
{
  "location": "$REGION",
  "properties": {
    "status": "Enabled",
    "taskType": "ComputeVmShutdownTask",
    "targetResourceId": "$VM_ID",
    "dailyRecurrence": { "time": "2000" },
    "timeZoneId": "W. Europe Standard Time",
    "notificationSettings": { "status": "Disabled", "timeInMinutes": 30 }
  }
}
JSON
SCHEDULE_URL="https://management.azure.com${VM_ID%/providers/Microsoft.Compute/virtualMachines/*}/providers/Microsoft.DevTestLab/schedules/shutdown-computevm-${VM}?api-version=2018-09-15"
if az rest --method put --url "$SCHEDULE_URL" --body "@$TEMP_SCHEDULE" \
  --headers 'Content-Type=application/json' -o none; then
  echo 'Automatisk avstängning skapad: 20:00 svensk tid.'
else
  echo 'VARNING: VM:n skapades, men auto-shutdown gick inte att ställa in. Stoppa/deallocera den manuellt!' >&2
fi

PUBLIC_IP="$(az network public-ip show -g "$RG" -n "$PIP" --query ipAddress -o tsv)"
echo
echo "KLART: Azure-resurser skapade. OBS: Nginx/cloud-init kan behöva några minuter till."
echo "Webbsida: http://$PUBLIC_IP"
echo "SSH från denna Bash-miljö: ssh -i \"$SSH_PRIVATE_KEY\" $ADMIN@$PUBLIC_IP"
echo "Kontroll på VM:n: sudo cloud-init status --wait && systemctl is-active nginx"
echo 'När du är klar för dagen: az vm deallocate -g '"$RG"' -n '"$VM"
echo 'Publik IP och disk kan fortfarande kosta även när VM:n är deallokerad.'