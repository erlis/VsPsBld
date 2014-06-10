#
# TODO: Adjust the following values for your project 
#
properties {
    # configuration to build. Possible values "Debug|Release" 
    $configuration = "Release"; 

    # path used as root for all other paths 
    $base_folder = ".."; 

    # the folder that will contains the build result. This folder is 
    # configured in Jenkins as the build artifact folder. 
    $build_output = "$base_folder\BuildOutput";

    # environments to be built. By default the Dev environment is created, no need to include dev here. 
    # Each value in this list should have a matching xsd transformation config file that will be used to 
    # create the config file for that environment. The $build_output folder will contain a folder by environment, 
    # this list will control that too. 
    $environments = @('stg', 'prd'); 

    $build_info = @( @{ # type of the build that will be performed. Possible values: App|Web|Db|Nuget. 
                        "build_type"   = "App" 

                        # folder for the project to be built. Used to locate the [web|app].config to apply transformations
                      ; "project_folder" = '$base_folder\[TODO:project_name]' 
                      
                        # USED ONLY if build_type=Web. Path to the web project. Typically a csproj file 
                      ; "web_project" = '$base_folder\[TODO project file].csproj' 

                        # full path to the file to build, typical a solution file. 
                        # For some build_type this file could be the csproj, i.e.: Web. 
                      ; "file_to_build" = '$base_folder\[TODO:SOLUTION FILE].[sln|csproj]'
           
                        # USED ONLY if build_type=App. Name of the generated  config file by enviroment 
                      ; "final_app_config_name" = '[TODO:project_name].exe.config'
           
                        # path to the binaries created by MSBuild usually in a \bin\x86\Debug\Release folder 
                      ; "msbuild_output" = '$project_folder\bin\x86\$configuration'
                      
                        # USED ONLY    if build_type=Nuget. Path to the nuspec file 
                      ; "nuspec" = '$project_folder\[TODO: Nuspecfile].nuspec' 
                      
                        # USED ONLY    if build_type=Nuget. URL to the local Nuget repository
                      ; "nuget_repository" = "http://s1wdvcomp01/ANNuGetFeed/" 

                      # USED ONLY if build_type=Db. Automatically deployed to these environments. 
                      ; "db_deploy_to" = @("int") 
           
                      # exclude config from output. For some environments we don't want 
                      # to publish a .config file. i.e.: some PRD environments.  
                      ; "exclude_config" = @("prd")
                      }
               # ... you can add more projects configurations here... 
               #   , @{}
                   );
}