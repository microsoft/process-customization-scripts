################################################################################################################
# ExportProjectTemplatesFromCSV.ps1
# This script exports the process template for a list of projects based on a csv file that contains a Project and Template column
#
# This script is dependent on having .\ExportVSOProjectTemplate.ps1 is the same directory
#
# You can then zip this exported template and upload to your custimization
# enabled VSO account. 
#
# Usage: .\ExportProjectTemplatesFromCSV.ps1 "https://1eson-test1.visualstudio.com/DefaultCollection" "C:\Users\dahellem\Desktop\Temp\vsoprojectlist.csv"
#
#
################################################################################################################

param
(
    [Parameter(Mandatory=$true,HelpMessage="CollectionURL is required. Usage Example: .\ExportProjectTemplatesFromCSV.ps1 http://myServer:8080/tfs/DefaultCollection")] [string] $CollectionURL,
    [Parameter(Mandatory=$true,HelpMessage="Export file path is required. Usage Example: c:\temp\vsoprojectlist.csv")] [string] $filePath,
    [Parameter(Mandatory=$true,HelpMessage="Folder where process templates exist. Usage Example: C:\myprocesstemplatesroot")] [string] $processfolder
)

$x = 0;
$projectList = IMPORT-CSV $filePath
$projectCount = $projectList.Count;

Write-Host "Conforming $projectCount projects"

FOREACH ($project in $projectList) 
{ 
    $x += + 1;
    $projectName = $project.Project;
   
    Write-Host "-----------------------------------------------------------------------------------------------" -ForegroundColor White;
    Write-Host "    $projectName ($x) " -ForegroundColor White;
    Write-Host "-----------------------------------------------------------------------------------------------" -ForegroundColor White;
   
    Invoke-Expression "& `".\ConformProject.ps1`" `"$CollectionURL`" `"$projectName`" `"$processfolder\$projectName`""
    
    Write-Host ""
    Write-Host ""
}