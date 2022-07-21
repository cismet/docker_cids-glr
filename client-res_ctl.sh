#!/bin/bash
DIR=$(dirname "$(readlink -f "$0")")
PATH="${PATH}:${JAVA_HOME}/bin"

#####

SESSION="$(echo ${RANDOM} | md5sum | head -c 8)"
TMP="/tmp/${SESSION}"

LOCAL="${CIDS_DISTRIBUTION_DIR}/lib/local${CIDS_EXTENSION}"

KEYSTORE="${CIDS_DISTRIBUTION_DIR}/signing/keystore.jks"
KEYSTORE_PASS=$(cat "${CIDS_DISTRIBUTION_DIR}/signing/keystore.pass")
CLERKSTER_CREDS=$(cat "${CIDS_DISTRIBUTION_DIR}/signing/clerkster.creds")
CLERKSTER_USER=$(echo ${CLERKSTER_CREDS} | cut -d ":" -f 1)
CLERKSTER_PASS=$(echo ${CLERKSTER_CREDS} | cut -d ":" -f 2)

APPS="${CIDS_DISTRIBUTION_DIR}/apps"
APPLIBS="${APPS}/.libs"

#####

function unpackJars {
    TO="$1"; shift
    FROM="$*"
    echo "unpacking jars for finding changes..."
    for fromPath in ${FROM}; do 
        if [ -f ${fromPath} ]; then unpackJar "$TO" "${fromPath}"; fi
    done
}
function unpackJar {
    destDir="$1"
    srcPath="$2"
    destPath="${destDir}/$(basename "${srcPath%%.jar}")"
    echo " * ${srcPath} => ${destPath}"
    unzip -qq "${srcPath}" -d "${destPath}"
}

function diffUnpackedJars {
    TO="$1"; shift
    FROM="$*"
    arrVar=()
    for fromPath in ${FROM}; do 
        diffUnpackedJar "$TO" "${fromPath}"
        if [ $? -ne 0 ]; then
            echo "${fromPath}"
        fi
    done
}
function diffUnpackedJar {
    destDir="$1"
    srcPath="$2"
    destPath="${destDir}/$(basename "${srcPath}")"
    diff --exclude="META-INF" -r "${srcPath}" "${destPath}" > /dev/null
    return $?
}

function buildJars {
    TO="$1"; shift
    FROM="$*"
    echo "building jars ..."
    for fromPath in ${FROM}; do 
        if [ -d ${fromPath} ]; then buildJar "$TO" "${fromPath}"; fi
    done
}
function buildJar {
    destDir="$1"
    srcPath="$2"
    destPath="${destDir}/$(basename "${srcPath}").jar"
    echo " * ${srcPath} => ${destPath}"
    jar cf "${destPath}" -C "${srcPath}" . 
}

function selfSignJars {
    TO="$1"; shift
    FROM="$*"
    echo "signing jars (self signed)..."
    for fromPath in ${FROM}; do 
        if [ -f ${fromPath} ]; then selfSignJar "${TO}" "${fromPath}"; fi
    done
}
function selfSignJar {
    destDir="$1"
    srcPath="$2"
    dstPath="${destDir}/$(basename "${srcPath}")"
    echo " * ${srcPath} => ${dstPath}"
    jarsigner -keystore "${KEYSTORE}" -signedjar "${dstPath}" "${srcPath}" wupp -storepass ${KEYSTORE_PASS} > /dev/null && \
    rm "${srcPath}"
}

function clerksterSignJars {
    TO="$1"; shift
    FROM="$*"
    echo "sending jars to clerkster (for signing with proper certificate) ..."
    for fromPath in ${FROM}; do 
        if [ -f ${fromPath} ]; then clerksterSignJar "${TO}" "$fromPath"; fi
    done
}
function clerksterSignJar {
    destDir="$1"
    srcPath="$2"
    dstPath="${destDir}/$(basename ${srcPath})"
    echo " * ${srcPath} => ${dstPath}"
    curl -s -u${CLERKSTER_USER}:${CLERKSTER_PASS} -X POST -H "Content-Type: multipart/form-data" -F "upload=@${srcPath}" https://clerkster.cismet.de/upload > "${dstPath}" && \
    rm "${srcPath}"
}

function deployJars {
    TO="$1"; shift
    FROM="$*"
    echo "deploying jars ..."
    for fromPath in ${FROM}; do 
        if [ -f ${fromPath} ]; then deployJar "${TO}" "${fromPath}"; fi
    done
}
function deployJar {
    destDir="$1"
    srcPath="$2"
    destPath="${destDir}/$(basename ${srcPath%%.signed})"
    echo " * ${srcPath} => ${destPath}"
    cp ${srcPath} ${destPath} && \
    rm ${srcPath}
}

function getdownJars {
    FROM="$*"
    echo "copying jars for getdown starters ..."
    for fromPath in ${FROM}; do 
        if [ -f ${fromPath} ]; then getdownJar "${fromPath}"; fi
    done 
}
function getdownJar {
    srcPath="$1"    
    jarFilename=$(basename ${srcPath})
    targetname=${jarFilename%%.jar}-1.0.jar
    echo " * ${srcPath} => ${APPLIBS}/${targetname}"
    cp "${srcPath}" "${APPLIBS}/${targetname}"
}

function rebuildGetdownApps {
    echo "rebuilding getdown starters ..."
    for appDirname in $(ls -1d ${APPS}/* | egrep -h -v "\-public|\-public\-"); do 
        echo " * ${appDirname}"
        java -classpath "${CIDS_DISTRIBUTION_DIR}/lib/m2/com/threerings/getdown/getdown-core/1.8.6/getdown-core-1.8.6.jar" com.threerings.getdown.tools.Digester "${appDirname}" 2> /dev/null
    done
}

#####

function deployChangedJars {
    SOURCE="${LOCAL}/src/plain"
    UNPACKED="${TMP}/unpacked"
    UNSIGNED="${TMP}/unsigned"
    CLERKSTER_SIGNED="${TMP}/clerkster"
    SELF_SIGNED="${TMP}/signed"

    if [ ! -z "$1" ]; then SOURCE="$1"; shift; fi

    mkdir -p "${UNPACKED}" "${UNSIGNED}" "${SELF_SIGNED}" "${CLERKSTER_SIGNED}"

    unpackJars "${UNPACKED}" "${LOCAL}/*.jar"

    echo "searching for changed resources ..."
    diffs="$(diffUnpackedJars "${UNPACKED}" "${SOURCE}/*")"
    rm -r "${UNPACKED}"

    if [ -z "${diffs}" ]; then
        echo ""
        echo "no changes found, nothing to do"
    else
        buildJars "${UNSIGNED}" "${diffs}"
        selfSignJars "${SELF_SIGNED}" "${UNSIGNED}/*.jar"
        clerksterSignJars "${CLERKSTER_SIGNED}" "${SELF_SIGNED}/*.jar"
        deployJars "${LOCAL}" "${CLERKSTER_SIGNED}/*.jar"

        getdownJars "${LOCAL}"/*.jar    
        rebuildGetdownApps
    fi
    rmdir "${UNSIGNED}" "${SELF_SIGNED}" "${CLERKSTER_SIGNED}" "${TMP}"
}

### LOCAL_CTL ###

COMMAND="$1"; shift

case "$COMMAND" in
    
    rebuildGetdown)
        rebuildGetdownApps
    ;;
	
    deployChanged)
        SOURCE=$1; shift
        deployChangedJars $SOURCE
    ;;    

    *)
        echo "Usage: $0 rebuildGetdown|deployChanged"
    ;;

esac