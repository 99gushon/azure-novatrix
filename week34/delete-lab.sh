#!/usr/bin/env bash
# FARA: raderar HELA resursgruppen och ALLA resurser i den.
set -Eeuo pipefail
RG="${RG:-rg-novatrix}"
command -v az >/dev/null 2>&1 || { echo 'Azure CLI saknas.' >&2; exit 1; }
az account show --output none 2>/dev/null || { echo 'Logga in med az login.' >&2; exit 1; }
if [[ -n "${AZURE_SUBSCRIPTION:-}" ]]; then az account set --subscription "$AZURE_SUBSCRIPTION"; fi
echo "Prenumeration: $(az account show --query name -o tsv)"
echo "Du tänker radera hela resursgruppen: $RG"
if [[ "$(az group exists -n "$RG" -o tsv)" != true ]]; then
  echo 'Resursgruppen finns inte. Inget har raderats.'
  exit 0
fi
echo 'ALLA resurser som kommer att försvinna:'
az resource list -g "$RG" --query '[].[name,type]' -o table
echo
echo 'Spara först skärmbilder och verifiera GitHub/PDF. Det här går inte att ångra.'
read -r -p "Skriv exakt DELETE $RG för att fortsätta: " CONFIRM
if [[ "$CONFIRM" != "DELETE $RG" ]]; then
  echo 'Avbrutet. Ingenting raderades.'
  exit 1
fi
az group delete --name "$RG" --yes
echo "Resursgruppen $RG har raderats. GitHub-repot och dina lokala SSH-nycklar påverkas inte."