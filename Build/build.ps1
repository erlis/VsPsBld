framework "4.0x86"
$psake.use_exit_on_error = $true
$ErrorActionPreference = "Stop"

. .\settings.ps1

$global:file_to_build         = ""; 
$global:build_type            = ""; 
$global:project_folder        = ""; 
$global:web_project           = ""; 
$global:final_app_config_name = ""; 
$global:msbuild_output        = ""; 
$global:nuspec                = ""; 
$global:nuget_repository      = ""; 
$global:db_deploy_to          = @();
$global:exclude_config        = @();  

task default -depends execute
task execute { 
    execute
} 


function execute() {
    version-assemblies

    $build_info | % {
        assign-globals( $_ );
        build; 
        create-build-output;
    } 
}


function assign-globals ($h) {
    $global:file_to_build         = ""; 
    $global:build_type            = ""; 
    $global:project_folder        = ""; 
    $global:web_project           = ""; 
    $global:final_app_config_name = ""; 
    $global:msbuild_output        = ""; 
    $global:nuspec                = ""; 
    $global:nuget_repository      = ""; 
    $global:db_deploy_to          = @();
    $global:exclude_config        = @(); 

    $global:build_type            = $h["build_type"]; 
    $global:final_app_config_name = $h["final_app_config_name"]; 
    $global:project_folder        = $ExecutionContext.InvokeCommand.ExpandString($h["project_folder"]);
    $global:web_project           = $ExecutionContext.InvokeCommand.ExpandString($h["web_project"]);
    $global:file_to_build         = $ExecutionContext.InvokeCommand.ExpandString($h["file_to_build"]);
    $global:msbuild_output        = $ExecutionContext.InvokeCommand.ExpandString($h["msbuild_output"]);
    $global:nuspec                = $ExecutionContext.InvokeCommand.ExpandString($h["nuspec"]);
    $global:nuget_repository      = $h["nuget_repository"]; 
    $global:db_deploy_to          = $h["db_deploy_to"]; 
    $global:exclude_config        = $h["exclude_config"]; 
}


function build() {
    if (_isAppBuild)   { build-app  }
    if (_isWebBuild)   { build-web  } 
    if (_isDbBuild)    { build-db   } 
    if (_isNugetBuild) { build-nuget}
}


function create-build-output() {
    if ((_isAppBuild) -or (_isWebBuild)) { create-app-build-output }
    if (_isNugetBuild) { create-nuget-build-output }
    if (_isDbBuild) {
        $environments | % { 
            create-db-build-output($_)
        }
    }
}


function build-app() {
    trace "Entering build-app..."; 
    exec { msbuild $file_to_build '/t:Build' "/p:Configuration=$configuration" }
}    


function build-web() {
    trace "Entering build-web..."; 
    
    # first build the solution 
    build-app; 

    trace "publishing the web application...";
    # then publish the web project 
    exec { msbuild build-web.xml "/p:Configuration=$configuration;BasePath=$base_folder;ProjectFile=$web_project" }  
}


function build-db() {
    trace "Entering build-db..."; 

    db-build-separator
    $environments | foreach {
        build-db-for($_)
    }
}


function build-nuget() {
    trace "Entering build-nuget..."; 
    
    build-app; 
    create-nuget-package; 
    publish-nuget-package; 
}


function create-nuget-package() {
    trace "Creating nuget package..."; 

    $version = get-version 
    $version3 = $version -replace "\.\d+$", ""
    # debug: if no version then force a value  
    if ($version3 -eq "") { $version3 = "1.0.0" } 

    exec { & "tools\NuGet.exe" pack $nuspec -version $version3 -OutputDirectory $msbuild_output }
}


function publish-nuget-package() {
    trace "Publishing nuget packages..."; 

    # locating all *.nupkg files. Name is unknown due to version. 
    get-childitem $msbuild_output -filter *.nupkg | %{
        $file = $_.FullName;
        exec { & 'tools\NuGet.exe' push $file -source $nuget_repository }
    }
}


function create-nuget-build-output() {
    trace "creating build output";
    
    $folder="$build_output"; 
    _createFolder $folder;
    Copy-Item "$msbuild_output\*" $folder -Recurse -Force
}


function create-output-config-transform($env_name) {
    $excludingConfig = $exclude_config -contains $env_name; 

    # veryfing if the environment is valid
    if ( !($excludingConfig) -and (! (test-path "$project_folder\$build_type.$env_name.config")) ){
        throw "Unable to create environment `"$env_name`". Environment transformation [$build_type.$env_name.config] was not found in [$project_folder]"
    }

    $ctt_output="Web.config";
    if (_isAppBuild) {$ctt_output=$final_app_config_name;} 

    # applying the transformation
    if (!($excludingConfig)) {
       exec { & 'tools\ctt.exe' "source:`"$project_folder\$build_type.config`"" "transform:`"$project_folder\$build_type.$env_name.config`"" "destination:`"$msbuild_output\$ctt_output`"" }
    }

    # copying the build to the environment
    $excludeStr = ""; 
    if ($excludingConfig) { $excludeStr = '*.config' } 
    _createFolder "$build_output\$env_name\$build_type"
    Copy-Item "$msbuild_output\*" "$build_output\$env_name\$build_type" -Recurse -Force -Exclude $excludeStr;
}


function get-version() {
    if( (Test-Path env:\BUILD_MAJOR  ) -and 
        (Test-Path env:\BUILD_MINOR  ) -and
        (Test-Path env:\BUILD_NUMBER ) -and
        (Test-Path env:\TFS_CHANGESET) ) {
        return "$env:BUILD_MAJOR.$env:BUILD_MINOR.$env:BUILD_NUMBER.$env:TFS_CHANGESET"
    }
    return "" 
}


function version-assemblies() {
    trace "Entering version-assemblies...";
    $version = get-version 
    if (IsNullOrEmpty $version) { return }

    # contains only major, minor i.e: 4.5.0.0    
    $version2 = $version -replace "\.\d+\.\d+$", ".0.0"
    
    #set the line pattern for matching
    $assemblyVersionPattern = '^\s*\[\s*assembly:\s*AssemblyVersion'
    $assemblyFileVersionPattern = '^\s*\[\s*assembly:\s*AssemblyFileVersion'
    $assemblyFileVersionModified = $false
    $assemblyInformationalVersionPattern = '^\s*\[\s*assembly:\s*AssemblyInformationalVersion'
    $assemblyInformationalVersionModified = $false
    
    
    #get all assemlby info files
    $assemblyInfos = gci -path $base_folder -include AssemblyInfo.cs -Recurse

    #foreach one, read it, find the line, replace the value and write out to temp
    $assemblyInfos | foreach-object -process {
        $file = $_
        write-host -ForegroundColor Green "- Updating build number in $file"
        if(test-path "$file.tmp" -PathType Leaf) { remove-item "$file.tmp" }
        
        get-content $file | foreach-object -process {
            $line = $_
            if ( $line -match $assemblyFileVersionPattern) {
                $line = $line -replace '"\d+\.\d+\.\d+\.\d+"', "`"$version`""
                $assemblyFileVersionModified = $true 
            }
            
            if ( $line -match $assemblyInformationalVersionPattern) {
                $line = $line -replace '"\d+\.\d+\.\d+\.\d+"', "`"$version`""
                $assemblyInformationalVersionModified = $true 
            }
            
            if ( $line -match $assemblyVersionPattern ) {
                $line = $line -replace '"\d+\.\d+\.\d+\.\d+"', "`"$version2`""
            }


            $line | add-content "$file.tmp"
        }
        
        if (! $assemblyFileVersionModified )          { "[assembly: AssemblyFileVersion(`"$version`")]" | add-content "$file.tmp" }
        if (! $assemblyInformationalVersionModified ) { "[assembly: AssemblyInformationalVersion(`"$version`")]" | add-content "$file.tmp" }
        
        #replace the old file with the new one
        remove-item $file -Force
        rename-item "$file.tmp" $file -Force -Confirm:$false
   }
}


function build-db-for($env_name) {
    write-host "" 
    write-host "Creating [$env_name] script..."
    write-host ":::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"
    $version = get-version 
    $modify_db = $db_deploy_to -contains $env_name 

    exec { 
        msbuild $file_to_build '/t:Build;Publish' "/p:Configuration=$configuration" '/p:Platform=AnyCPU' "/p:UpdateDatabase=${modify_db}" "/p:SqlPublishProfilePath=$env_name.publish.xml" "/p:PublishScriptFileName=script_${version}_${env_name}.sql"
    }
}


function create-app-build-output() {
    trace "Entering create-app-build-output..."; 

    # creating Dev configuration
    $folder="$build_output\Dev\$build_type"; 
    _createFolder $folder;
    Copy-Item "$msbuild_output\*" $folder -Recurse -Force
    
    # create other environments
    $environments | %{
        create-output-config-transform($_); 
    } 
}


function create-db-build-output($env_name) {
    $target_folder = "$build_output\$env_name\SQL"; 
    _createFolder $target_folder
    Copy-Item "$msbuild_output\*$env_name*.sql" $target_folder -Recurse -Force

    if (_isEmpty($target_folder)) {
        throw "Could not find DB build output for environment [$env_name]!"; 
    }
}


function _createFolder($folder) {
    if(! (test-path $folder -PathType container)) {
        mkdir $folder  
    }
}

function _isEmpty($folder) {
    $directoryInfo = Get-ChildItem $folder | Measure-Object
    $directoryInfo.count -eq 0
}


function IsNullOrEmpty($str) {
    if ($str) {
        $false 
    } else {
        $true 
    }
}


function db-build-separator() {
    write-host "________ ________     ________         _____ _______________"
    write-host "___  __ \___  __ )    ___  __ )____  _____(_)___  /______  /"
    write-host "__  / / /__  __  |    __  __  |_  / / /__  / __  / _  __  / "
    write-host "_  /_/ / _  /_/ /     _  /_/ / / /_/ / _  /  _  /  / /_/ /  "
    write-host "/_____/  /_____/      /_____/  \__,_/  /_/   /_/   \__,_/   "
}

function trace ($msg) {
    write-host $msg -foregroundcolor "cyan"; 
}


function _isAppBuild()   { $build_type.ToLower() -eq "app"  }
function _isWebBuild()   { $build_type.ToLower() -eq "web"  } 
function _isDbBuild()    { $build_type.ToLower() -eq "db"   }
function _isNugetBuild() { $build_type.ToLower() -eq "nuget"}