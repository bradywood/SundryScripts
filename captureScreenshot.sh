#!/bin/bash
echo "Screenshot Capture Script"
##
## This script will capture Screenshot (every 0.1 seconds) of an automated GUI (for ex: Selenium tests) tests running behind a HEADLESS Xvfb display instance.
## Then, it'll create a mp4 format movie using the captured screenshots.
##
## Machine where you run this script, should have: Xvfb service running, a session started by Xvfb plugin via Jenkins, xwd,ffmpeg OS commands and imagemagick (utilities).
## - For ex, try this on RHEL to install imagemagick:  yum install imagemagick
##
## Variables
ws=$1;                                                  ## Workspace folder location
d=$2; d=$(echo $d | tr -d ':');                         ## Display number associated with the Xvfb instance started by Xvfb plugin from a Jenkins job
wscapdir=${ws}/capturebrowserss;                        ## Workspace capture browser's screen shot folder
if [[ -n $3 ]]; then wscapdir=${wscapdir}/$3; fi        ## If a user pass a 3rd parameter i.e. a Jenkins BUILD_NUMBER, then create a child directory with that name to archive that specific run.

echo "using settings ws=${ws} wscapdir=${wscapdir}"

i=1;
a=1
rm -fr ${wscapdir} 2>/dev/null || ( echo - Oh Oh.. Cant remove ${wscapdir} folder; echo -e "-- Still exiting gracefully! \n"; exit 0);
mkdir -p ${wscapdir}
while : ; do
 ssFile=${wscapdir}/capFile_${d}_dispId`printf "%08d" $i`.png
 xwd -root -display :$d 2>/dev/null | convert xwd:- ${ssFile} ;

 echo "captured ${i}"

 if [[ ${PIPESTATUS[0]} -gt 0 || ${PIPESTATUS[1]} -gt 0 ]]; then 
    echo -e "\n-- Something bad happened during xwd or imagemagick convert command, manually check it.\n";
    echo "Stopping captures"
    break;
 fi

 command="convert ${ssFile} -format \"%[mean]\" info:"  ;

 echo "Executing: ${command}" ;

 mean=`${command}`;
  
 echo "Average colour of ${ssFile} is '${mean}' " ;
 
 if [ "${mean}" = "\"0\"" ]; then
   echo "---> deleting" ;
   rm ${ssFile} -f ;
 else
   echo "---> renaming" ;
   newName=$(printf "${wscapdir}/cleaned.%08d.png" "$a") ;
   mv -- ${ssFile} ${newName} ;
   let a=a+1;
 fi

 if [ "$i" -gt "1500" ]; then break; fi

 ((i++));
 sleep 0.1;
done

echo "Long Loop"

EOF

cat << 'EOF' > /tmp/createVideo.sh
#!/bin/bash
echo "Video Encoding Script"
## Variables
ws=$1;                                                  ## Workspace folder location
d=$2; d=$(echo $d | tr -d ':');                         ## Display number associated with the Xvfb instance started by Xvfb plugin from a Jenkins job
wscapdir=${ws}/capturebrowserss;                        ## Workspace capture browser's screen shot folder
if [[ -n $3 ]]; then wscapdir=${wscapdir}/$3; fi        ## If a user pass a 3rd parameter i.e. a Jenkins BUILD_NUMBER, then create a child directory with that name to archive that specific run.

echo "using settings ws=${ws} wscapdir=${wscapdir}"

/usr/bin/ffmpeg -pattern_type sequence -framerate 5 -i ${wscapdir}/cleaned.%08d.png -c:v libx264 -r 30 -pix_fmt yuv420p ${wscapdir}/outputVideo.mp4 

EOF
