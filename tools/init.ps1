param( $installPath, $toolsPath, $package )

# find out where to put the files, we're going to create a Build folder at the solution level. 
$root  = (get-item $installPath).parent.parent.fullname; 
$buildTarget = "$root\Build";  
$buildSource = join-path $installPath 'Build'
$copyFiles = $true; 

# create the build target folder if it doesn't exists 
if (test-path $buildTarget) { 
    write-host "Warning! [$buildTarget] already exists. Files won't be copied over."; 
    $copyFiles = $false; 
} else { 
    mkdir $buildTarget; 
}

if ($copyFiles) {
    # copy from build source to target
    copy-item "$buildSource/*" $buildTarget -Recurse -Force 
}

# get the active solution 
$solution = get-interface $dte.Solution ([EnvDTE80.Solution2]); 

# create the build solution folder if it doesn't exists 
$solutionFolder = $solution.Projects | ? { $_.ProjectName -eq "Build" } | select -first 1; 
if ( !$solutionFolder ) {
    $solutionFolder = $solution.AddSolutionFolder("Build"); 
}

# add all our build scripts to the solution folder 
$solutionFolderItems = Get-Interface $solutionFolder.ProjectItems ([EnvDTE.ProjectItems]);

gci -path $buildTarget *.ps1 | %{ 
    $solutionFolderItems.AddFromFile($_.FullName) > $null;  
} > $null 

