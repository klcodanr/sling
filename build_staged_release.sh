#!/bin/sh
OPTIND=2

function print_help {
	bold=`tput bold`
	normal=`tput sgr0`
	echo "Usage: build_staged_release.sh <staging-number> [-d temp-directory] [-p port] [-hxk]"
	echo "${bold}Parameters:${normal}"
	echo "     -h/?    Display this message."
	echo "     -d      (optional) set the download directory, default is /tmp/sling-build"
	echo "     -p      (optional) the port to start Sling on"
	echo "     -x      (optional) skips the deployment and integration tests for this build, will not start Sling"
	exit $STOP_CODE
}

function do_cleanup {
	echo "################################################################################"
	echo "                                Cleaning Up                                     "
	echo "################################################################################"
	echo "Cleaning up Sling Trunk build artifacts..."
	mvn clean -f ${DOWNLOAD}/build/sling/pom.xml > /dev/null 2>&1
	if [ -n "$PID" ]; then
		if ps -p $PID > /dev/null 2>&1; then
			kill $PID
			echo "Stopped Sling process $PID..."
		else
			echo "Process ${PID} not running..."
		fi
	fi
	echo "################################################################################"

	exit $STOP_CODE
}

# trap ctrl-c and call ctrl_c()
trap do_cleanup INT

# Initialize our variables
STAGING=$1
NO_DEPLOY=0
DOWNLOAD="/tmp/sling-build"
PORT="8080"
STOP_CODE=0

# Make sure maven has enough memory
if [ -n "$MAVEN_OPTS" ]; then
	MACHINE_TYPE=`uname -m`
	if [ ${MACHINE_TYPE} == 'x86_64' ]; then
		export MAVEN_OPTS="-Xmx512m -XX:MaxPermSize=512m"
	else
		export MAVEN_OPTS="-Xmx256m -XX:MaxPermSize=256m"
	fi
fi

while getopts "h?d:p:x" opt; do
	case "$opt" in
	h|\?)
		print_help
		;;
	d)  DOWNLOAD=$OPTARG
		;;
	x)  NO_DEPLOY=1
		;;
	p)  PORT=$OPTARG
		;;
	esac
done

if [ "$STAGING" -eq "-1" ]
then
	print_help
	exit 1
fi

echo "Creating directory $DOWNLOAD..."
mkdir -p ${DOWNLOAD} 2>/dev/null
mkdir -p ${DOWNLOAD}/logs 2>/dev/null
mkdir -p ${DOWNLOAD}/run 2>/dev/null
mkdir -p ${DOWNLOAD}/build 2>/dev/null
mkdir -p ${DOWNLOAD}/staging 2>/dev/null

if [ ! -e "${DOWNLOAD}/${STAGING}" ]
then
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

if [ "$NO_DEPLOY" -eq "0" ]
then
	echo "################################################################################"
	echo "                            SETTING UP SLING INSTANCE                           "
	echo "################################################################################"
	rm -r ${DOWNLOAD}/run 2> /dev/null
	rm ${DOWNLOAD}/logs/sling-*.log 2> /dev/null
	if [ ! -e "${DOWNLOAD}/build/sling" ]; then
		echo "Downloading Sling Trunk SVN Repo to ${DOWNLOAD}/build/sling..."
		mkdir -p ${DOWNLOAD}/build/sling
		svn co http://svn.apache.org/repos/asf/sling/trunk/ ${DOWNLOAD}/build/sling/ > /dev/null 2>&1
	else 
		echo "Updating Sling Trunk at ${DOWNLOAD}/build/sling..."
		svn up ${DOWNLOAD}/build/sling/ > /dev/null 2>&1
	fi	
	echo "Building Sling Trunk..."
	mvn clean install -f ${DOWNLOAD}/build/sling/pom.xml -DskipTests=true > ${DOWNLOAD}/logs/sling-build.log 2>&1
	rc=$?
	if [[ $rc != 0 ]] ; then
		echo "mvn: BAD!! : Failed to build Sling trunk, see ${DOWNLOAD}/logs/sling-build.log"
		exit 1
	else
		echo "mvn: GOOD : Successfully built Sling trunk"
	fi
	echo "Starting Sling instance at ${DOWNLOAD}/build/sling/launchpad/builder/target/*standalone.jar on port ${PORT}..."
	java -jar ${DOWNLOAD}/build/sling/launchpad/builder/target/*standalone.jar -c ${DOWNLOAD}/run/sling -p $PORT > ${DOWNLOAD}/logs/sling-start.log 2>&1 &
	PID=$!
	
	# Wait until Sling starts...
	i=0
	while [ $i -le "10" ]
	do
		i=$(($i+1))
		RES=$(curl -s -u admin:admin http://localhost:${PORT}/index.html)
		if [[ $RES == *"Do not remove this comment, used for Launchpad integration tests"* ]]
		then
			echo "Sling started successfully, process: $PID"
			break
		else
			echo "Waiting for Sling to start..."
			sleep 30
		fi
	done
fi

echo "################################################################################"
echo "                            RUNNING MAVEN BUILD(s)                              "
echo "################################################################################"
for i in `find "${DOWNLOAD}/staging/${STAGING}" -type f | grep '\.\(pom\)$'`
do
	# Parse the info required for build out of the pom
	sed -e 's/xmlns="http:\/\/maven\.apache\.org\/POM\/4\.0\.0"//g' $i > ${DOWNLOAD}/staging/${STAGING}/pom.xml
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
	if [[ $rc != 0 ]] ; then
		echo "mvn: BAD!! : Failed to build $ARTIFACT_ID, see ${DOWNLOAD}/logs/${STAGING}-$ARTIFACT_ID-build.log"
		exit 1
	else 
		echo "mvn: GOOD : Successfully built $ARTIFACT_ID"
		if [ "$NO_DEPLOY" -eq "0" ]
		then 
			curl -s -u admin:admin -F "action=install" -F "_noredir_=_noredir_" -F "bundlefile=@${DOWNLOAD}/build/${STAGING}/$ARTIFACT_ID/target/$ARTIFACT_ID-$VERSION.jar" -F "bundlestart=start" http://localhost:${PORT}/system/console/bundles
			sleep 30
			RES=$(curl -s -u admin:admin http://localhost:${PORT}/system/console/bundles/$ARTIFACT_ID -F action=start)
			if [[ $RES == *"32"* ]]
			then
				echo "bundle: GOOD : Successfully installed/started bundle $ARTIFACT_ID"
			else
				echo "bundle: BAD!! : Failed to install/start bundle $ARTIFACT_ID, response $RES"
				STOP_CODE=1
			fi
		fi
	fi
done
if [ "$NO_DEPLOY" -eq "0" ]; then 
	echo "################################################################################"
	echo "                             CHECK INTEGRATION TESTS                            "
	echo "################################################################################"
	mvn clean install  -Dhttp.port=${PORT} -Dtest.host=localhost -f ${DOWNLOAD}/build/sling/launchpad/integration-tests/pom.xml -Dtest=**/integrationtest/**/*Test.java > ${DOWNLOAD}/logs/${STAGING}-it.log 2>&1
	rc=$?
	if [[ $rc != 0 ]] ; then
		echo "mvn: BAD!! : Failed to run integration tests, see ${DOWNLOAD}/logs/${STAGING}-it.log"
		STOP_CODE=1
	else
		echo "mvn: GOOD : Successfully ran integration tests"
	fi
fi

do_cleanup