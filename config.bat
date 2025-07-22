@echo off
setlocal enabledelayedexpansion

:: Set working directory
set "WORKDIR=%cd%"
set "NGINX_DIR=%WORKDIR%\nginx\nginx-1.24.0"

echo [*] Opening firewall ports 8443, 80, 443...
netsh advfirewall firewall add rule name="Amazon DCV" dir=in action=allow protocol=TCP localport=8443
netsh advfirewall firewall add rule name="NGINX HTTP" dir=in action=allow protocol=TCP localport=80
netsh advfirewall firewall add rule name="Nginx HTTPS" dir=in action=allow protocol=TCP localport=443
echo Ok.

:: Download NICE DCV Server MSI
echo [*] Downloading NICE DCV...
curl -L -o "%WORKDIR%\nice-dcv-server.msi" "https://d1uj6qtbmh3dt5.cloudfront.net/2024.0/Servers/nice-dcv-server-x64-Release-2024.0-19030.msi"

:: Start Windows Installer service
echo [*] Starting Windows Installer service...
net start msiserver >nul 2>&1

:: Install NICE DCV silently
echo [*] Installing NICE DCV silently...
msiexec /i "%WORKDIR%\nice-dcv-server.msi" /quiet /norestart /l*v "%WORKDIR%\dcv_install.log"

:: Verify DCV installation
echo [*] Verifying NICE DCV service...
timeout /t 10 >nul
sc query dcvserver

:: Create DCV session
echo [*] Creating DCV session...
cd /d "C:\Program Files\NICE\DCV\server\bin"
dcv.exe close-session console 2>nul
dcv.exe close-session my-session 2>nul
dcv.exe create-session my-session --owner %USERNAME%
if errorlevel 1 (
  echo Failed to create DCV session!
  pause
  exit /b 1
)

:: Download NGINX
echo [*] Downloading NGINX...
curl -L -o "%WORKDIR%\nginx.zip" "https://nginx.org/download/nginx-1.24.0.zip"

:: Unzip NGINX
echo [*] Extracting NGINX...
powershell -Command "Expand-Archive -Path '%WORKDIR%\nginx.zip' -DestinationPath '%WORKDIR%\nginx' -Force"

:: Download OpenSSL Light
echo [*] Downloading OpenSSL Light...
curl -L -o "%WORKDIR%\Win64OpenSSL_Light.exe" "https://slproweb.com/download/Win64OpenSSL_Light-3_5_1.exe"

:: Install OpenSSL Light silently
echo [*] Installing OpenSSL Light silently...
start /wait "" "%WORKDIR%\Win64OpenSSL_Light.exe" /silent

:: Set OpenSSL paths
set "OPENSSL_CONF=C:\Program Files\Common Files\SSL\openssl.cnf"
set "PATH=%PATH%;C:\Program Files\OpenSSL-Win64\bin"

:: Generate SSL certificate
echo [*] Generating self-signed SSL certificate...
if not exist "%NGINX_DIR%\certs" mkdir "%NGINX_DIR%\certs"

:: FIX: Removed space after caret for proper line continuation
openssl req -x509 -nodes -days 365 -newkey rsa:2048^
 -keyout "%NGINX_DIR%\certs\dcv.key"^
 -out "%NGINX_DIR%\certs\dcv.crt"^
 -subj "/CN=localhost"^
 -config "C:\Program Files\Common Files\SSL\openssl.cnf" 2>nul

:: Write nginx.conf
echo [*] Writing nginx.conf...
(
echo worker_processes 1;
echo;
echo events {
echo     worker_connections 1024;
echo }
echo;
echo http {
echo     include       mime.types;
echo     default_type  application/octet-stream;
echo;
echo     sendfile        on;
echo     keepalive_timeout  65;
echo;
echo     server {
echo         listen 443 ssl;
echo         server_name localhost;
echo;
echo         ssl_certificate     ../certs/dcv.crt;
echo         ssl_certificate_key ../certs/dcv.key;
echo;
echo         ssl_protocols TLSv1.2 TLSv1.3;
echo         ssl_ciphers HIGH:!aNULL:!MD5;
echo;
echo         location / {
echo             proxy_pass https://localhost:8443;
echo             proxy_http_version 1.1;
echo             proxy_ssl_verify off;
echo             proxy_set_header Upgrade $http_upgrade;
echo             proxy_set_header Connection "upgrade";
echo             proxy_set_header Host $host;
echo             proxy_set_header X-Real-IP $remote_addr;
echo             proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
echo             proxy_hide_header X-Frame-Options;
echo             add_header X-Frame-Options "ALLOWALL";
echo             add_header Content-Security-Policy "frame-ancestors *;";
echo         }
echo     }
echo }
) > "%NGINX_DIR%\conf\nginx.conf"

:: Restart NGINX
echo [*] Restarting NGINX...
taskkill /F /IM nginx.exe >nul 2>nul
cd /d "%NGINX_DIR%"
start nginx.exe

echo [✓] Setup completed successfully.
