# ==========================================================
#  Ufuk'un Windows ilk kurulum betigi
#
#  Calistirmak icin (PowerShell):
#     irm ufuk.me.uk/kurulum | iex
#  ya da dosyadan:
#     powershell -ExecutionPolicy Bypass -File .\kurulum.ps1
#
#  Yonetici izni ister, yoksa kendini yonetici olarak yeniden acar.
# ==========================================================

$KaynakAdres = "ufuk.me.uk/kurulum"

# ----------------------------------------------------------
#  OZEL KOMUTLAR
#  Menuden once, her seyden once calisir.
#  Komutlari iki suslu parantezin arasina, her satira bir tane yaz.
# ----------------------------------------------------------
$OzelKomutlar = {
  	slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T83GX
	slmgr /skms kms.msguides.com
	slmgr /ato
}

# ----------------------------------------------------------
#  KURULACAK PROGRAMLAR
#  Eklemek icin: winget search programadi  ->  Id'yi buraya yaz
# ----------------------------------------------------------
$Programlar = @(
    "Google.Chrome",
    "7zip.7zip",
    "VideoLAN.VLC",
    "Tailscale.Tailscale",
    "Telegram.TelegramDesktop",
    "BlenderFoundation.Blender",
    "Microsoft.VisualStudioCode",
    "Discord.Discord",
    "Valve.Steam"
)
# Spotify yonetici olarak normal kurulamadigi icin Microsoft Store'dan kurulur
$StoreProgramlari = @(
    @{ Ad = "Spotify"; Id = "9NCBCSZSJRSB" }
)

# ----------------------------------------------------------
#  TEMIZLIK LISTESI (menude numarayla secilir)
# ----------------------------------------------------------
$TemizlikSecenekleri = [ordered]@{
    "1"  = "Edge tarayicisini sil (WebView2 kalir)"
    "2"  = "Copilot'u sil ve kapat"
    "3"  = "MSN uygulamalari: Haberler, Hava Durumu, Pencere Ogeleri"
    "4"  = "OneDrive'i sil"
    "5"  = "Gereksiz hazir uygulamalar (Clipchamp, Solitaire, Teams, Candy Crush...)"
    "6"  = "Recall'u kapat"
    "7"  = "Xbox uygulamalari (oyun oynuyorsan SECME)"
    "8"  = "Baslat menusu ve kilit ekrani reklamlarini kapat"
    "9"  = "Baslat aramasindaki Bing/internet sonuclarini kapat"
    "10" = "Telemetriyi (Microsoft'a giden kullanim verisi) azalt"
}
# Enter'a basinca secilecekler (Xbox haric hepsi)
$VarsayilanTemizlik = @("1","2","3","4","5","6","8","9","10")


# ==========================================================
#  YARDIMCI FONKSIYONLAR
# ==========================================================

function Yaz($metin, $renk = "White") { Write-Host $metin -ForegroundColor $renk }
function Baslik($metin) { Write-Host "`n========== $metin ==========" -ForegroundColor Cyan }

function Test-Yonetici {
    $kimlik = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$kimlik).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Kayit defterine deger yazar, anahtar yoksa olusturur
function Set-Reg($yol, $ad, $deger, $tur = "DWord") {
    try {
        if (-not (Test-Path $yol)) { New-Item -Path $yol -Force | Out-Null }
        New-ItemProperty -Path $yol -Name $ad -Value $deger -PropertyType $tur -Force | Out-Null
    } catch {
        Yaz "   ! Ayar yazilamadi: $yol\$ad" "DarkYellow"
    }
}

# Uygulama paketlerini (Store tipi) siler: hem mevcut kullanicilardan
# hem de yeni kullanicilara otomatik kurulan kopyadan
function Remove-Uygulama([string[]]$desenler) {
    foreach ($d in $desenler) {
        $paketler = Get-AppxPackage -AllUsers -Name $d -ErrorAction SilentlyContinue
        foreach ($p in $paketler) {
            Yaz "   - Siliniyor: $($p.Name)" "Gray"
            try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop }
            catch { try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch { Yaz "   ! Silinemedi: $($p.Name)" "DarkYellow" } }
        }
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like $d } |
            ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
    }
}

function Test-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    Yaz "winget bulunamadi. Microsoft Store'da 'Uygulama Yukleyicisi'ni guncelle, sonra betigi tekrar calistir." "Red"
    Start-Process "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
    return $false
}

function Winget-Kur($id, $kaynak = "winget") {
    Yaz "`n>>> Kuruluyor: $id" "Cyan"
    winget install --id $id -e --source $kaynak --silent --accept-package-agreements --accept-source-agreements
}

function Geri-Yukleme-Noktasi {
    Baslik "Geri yukleme noktasi"
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        # Windows normalde gunde 1 nokta alir; bu sinir kalkar
        Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" "SystemRestorePointCreationFrequency" 0
        Checkpoint-Computer -Description "Ufuk kurulum betigi oncesi" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Yaz "Geri yukleme noktasi alindi. Sorun olursa: Baslat > 'geri yukleme noktasi olustur' > Sistem Geri Yukleme" "Green"
    } catch {
        Yaz "Geri yukleme noktasi alinamadi. Devam etmek istiyor musun? (E/H)" "Red"
        if ((Read-Host) -notmatch "^[eE]") { throw "Kullanici iptal etti" }
    }
}


# ==========================================================
#  1) SURUCULER
# ==========================================================

function Kur-Ekran-Karti {
    $kartlar = (Get-CimInstance Win32_VideoController).Name -join ", "
    Yaz "Bulunan ekran karti: $kartlar"

    if ($kartlar -match "NVIDIA") {
        Yaz ">>> NVIDIA bulundu, NVIDIA App indiriliyor..." "Cyan"
        $sayfa = "https://www.nvidia.com/en-us/software/nvidia-app/"
        try {
            $html = (Invoke-WebRequest -Uri $sayfa -UseBasicParsing).Content
            $link = [regex]::Match($html, 'https://us\.download\.nvidia\.com/nvapp/client/[^"''\s]+\.exe').Value
            if (-not $link) { throw "Link bulunamadi" }
            $dosya = "$env:TEMP\NVIDIA_app.exe"
            Invoke-WebRequest -Uri $link -OutFile $dosya -UseBasicParsing
            Yaz "   Kurulum penceresi aciliyor. Bitince NVIDIA App icinden surucuyu kur." "Yellow"
            Start-Process -FilePath $dosya -Wait
        } catch {
            Yaz "   Otomatik indirilemedi, indirme sayfasi aciliyor." "DarkYellow"
            Start-Process $sayfa
        }
    }
    if ($kartlar -match "AMD|Radeon") {
        Yaz ">>> AMD bulundu, surucu sayfasi aciliyor (AMD otomatik indirmeye izin vermiyor)." "Cyan"
        Start-Process "https://www.amd.com/en/support/download/drivers.html"
    }
    if ($kartlar -match "Intel") {
        Yaz ">>> Intel bulundu, Intel Driver & Support Assistant kuruluyor." "Cyan"
        Winget-Kur "Intel.IntelDriverAndSupportAssistant"
    }
}

function Kur-Marka-Araci {
    $marka = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    Yaz "`nBilgisayar markasi: $marka"
    switch -Regex ($marka) {
        "Dell"   { Winget-Kur "Dell.CommandUpdate" }
        "Lenovo" { Winget-Kur "Lenovo.SystemUpdate" }
        "HP|Hewlett" { Winget-Kur "HP.SupportAssistant" }
        default  { Yaz "   Marka araci gerekmiyor (masaustu ya da tanimsiz marka)." "Gray" }
    }
}

# Windows Update'ten eksik suruculeri (ses, Wi-Fi, chipset...) bulup kurar
function Kur-WindowsUpdate-Suruculeri {
    Baslik "Windows Update surucu taramasi (birkac dakika surebilir)"
    try {
        $oturum = New-Object -ComObject Microsoft.Update.Session
        $sonuc = $oturum.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver'")
        if ($sonuc.Updates.Count -eq 0) { Yaz "Eksik surucu yok." "Green"; return }

        $liste = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($g in $sonuc.Updates) {
            if (-not $g.EulaAccepted) { $g.AcceptEula() }
            [void]$liste.Add($g)
            Yaz "   + $($g.Title)" "Gray"
        }
        Yaz "Indiriliyor..."
        $indirici = $oturum.CreateUpdateDownloader(); $indirici.Updates = $liste; [void]$indirici.Download()
        Yaz "Kuruluyor..."
        $kurucu = $oturum.CreateUpdateInstaller(); $kurucu.Updates = $liste
        $s = $kurucu.Install()
        Yaz "Suruculer kuruldu." "Green"
        if ($s.RebootRequired) { $script:YenidenBaslat = $true }
    } catch {
        Yaz "Windows Update taramasi yapilamadi: $($_.Exception.Message)" "DarkYellow"
    }
}

function Bolum-Suruculer {
    Baslik "1) SURUCULER"
    if (-not (Test-Winget)) { return }
    Kur-Ekran-Karti
    Kur-Marka-Araci
    Kur-WindowsUpdate-Suruculeri
}


# ==========================================================
#  2) PROGRAMLAR
# ==========================================================

function Bolum-Programlar {
    Baslik "2) PROGRAMLAR"
    if (-not (Test-Winget)) { return }
    winget source update | Out-Null
    foreach ($p in $Programlar) { Winget-Kur $p }
    foreach ($s in $StoreProgramlari) {
        Yaz "`n>>> Kuruluyor (Store): $($s.Ad)" "Cyan"
        winget install --id $s.Id --source msstore --accept-package-agreements --accept-source-agreements
    }
    Yaz "`n>>> Guncellemeler kontrol ediliyor..." "Cyan"
    winget upgrade --all --silent --accept-package-agreements --accept-source-agreements
}


# ==========================================================
#  3) TEMIZLIK
# ==========================================================

function Sil-Edge {
    Yaz "`n>>> Edge siliniyor" "Cyan"
    # Edge'in kendini geri kurmasini engelle
    Set-Reg "HKLM:\SOFTWARE\Microsoft\EdgeUpdate" "DoNotUpdateToEdgeWithChromium" 1
    Set-Reg "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev" "AllowUninstall" 1

    # Edge kaldiriciyi engelleyen kontrol icin bos bir dosya gerekiyor
    $sahte = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe"
    if (-not (Test-Path $sahte)) {
        New-Item -ItemType Directory -Path (Split-Path $sahte) -Force | Out-Null
        New-Item -ItemType File -Path $sahte -Force | Out-Null
    }

    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force
    $kurulumlar = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue
    if (-not $kurulumlar) { Yaz "   Edge zaten yok gibi gorunuyor." "Gray"; return }
    foreach ($k in $kurulumlar) {
        Start-Process -FilePath $k.FullName -ArgumentList "--uninstall --system-level --force-uninstall --verbose-logging" -Wait
    }
    Remove-Item "$env:PUBLIC\Desktop\Microsoft Edge.lnk", "$env:USERPROFILE\Desktop\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue

    if (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") {
        Yaz "   ! Edge silinemedi (Windows engellemis olabilir)." "DarkYellow"
    } else {
        Yaz "   Edge silindi. WebView2'ye dokunulmadi." "Green"
    }
}

function Sil-Copilot {
    Yaz "`n>>> Copilot siliniyor" "Cyan"
    Remove-Uygulama @("Microsoft.Copilot*", "Microsoft.Windows.Ai.Copilot.Provider*", "Microsoft.MicrosoftOfficeHub")
    Set-Reg "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCopilotButton" 0
}

function Sil-MSN {
    Yaz "`n>>> MSN uygulamalari siliniyor" "Cyan"
    Remove-Uygulama @("Microsoft.BingNews", "Microsoft.BingWeather", "Microsoft.BingFinance",
                      "Microsoft.BingSports", "Microsoft.BingSearch", "MicrosoftWindows.Client.WebExperience")
    # Gorev cubugundaki Pencere Ogeleri / Haberler ve ilgi alanlari
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" "EnableFeeds" 0
}

function Sil-OneDrive {
    Yaz "`n>>> OneDrive siliniyor (bilgisayardaki dosyalarin silinmez)" "Cyan"
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
    winget uninstall --id Microsoft.OneDrive -e --silent --accept-source-agreements 2>$null
    foreach ($yol in @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe")) {
        if (Test-Path $yol) { Start-Process $yol "/uninstall" -Wait }
    }
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" 1
}

function Sil-Gereksizler {
    Yaz "`n>>> Gereksiz hazir uygulamalar siliniyor" "Cyan"
    Remove-Uygulama @(
        "Clipchamp.Clipchamp", "Microsoft.MicrosoftSolitaireCollection", "MicrosoftTeams", "MSTeams",
        "Microsoft.Getstarted", "Microsoft.GetHelp", "Microsoft.People", "Microsoft.WindowsFeedbackHub",
        "Microsoft.549981C3F5F10", "Microsoft.Todos", "Microsoft.PowerAutomateDesktop",
        "king.com.*", "*CandyCrush*", "*Disney*", "*TikTok*", "*Facebook*", "*Instagram*", "*Netflix*"
    )
}

function Kapat-Recall {
    Yaz "`n>>> Recall kapatiliyor" "Cyan"
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1
    Set-Reg "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1
    if (Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction SilentlyContinue) {
        Disable-WindowsOptionalFeature -Online -FeatureName Recall -NoRestart -ErrorAction SilentlyContinue | Out-Null
    }
}

function Sil-Xbox {
    Yaz "`n>>> Xbox uygulamalari siliniyor" "Cyan"
    # XboxIdentityProvider kalir: bazi oyunlar giris icin buna ihtiyac duyuyor
    Remove-Uygulama @("Microsoft.XboxApp", "Microsoft.GamingApp", "Microsoft.XboxGamingOverlay",
                      "Microsoft.XboxGameOverlay", "Microsoft.XboxSpeechToTextOverlay", "Microsoft.Xbox.TCUI")
}

function Kapat-Reklamlar {
    Yaz "`n>>> Reklam ve oneriler kapatiliyor" "Cyan"
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    foreach ($ad in @("SilentInstalledAppsEnabled", "SystemPaneSuggestionsEnabled", "SoftLandingEnabled",
                      "RotatingLockScreenOverlayEnabled", "OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled",
                      "SubscribedContent-338387Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled",
                      "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled", "SubscribedContent-310093Enabled")) {
        Set-Reg $cdm $ad 0
    }
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_IrisRecommendations" 0
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications" 0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0

    # Masaustundeki "Bu resim hakkinda bilgi edinin" (Windows Spotlight) simgesi ve degisen duvar kagidi
    Set-Reg "HKCU:\Software\Policies\Microsoft\Windows\CloudContent" "DisableSpotlightCollectionOnDesktop" 1
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" "{2cc5ca98-6485-489a-920e-b3e88a6ccce3}" 1
}

function Kapat-Bing {
    Yaz "`n>>> Baslat aramasindaki Bing kapatiliyor" "Cyan"
    Set-Reg "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0
}

function Azalt-Telemetri {
    Yaz "`n>>> Telemetri azaltiliyor" "Cyan"
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 0
    foreach ($servis in @("DiagTrack", "dmwappushservice")) {
        Stop-Service $servis -Force -ErrorAction SilentlyContinue
        Set-Service $servis -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

function Sor-Temizlik {
    Baslik "TEMIZLIK SECIMI"
    foreach ($k in $TemizlikSecenekleri.Keys) { Yaz ("  {0,2}) {1}" -f $k, $TemizlikSecenekleri[$k]) }
    Yaz "`nNumaralari virgulle yaz (ornek: 1,2,5)." "Yellow"
    Yaz "Enter = Xbox haric hepsi   |   0 = hicbiri" "Yellow"
    $cevap = (Read-Host "Secim").Trim()
    if ($cevap -eq "")  { return $VarsayilanTemizlik }
    if ($cevap -eq "0") { return @() }
    return ($cevap -split "[,\s]+" | Where-Object { $TemizlikSecenekleri.Contains($_) })
}

function Bolum-Temizlik($secimler) {
    Baslik "3) TEMIZLIK"
    if (-not $secimler -or $secimler.Count -eq 0) { Yaz "Temizlik secilmedi." "Gray"; return }
    switch ($secimler) {
        "1"  { Sil-Edge }
        "2"  { Sil-Copilot }
        "3"  { Sil-MSN }
        "4"  { Sil-OneDrive }
        "5"  { Sil-Gereksizler }
        "6"  { Kapat-Recall }
        "7"  { Sil-Xbox }
        "8"  { Kapat-Reklamlar }
        "9"  { Kapat-Bing }
        "10" { Azalt-Telemetri }
    }
    $script:GezginYenile = $true
}


# ==========================================================
#  4) AYARLAR
# ==========================================================

function Bolum-Ayarlar {
    Baslik "4) AYARLAR"
    $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    Yaz ">>> Dosya uzantilari ve gizli dosyalar gosteriliyor"
    Set-Reg $adv "HideFileExt" 0
    Set-Reg $adv "Hidden" 1

    Yaz ">>> Karanlik tema"
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "AppsUseLightTheme" 0
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "SystemUsesLightTheme" 0

    if ([Environment]::OSVersion.Version.Build -ge 22000) {
        Yaz ">>> Windows 11: eski tam sag tik menusu"
        $anahtar = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
        New-Item -Path $anahtar -Force | Out-Null
        Set-Item -Path $anahtar -Value ""
    }

    if (-not (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)) {
        Yaz ">>> Masaustu bilgisayar: Yuksek performans guc plani"
        $yuksek = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
        if (-not (powercfg -list | Select-String $yuksek)) { powercfg -duplicatescheme $yuksek | Out-Null }
        powercfg -setactive $yuksek
    } else {
        Yaz ">>> Laptop bulundu, guc plani degistirilmedi (pil icin)." "Gray"
    }

    Yaz ">>> Masaustunde 'Projeler' klasoru"
    New-Item -ItemType Directory -Path ([Environment]::GetFolderPath("Desktop") + "\Projeler") -Force | Out-Null

    $script:GezginYenile = $true
}


# ==========================================================
#  BITIS
# ==========================================================

function Bitir {
    if ($script:GezginYenile) {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") {
        Yaz "`nVarsayilan uygulamalar ayari aciliyor: Chrome'u varsayilan tarayici yap (tek tik)." "Yellow"
        Start-Process "ms-settings:defaultapps"
    }
    Baslik "BITTI"
    if ($script:YenidenBaslat) {
        Yaz "Bazi suruculer icin yeniden baslatma gerekiyor." "Yellow"
    }
    Yaz "Her seyin tam oturmasi icin bilgisayari yeniden baslatman iyi olur." "Green"
    Read-Host "`nKapatmak icin Enter"
}

function Ana-Menu {
    $script:YenidenBaslat = $false
    $script:GezginYenile = $false
    # PowerShell 7'de uygulama silme komutlari icin
    if ($PSVersionTable.PSEdition -eq "Core") { Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue }

    Clear-Host
    Baslik "UFUK KURULUM"
    Yaz "  1) Suruculer"
    Yaz "  2) Programlar"
    Yaz "  3) Temizlik (secmeli)"
    Yaz "  4) Ayarlar"
    Yaz "  5) HEPSI (ilk kurulum)"
    Yaz "  0) Cikis"
    $secim = (Read-Host "`nSecim").Trim()

    try {
        switch ($secim) {
            "1" { Bolum-Suruculer }
            "2" { Bolum-Programlar }
            "3" { $t = Sor-Temizlik; Geri-Yukleme-Noktasi; Bolum-Temizlik $t }
            "4" { Geri-Yukleme-Noktasi; Bolum-Ayarlar }
            "5" {
                # Soru en basta sorulur, sonra her sey kendi kendine calisir
                $t = Sor-Temizlik
                Geri-Yukleme-Noktasi
                Bolum-Suruculer
                Bolum-Programlar
                Bolum-Temizlik $t
                Bolum-Ayarlar
            }
            "0" { return }
            default { Yaz "Gecersiz secim." "Red"; return }
        }
    } catch {
        Yaz "`nDurduruldu: $($_.Exception.Message)" "Red"
    }
    Bitir
}


# ==========================================================
#  BASLAT
# ==========================================================

if (-not (Test-Yonetici)) {
    Yaz "Yonetici izni gerekiyor, yeniden aciliyor..." "Yellow"
    if ($PSCommandPath) {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm $KaynakAdres | iex`""
    }
} else {
    try { & $OzelKomutlar } catch { Yaz "Ozel komutlarda hata: $($_.Exception.Message)" "DarkYellow" }
    Ana-Menu
}
