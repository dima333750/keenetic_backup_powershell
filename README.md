# keenetic_backup_powershell
Автоматическое резервное копирование настроек Keenetic: надёжно, безопасно и с умной ротацией через powershell
<ul>
 	<li>
<p>создание отдельного пользователя с правами только на чтение;</p>
</li>
 	<li>
<p>безопасную передачу пароля (Base64);</p>
</li>
 	<li>
<p>ротацию бэкапов: ежедневные, еженедельные, ежемесячные и годовые копии.</p>
</li>
</ul>
<h2>1. Подготовка: создаём пользователя backup на Keenetic</h2>
<p>Для безопасности <strong>не используйте учётную запись администратора</strong> в скриптах. В Keenetic (на базе ОС NDMS) можно создать отдельного пользователя с правами <strong>только на чтение</strong> (read-only).</p>
<h3>Как создать:</h3>
<ol>
 	<li>
<p>Зайдите в веб-интерфейс Keenetic.</p>
</li>
 	<li>
<p>Перейдите в раздел <strong>"Управление"</strong> > <strong>"Пользователи"</strong>.</p>
</li>
 	<li>
<p>Нажмите <strong>"Добавить пользователя"</strong>.</p>
</li>
 	<li>
<p>Задайте имя, например <code>backup</code>.</p>
</li>
 	<li>
<p>Установите флажок <strong>"Только чтение"</strong>.</p>
</li>
 	<li>
<p>Придумайте пароль (запишите его, он понадобится позже).</p>
</li>
</ol>
<p>Такой пользователь сможет скачивать конфигурацию (<code>startup-config.txt</code>), но не сможет менять настройки роутера.</p>
<h2>2. Шифрование пароля: почему Base64 и как это сделать</h2>
<p>Хранить пароль в скрипте в открытом виде — плохая практика. Мы используем простое, но эффективное решение: кодирование в Base64. Это не шифрование, но скрывает пароль от "поверхностного" взгляда.</p>
<h3>Кодируем пароль в PowerShell:</h3>
<p>Запустите PowerShell и выполните:</p>
<div>
<div>
<div>
<div>
<div>powershell</div>
</div>
</div>
</div>
<pre>$pass = "ваш_пароль_пользователя_backup"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($pass)
[Convert]::ToBase64String($bytes)</pre>
</div>
<p>Вы получите строку вида <code>0JDRgdCw0L3QvdC+0Y8=</code>. Это и есть ваш закодированный пароль. В скрипте мы будем передавать именно его.</p>
<h2>3. Скрипт автоматического бэкапа</h2>
<p>Скрипт делает следующее:</p>
<ul>
 	<li>
<p>авторизуется на Keenetic по HTTP (используется NDMS-авторизация с вызовом <code>auth</code>);</p>
</li>
 	<li>
<p>скачивает файл <code>startup-config.txt</code>;</p>
</li>
 	<li>
<p>упаковывает его в ZIP с именем, зависящим от даты (daily/weekly/monthly/yearly);</p>
</li>
 	<li>
<p>удаляет старые бэкапы согласно политике ротации.</p>
</li>
</ul>
<h3>Логика ротации:</h3>
<ul>
 	<li>
<p><strong>Daily</strong> — храним 7 последних копий.</p>
</li>
 	<li>
<p><strong>Weekly</strong> (воскресенье) — храним 4 последние копии.</p>
</li>
 	<li>
<p><strong>Monthly</strong> (1 число) — храним 12 последних копий.</p>
</li>
 	<li>
<p><strong>Yearly</strong> (1 января) — храним 20 последних копий.</p>
</li>
</ul>
<h3>Полный код скрипта</h3>
<p>Сохраните файл как <code>backup_keenetic.ps1</code>:</p>
<div>
<div>
<div>
<div>
<div>powershell</div>
</div>
</div>
</div>
<pre># Keenetic Backup with ZIP and smart rotation
# Run: powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File backup_keenetic.ps1 -Password "BASE64_STRING"
param(
    [string]$RouterIp = "192.168.0.1",  # IP или домен (например, my.keenetic.net)
    [string]$Login = "backup",
    [string]$Password = "",
    [string]$BackupDir = "C:\Backups\Keenetic"
)
$ErrorActionPreference = "Continue"
function Log {
    param([string]$Text)
    $time = Get-Date -Format "HH:mm:ss"
    Write-Host "[$time] $Text"
}
# Decode password
if ($Password -eq "") {
    Log "ERROR: No password"
    exit 1
}
try {
    $bytes = [Convert]::FromBase64String($Password)
    $RealPassword = [System.Text.Encoding]::UTF8.GetString($bytes)
    Log "Password loaded: ****"
} catch {
    Log "ERROR: Invalid Base64 password"
    exit 1
}
# Create folder
if (!(Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}
# Auth
Log "=== AUTH ==="
$AuthUrl = "http://$RouterIp/auth"
$Session = $null
try {
    Invoke-WebRequest -Uri $AuthUrl -Method GET -SessionVariable Session -TimeoutSec 10 | Out-Null
} catch {
    if ($_.Exception.Response.StatusCode -eq 401) {
        $headers = $_.Exception.Response.Headers
        $Realm = $headers['X-NDM-Realm']
        $Challenge = $headers['X-NDM-Challenge']
        Log "Got challenge"
    } else {
        Log "Auth error: $_"
        exit 1
    }
}
$md5Input = "$Login`:$Realm`:$RealPassword"
$md5Bytes = [System.Text.Encoding]::UTF8.GetBytes($md5Input)
$md5Hash = [BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash($md5Bytes)).Replace("-", "").ToLower()
$shaInput = "$Challenge$md5Hash"
$shaBytes = [System.Text.Encoding]::UTF8.GetBytes($shaInput)
$shaHash = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($shaBytes)).Replace("-", "").ToLower()
$body = ([PSCustomObject]@{login = $Login; password = $shaHash} | ConvertTo-Json)
try {
    $auth = Invoke-WebRequest -Uri $AuthUrl -Method POST -Body $body -ContentType "application/json" -WebSession $Session -TimeoutSec 10
    Log "Auth OK: $($auth.StatusCode)"
} catch {
    Log "Auth failed: $_"
    exit 1
}
# Download
$now = Get-Date
$timestamp = $now.ToString("yyyyMMdd-HHmmss")
$ConfigUrl = "http://$RouterIp/ci/startup-config.txt"
$tempFile = Join-Path $BackupDir "temp-$timestamp.txt"
Log "Downloading..."
try {
    Invoke-WebRequest -Uri $ConfigUrl -WebSession $Session -OutFile $tempFile -TimeoutSec 30
    $size = (Get-Item $tempFile).Length
    Log "Downloaded: $size bytes"
} catch {
    Log "ERROR download: $_"
    exit 1
}
# Determine archive type
$day = $now.Day
$month = $now.Month
$year = $now.Year
$dayOfWeek = $now.DayOfWeek
# Daily (every day)
$archiveName = "daily-$timestamp.zip"
# Weekly (every Sunday, keep 4)
if ($dayOfWeek -eq "Sunday") {
    $archiveName = "weekly-$timestamp.zip"
}
# Monthly (1st day of month, keep 12)
if ($day -eq 1) {
    $archiveName = "monthly-$timestamp.zip"
}
# Yearly (Jan 1, keep 20)
if ($month -eq 1 -and $day -eq 1) {
    $archiveName = "yearly-$timestamp.zip"
}
$archivePath = Join-Path $BackupDir $archiveName
# Create ZIP
try {
    Compress-Archive -Path $tempFile -DestinationPath $archivePath -Force
    Remove-Item $tempFile -Force
    $zipSize = (Get-Item $archivePath).Length
    Log "ZIP created: $archiveName ($zipSize bytes)"
} catch {
    Log "ERROR creating ZIP: $_"
    Remove-Item $tempFile -Force
    exit 1
}
# Rotation
Log "=== ROTATION ==="
# Daily: keep 7
$dailies = Get-ChildItem $BackupDir -Filter "daily-*.zip" | Sort-Object Name -Descending
if ($dailies.Count -gt 7) {
    $toDelete = $dailies | Select-Object -Skip 7
    foreach ($file in $toDelete) {
        Remove-Item $file.FullName -Force
        Log "Deleted old daily: $($file.Name)"
    }
}
# Weekly: keep 4
$weeklies = Get-ChildItem $BackupDir -Filter "weekly-*.zip" | Sort-Object Name -Descending
if ($weeklies.Count -gt 4) {
    $toDelete = $weeklies | Select-Object -Skip 4
    foreach ($file in $toDelete) {
        Remove-Item $file.FullName -Force
        Log "Deleted old weekly: $($file.Name)"
    }
}
# Monthly: keep 12
$monthlies = Get-ChildItem $BackupDir -Filter "monthly-*.zip" | Sort-Object Name -Descending
if ($monthlies.Count -gt 12) {
    $toDelete = $monthlies | Select-Object -Skip 12
    foreach ($file in $toDelete) {
        Remove-Item $file.FullName -Force
        Log "Deleted old monthly: $($file.Name)"
    }
}
# Yearly: keep 20
$yearlies = Get-ChildItem $BackupDir -Filter "yearly-*.zip" | Sort-Object Name -Descending
if ($yearlies.Count -gt 20) {
    $toDelete = $yearlies | Select-Object -Skip 20
    foreach ($file in $toDelete) {
        Remove-Item $file.FullName -Force
        Log "Deleted old yearly: $($file.Name)"
    }
}
Log "Done"</pre>
</div>
<h2>4. Настройка планировщика Windows</h2>
<p>Чтобы скрипт выполнялся автоматически, добавим задание в Планировщик задач.</p>
<h3>Шаги:</h3>
<ol>
 	<li>
<p>Откройте <strong>Task Scheduler</strong>.</p>
</li>
 	<li>
<p>Создайте новую задачу:</p>
<ul>
 	<li>
<p><strong>Триггер</strong>: ежедневно, в удобное время (например, 3:00 ночи).</p>
</li>
 	<li>
<p><strong>Действие</strong>: запуск программы <code>powershell.exe</code>.</p>
</li>
 	<li>
<p><strong>Аргументы</strong>:</p>
<div>
<div>
<div>
<div>

</div>
</div>
</div>
<pre>-WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Scripts\backup_keenetic.ps1" -Password "0JDRgdCw0L3QvdC+0Y8="</pre>
</div></li>
</ul>
</li>
 	<li>
<p>Убедитесь, что задача выполняется от имени пользователя с правами на запись в папку <code>C:\Backups\Keenetic</code>.</p>
</li>
</ol>
<h2>5. Проверка и логирование</h2>
<p>При запуске скрипт выводит в консоль временные метки и статус операций. Для отладки можно запустить его вручную. В фоновом режиме окно PowerShell будет скрыто (<code>-WindowStyle Hidden</code>).</p>
<p>Пример успешного выполнения:</p>
<div>
<div>
<div>
<div>
<div>text</div>
</div>
</div>
</div>
<pre>[12:30:15] Password loaded: ****
[12:30:15] === AUTH ===
[12:30:16] Got challenge
[12:30:16] Auth OK: 200
[12:30:16] Downloading...
[12:30:17] Downloaded: 5842 bytes
[12:30:17] ZIP created: daily-20250213-123015.zip (2143 bytes)
[12:30:17] === ROTATION ===
[12:30:17] Deleted old daily: daily-20250206-030001.zip
[12:30:17] Done</pre>
</div>
<h2>Заключение</h2>
<p>Теперь у вас есть полностью автоматизированная система резервного копирования конфигурации Keenetic с продуманной ротацией. Вы всегда сможете откатиться на нужную версию настроек: от вчерашней до копии годичной давности.</p>
<h3>Плюсы подхода:</h3>
<ul>
 	<li>
<p>Не требует установки дополнительного ПО на роутер.</p>
</li>
 	<li>
<p>Безопасно (read-only пользователь).</p>
</li>
 	<li>
<p>Экономит место за счёт ротации.</p>
</li>
 	<li>
<p>Пароль не светится в открытом виде.</p>
</li>
</ul>
<p>Можно доработать скрипт под себя: добавить отправку уведомлений по почте или в Telegram, копирование бэкапов в облако и т.д.</p>
<p>Удачи в автоматизации!</p>
