#!/bin/bash

PORT="8080"

### Don't configure below this line.

echo "Building projects..."
lines=`cat $1`
for line in $lines; do
	params=(${line//;/ })
	project="${params[0]}"
	bundle="${params[1]}"
	
	echo "Building $project..."
	mvn clean install --batch-mode -f $project/pom.xml
	rc=$?
	if [[ $rc -ne 0 ]] ; then
		echo "Failed to build $project!"; exit $rc
	fi
	
	echo "Build of $project complete!"
done

echo "Starting Apache Sling on port $PORT"
mvn clean install -f launchpad/testing/pom.xml -Dlaunchpad.keep.running=true -Dhttp.port=$PORT -Ddebug=true &

COUNTER=0
while [  $COUNTER -lt 10 ]; do
	sleep 15
	echo "Checking if Sling Launchpad Started..."
	content=$(wget http://localhost:$PORT/index.html -q -O -)
	if [[ $content == *"Do not remove this comment, used for Launchpad integration tests"* ]]; then
		echo "Sling Started!"
		break
	fi
done

echo "Installing builds..."
lines=`cat $1`
for line in $lines; do
	params=(${line//;/ })
	project="${params[0]}"
	bundle="${params[1]}"
	
	echo "Installing $project/target/$bundle..."
	curl -u admin:admin -F action=install -F bundlestartlevel=20 -F bundlefile=@"$project/target/$bundle" http://localhost:$PORT/system/console/bundles
	rc=$?
	if [[ $rc -ne 0 ]] ; then
		echo "Failed to upload $project/target/$bundle!"; exit $rc
	fi
	echo "Installation of $project/target/$bundle complete!"
done

echo "Running Integration tests..."
mvn test  -f launchpad/integration-tests/pom.xml  -Dtest=**/integrationtest/**/*Test.java
rc=$?
if [[ $rc -ne 0 ]] ; then
	echo "Integration Tests Failed!"; exit $rc
else
	echo "Integration Tests Succeeded!"
fi