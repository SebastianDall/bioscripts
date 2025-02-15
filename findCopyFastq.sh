#!/usr/bin/env bash
set -eu

#default options
fastq="/space/sequences/Illumina/"
input="samples"
output="fastq"
samplesep="_"
doCopy="yes"
nfind=${nfind:-2}
if command -v fdfind 1> /dev/null
then
  cmd="fdfind"
else
  cmd="find"
fi

#default error message if bad usage
usageError() {
  echo "Error: $1" 1>&2
  echo ""
  eval "bash $0 -h"
}

while getopts ":hi:f:o:s:d" opt
do
case ${opt} in
  h )
    echo "Find and copy fastq files. Reports for each sample how many files were found and copied."
    echo "Options:"
    echo "  -h    Display this help text and exit."
    echo -e "  -i    (Required) Path to file containing sample ID's to find and copy. One sample ID per line. \n          (Default: ${input})"
    echo -e "  -f    (Required) Path to folder containing fastq files (will be searched recursively). \n          (Default: ${fastq})"
    echo -e "  -o    (Required) Output folder to copy fastq files into. \n          (Default: ${output})"
    echo -e "  -d    (flag) Don't copy the files, instead only report whether they are found or not."
    echo -e "  -s    Separator to append after sample name. \n          (Default: ${samplesep})"
    echo
    echo -e "Additional options can be set by exporting environment variables before running the script:"
    echo -e "  - nfind: Max number of files to find per sample ID. The search will be aborted after the first nfind hits. Useful for speeding up things if fx only the forward read (R1) is needed. (Default: ${nfind})"
    exit 1
    ;;
  i )
    input="$OPTARG"
    ;;
  f )
    fastq="$OPTARG"
    ;;
  o )
    output="$OPTARG"
    ;;
  s )
    samplesep="$OPTARG"
    ;;
  d )
    doCopy="no"
  ;;
  \? )
    usageError "Invalid Option: -$OPTARG"
    exit 1
    ;;
  : )
    usageError "Option -$OPTARG requires an argument"
    exit 1
    ;;
esac
done
shift $((OPTIND -1)) #reset option pointer

# check options
if [ ! -s "$input" ]
then
  usageError "File '${input}' does not exist or is empty"
  exit 1
fi
if [ ! -d "$fastq" ]
then
  usageError "Directory '${fastq}' does not exist"
  exit 1
fi

mkdir -p "$output"

#clean samples file
  tr "\r" "\n" < "$input" |\
  sed -e '$a\' |\
  sed -e '/^$/d' -e 's/ //g' > "${output}/samples.txt"

nsamples=$(wc -w < "${output}/samples.txt")
echo "Searching for ${nsamples} sample(s) in $fastq (only first hits)..."
if [ $doCopy == "yes" ]
then
  echo "Copying files into $(realpath -m "$output")"
fi
i=0
notFound=0
while ((i++)); read -r sample
do
  echo -n "  - ($i/$nsamples) $sample: "
  #find the sample fastq file
  fileStatus=$(
    if [ "$cmd" == "fdfind" ]
    then
      #fdfind is just blazing
      $cmd -s \
        -g "*${sample}${samplesep}*" \
        -L \
        -t file -t symlink \
        -e gz -e fastq -e fq \
        --max-results 1 \
        "$fastq"
    elif [ "$cmd" == "find" ]
    then
      #use head -n x to stop find from searching further after the first x hits
      #use "|| true" to avoid exiting when the find command doesn't 
      #have permission to access some files/folders
      $cmd -L "$fastq" \
          -type f \
          -name "*${sample}${samplesep}*.f*q*" \
          2> /dev/null |\
        head -n "$nfind" \
        || true
    fi
  )
  if [ -z "$fileStatus" ]
  then
    echo "not found"
    ((notFound=notFound+1))
  elif [ -n "$fileStatus" ]
  then
    echo -e "found at: \n$fileStatus"
    if [ $doCopy == "yes" ]
    then
      #--max-results can't be used together with --exec, so separate cp command
      # shellcheck disable=SC2086
      cp $fileStatus -fvt "$output"
    fi
    echo -e "\n"
  fi
done < "${output}/samples.txt"

echo
if [ "$notFound" != "0" ]
then
  echo "$notFound sample(s) couldn't be found"
else
  echo "All $nsamples samples were found"
fi
