#!/bin/sh

####################################################################################################
# This is a workaround for the issue described 
#       here: https://jira.atlassian.com/browse/BSERV-8647
#   and here: https://jira.atlassian.com/browse/BSERV-7475
#
# Note that there is an option added in BitBucket 4.5.1 that
# allows a user (e.g. JenkinsUser or BambooUser) to be exempted from the 
# restriction prohibiting "Changes without a pull request"
# which would be preferred to this workaround.
#
# REF: https://developer.atlassian.com/static/rest/bitbucket-server/4.9.0/bitbucket-rest.html
# REF: https://developer.atlassian.com/bitbucket/server/docs/latest/how-tos/command-line-rest.html
####################################################################################################

# Note: This base branch name might not make sense if the build job is
# doing something besides updating the Maven artifact version.
# It can be changed to whatever makes sense.
base_branch_name="jenkins_pom_vers_update_"

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
check_inputs() {
	if [ $# -lt 3 ]
	then
		echo "Missing required arguments."
		usage
	fi
}

load_properties() {
	bitbucket_rest_properties_file=~/.bitbucket_rest_properties

	if [ -f "$bitbucket_rest_properties_file" ]
	then
	    echo "Found ${bitbucket_rest_properties_file}."
	    while IFS='=' read -r key value
	    do
	    	eval "${key}='${value}'"
	    done < "$bitbucket_rest_properties_file"
	else
		echo "Missing required config file: ${bitbucket_rest_properties_file}"
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
	#  ADD ANY OTHER AUTOMATED SOURCE CHANGES HERE!!!
	#
	# As an example of a typical build automated change, this script just 
	# changes the version in the pom.xml file(s)
	mvn -DnewVersion=${new_version} -DgenerateBackupPoms=false versions:set
}	

commit_and_push_modified_source() {
	local branch_name_suffix=$1
	# commit locally
	git commit -m "Build Job modifications to branch with pull request restriction."
	# push to bitbucket remote (creating the tracking branch at the same time)
	git push --set-upstream origin "${base_branch_name}${branch_name_suffix}"
}

build_pull_request_json() {
	local bitbucket_project=$1
	local bitbucket_repo=$2
	local pull_request_name=$3
	local pull_request_json="{"
	pull_request_json="${pull_request_json} \"title\": \"Jenkins Release Version pom.xml Update\""
	pull_request_json="${pull_request_json} ,\"description\": \"Jenkins release build automation.\""
	pull_request_json="${pull_request_json} ,\"state\": \"OPEN\""
	pull_request_json="${pull_request_json} ,\"open\": \"true\""
	pull_request_json="${pull_request_json} ,\"closed\": \"false\""
	pull_request_json="${pull_request_json} ,\"fromRef\": {"
	pull_request_json="${pull_request_json}     \"id\": \"refs/heads/${base_branch_name}_${pull_request_name}\""
	pull_request_json="${pull_request_json}     ,\"repository\": {"
	pull_request_json="${pull_request_json}         \"slug\": \"${bitbucket_repo}\""
	pull_request_json="${pull_request_json}         ,\"name\": null"
	pull_request_json="${pull_request_json}         ,\"project\": {"
	pull_request_json="${pull_request_json}             \"key\": \"${bitbucket_project}\""
	pull_request_json="${pull_request_json}         }"
	pull_request_json="${pull_request_json}     }"
	pull_request_json="${pull_request_json} }" # close fromRef
	pull_request_json="${pull_request_json} ,\"toRef\": {"
	pull_request_json="${pull_request_json}     \"id\": \"refs/heads/develop\""
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
	local bitbucket_project=$2
	local bitbucket_repo=$3
	local pull_request_name=$1
	local create_pull_request_body=$(build_pull_request_json $pull_request_name $bitbucket_project $bitbucket_repo)
    local create_pull_request_curl_cmd="curl --request POST --url ${base_rest_url}/projects/${bitbucket_project}/repos/${bitbucket_repo}/pull-requests"
    create_pull_request_curl_cmd="${create_pull_request_curl_cmd} --user '${primary_username}:${primary_password}'"
    create_pull_request_curl_cmd="${create_pull_request_curl_cmd} --header 'cache-control: no-cache'"
    create_pull_request_curl_cmd="${create_pull_request_curl_cmd} --header 'content-type: application/json'"
    create_pull_request_curl_cmd="${create_pull_request_curl_cmd} --data ${create_pull_request_body}"
    echo "TODO: actually execute: $create_pull_request_curl_cmd"
	# Note: This will sort the json alphabetically for display
	# Use yajl json_reformat instead if it becomes important to see it in the original order.
	# See: http://www.skorks.com/2013/04/the-best-way-to-pretty-print-json-on-the-command-line/
	echo "TODO: actually send body:" 
    echo "${create_pull_request_body}" | python -m json.tool
    #TODO: parse response and capture the pull-request id (should be numeric)
    local pull_request_id=1
    return ${pull_request_id}
}

approve_pull_request() {
	local bitbucket_project=$1
	local bitbucket_repo=$2
	local pull_request_id=$3
    local approve_pull_request_curl_cmd="curl --request POST --url ${base_rest_url}/projects/${bitbucket_project}/repos/${bitbucket_repo}/pull-requests/${pull_request_id}"
    approve_pull_request_curl_cmd="${approve_pull_request_curl_cmd}/participants/${secondary_username}"
    approve_pull_request_curl_cmd="${approve_pull_request_curl_cmd} --user '${secondary_username}:${secondary_password}'"
    approve_pull_request_curl_cmd="${approve_pull_request_curl_cmd} --header 'cache-control: no-cache'"
    echo "TODO: actually execute: ${approve_pull_request_curl_cmd}"
}

merge_pull_request() {
	local bitbucket_project=$1
	local bitbucket_repo=$2
	local pull_request_id=$3
    local merge_pull_request_curl_cmd="curl --request GET --url ${base_rest_url}/projects/${bitbucket_project}/repos/${bitbucket_repo}/pull-requests/${pull_request_id}/merge"
    merge_pull_request_curl_cmd="${merge_pull_request_curl_cmd} --user '${primary_username}:${primary_password}'"
    merge_pull_request_curl_cmd="${merge_pull_request_curl_cmd} --header 'cache-control: no-cache'"
    echo "TODO: actually execute: ${merge_pull_request_curl_cmd}"
}

#########################################################################
##      Main script follows...                                         ##
#########################################################################
check_inputs "$@"
load_properties
create_modified_branch_in_remote_bitbucket "$3"
modify_source_files "$3"
commit_and_push_modified_source "$3"
create_pull_request "$1" "$2" "$3"
pull_request_id=$?
approve_pull_request "$1" "$2" $pull_request_id 
merge_pull_request "$1" "$2" $pull_request_id
