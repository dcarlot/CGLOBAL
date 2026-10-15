rem Creating tasks if does not exist, because SCHTASKS will not delete files associated with the task,
rem if the tasks itself is not present and files are somehow left behind

SCHTASKS /CREATE /SC DAILY /TN "McAfee\MGS\Update" /TR "McAfee" /ST 00:00 /F
SCHTASKS /CREATE /SC DAILY /TN "McAfee\MGS\Update Maintenance" /TR "McAfee" /ST 00:00 /F

rem Now that the task is created, we can delete the tasks and files by using SCHTASKS command 

SCHTASKS /DELETE /TN "McAfee\MGS\Update" /F
SCHTASKS /DELETE /TN "McAfee\MGS\Update Maintenance" /F
SCHTASKS /DELETE /TN "McAfee\MGS" /F


