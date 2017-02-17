#!/bin/bash

OPTIND=2
bold=`tput bold`
normal=`tput sgr0`

print_help () {
	echo "Usage: test_build.sh <project-list-file> [-p port]  [-t test-pattern] [-h]"
	echo "${bold}Parameters:${normal}"
	echo "     -h/?    Display this message."
	echo "     -p      (optional) the port on which to start Sling"
	echo "     -s      (optional) stop the sling instance after completing"
	echo "     -t      (optional) the tests to execute, defaults to **/integrationtest/**/*Test.java"
	exit 1
}

function checkrc () {
	if [[ $rc -ne 0 ]] ; then
		echo "Failed to execute step, exiting..."
		checkkill
		exit $rc
	fi
}

function checkkill () {
	if [[ "$STOP" = "1" ]]; then
		pkill -TERM -P $PID
		echo "Stopped Sling process $PID..."
	else
		read -p "Stop Sling Instance? (y/n) " RES
		if [[ $RES =~ ^[Yy]$ ]]; then
			pkill -TERM -P $PID
			kill $PID
			echo "Stopped Sling process $PID..."
		else
			echo "To stop sling, execute: pkill -TERM -P $PID && kill $PID"
		fi
	fi
}

trapexit () {
	if [ -n "$PID" ]; then
		checkkill
	fi
	exit 1
}

# trap ctrl-c 
trap do_trap INT

# Initialize our variables
STOP=0
PORT="8080"
TESTS="**/integrationtest/**/*Test.java"
DIR=$(dirname $0)

while getopts "shp:t:" opt; do
	case "$opt" in
	h)
		print_help
		;;
	s)
		STOP=1
		;;
	p)  PORT=$OPTARG
		;;
	t)  TESTS=$OPTARG
		;;
	esac
done

# Make sure maven has enough memory
if [ -n "$MAVEN_OPTS" ]; then
	MACHINE_TYPE=`uname -m`
	if [ ${MACHINE_TYPE} == 'x86_64' ]; then
		export MAVEN_OPTS="-Xmx512m -XX:MaxPermSize=512m"
	else
		export MAVEN_OPTS="-Xmx256m -XX:MaxPermSize=256m"
	fi
fi

echo "################################################################################"
echo "                            RUNNING MAVEN BUILD                                 "
echo "################################################################################"
lines=`cat $1`
for line in $lines; do
	params=(${line//;/ })
	project="${params[0]}"
	bundle="${params[1]}"
	
	echo "Building $project..."
	mvn clean install --batch-mode -f $DIR/$project/pom.xml
	rc=$?
	if [[ $rc -ne 0 ]] ; then
		echo "mvn: BAD : Failed to build $project"
		exit 1
	else 
	
		echo "mvn: GOOD : Successfully built $project"
	fi
	
done


echo "################################################################################"
echo "                            SETTING UP SLING INSTANCE                           "
echo "################################################################################"
mvn clean install -f $DIR/launchpad/testing/pom.xml -Dlaunchpad.keep.running=true -Dhttp.port=$PORT -Ddebug=true &
PID=$!

COUNTER=0
while [  $COUNTER -lt 10 ]; do
	i=$(($i+1))
	sleep 15
	echo "Checking if Sling Launchpad Started..."
	content=$(wget http://localhost:$PORT/index.html -q -O -)
	if [[ $content == *"Do not remove this comment, used for Launchpad integration tests"* ]]; then
		echo "Sling started successfully, process: $PID"
		break
	else
		echo "($i of 10) Waiting for Sling to start..."
		sleep 30
	fi
done

echo "################################################################################"
echo "                            INSTALLING BUILDS                                   "
echo "################################################################################"
lines=`cat $1`
for line in $lines; do
	params=(${line//;/ })
	project="${params[0]}"
	bundle="${params[1]}"
	if [[ ! -z "$bundle" ]]; then	
		echo "Installing $project/target/$bundle..."
		curl -u admin:admin -F action=install -F refreshPackages=true -F bundlestart=true -F bundlefile=@"$DIR/$project/target/$bundle" http://localhost:$PORT/system/console/bundles
		rc=$?
		checkrc
		echo "bundle: GOOD : Successfully installed $bundle"
	fi
done

echo "################################################################################"
echo "                             CHECK INTEGRATION TESTS                            "
echo "################################################################################"
echo "Running Sling Integration Tests $TESTS..."
mvn test  -f $DIR/launchpad/integration-tests/pom.xml  -Dtest=$TESTS
rc=$?
checkrc

echo "################################################################################"
echo "                             ALL CHECKS SUCCESSFUL                              "
echo "################################################################################"

checkkill