################################################################################################################
# ConformProject.ps1
# 1. Ensures the template passes validation
# 2. Does validation to make sure you do not add or remove any new work item types
# 3. Conforms the project to be identical to the template
#
# * $WitAdminExe is the path for the TFS specific witadmin.exe. 
# * validation assumes that the WIT.xml files match the names from witadmin.exe listwitd command with spaces removed
#   Example. User Story = UserStory.xml 
#
#
# Usage: .\ConformProject.ps1 "https://tfs/DefaultCollection" "Dan Sample One" "C:\Import\Agile" -ValidateOnly
#        
################################################################################################################

param
(
    [Parameter(Mandatory=$true,HelpMessage="CollectionURL is required. Usage Example: .\ExportProjectTemplatesFromCSV.ps1 https://myServer:8080/tfs/DefaultCollection")] [string] $CollectionURL,
    [Parameter(Mandatory=$true,HelpMessage="Project name is required. Usage Example: .\ExportProjectTemplate.ps1 http://myServer:8080/tfs/DefaultCollection myProject")] [string] $ProjectName,
    [Parameter(Mandatory=$true,HelpMessage="Template path is required")] [string] $global:templatePath,
    [Parameter(Mandatory=$false, HelpMessage="Set to false if you only want to see what changes will be made")] [switch] $ValidateOnly = $false
)

$scriptFolder = Split-Path -Path $MyInvocation.MyCommand.Path

$VSDirectories = @()
$VSDirectories += "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer"
$VSDirectories += "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer"
$VSDirectories += "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Enterprise\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer"
$VSDirectories += "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\TeamExplorer\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer"
$VSDirectories += "${env:ProgramFiles(x86)}\Microsoft Visual Studio 14.0\Common7\IDE"
$VSDirectories += "${env:ProgramFiles(x86)}\Microsoft Visual Studio 12.0\Common7\IDE"
$VSDirectories += "${env:ProgramFiles(x86)}\Microsoft Visual Studio 11.0\Common7\IDE"
$VSDirectories += "${env:ProgramFiles(x86)}\Microsoft Visual Studio 10.0\Common7\IDE"

$WitAdminExe = "witadmin.exe"

if(-not (Get-Command $WitAdminExe -ErrorAction SilentlyContinue)) {
  Write-Host -Verbose "Unable to find witadmin.exe on your path. Attempting VS install directories"
  foreach($vsDir in $VSDirectories) {
    $WitAdminExe = Join-Path $vsDir "witadmin.exe"
    Write-Host -Verbose "Testing for $WitAdminExe"
    if(Test-Path $WitAdminExe) {
      break
    }
  }
}

if(-not (Test-Path $WitAdminExe)) {
  throw "Unable to find the witadmin.exe in your path or in any VS install."
}

# Format witadmin exe with quotes for the invoke-expression to like
$WitAdminExe = "'$WitAdminExe'"

function ValidateTemplate() {
	##TODO: Call the validator on the template and if there are no errors, Move forward...

	$IsError = 0;

	#check to make sure all the expected folders and files are in place
	if (! (Test-Path -path $global:templatePath))
	{            
		Write-Host "Error - Process template directory '$global:templatePath' does not exists" -ForegroundColor Red       
		$IsError = 1;
	}
	else
	{
		if (! (Test-Path "$global:templatePath\WorkItem Tracking\LinkTypes"))
		{
			Write-Host "Error - '$global:templatePath\WorkItem Tracking\LinkTypes' does not exists" -ForegroundColor Red       
			$IsError = 1;
		}
    
		if(! (Test-Path -path "$global:templatePath\WorkItem Tracking\TypeDefinitions"))
		{
			Write-Host "Error - '$global:templatePath\WorkItem Tracking\TypeDefinitions' does not exists" -ForegroundColor Red       
			$IsError = 1;
		}

		if (! (Test-Path "$global:templatePath\WorkItem Tracking\Categories.xml"))
		{
			Write-Host "Error - '$global:templatePath\WorkItem Tracking\Categories.xml' does not exists" -ForegroundColor Red       
			$IsError = 1;
		}

		if (! (Test-Path "$global:templatePath\WorkItem Tracking\Process\ProcessConfiguration.xml"))
		{
			Write-Host "Error - '$global:templatePath\WorkItem Tracking\Process\ProcessConfiguration.xml' does not exists" -ForegroundColor Red       
			$IsError = 1;
		}   

	}

	If ($IsError -eq 1)
	{
		Write-Host ""
		Write-Host "Errors during preperation checks. Please fix and try again."

		Exit
	}
	else
	{
		Write-Host "Operation Complete"           
	} 
}

function ValidateWorkItems()
{
	$ErrorFound = $false
	$workItemTypesInProject = @()
	   
    Invoke-Expression "& $WitAdminExe listwitd /collection:$CollectionURL /p:`"$projectName`"" | % {
		$workItemTypesInProject += "$_.xml".replace(' ', '')
	}    

	$workItemTypesInTemplate = Get-ChildItem -Path "$global:templatePath\WorkItem Tracking\TypeDefinitions" –File -Filter *.xml

	#Ensure each type in the template exists in the project
	FOREACH ($templateWIT in $workItemTypesInTemplate) {        
        if ($workItemTypesInProject -notcontains $templateWIT) {
			Write-Host "Work Item Type $templateWIT missing from the project, it will be added in Step 5" -ForegroundColor Red
		}
	}

	#Ensure there are no additional types in the projet 
	FOREACH ($projectWIT in $workItemTypesInProject) {
		if ($workItemTypesInTemplate -Contains $projectWIT) {
			Write-Host "Work Item Type $projectWIT should not exist in the project, it needs to be removed" -ForegroundColor Red  
			$ErrorFound = $true
		}
	}

	#Exit the script if any errors are found
	If ($ErrorFound)
	{
		Write-Host "The above errors must be fixed before conforming." -ForegroundColor Red
		Exit             
	}
}

Write-Host "Step 1: Preparing Conform" -ForegroundColor Yellow
ValidateTemplate 
Write-Host "Step 1: Complete" -ForegroundColor Green

Write-Host "Step 2: Validating Work Items" -ForegroundColor Yellow 
ValidateWorkItems
Write-Host "Step 2: Complete" -ForegroundColor Green

# If the user passes the flag to validate, don't continue with the conform steps
if ($ValidateOnly) {	
    Write-Host "Validation Only Complete" -ForegroundColor Green
    Exit
}

Write-Host "Step 3: Conform project - Link Types" -ForegroundColor Yellow

Get-ChildItem "$global:templatePath\WorkItem Tracking\LinkTypes" -Filter "*.xml" | % {   	   
    Write-Host "Importing Link Type: "$_.Name -ForegroundColor Yellow
    $lt = $_.FullName #full path not being found if adding $_.FullName to witadminexe expression	    
       
    Invoke-Expression "& $WitAdminExe importlinktype /collection:$CollectionUrl /f:`"$lt`""
}

Write-Host "Step 3: Complete" -ForegroundColor Green

        
Write-Host "Step 4: Conform project - Type Definitions" -ForegroundColor Yellow

Get-ChildItem "$global:templatePath\WorkItem Tracking\TypeDefinitions" -Filter "*.xml" | % {   
	Write-Host "Importing Work Item Type: "$_.Name -ForegroundColor Yellow
	$wit = $_.FullName #full path not being found if adding $_.FullName to witadminexe expression
	
    Invoke-Expression "& $WitAdminExe importwitd /collection:$CollectionUrl /p:`"$projectName`" /f:`"$wit`""
}
Write-Host "Step 4: Complete" -ForegroundColor Green

Write-Host "Step 5: Conform project - Categories" -ForegroundColor Yellow
Invoke-Expression "& $WitAdminExe importcategories /collection:$CollectionUrl /p:`"$projectName`" /f:`"$global:templatePath\WorkItem Tracking\Categories.xml`""
Write-Host "Step 5: Complete" -ForegroundColor Green

Write-Host "Step 6: Conform project - Process Configuration" -ForegroundColor Yellow
Invoke-Expression "& $WitAdminExe importprocessconfig /collection:$CollectionUrl /p:`"$projectName`" /f:`"$global:templatePath\WorkItem Tracking\Process\ProcessConfiguration.xml`""
Write-Host "Step 6: Complete" -ForegroundColor Green

Write-Host "Project '$projectName' conforms to the template" -ForegroundColor Green
