# bitbucket-jenkins-permissions-workaround
Shell script to allow a build job in Jenkins (or Bamboo or similar build tool) to work around bitbucket's "No changes without a pull request" branch restriction.

* Note: This depends on having 2 BitBucket users defined for use by the build system.  For instance, JenkinsUser and JenkinsApprovalUser.

* Note: The sample .bitbucket_rest_properties file would be moved into the profile/user directory in the OS for
the user that runs the Jenkins worker-process/job (e.g. /home/JenkinsWorkerAccount/.bitbucket_rest_properties).
However, these properties could also be supplied to the script in a different way with modifications to the 
load_properties() function in the script.