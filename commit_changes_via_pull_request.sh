#!/bin/sh

####################################################################################################
# This is a workaround for the issue described 
#       here: https://jira.atlassian.com/browse/BSERV-8647
#   and here: https://jira.atlassian.com/browse/BSERV-7475
#
# Note that there is an option added in BitBucket 4.5.1 that
# allows a user (e.g. JenkinsUser or BambooUser) to be exempted from the 
# restriction enforcing "No changes without a pull request"
# which would be preferred to this workaround.
#
# REF: https://developer.atlassian.com/static/rest/bitbucket-server/4.3.1/bitbucket-rest.html
# REF: https://developer.atlassian.com/bitbucket/server/docs/latest/how-tos/command-line-rest.html
####################################################################################################

# Note: This base branch name might not make sense if the build job is
# doing something besides updating the Maven artifact version.
# It can be changed to whatever makes sense.
base_branch_name="jenkins_pom_vers_update_"
base_pull_request_title="Jenkins Build Automation "

# Expected properties are.
# base_rest_url - the bitbucket server's rest API url path
#       example: http://bitbucket.example.com/bitbucket/rest/api/1.0
# starting_branch - the branch from which the temporary modification branch should be created
#       example: develop
# primary_username - the main bitbucket user account name (permitted to create branches, merge/write, etc.)
#       example: JenkinsUser
# primary_password - the password to use when authenticating the user specified by primary_username
# secondary_username - the bitbucket user account name used for approving a pull request
#       example: JenkinsApprovalUser
# secondary_password - the password to use when authenticating the user specified by secondary_username
#
# Note: Because this file contains passwords, it should be kept in a user directory that
# is only accessible by the OS (e.g. Linux) user account that runs the build process.
# Also, permissions should be set to 600 (i.e. user=rw, group=none, others=none)
load_properties() {
	local bitbucket_rest_properties_file=~/.bitbucket_rest_properties

	if [ -f "$bitbucket_rest_properties_file" ]
	then
	    # echo "Found ${bitbucket_rest_properties_file}."
	    while IFS='=' read -r key value
	    do
	    	eval "${key}='${value}'"
	    done < "$bitbucket_rest_properties_file"
	else
		echo "Missing required config file: ${bitbucket_rest_properties_file}"
	fi
}

usage() {
	# Note: Calling the third parameter new_version in the usage help
	# message is related to the fact that this script is set up to change the 
	# Maven build artifact version.  In other circumstances, this input
	# might be called something else.
	echo
    echo "Usage:"
    echo "    $0 {bitbucket_project} {bitbucket_repo} {new_version}" 
    echo
    exit 1
}

# Verify that the inputs are present and, as much as possible, that they look right
# TODO: get the project and repo names from the context git repo/clone instead
# of requiring them to be passed as inputs.
check_inputs_and_context() {
	if [ $# -lt 3 ]
	then
		echo "Missing required arguments."
		usage
	fi
	local scriptname=$(basename "$0")
	if [ -f "./${scriptname}" ]
	then
	    echo "Do not run this from the script directory where ${scriptname} is located."
	    echo "It must be run from the base directory of the local git repository (clone) of the BitBucket repository that is being modified."
	    exit 1
	fi
	local currentbranch=$(git branch | grep "\*" | cut -d ' ' -f2)
	if [ -z ${starting_branch+x} ]
	then
	    echo "Missing property value for \$starting_branch"
	    exit 1
	fi
	if [ $currentbranch != $starting_branch ]
	then
	    echo "The local git repository (clone) must be switched to branch: '${starting_branch}' before running this script."
	    echo "It is currently set to branch: '${currentbranch}'."
	    exit 1
	fi
}

# This assumes the current directory is a local clone of a git repository
create_modified_branch_in_remote_bitbucket() {
	local branch_name_suffix=$1
	# create a new branch and switch to it.
	git checkout -b "${base_branch_name}${branch_name_suffix}"
}

modify_source_files() {
	local new_version=$1
    #
	#  CHANGE THIS TO PERFORM WHATEVER BUILD AUTOMATED SOURCE FILE MODIFICATON
	#  IS DESIRED.
	#
	# As an example of a typical build automated change, this script just 
	# changes the version in the pom.xml file(s)
	mvn -DnewVersion=${new_version} -DgenerateBackupPoms=false versions:set
	
	# Other suggestions...
    # * Run a linter/formatter on source code to correct non-compliant formatting.
    # * Insert Copyright/timestamp/release-version-markers/etc in source files.

}	

commit_and_push_modified_source() {
	local branch_name_suffix=$1
	# commit locally
	git add .
	git commit -m "Build Job modifications to branch with pull request restriction."
	# push to bitbucket remote (creating the tracking branch at the same time)
	git push --set-upstream origin "${base_branch_name}${branch_name_suffix}"
}

build_pull_request_json() {
	local bitbucket_project=$1
	local bitbucket_repo=$2
	local branch_name_suffix=$3
	local pull_request_json="{"
	pull_request_json="${pull_request_json} \"title\": \"${base_pull_request_title}${branch_name_suffix}\""
	pull_request_json="${pull_request_json} ,\"description\": \"Build automation.\""
	pull_request_json="${pull_request_json} ,\"state\": \"OPEN\""
	pull_request_json="${pull_request_json} ,\"open\": \"true\""
	pull_request_json="${pull_request_json} ,\"closed\": \"false\""
	pull_request_json="${pull_request_json} ,\"fromRef\": {"
	pull_request_json="${pull_request_json}     \"id\": \"refs/heads/${base_branch_name}${branch_name_suffix}\""
	pull_request_json="${pull_request_json}     ,\"repository\": {"
	pull_request_json="${pull_request_json}         \"slug\": \"${bitbucket_repo}\""
	pull_request_json="${pull_request_json}         ,\"name\": null"
	pull_request_json="${pull_request_json}         ,\"project\": {"
	pull_request_json="${pull_request_json}             \"key\": \"${bitbucket_project}\""
	pull_request_json="${pull_request_json}         }"
	pull_request_json="${pull_request_json}     }"
	pull_request_json="${pull_request_json} }" # close fromRef
	pull_request_json="${pull_request_json} ,\"toRef\": {"
	pull_request_json="${pull_request_json}     \"id\": \"refs/heads/${starting_branch}\""
	pull_request_json="${pull_request_json}     ,\"repository\": {"
	pull_request_json="${pull_request_json}         \"slug\": \"${bitbucket_repo}\""
	pull_request_json="${pull_request_json}         ,\"name\": null"
	pull_request_json="${pull_request_json}         ,\"project\": {"
	pull_request_json="${pull_request_json}             \"key\": \"${bitbucket_project}\""
	pull_request_json="${pull_request_json}         }"
	pull_request_json="${pull_request_json}     }"
	pull_request_json="${pull_request_json} }" # close toRef
	pull_request_json="${pull_request_json} ,\"locked\": \"false\""
	pull_request_json="${pull_request_json} ,\"reviewers\": ["
	pull_request_json="${pull_request_json}     {"
	pull_request_json="${pull_request_json}         \"user\": {"
	pull_request_json="${pull_request_json}             \"name\": \"${secondary_username}\""
	pull_request_json="${pull_request_json}         }"
	pull_request_json="${pull_request_json}     }"
	pull_request_json="${pull_request_json} ]" # close reviewers
	pull_request_json="${pull_request_json} ,\"links\": {"
	pull_request_json="${pull_request_json}     \"self\": ["
	pull_request_json="${pull_request_json}             null"
	pull_request_json="${pull_request_json}     ]"
	pull_request_json="${pull_request_json} }" # close links
	pull_request_json="${pull_request_json} }" # close root json object
	# Note: This is meant to be captured by the caller, not actually echoed to stdout
	# Caller should use:  var_name=$(function_name arg arg ...) syntax
    echo ${pull_request_json}
}

create_pull_request() {
	local bitbucket_project=$1
	local bitbucket_repo=$2
	local branch_name_suffix=$3
	local create_pull_request_body=$(build_pull_request_json $bitbucket_project $bitbucket_repo $branch_name_suffix)
   	# Note: Python's json.tool will sort the json alphabetically for display
    # Use yajl json_reformat instead if it becomes important to see it in the original order.
    # See: http://www.skorks.com/2013/04/the-best-way-to-pretty-print-json-on-the-command-line/
    # echo "Sending:\n${create_pull_request_body}" | python -m json.tool
    local create_pull_request_curl_args="-X POST --silent"
    # Note: password may have special characters that would need to be escaped, so
    # the -u,--user argument must be in single quotes to be interpreted as a literal string.
    create_pull_request_curl_args="${create_pull_request_curl_args} -u '${primary_username}:${primary_password}'"
    create_pull_request_curl_args="${create_pull_request_curl_args} -H \"cache-control: no-cache\""
    create_pull_request_curl_args="${create_pull_request_curl_args} -H \"content-type: application/json\""
    create_pull_request_curl_args="${create_pull_request_curl_args} --data '${create_pull_request_body}'"
    create_pull_request_curl_args="${create_pull_request_curl_args} ${base_rest_url}/projects/${bitbucket_project}/repos/${bitbucket_repo}/pull-requests"
    echo $create_pull_request_curl_args
    local create_pull_request_response=$(eval "curl ${create_pull_request_curl_args}")
    #echo "create pull request response"
    # echo "$create_pull_request_response"

    # TODO: check the response for errors and quit if there are any.

    # parse response and capture the pull-request id (should be numeric)
    # tr splits the response json into lines at every comma
    # grep grabs the very first match on "id", which is the pull request id
    # cut pulls out just the numeric value of the id
    local pull_request_id=$(echo ${create_pull_request_response} | tr , '\n' | grep -m 1 "id" | cut -d ':' -f2)
    return ${pull_request_id}
}

approve_pull_request() {
	local bitbucket_project=$1
	local bitbucket_repo=$2
	local pull_request_id=$3
    local approve_pull_request_curl_args="-X PUT --silent"
    approve_pull_request_curl_args="${approve_pull_request_curl_args} --user '${secondary_username}:${secondary_password}'"
    approve_pull_request_curl_args="${approve_pull_request_curl_args} -H \"cache-control: no-cache\""
    approve_pull_request_curl_args="${approve_pull_request_curl_args} -H \"content-type: application/json\""
    approve_pull_request_curl_args="${approve_pull_request_curl_args} --data '{\"status\": \"APPROVED\"}'"
    approve_pull_request_curl_args="${approve_pull_request_curl_args} ${base_rest_url}/projects/${bitbucket_project}/repos/${bitbucket_repo}/pull-requests/${pull_request_id}/participants/${secondary_username}"
    echo "Calling: curl ${approve_pull_request_curl_args}"
    local approve_pull_request_response=$(eval "curl ${approve_pull_request_curl_args}")

    # TODO: check the response for errors and quit if there are any.

    echo $approve_pull_request_response
}

merge_pull_request() {
	local bitbucket_project=$1
	local bitbucket_repo=$2
	local pull_request_id=$3
    local merge_pull_request_curl_args="-X POST --silent"
    merge_pull_request_curl_args="${merge_pull_request_curl_args} --user '${primary_username}:${primary_password}'"
    merge_pull_request_curl_args="${merge_pull_request_curl_args} -H \"cache-control: no-cache\""
    merge_pull_request_curl_args="${merge_pull_request_curl_args} -H \"X-Atlassian-Token:nocheck\""
    merge_pull_request_curl_args="${merge_pull_request_curl_args} ${base_rest_url}/projects/${bitbucket_project}/repos/${bitbucket_repo}/pull-requests/${pull_request_id}/merge?version=0"
    echo "Calling: curl ${merge_pull_request_curl_args}"
    local merge_pull_request_response=$(eval "curl ${merge_pull_request_curl_args}")

    # TODO: check the response for errors and quit if there are any.

    echo $merge_pull_request_response
}

cleanup_branch() {
	local branch_name_suffix=$1
	git checkout "${starting_branch}"
	git branch -d "${base_branch_name}${branch_name_suffix}"
	git push origin --delete "${base_branch_name}${branch_name_suffix}"
}

#########################################################################
##      Main script follows...                                         ##
#########################################################################
load_properties
check_inputs_and_context "$@"
create_modified_branch_in_remote_bitbucket "$3"
modify_source_files "$3"
commit_and_push_modified_source "$3"
create_pull_request "$1" "$2" "$3"
pull_request_id=$?
approve_pull_request "$1" "$2" ${pull_request_id}
merge_pull_request "$1" "$2" ${pull_request_id}
cleanup_branch "$3"
