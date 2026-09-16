# Novatrix AB – återskapa vecka 34 med Azure CLI

Detta är ett **extra automationsspår** som återskapar resurserna från kod. Den manuellt
driftsatta miljön behövde inte detta för G. Du kan lägga filerna bredvid din
befintliga `week34/index.html` i repot `99gushon/azure-novatrix`, grenen `Vecka-34`.

## Vad skapas?

| Resurs | Namn / inställning |
|---|---|
| Resursgrupp | `rg-novatrix` |
| VNet | `vnet-novatrix`, `10.0.0.0/16` |
| Subnet | `subnet-novatrix-web`, `10.0.0.0/24` |
| NSG | `nsg-novatrix-web`, TCP 22 och 80 |
| Publik IP | `pip-novatrix-web`, Standard / statisk |
| Virtuell maskin | `vm-novatrix-web`, Ubuntu 24.04 x64 |
| VM-storlek | `Standard_B2ats_v2` |
| Disk | Standard SSD |
| Säkerhet | SSH-nyckel, Trusted Launch + Secure Boot + vTPM |
| Webbtjänst | Nginx, med din `index.html` i `/var/www/html/` |
| Kostnadsskydd | Auto-shutdown kl. 20:00 svensk tid, utan e-postnotis |

`deploy.sh` genererar cloud-init med den HTML-fil som ligger bredvid skriptet.
Det finns alltså **bara en källa** för webbsidans innehåll.

## Viktigt – gör detta innan du kör

Om din manuellt skapade `vm-novatrix-web` fortfarande finns är det **ingen bra idé
att köra skriptet direkt mot samma miljö**. Skriptet stoppar då utan att röra VM:n.
Vill du bygga om med samma namn måste du först spara allt du behöver och radera
den tidigare miljön medvetet. **Radera inte resursgruppen om du har annat där,
t.ex. material från kommande kursveckor.**

Skriptet skapar debiterbara Azure-resurser. Kontrollera rätt prenumeration och
kvoter. En avstängd/deallokerad VM kan fortfarande ha kostnad för disk och publik IP.

## Kör i Azure Cloud Shell (Bash)

1. Lägg upp `deploy.sh`, `delete-lab.sh` och `AUTOMATION-GUIDE.md` i samma
   `week34`-mapp som **din befintliga `index.html`** i GitHub. Lägg aldrig en
   `.pem`-fil eller privat SSH-nyckel i GitHub.
2. Öppna Azure Portal → Cloud Shell (`>_`) → välj **Bash**. Om Azure första
   gången begär uppsättning av Cloud Shell behöver du följa uppstartsdialogen;
   eventuell lagring för Cloud Shell kan kosta pengar.
3. Hämta kursgrenen och kör:

   ```bash
   git clone --branch Vecka-34 https://github.com/99gushon/azure-novatrix.git
   cd azure-novatrix/week34
   bash deploy.sh
   ```

   Om du har flera Azure-prenumerationer, välj en specifikt innan du kör:

   ```bash
   az account list --output table
   export AZURE_SUBSCRIPTION="Azure subscription 1"
   bash deploy.sh
   ```

   `bash deploy.sh` skapar ett nytt SSH-nyckelpar i `~/.ssh/novatrix-key` om
   inget finns där. **Det är då ett annat nyckelpar än din tidigare
   `novatrix-key.pem` från portalen!** SSH från Cloud Shell fungerar med den
   nya nyckeln. För SSH från din egen dator behöver du antingen hämta den nya
   privata nyckeln via Cloud Shells funktion för filnedladdning och förvara
   den säkert, eller använda din gamla nyckels **publika** del vid provisionering.
   Dela inte den privata nyckeln med någon.

### Återanvänd din gamla SSH-nyckel om du vill

Generera motsvarande publika nyckel från `novatrix-key.pem` på din egen dator:

```powershell
ssh-keygen -y -f "$HOME\Downloads\novatrix-key.pem" > "$HOME\Downloads\novatrix-key.pub"
```

Överför **bara `.pub`-filen** till Cloud Shell och kör exempelvis:

```bash
SSH_PUBLIC_KEY_FILE="$HOME/novatrix-key.pub" bash deploy.sh
```

Den gamla privata `.pem`-filen stannar på din dator.

### Begränsa SSH till din egen publika IP (rekommenderas)

Om du känner din dators publika IPv4-adress kan du använda `/32`:

```bash
SSH_SOURCE_CIDR="DIN_PUBLIKA_IPV4/32" bash deploy.sh
```

Standardläget öppnar SSH (22) från alla IP-adresser för att förenkla labbet;
endast nyckelautentisering används. Webbplatsen är öppet tillgänglig på HTTP
(80). Formuläret skickar eller sparar fortfarande inga ärenden. Detta är en
övningsmiljö, inte en färdig säker produktionswebbplats (HTTPS saknas).

## Kontrollera efter körningen

Skriptet visar `http://DIN_IP`. Cloud-init fortsätter en stund efter att Azure
rapporterar att VM:n är skapad. Om sidan inte syns direkt, vänta någon minut.

```bash
az vm show -g rg-novatrix -n vm-novatrix-web -o table
az network public-ip show -g rg-novatrix -n pip-novatrix-web \
  --query ipAddress -o tsv
```

Anslut med SSH-adressen och nyckeln som skriptet skriver ut. Inne i VM:n:

```bash
sudo cloud-init status --wait
systemctl is-active nginx
curl -I http://localhost
grep 'Novatrix AB' /var/www/html/index.html
```

Om något misslyckas:

```bash
sudo tail -n 100 /var/log/cloud-init-output.log
sudo systemctl status nginx --no-pager
```

## Under arbetet – deallokera och starta igen

```bash
az vm deallocate -g rg-novatrix -n vm-novatrix-web
az vm start -g rg-novatrix -n vm-novatrix-web
```

Cloud-init körs vid **första skapandet** och är inte en mekanism för att uppdatera
redan befintliga VM:ar. Om du ändrar `index.html` och vill återskapa *från noll*,
ta bort den gamla miljön först **efter att du kontrollerat vad som raderas**.

## Radera labbet när PDF och GitHub är sparade

`delete-lab.sh` visar alla resurser och kräver att du skriver en exakt
bekräftelse. Skriptet raderar **hela `rg-novatrix`**, inklusive andra resurser
som du kan ha lagt i samma resursgrupp. Kör inte om du vill behålla dem.

```bash
bash delete-lab.sh
```

Om du vill testa i en **annan resursgrupp** utan att beröra den nuvarande VM:n
kan du använda miljövariabeln `RG`, exempelvis:

```bash
RG=rg-novatrix-test bash deploy.sh
RG=rg-novatrix-test bash delete-lab.sh
```

Detta skapar dock ytterligare debiterbara resurser. Resursnamn kan återanvändas
i olika resursgrupper, men kvoter och regiontillgänglighet måste fortfarande räcka.

## Tekniska referenser

- Azure CLI VM: https://learn.microsoft.com/en-us/cli/azure/vm
- Azure CLI VNet: https://learn.microsoft.com/en-us/cli/azure/network/vnet
- Cloud-init: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/using-cloud-init
- Auto-shutdown-scheman: https://learn.microsoft.com/en-us/azure/templates/microsoft.devtestlab/2018-09-15/schedules