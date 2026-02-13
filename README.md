# keenetic_backup_powershell
Автоматическое резервное копирование настроек Keenetic powershell
<h2>Краткая инструкция по настройке</h2>
<h3>1. Создание пользователя на Keenetic</h3>
<ul>
<li>
<p>Зайдите в веб-интерфейс роутера</p>
</li>
<li>
<p><strong>Управление</strong>&rarr;<strong>Пользователи</strong>&rarr;<strong>Добавить пользователя</strong></p>
</li>
<li>
<p>Имя:<code>backup</code>(или любое другое)</p>
</li>
<li>
<p>Пароль: придумайте и запишите</p>
</li>
<li>
<p>Обязательно поставьте галочку<strong>"Только чтение"</strong></p>
</li>
<li>
<p>Сохраните</p>
</li>
</ul>
<h3>2. Кодирование пароля в Base64</h3>
<p>В PowerShell выполните:</p>
<div>
<div>
<div>
<div>
<div>powershell</div>
</div>
</div>
</div>
<pre>$pass = "пароль_от_backup"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($pass)
[Convert]::ToBase64String($bytes)</pre>
</div>
<p>Полученную строку (например<code>0JDRgdCw0L3QvdC+0Y8=</code>) сохраните &mdash; это закодированный пароль.</p>
<h3>3. Что нужно изменить в скрипте</h3>
<p>В файле<code>backup_keenetic.ps1</code>укажите свои параметры:</p>
<ul>
<li>
<p><strong>$RouterIp</strong>= IP-адрес вашего Keenetic (например<code>192.168.1.1</code>)</p>
</li>
<li>
<p><strong>$Login</strong>= имя созданного пользователя (<code>backup</code>)</p>
</li>
<li>
<p><strong>$BackupDir</strong>= папка для сохранения бэкапов (например<code>D:\Backups\Keenetic</code>)</p>
</li>
</ul>
<p>Пароль передаётся при запуске, его менять в скрипте не нужно.</p>
<h3>4. Запуск вручную для проверки</h3>
<div>
<div>
<div>
<div>
<div>powershell</div>
</div>
</div>
</div>
<pre>powershell.exe -ExecutionPolicy Bypass -File "C:\путь\к\backup_keenetic.ps1" -Password "ваша_base64_строка"</pre>
</div>
<h3>5. Настройка автоматического запуска</h3>
<p>В Планировщике Windows создайте задачу:</p>
<ul>
<li>
<p><strong>Триггер</strong>: ежедневно в 3:00 ночи</p>
</li>
<li>
<p><strong>Действие</strong>: запуск программы<code>powershell.exe</code></p>
</li>
<li>
<p><strong>Аргументы</strong>:</p>
</li>
</ul>
<div>
<div>
<div>
<div>
<div>text</div>
</div>
</div>
</div>
<pre>-WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\путь\к\backup_keenetic.ps1" -Password "ваша_base64_строка"</pre>
</div>
<p>Готово. Скрипт будет сам скачивать конфигурацию, создавать ZIP с правильной меткой (daily/weekly/monthly/yearly) и удалять старые копии.</p>
