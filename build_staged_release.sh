#!/bin/bash
OPTIND=2
bold=`tput bold`
normal=`tput sgr0`

print_help () {
	echo "Usage: build_staged_release.sh <staging-number> [-d temp-directory] [-p port]  [-t test-pattern] [-hlx]"
	echo "${bold}Parameters:${normal}"
	echo "     -h/?    Display this message."
	echo "     -d      (optional) set the download directory, default is /tmp/sling-build"
	echo "     -l      (optional) leave the Sling instance running"
	echo "     -o      (optional) a comma separated lists of artifact IDs to execute.  Used if the projects need to be built in a particular order"
	echo "     -p      (optional) the port on which to start Sling"
	echo "     -t      (optional) the tests to execute, defaults to **/integrationtest/**/*Test.java"
	echo "     -x      (optional) skips the deployment and integration tests for this build, will not start Sling"
	exit $STOP_CODE
}

do_cleanup () {
	echo "################################################################################"
	echo "                                Cleaning Up                                     "
	echo "################################################################################"
	if [ -n "$PID" ] && [ "$LEAVE_RUNNING" -eq "0" ]; then
		if ps -p $PID > /dev/null 2>&1; then
			kill $PID
			echo "Stopped Sling process $PID..."
		else
			echo "Process ${PID} not running..."
		fi
		rm ${DOWNLOAD}/run/sling.pid
	fi
	echo "################################################################################"
	exit $STOP_CODE
}

# trap ctrl-c 
trap do_cleanup INT

# Initialize our variables
DOWNLOAD="/tmp/sling-build"
LEAVE_RUNNING=0
NO_DEPLOY=0
ORDER=".pom"
PORT="8080"
STAGING=$1
STOP_CODE=0
TESTS="**/integrationtest/**/*Test.java"

# Make sure maven has enough memory
if [ -n "$MAVEN_OPTS" ]; then
	MACHINE_TYPE=`uname -m`
	if [ ${MACHINE_TYPE} == 'x86_64' ]; then
		export MAVEN_OPTS="-Xmx512m -XX:MaxPermSize=512m"
	else
		export MAVEN_OPTS="-Xmx256m -XX:MaxPermSize=256m"
	fi
fi

# Make sure xmllint and svn are installed
command -v xmllint >/dev/null 2>&1 || { echo "This script requires xmllint but it's not installed.  Aborting." >&2; exit 1; }
command -v svn >/dev/null 2>&1 || { echo "This script requires svn but it's not installed.  Aborting." >&2; exit 1; }
command -v mvn >/dev/null 2>&1 || { echo "This script requires mvn but it's not installed.  Aborting." >&2; exit 1; }

while getopts "hd:lo:p:t:x" opt; do
	case "$opt" in
	h)
		print_help
		;;
	d)  DOWNLOAD=$OPTARG
		;;
	l)  LEAVE_RUNNING=1
		;;
	o)  ORDER=$OPTARG
		;;
	p)  PORT=$OPTARG
		;;
	t)  TESTS=$OPTARG
		;;
	x)  NO_DEPLOY=1
		;;
	esac
done

# Ensure the user specified the staging ID
if [ -z "$STAGING" ]; then
	print_help
	exit 1
fi

if [ "$STAGING" == "-h" ] || [ "$STAGING" == "help" ]; then
	print_help
	exit 0
fi

# Make sure Sling isn't still running
PID=`cat ${DOWNLOAD}/run/sling.pid 2> /dev/null`

if [ ! -z "$PID" ] && [ ps -p $PID > /dev/null 2>&1 ]; then
	echo "Sling appears to be running on process $PID, please stop Sling or remove the file ${DOWNLOAD}/run/sling.pid before continuing!"
	exit 1
fi

rm -r ${DOWNLOAD}/run 2> /dev/null
mkdir -p ${DOWNLOAD}/logs 2>/dev/null

if [ ! -e "${DOWNLOAD}/staging/${STAGING}" ]; then
	echo "################################################################################"
	echo "                          DOWNLOAD STAGED REPOSITORY                            "
	echo "################################################################################"
	
	mkdir -p ${DOWNLOAD}/staging/${STAGING}
	if [ `wget --help | grep "no-check-certificate" | wc -l` -eq 1 ]
	then
		CHECK_SSL=--no-check-certificate
	fi
	
	echo "Downloading repository http://repository.apache.org/content/repositories/orgapachesling-${STAGING}/org/apache/sling/..."
	wget $CHECK_SSL \
		-e "robots=off" --wait 1 -nv -r -np "--accept=pom" "--follow-tags=" \
		-P "${DOWNLOAD}/staging/${STAGING}" -nH "--cut-dirs=3" --ignore-length \
		"http://repository.apache.org/content/repositories/orgapachesling-${STAGING}/org/apache/sling/"
else
	echo "################################################################################"
	echo "                            USING EXISTING STAGED REPOSITORY                    "
	echo "################################################################################"
	echo "${DOWNLOAD}/staging/${STAGING}"
fi

if [ "$NO_DEPLOY" -eq "0" ]; then
	echo "################################################################################"
	echo "                            SETTING UP SLING INSTANCE                           "
	echo "################################################################################"
	mkdir -p ${DOWNLOAD}/run
	
	if [ ! -e "${DOWNLOAD}/run/testing" ]; then
		echo "Downloading Sling Testing Project to ${DOWNLOAD}/run/testing..."
		mkdir -p ${DOWNLOAD}/run/testing
		svn co http://svn.apache.org/repos/asf/sling/trunk/launchpad/testing/ \
			${DOWNLOAD}/run/testing/ > /dev/null 2>&1
	else 
		echo "Updating Sling Trunk at ${DOWNLOAD}/run/testing..."
		svn up ${DOWNLOAD}/run/testing/ > /dev/null 2>&1
	fi
	echo "Starting Sling on port ${PORT}..."
	mvn clean install -f launchpad/testing/pom.xml -Dlaunchpad.keep.running=true -Dhttp.port=$PORT -Ddebug=true > \
		${DOWNLOAD}/logs/sling-start.log 2>&1 &
	PID=$!
	echo $! > ${DOWNLOAD}/run/sling.pid
	
	# Wait until Sling starts...
	i=0
	while [ $i -le "9" ]
	do
		i=$(($i+1))
		RES=$(curl -s -u admin:admin http://localhost:${PORT}/index.html)
		if [[ "$RES" =~ "Do not remove this comment, used for Launchpad integration tests" ]]; then
			echo "Sling started successfully, process: $PID"
			break
		else
			echo "($i of 10) Waiting for Sling to start..."
			sleep 30
		fi
	done
fi

echo "################################################################################"
echo "                            RUNNING MAVEN BUILD                                 "
echo "################################################################################"
OIFS=$IFS
if [ "$ORDER" != ".pom" ]; then
	export IFS=","
fi
for ORDER_ITEM in $ORDER
do
	if [ "$ORDER_ITEM" != ".pom" ]; then
		ORDER_ITEM_EXP="\/$ORDER_ITEM\/"
	else	
		ORDER_ITEM_EXP="$ORDER_ITEM"
	fi
	echo "Searching for $ORDER_ITEM_EXP..."
	for POM in `find "${DOWNLOAD}/staging/${STAGING}" -type f | grep '\.\(pom\)$' | grep $ORDER_ITEM_EXP`
	do
		if [ "$ORDER" != ".pom" ]; then
			echo "${bold}Building $POM from $ORDER_ITEM${normal}"
		fi
		# Parse the info required for build out of the pom
		sed -e 's/xmlns="http:\/\/maven\.apache\.org\/POM\/4\.0\.0"//g' $POM > ${DOWNLOAD}/staging/${STAGING}/pom.xml
		PACKAGING=`xmllint --xpath '/project/packaging/text()' ${DOWNLOAD}/staging/${STAGING}/pom.xml`
		TAG=`xmllint --xpath '/project/scm/connection/text()' ${DOWNLOAD}/staging/${STAGING}/pom.xml`
		VERSION=`xmllint --xpath '/project/version/text()' ${DOWNLOAD}/staging/${STAGING}/pom.xml`
		TAG=${TAG/scm:svn:/} 
		ARTIFACT_ID=`xmllint --xpath '/project/artifactId/text()' ${DOWNLOAD}/staging/${STAGING}/pom.xml`
		echo "Running build for $TAG..."
		mkdir -p ${DOWNLOAD}/build/${STAGING}/$ARTIFACT_ID
		echo "Exporting tag $TAG to ${DOWNLOAD}/build/${STAGING}/$ARTIFACT_ID..."
		svn export --force $TAG ${DOWNLOAD}/build/${STAGING}/$ARTIFACT_ID > ${DOWNLOAD}/logs/${STAGING}-$ARTIFACT_ID-build.log 2>&1
		echo "Building tag ${DOWNLOAD}/build/${STAGING}/$ARTIFACT_ID..."
		mvn clean install -f ${DOWNLOAD}/build/${STAGING}/$ARTIFACT_ID/pom.xml >> ${DOWNLOAD}/logs/${STAGING}-$ARTIFACT_ID-build.log 2>&1
		rc=$?
		if [ $rc != 0 ] ; then
			echo "mvn: BAD!! : Failed to build $ARTIFACT_ID, see ${DOWNLOAD}/logs/${STAGING}-$ARTIFACT_ID-build.log"
			do_cleanup
			exit 1
		else 
			echo "mvn: GOOD : Successfully built $ARTIFACT_ID"
			if [ "$NO_DEPLOY" -eq "0" ]; then 
				if [ "$PACKAGING" = "bundle" ]; then
					curl -s -u admin:admin -F "action=install" -F "_noredir_=_noredir_" -F \
						"bundlefile=@${DOWNLOAD}/build/${STAGING}/$ARTIFACT_ID/target/$ARTIFACT_ID-$VERSION.jar" \
						-F "bundlestart=start" http://localhost:${PORT}/system/console/bundles
					sleep 30
					RES=$(curl -s -u admin:admin http://localhost:${PORT}/system/console/bundles/$ARTIFACT_ID -F action=start)
					if [[ "$RES" =~ "32" ]]; then
						echo "bundle: GOOD : Successfully installed/started bundle $ARTIFACT_ID"
					else
						echo "bundle: BAD!! : Failed to install/start bundle $ARTIFACT_ID, response $RES"
						STOP_CODE=1
					fi
				else
					echo "Project $ARTIFACT_ID has packaging $PACKAGING, not installing..."
				fi
			fi
		fi
	done
done
IFS=$OIFS
if [ "$NO_DEPLOY" -eq "0" ]; then 
	echo "################################################################################"
	echo "                             CHECK INTEGRATION TESTS                            "
	echo "################################################################################"
	if [ ! -e "${DOWNLOAD}/build/integration-tests" ]; then
		echo "Downloading Sling Integration Tests to ${DOWNLOAD}/build/integration-tests..."
		mkdir -p ${DOWNLOAD}/build/integration-tests
		svn co http://svn.apache.org/repos/asf/sling/trunk/launchpad/integration-tests/ \
			${DOWNLOAD}/build/integration-tests/ > /dev/null 2>&1
	else 
		echo "Updating Sling Trunk at ${DOWNLOAD}/build/integration-tests..."
		svn up ${DOWNLOAD}/build/integration-tests/ > /dev/null 2>&1
	fi
	mvn clean install  -Dhttp.port=${PORT} -Dtest.host=localhost -f ${DOWNLOAD}/build/integration-tests/pom.xml \
		-Dtest=${TESTS} > ${DOWNLOAD}/logs/${STAGING}-it.log 2>&1
	rc=$?
	if [ $rc != 0 ]; then
		echo "mvn: BAD!! : Failed to run integration tests, see ${DOWNLOAD}/logs/${STAGING}-it.log"
		STOP_CODE=1
	else
		echo "mvn: GOOD : Successfully ran integration tests"
	fi
fi

do_cleanup
