#!/bin/bash
#
# Extract contents of a tape. Each session on the tape is extracted as a separate file.
#
# Script must be executed as root (sudo)
#

# **************
# Functions
# **************

getUserInput ()
{   # Get user input through GUI dialog
    userInput=$(yad --width=400 --title="Read tape" \
    --form \
    --field="Output Directory":DIR "$DIR" \
    --field="Tape Device" "$tapeDevice" \
    --field="Initial Block Size":NUM "$blockSize"[!"$blockSize"..10485760[!512![!0]]] \
    --field="Sessions" "$sessions" \
    --field="Prefix" "$prefix" \
    --field="Extension" "$extension" \
    --field="Fill failed blocks":CHK $fill \
    )
}

findBlocksize ()
{   # Find block size for this session

    # Initial block size
    bSize="$blockSize"
    # Flag that indicates block size was found
    bSizeFound="false"

    while [ "$bSizeFound" == "false" ]
    do
        # Try reading 1 block from tape
        echo "*** Guessing block size for session # ""$session"", trial value ""$bSize"" ***" >> "$logFile"
        dd if="$tapeDevice" of=/dev/null bs="$bSize" count=1 >> "$logFile" 2>&1
        ddStatus="$?"
        # Position tape 1 record backward (i.e. to the start of this session)
        mt -f "$tapeDevice" bsr 1 >> "$logFile" 2>&1
        if [[ "$ddStatus" -eq 0 ]]; then
            # dd exit status 0: block size found
            bSizeFound="true"
        else
            # dd exit status not 0, try again with larger block size
            let bSize="$bSize"+512
        fi
    done
}

processSession ()
{   # Process one session

    if [ "$extractSession" = "true" ] ; then
        # Determine block size for this session
        findBlocksize
        echo "*** Block size = ""$bSize"" ***" >> "$logFile"

        # Name of output file for this session
        ofName="$dirOut"/""$prefix""`printf "%06g" "$session"`."$extension"

        echo "*** Extracting session # ""$session"" to file ""$ofName"" ***" >> "$logFile"

        if [ "$fill" = "TRUE" ] ; then
            # Invoke dd with conv=noerror,sync options
            dd if="$tapeDevice" of="$ofName" bs="$bSize" conv=noerror,sync >> "$logFile" 2>&1
        else
            dd if="$tapeDevice" of="$ofName" bs="$bSize" >> "$logFile" 2>&1
        fi

        ddStatus="$?"
        echo "*** dd exit code = " "$ddStatus"" ***" >> "$logFile"
    else
        # Fast-forward tape to next session
        echo "*** Skipping session # ""$session"", fast-forward to next session ***" >> "$logFile"
        mt -f "$tapeDevice" fsf 1 >> "$logFile" 2>&1
    fi

    # Try to position tape 1 record forward; if this fails this means
    # the end of the tape was reached
    mt -f "$tapeDevice" fsr 1 >> "$logFile" 2>&1
    mtStatus="$?"
    echo "*** mt exit code = " "$mtStatus"" ***" >> "$logFile"

    if [[ "$mtStatus" -eq 0 ]]; then
        # Another session exists. Position tape one record backward
        mt -f "$tapeDevice" bsr 1 >> "$logFile" 2>&1
    else
        # No further sessions, end of tape reached
        echo "*** Reached end of tape ***" >> "$logFile"
        endOfTape="true"
    fi
}

# **************
# Main code
# **************

# Initialize command user-defined variables

# Non-rewind tape device
tapeDevice="/dev/nst0"
# Initial block size
blockSize="512"
sessions=""
# Output prefix
prefix="session"
# Output extension
extension="dd"
fill="FALSE"

# Get user input through GUI
getUserInput

# Parse yad output into variables
dirOut="$(cut -d'|' -f1 <<<$userInput)"
tapeDevice="$(cut -d'|' -f2 <<<$userInput)"
blockSize="$(cut -d'|' -f3 <<<$userInput)"
# Needed because yad adds ",0000" to numerical value, apparently this 
# fix is not needed with mthe most recent version of yad
blockSize="$(cut -d',' -f1 <<<"$blockSize")"
sessions="$(cut -d'|' -f4 <<<$userInput)"
prefix="$(cut -d'|' -f5 <<<$userInput)"
extension="$(cut -d'|' -f6 <<<$userInput)"
fill="$(cut -d'|' -f7 <<<$userInput)"

if ! [ -d "$dirOut" ] ; then
    echo "ERROR: dirOut must be a directory" >&2
    exit 1
fi

# Log file
logFile="$dirOut""/readtape.log"

# Remove log file if it already exists
if [ -f "$logFile" ] ; then
    rm "$logFile"
fi

# Write some general info to log file
echo "*** Tape extraction log ***" >> "$logFile"
dateStart="$(date)"
echo "*** Start date/time ""$dateStart"" ***" >> "$logFile"
echo "*** Command-line arguments ***" >> "$logFile"
echo "dirOut = ""$dirOut" >> "$logFile"
echo "fill = ""$fill" >> "$logFile"
echo "tapeDevice = ""$tapeDevice" >> "$logFile" 
echo "blockSize = ""$blockSize" >> "$logFile"
echo "sessions = ""$sessions" >> "$logFile"
echo "prefix = ""$prefix" >> "$logFile"
echo "extension = ""$extension" >> "$logFile"

# Check if block size is valid (i.e. a multiple of 512) by comparing integer
# division of blockSize by 512 against floating-point division
blocksInt=$(($blockSize / 512))
blocksFloat=$(echo "$blockSize/512" | bc -l )
# This yields 1 if block size is valid, and 0 otherwise 
blocksizeValid=$(echo "$blocksInt == $blocksFloat" |bc -l)

if ! [ "$blocksizeValid" -eq 1 ] ; then
    echo "ERROR: invalid blockSize, must be a multiple of 512!" >&2
    exit 1
fi

if [ "$fill" = "TRUE" ] ; then
    # dd's conv=sync flag results in padding bytes for each block if block 
    # size is too large, so override user-defined value with default
    # if -f flag was used
    blockSize=512
    echo "*** Reset blockSize to 512 because -f flag is used  ***" >> "$logFile"
fi

# Flag that indicates end of tape was reached
endOfTape="false"
# Session index
session="1"

# Get tape status, output to log file
echo "*** Tape status ***" >> "$logFile"
mt -f "$tapeDevice" status >> "$logFile"

# Iterate over all sessions on tape until end is detected
while [ "$endOfTape" == "false" ]
do
    # Set initial value of extractSessionFlag depending on sessions parameter
    if [ -z "$sessions" ] ; then
        extractSession="true"
    else
        extractSession="false"
    fi

    # Only extract sessions defined by sessions parameter
    # (if session parameter is empty all sessions are extracted)
    for i in ${sessions//,/ }
        do
            if [ "$i" == "$session" ] ; then
                extractSession="true"
            fi
    done

    # Call session processing function 
    processSession
    # Increase session number
    let session="$session"+1
done

# Create checksum file
workDir="$PWD"
cd "$dirOut"
checksumFile="$prefix"".sha512"
sha512sum *."$extension" > "$checksumFile"
cd "$workDir"
echo "*** Created checksum file ***" >> "$logFile"

# Rewind and eject the tape
echo "*** Rewinding tape ***" >> "$logFile"
mt -f "$tapeDevice" rewind >> "$logFile" 2>&1
echo "*** Ejecting tape ***" >> "$logFile"
mt -f "$tapeDevice" eject >> "$logFile" 2>&1

# Write end date/time to log
dateEnd="$(date)"
echo "*** End date/time ""$dateEnd"" ***" >> "$logFile"