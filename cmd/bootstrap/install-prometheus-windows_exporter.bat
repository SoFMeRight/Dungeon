@echo off

:: Syntax is as follows:
:: install-prometheus-windows_exporter.bat [DESTINATION_PATH] [PROMETHEUS_VERSION]
:: This script requires in tacticalrmm an environmental variable of "password={{global.Windows_Admin_Pass}}" to be set and the value entered in tacticalrmm settings in a global variable.

:: Check if a path is provided as an argument, otherwise use the default.
if "%1" == "" (
    set DESTINATION_PATH=C:\_Ant_Parade\Monitoring-Agents\prometheus-windows_exporter
) else (
    set DESTINATION_PATH=%1
)

:: Check if Prometheus version is provided as an argument, otherwise use the default.
if "%2" == "" (
    set PROMETHEUS_VERSION=0.30.5
) else (
    set PROMETHEUS_VERSION=%2
)

set DOWNLOAD_URL=https://github.com/prometheus-community/windows_exporter/releases/download/v%PROMETHEUS_VERSION%/windows_exporter-%PROMETHEUS_VERSION%-amd64.exe

:: Create the destination path if it doesn't exist
powershell -Command "New-Item -Path '%DESTINATION_PATH%' -ItemType Directory -Force"

:: Download Windows Exporter executable to C:\_Staging\_Toolchest directory
powershell -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%DESTINATION_PATH%\prometheus-windows_exporter.exe'"

echo Done! Prometheus Windows Exporter version %PROMETHEUS_VERSION% has been downloaded and saved in the %DESTINATION_PATH% directory.

:: Add a task to Task Scheduler
set DOWNLOAD_URL_TASK_SCHEDULER=https://git.optcp.com/precisionplanit/ant_parade-public/-/raw/main/fs/_windows/_Ant_Parade/Monitoring-Agents/prometheus-windows_exporter/prometheus-windows_exporter.xml?inline=false
powershell -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL_TASK_SCHEDULER%' -OutFile '%DESTINATION_PATH%\prometheus-windows_exporter.xml'"
powershell -Command "Register-ScheduledTask -xml (Get-Content '%DESTINATION_PATH%\prometheus-windows_exporter.xml' | Out-String) -TaskName 'prometheus-windows_exporter' -TaskPath '\SoFMeRight' -User kaiha -Password %password%"
powershell -Command "Start-ScheduledTask -TaskName \SoFMeRight\prometheus-windows_exporter"
