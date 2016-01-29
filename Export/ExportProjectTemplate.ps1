################################################################################################################
# ExportProjectTemplate.ps1
# Version: 1.0
#
# This script exports the process template for a individual project
# You can then zip this exported template and upload to your custimization
# enabled VSTS account. 
#
# Usage: .\ExportProjectTemplate.ps1 http://myServer:8080/tfs/DefaultCollection myProject
#        This will export the process template for myProject in the given collection. The
#        exported template will be in a folder next to this script with the name ExportedTemplate_myProject
#
#
# Usage:  .\ExportProjectTemplate.ps1 http://myServer:8080/tfs/DefaultCollection myProject -Force
#         This will export the template even if you already have an existing folder with the
#         name ExportedTemplate_myProject. It will delete the current folder.
#
################################################################################################################
param( 
    [Parameter(Mandatory=$true,HelpMessage="CollectionURL is required. Usage Example: .\ExportProjectTemplate.ps1 http://myServer:8080/tfs/DefaultCollection myProject")] [string] $CollectionURL,
    [Parameter(Mandatory=$true,HelpMessage="ProjectName is required. Usage Example: .\ExportProjectTemplate.ps1 http://myServer:8080/tfs/DefaultCollection myProject")] [string] $ProjectName,
    [Parameter(Mandatory=$false, HelpMessage="Overwrite existing template if found")] [switch] $Force = $false
    )
 
$ErrorActionPreference = "Stop" 
$scriptFolder = Split-Path -Path $MyInvocation.MyCommand.Path

#Invoking expression and checking if any errors are thrown
function invokeExpression($expression){
  $error = (Invoke-Expression $expression) 
  if ($lastexitcode) {throw $error}
}

function RemoveDisallowedCharacters($initialString) {
    $disallowedCharacters = (' ', '.', ',', ';', '''', '`', '"', ':', '/', '\', '*', '|', '?',  '&', '%', '$', '!', '+', '=', '(', ')', '[', ']', '{', '}', '<', '>', '-')
    $output=$initialString
    $disallowedCharacters | ForEach-Object {
        $output = $output.Replace("$_","")
    }
    return $output
}

function ClearGlobalLists($fieldRefName) {
    # Clear global list from FoundIn field
    $fieldsElem = $witdXml | Select-Xml -Namespace $Namespace -XPath "/witd:WITD/WORKITEMTYPE/FIELDS"
    $buildFieldElem = $fieldsElem | Select-Xml -Namespace $Namespace -XPath "/witd:WITD/WORKITEMTYPE/FIELDS/FIELD[@refname='$fieldRefName']"
    if ($buildFieldElem -ne $null) {
        $buildFieldElem.Node.SUGGESTEDVALUES | % {
            $buildFieldElem.Node.RemoveChild($_) | Out-Null
        }
        
        $elem = $witdXml.CreateElement("SUGGESTEDVALUES")
        $elem.SetAttribute("expanditems", "true")
        $itemElem = $witdXml.CreateElement("LISTITEM")
        $itemElem.SetAttribute("value", "&lt;None&gt;")
        $elem.AppendChild($itemElem) | Out-Null
        $buildFieldElem.Node.AppendChild($elem) | Out-Null
        $fieldsElem.Node.AppendChild($buildFieldElem.Node) | Out-Null
    }
}

# Directory that contains an "empty" template.  This will be used to copy certain files that are needed to create a template
$EmptyTemplateDirectory = (Resolve-Path Default_EmptyTemplate)
if(-not (Test-Path $EmptyTemplateDirectory)) {
  throw "The default template could not be found at $EmptyTemplateDirectory."
  return
}

$OutputDirectory = Join-Path $scriptFolder "ExportedTemplates\$ProjectName"
if(Test-Path $OutputDirectory) {

  if($Force) {
    Remove-Item $OutputDirectory -Recurse -Force
  }
  else {
    throw "The directory $OutputDirectory exists already. Please delete before running."
    exit
  }
}

#if your vs directory is someplace else other than the standard location, you will need to set it here
$VSDirectories = @()
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

Write-Host "Exporting $ProjectName..." -ForegroundColor Yellow

Try {
	Write-Host "STEP 1: Copy the default process template files" -ForegroundColor Yellow
	Copy-Item $EmptyTemplateDirectory -Destination $OutputDirectory -Recurse

	Write-Host "STEP 2: Set Name and Description for process template" -ForegroundColor Yellow
	$processTemplateXml = "$OutputDirectory\ProcessTemplate.xml"
	$xml = [xml](Get-Content $processTemplateXml)
	$xml | Select-Xml "ProcessTemplate/metadata/name" | % { $_.Node.set_InnerText($ProjectName) }
	$xml | Select-Xml "ProcessTemplate/metadata/version/@type" | % { $_.Node.set_InnerText([System.Guid]::NewGuid().toString()) }
	$xml.Save($processTemplateXml)

	Write-Host "STEP 3: Export Process Configuration & Categories" -ForegroundColor Yellow
	$witDirectory = "$OutputDirectory\WorkItem Tracking"
	mkdir "$witDirectory\Process" | Out-Null

	invokeExpression "& $WitAdminExe exportcategories /collection:$CollectionURL /p:`"$ProjectName`" /f:`"$witDirectory\Categories.xml`""
	invokeExpression "& $WitAdminExe exportprocessconfig /collection:$CollectionURL /p:`"$ProjectName`" /f:`"$witDirectory\Process\ProcessConfiguration.xml`""
	
	Write-Host "STEP 4: Export Global lists and workflow" -ForegroundColor Yello
	
	$globalListFile = "$witDirectory\GlobalList.xml"
	invokeExpression "& $WitAdminExe exportgloballist /collection:$CollectionURL /f:`"$globalListFile`""
	$glNamespace = @{gl="http://schemas.microsoft.com/VisualStudio/2005/workitemtracking/globallists"}
	$xml = [xml](Get-Content $globalListFile)
	$gls = $xml | Select-Xml "/gl:GLOBALLISTS/GLOBALLIST" -Namespace $glNamespace
	if ($gls) {
		Write-Host "WARNING: Global lists are not supported on Visual Studio Online.  Please convert these into AllowedValues lists per work item type. For more information contact vsocustpt@microsoft.com" -ForegroundColor Red
	}

	$globalWorkflowFile = "$witDirectory\GlobalWorkflow.xml"
	invokeExpression "& $WitAdminExe exportglobalworkflow /collection:$CollectionURL /f:`"$globalWorkflowFile`""
	$xml = [xml](Get-Content $globalWorkflowFile)
	$gwf = $xml | Select-Xml "/GLOBALWORKFLOW/FIELDS"
	if ($gwf) {
		Write-Host "WARNING: Global Workflow is not supported on Visual Studio Online.  Please copy these fields into each work item type. For more information contact vsocustpt@microsoft.com" -ForegroundColor Red
	}

	# Set reference to WorkItem Tracking\workitems.xml
	$workItemsXml = "$witDirectory\WorkItems.xml"
	$xml = [xml](Get-Content $workItemsXml)

	Write-Host "STEP 5: Export LinkTypes" -ForegroundColor Yellow
	mkdir "$witDirectory\LinkTypes" | Out-Null
	Invoke-Expression "& $WitAdminExe listLinkTypes /collection:$CollectionURL" | % {
	  if ($_ -like "Reference Name:*")
	  {
		$linkTypeName = $_.Split(":")[1].Trim()
		if(!$linkTypeName.StartsWith("System."))
		{	
			$linkType = RemoveDisallowedCharacters $linkTypeName
			$linkTypeFileName = "$witDirectory\LinkTypes\$linkType.xml"
			invokeexpression "& $WitAdminExe exportlinktype /collection:$CollectionURL /n:`"$linkTypeName`" /f:`"$linkTypeFileName`""

			$fileNameAttribute = $xml.CreateAttribute("fileName")
			$fileNameAttribute.Value = "WorkItem Tracking\LinkTypes\$linkType.xml"
			$linkTypeXmlElement = $xml.CreateElement("LINKTYPE")
			$linkTypeXmlElement.Attributes.Append($fileNameAttribute)

			$linkTypesXmlElement = $xml.tasks.task | ? { $_.id -eq "LinkTypes"} | Select-Xml "taskXml/LINKTYPES"
			$linkTypesXmlElement.Node.AppendChild($linkTypeXmlElement)
		}
	  }
	}

	Write-Host "STEP 6: Export WITDs" -ForegroundColor Yellow
	mkdir "$witDirectory\TypeDefinitions" | Out-Null

	$Namespace = @{witd="http://schemas.microsoft.com/VisualStudio/2008/workitemtracking/typedef"}

	Invoke-Expression "& $WitAdminExe listwitd /collection:$CollectionURL /p:`"$ProjectName`"" | % {
		$WITD = RemoveDisallowedCharacters $_
		$witdFileName = "$witDirectory\TypeDefinitions\$WITD.xml"
 
		invokeExpression "& $WitAdminExe exportwitd /collection:$CollectionURL /p:`"$ProjectName`" /n:`"$_`" /f:`"$witdFileName`""

		# generate a refname in the WITD file if it doesn't exist   
		$witdXml = [xml](Get-Content $witdFileName)
		$workItemTypeNode = $witdXml | Select-Xml -Namespace $Namespace -XPath "/witd:WITD/WORKITEMTYPE"
		if (!$workItemTypeNode.Node.HasAttribute("refname"))
		{
			$projectNoSpaces = $ProjectName -replace " ", ""
      $workItemTypeNode.Node.SetAttribute("refname", "$projectNoSpaces.$WITD")
		}

    ClearGlobalLists "Microsoft.VSTS.Build.FoundIn"
    ClearGlobalLists "Microsoft.VSTS.Build.IntegrationBuild"

    $witdXml.Save($witdFileName)

		# add WITD to WorkItems.XML
		$fileNameAttribute = $xml.CreateAttribute("fileName")
		$fileNameAttribute.Value = "WorkItem Tracking\TypeDefinitions\$WITD.xml"
		$workitemtypeXmlElement = $xml.CreateElement("WORKITEMTYPE")
		$workitemtypeXmlElement.Attributes.Append($fileNameAttribute)
		$workitemtypesXmlElement = $xml.tasks.task | ? { $_.id -eq "WITs"} | Select-Xml "taskXml/WORKITEMTYPES"
		$workitemtypesXmlElement.Node.AppendChild($workitemtypeXmlElement)
	}

	$xml.Save($workItemsXml)

	Write-Host "Exported $ProjectName!" -ForegroundColor Green
}
Catch {
	Remove-Item $OutputDirectory -Recurse -Force
	Write-Host "Project export failed" -ForegroundColor Red
}