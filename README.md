# BitBucket Build System Permissions Workaround

This is a workaround for the issue described 
      here: https://jira.atlassian.com/browse/BSERV-8647
  and here: https://jira.atlassian.com/browse/BSERV-7475

* Note that there is an option added in BitBucket 4.5.1 that allows a user (e.g. JenkinsUser or BambooUser) to be exempted from the branch restriction that enforces "No changes without a pull request".  Upgrading to 4.5.1 or later would be preferred to this workaround.

* The shell script allow a build job in Jenkins (or Bamboo or similar build tool) to work around bitbucket's "No changes without a pull request" branch restriction and "Requires (x) reviewers" pull-request restriction by automating the process of creating a branch and a pull-request with reviewers, and then approving and merging the pull request.

* Note: To comply with both the "No changes without a pull request" and the "Requires (x) reviewers" restrictions, this depends on having 2 BitBucket users defined for use by the build system.  For instance, JenkinsUser to checkout, branch, commit, push, and merge, and JenkinsApprovalUser to serve as a separate "approver".  If more than one reviewer is required, this would need to be modified to add multiple reviewers and submit approvals from all of them.

* Note: The sample .bitbucket_rest_properties file would be moved into the profile/user directory in the OS for
the user that runs the Jenkins worker-process/job (e.g. /home/JenkinsWorkerAccount/.bitbucket_rest_properties).
However, these properties could also be supplied to the script in a different way with modifications to the 
load_properties() function in the script.