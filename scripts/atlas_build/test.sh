#/bin/sh
BUILDS_INFO="$HOME/scripts/builds_info.txt"
while read line; do
BUILD_NUMBER=$(echo $line | cut -d "|" -f 1)
BUILD_NUMBER2=$(echo $line | cut -d "|" -f 2)
BUILD_NAME=$(echo $line | cut -d "|" -f 3)
BUILD_FLAGS=$(echo $line | cut -d "|" -f 4)
HPL_OPT_FLAGS=$(echo $line | cut -d "|" -f 5)
HPL_FLAGS=$(echo $line | cut -d "|" -f 6)
echo $BUILD_NUMBER
echo $BUILD_NUMBER2
echo $BUILD_NAME
echo $BUILD_FLAGS
echo $HPL_OPT_FLAGS
echo $HPL_FLAGS
echo "============"
done < $BUILDS_INFO
