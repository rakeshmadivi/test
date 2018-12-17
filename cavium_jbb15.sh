#!/bin/bash
set -x
LABEL="saber"
JAVA_PATH="auto"
JVM_URL="http://openjdk.linaro.org/releases/jdk9-server-release-1708.tar.xz"
JVM_VERSION="1708"
NUMA="any"
OPT_HEAP="auto"
OPT_DEBUG="NA"
OPT_GC="-XX:+UseParallelOldGC"
OPT_SERVER="-server"
OPT_SPEC="DRIVERS_AUTO WORKERS_AUTO"
FREEFORM_JAVA="NA"
FREEFORM_SPEC="NA"
NUM_OF_RUNS="1"
RATIO_WORKERS="1 0.5 0.3"
RATIO_DRIVERS="2 2 2"
THP_SET="always"
BUILD_NAME="specjbb"
FIXED_RT="0"
NUMA_BALANCING="0"
OPT_PREFETCH="0"
NGROUPS=`lscpu|grep "NUMA node(s)"|sed -e 's/.* //'`	#"2"
SYSCTL_TUNE="NA"
COREBIND="NA"
SPEC_TAR_DIR="" #FILL UP SPEC TAR DIR
WORKSPACE=`pwd`
#----- setup specjbb and scripts ----
cd $WORKSPACE
VER=1.02
FILE_NAME=specjbb2015-${VER}.tar.gz
if [ ! -f specjbb2015/${FILE_NAME} ] ; then 
 mkdir -p specjbb2015
 pushd specjbb2015
 wget ${SPEC_TAR_DIR}/${FILE_NAME}
 popd
fi

TESTVER=`grep $VER specjbb2015/version.txt || echo "TODO"`
if [[ "$TESTVER" == "TODO" ]] ; then
 pushd specjbb2015
 tar xf ${FILE_NAME}
 if [ ! -f specjbb2015.jar ] ; then 
  echo "Can't find specjbb jar" ; false 
 fi
 TESTVER=`grep $VER version.txt || echo "TODO"`
 if [[ "$TESTVER" == "TODO" ]] ; then
  echo "Version mismatch" ; false 
 fi 
 popd
fi

if [ -f /mnt/nas/benchmarks/specjbb/c-generator.sh ] ; then 
	cd specjbb2015
    cp -r /mnt/nas/benchmarks/specjbb/c-generator* .
fi
bc <<< "1+1" 2> /dev/null || sudo apt install -y bc

echo "==== SYSTEM INFO ===="
uname -a
tail /proc/cpuinfo
grep DISTRIB_DESCRIPTION /etc/lsb-release || lsb_release -a || echo "LSB info not available"
echo -n "CPU count: "
grep  -c  "processor" /proc/cpuinfo

echo "============================================"
cat /proc/meminfo | grep Mem  

cat /proc/meminfo | grep Huge   

echo -n "transparent_hugepage/enabled: "
cat /sys/kernel/mm/transparent_hugepage/enabled 

echo "============================================"

grep -s -H .* /proc/sys/kernel/sched_* || true
echo good
grep -s -H .* /proc/sys/kernel/randomize_va_space /proc/sys/kernel/numa_balancing || true

echo "============================================"

if [[ "$THP_SET" != "NA" ]] ; then 
	echo $THP_SET | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
fi
echo "$NUMA_BALANCING" | sudo tee /proc/sys/kernel/numa_balancing
if [[ "$SYSCTL_TUNE" != "NA" ]] ; then 
	for val in $SYSCTL_TUNE ; do
    	sudo sysctl $val || echo "Kernel does not support $val"
    done
fi

#==============================================================
: '
if [[ "$JVM_URL" != "NA" ]] ; then
	cd $WORKSPACE
	JVM_URL=`echo $JVM_URL | sed -e "s/JVM_VERSION/$JVM_VERSION/"`
    fname=`basename $JVM_URL`
    dname=`echo $fname | sed -e ': 's/\.[^.]*$//': '`
    if [ ! -f $fname ] ; then wget $JVM_URL ; fi
    if [ ! -d $dname ] ; then 
    	mkdir z ; cd z
    	tar xf ../$fname 
        mv * ../$dname
        cd .. ; rmdir z
    fi
  	export JAVA_HOME=$WORKSPACE/$dname
  	export PATH=$JAVA_HOME/bin:$PATH
fi
'
echo "==== Get cores/threads info ===="

which java
java -version

#echo Exiting here....;exit

NODE="ALL"
THREADS=`grep  -c  "processor" /proc/cpuinfo`
THREADS_PER_CORE=`cat /sys/devices/system/cpu/cpu0/topology/thread_siblings_list | tr ',' ' ' | wc -w`
if [[ $NUMA == *"Node"* ]] ; then 
	NODE=`echo $NUMA | sed 's/.* //'`
	NCTL="numactl -m $NODE -N $NODE" 
    THREADS=`numactl -H | grep "node $NODE cpus" | cut -d ':' -f 2 | wc -w`
    OPT_SPEC="$OPT_SPEC -XX:-UseNUMA"
    NUM_NODES=1
fi
if [[ $NUMA == *"any"* ]] ; then 
	if (( $NGROUPS < 2 )) ; then 
    OPT_SPEC="$OPT_SPEC -XX:+UseNUMA -XX:-UseNUMAInterleaving"
    else 
    OPT_SPEC="$OPT_SPEC -XX:-UseNUMA -XX:-UseNUMAInterleaving"
    fi
    NUM_NODES=`lscpu | grep 'node(s)' | sed -e 's/.* //'`
fi
if [[ $NUMA == *"single core"* ]] ; then 
    NODE=`echo $NUMA | sed 's/.* //'`
	N0CORE=$[$NODE+1]
	TS=`cat /sys/devices/system/cpu/cpu${N0CORE}/topology/thread_siblings_list`
	NCTL="numactl -m $NODE -C $TS" 
    THREADS=$THREADS_PER_CORE
    OPT_SPEC="$OPT_SPEC -XX:-UseNUMA"
    NUM_NODES=1
fi
CORES=$[$THREADS/$THREADS_PER_CORE]
HALF_THREADS=$[$THREADS/2]
GC_THREADS=$[$HALF_THREADS/2]
OPT_GC="$OPT_GC -XX:ParallelGCThreads=$HALF_THREADS"
threads_per_group=$[$THREADS/2]

echo "==== SPECjbb ===="

cd $WORKSPACE/specjbb2015
chmod +x *.sh

pagesize=`getconf PAGE_SIZE`
if [[ "$pagesize" == "65536" ]] ; then 
	SUB=$[50+2*2]
else
	SUB=$[20+2*2]
fi
if [[ "$OPT_HEAP" == "auto" ]] ; then
 if [[ "$NODE" == "ALL" ]] ; then
    DDRmem=`cat /proc/meminfo | grep MemTotal | perl -p -e 's/.*:\s*(\d+).*/\1/'`
    DDMB=$[$DDRmem/1024]
 else
 	#For single node, reserve only 12g with 4k pages [64k and huge pages can fail with less than 32g reserved on single socket]
    which numactl || sudo apt install -y numactl
 	DDMB=`numactl -H | grep "node $NODE size" | cut -d ' ' -f 4`
    pagesize=`getconf PAGE_SIZE`
    if [[ "$pagesize" == "4096" ]] ; then 
    	SUB=12
    fi
 fi
 DDGB=$[$DDMB/1024]
 MEMSIZE=$[${DDGB}-$SUB]
 MEMSIZE=$[$MEMSIZE/2]
else
 MEMSIZE=$OPT_HEAP
fi


which bc || sudo apt install -y bc
if (( $(bc <<< "$MEMSIZE < 100") )) ; then
	if (( $(bc <<< "$MEMSIZE < 32") )) ; then
     mb_to_use=$(bc <<< "($MEMSIZE * 1000)/1")
     mb_80_pct=$(bc <<< "($mb_to_use * .8)/1")
     MS="${mb_to_use}m"
     MX="${mb_to_use}m"
     MN="${mb_80_pct}m"
     OPT_SPEC="$OPT_SPEC"
    else
     MS=${MEMSIZE}g
     MX=${MEMSIZE}g
     MN=$[${MEMSIZE}-1]g
    fi
else
 MS=${MEMSIZE}g
 MX=${MEMSIZE}g
 MN=$[${MEMSIZE}-16]g
fi
PARM="-Xms$MS -Xmx$MX -Xmn$MN"

# Auto set workser/drivers if needed
if [[ "$OPT_SPEC" == *"WORKERS_AUTO"* ]] ; then
    WOPT=""
    echo "Ratio workers: $RATIO_WORKERS"
   	ratios=( index0 $RATIO_WORKERS )
	for tier in 1 2 3 ; do
    	workers=`bc <<< "(${ratios[$tier]}*$threads_per_group)/2"`
        WOPT="$WOPT -Dspecjbb.forkjoin.workers.Tier$tier=$workers"
	done
    OPT_SPEC=`echo $OPT_SPEC | sed -e "s/WORKERS_AUTO/$WOPT/"`
fi
if [[ "$OPT_SPEC" == *"DRIVERS_AUTO"* ]] ; then
    WOPT=""
   	ratios=( $RATIO_DRIVERS )
    names=( probe service saturate )
	for tier in 0 1 2 ; do
    	drivers=`bc <<< "(${ratios[$tier]}*$threads_per_group)/2"`
        #compliance for drivers
        if (( $drivers < 64 )) ; then drivers=64; fi
        name="specjbb.customerDriver.threads.${names[$tier]}"
        WOPT="$WOPT -D$name=$drivers"
	done
    OPT_SPEC=`echo $OPT_SPEC | sed -e "s/DRIVERS_AUTO/$WOPT/"`
fi
#Handle freeform options
if [[ "$OPT_SPEC" == "FREEFORM" ]] ; then
 SPEC_OPTS="$FREEFORM_SPEC"
else
 if [[ "$FREEFORM_SPEC" != "NA" ]] ; then
  SPEC_OPTS="$OPT_SPEC $FREEFORM_SPEC"
 else
  SPEC_OPTS="$OPT_SPEC"
 fi
fi

#Handle freeform in OPT_OPTIMIZE
if [[ "$OPT_OPTIMIZE" == "FREEFORM" ]] ; then
 OPT_OPTIMIZE=""
fi

#Add THP if set to madvise
if [[ "$THP_SET" == "madvise" ]] ; then
 OPT_OPTIMIZE="$OPT_OPTIMIZE -XX:+UseTransparentHugePages -XX:+UseLargePagesInMetaspace"
fi

if [[ "$OPT_PREFETCH" == *"XX"* ]] ; then 
 OPT_OPTIMIZE="$OPT_OPTIMIZE $OPT_PREFETCH"
fi

# Java options for Composite JVM
#Note: AggressiveHeap flag broken in JDK9!


if [[ "$OPT_JAVA" == "FREEFORM" ]] ; then
 JAVA_OPTS="$FREEFORM_JAVA"
else

 if [[ "$FREEFORM_JAVA" != "NA" ]] ; then
  JAVA_OPTS="$MPARM $OPT_GC $OPT_OPTIMIZE $FREEFORM_JAVA"
 else
  JAVA_OPTS="$MPARM $OPT_GC $OPT_OPTIMIZE"
 fi
 
 if [[ "$OPT_DEBUG" != "NA" ]] ; then
  JAVA_OPTS="$JAVA_OPTS $OPT_DEBUG"
 fi
fi
java --add-modules ALL-SYSTEM -version 2>&1 | grep "Unrecognized option" || BASE_OPTS="--add-modules ALL-SYSTEM "
java --addmods ALL-SYSTEM -version 2>&1 | grep "Unrecognized option" || BASE_OPTS="--addmods ALL-SYSTEM "

JAVA_OPTS_BE="$BASE_OPTS $JAVA_OPTS"
JAVA_OPTS_C="$BASE_OPTS -Xms2g -Xmx3g -Xmn1536m"
JAVA_OPTS_TI="$BASE_OPTS -Xms2g -Xmx3g -Xmn1536m"
SPEC_OPTS_C="-Dspecjbb.group.count=$NGROUPS -Dspecjbb.txi.pergroup.count=1 $SPEC_OPTS"
SPEC_OPTS_TI="$SPEC_OPTS"
SPEC_OPTS_BE="$SPEC_OPTS"

#Handle fixed RT
if (( $FIXED_RT > 0 )) ; then
  SPEC_OPTS_C="$SPEC_OPTS_C -Dspecjbb.controller.maxir.maxFailedPoints=1 \
  -Dspecjbb.controller.preset.ir=$FIXED_RT \
  -Dspecjbb.controller.rtcurve.start=0.45 \
  -Dspecjbb.controller.rtcurve.step=0.04 \
  -Dspecjbb.controller.rtcurve.warmup.step=0.5 \
  -Dspecjbb.controller.type=FIXED_RT"
fi


# Optional arguments for 
MODE_ARGS=""

JAVA=`which java`

which $JAVA > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Could not find a 'java' executable. Please set the JAVA environment variable or update the PATH."
    exit 1
fi

DATE=$(date '+%y-%m-%d_%H%M%S')
rm -f command.txt

run_controller() {
  echo "Start Controller JVM"
  CMD="$JAVA $JAVA_OPTS_C $SPEC_OPTS_C -jar ../specjbb2015.jar -m MULTICONTROLLER $MODE_ARGS_C"
  echo "$CMD" >> ../command.txt
  $CMD  2>controller.log > controller.out &
  
  CTRL_PID=$!
  echo "Controller PID = $CTRL_PID"

  sleep 3
}

run_group() {

    GID=$1
    NID=$2
    nodecpus=`lscpu | grep "NUMA node${2}"| sed -e 's/.* //'`
    NCTL="numactl --localalloc"
    #first_core=$[$GID*$threads_per_group]
    #last_core=$[($GID+1)*$threads_per_group-1]
  	NCTL="$NCTL -C $nodecpus"	#$first_core-$last_core"

    GROUPID=Group$GID
    echo -e "\nStarting JVMs from $GROUPID: on node $NID cores $nodecpus"	#$first_core-$last_core"
    sleep 3
    JVMID=txiJVM
    TI_NAME=$GROUPID.TxInjector.$JVMID
    CMD_TXI="$JAVA $JAVA_OPTS_TI $SPEC_OPTS_TI -jar ../specjbb2015.jar -m TXINJECTOR -G=$GROUPID -J=$JVMID $MODE_ARGS_TI" 
    echo "$NCTL $CMD_TXI" >> ../command.txt
    $NCTL $CMD_TXI > $TI_NAME.log 2>&1 &
    echo -e "\t$TI_NAME PID = $!"
    sleep 1


    JVMID=beJVM
    BE_NAME=$GROUPID.$JVMID
    
    # DEBUG_OPTS="-XX:+UnlockDiagnosticVMOptions -XX:+LogVMOutput -XX:LogFile=$BE_NAME.vm.log -Xlog:gc=debug,heap*=debug,phases*=debug,gc+age=debug:$BE_NAME.gc.log"
	  DEBUG_OPTS=""
    
    CMD_BE="$JAVA $JAVA_OPTS_BE $SPEC_OPTS_BE $DEBUG_OPTS -jar ../specjbb2015.jar -m BACKEND -G=$GROUPID -J=$JVMID $MODE_ARGS_BE"
    echo $CMD_BE > $BE_NAME.java_command.txt
    echo "$NCTL $CMD_BE" >> ../command.txt
    $NCTL $CMD_BE > $BE_NAME.log 2>&1 &
    echo -e "\t$BE_NAME PID = $!"
    sleep 1
}


echo Running $JAVA...
for ((n=1; $n<=$NUM_OF_RUNS; n=$n+1)); do

  # Create result directory                
  result=./${DATE}.$n
  mkdir $result

  # Copy current config to the result directory
  cp -r config $result

  if [ -f c-generator.sh ] ; then
    sudo env JAVA="$JAVA" \
    SPEC_OPTS_C="\"$SPEC_OPTS_C\"" SPEC_OPTS_TI="\"$SPEC_OPTS_TI\"" SPEC_OPTS_BE="\"$SPEC_OPTS_BE\"" \
    JAVA_OPTS_C="\"$JAVA_OPTS_C\"" JAVA_OPTS_TI="\"$JAVA_OPTS_TI\"" JAVA_OPTS_BE="\"$JAVA_OPTS_BE\"" \
    JVM_TUNING="\"$NCTL\"" ./c-generator.sh M
    mv generated-template.raw $result/config/template-M.raw
  fi 
  cd $result

  echo "Run $n: $timestamp"
  echo "Launching SPECjbb2015 in multijvm mode..."
  echo

  run_controller
  for group in `seq 1 4` ; do
  	ID=$[$group-1]
  	run_group $ID $[$ID % $NUM_NODES] 
  done

  echo "Please monitor $result/controller.log and $result/controller.out for progress"

  wait $CTRL_PID
  echo "SPECjbb2015 has finished"
  echo

  export SPEC_RAW=`find result -name \*.html -exec grep title {} \;`
  export SPEC_RESULTS=`echo $SPEC_RAW|awk '{ print "Max="$6 "/ Crit=" $9 }'`
  if [[ $SPEC_RAW == "" ]]
  then
    SPEC_RESULTS="JVM crashed!"
    exit 1
  fi

  MAX=$(echo $SPEC_RAW | awk '{print $6}')
  CRIT=$(echo $SPEC_RAW | awk '{print $9}')
  JV=`java -version 2>&1 | head -1`
  echo -e "$DATE,$HOSTNAME,2,$JV,$JAVA_OPTS,$SPEC_OPTS,$MAX,$CRIT" >> ../scores.csv

 cd ..

done

if [[ "$MAX" == "N/A" ]] ; then MAX=0 ; fi
if [[ "$CRIT" == "N/A" ]] ; then CRIT=0 ; fi
#--- jenkins bnechmark tables tracker
NID=`. /mnt/nas/scripts/nodeID/nodeID-basic.sh`
echo "{" > tracking.json
echo " \"$NID\": {" >> tracking.json
echo "	\"params\" : \"2,$JAVA_OPTS,$SPEC_OPTS\"," >> tracking.json
echo "	\"max-jops\" : $MAX," >> tracking.json
echo "	\"crit-jops\" : $CRIT" >> tracking.json
echo " }" >> tracking.json
echo "}" >> tracking.json

mv tracking.json $WORKSPACE

#------------------------ end of specjbb run ----
rm -rf data
mkdir -p data
cp -r $DATE* command.txt data
pushd data
  $JAVA -version > settings.txt 2>&1
  echo "OPTIONS: $JAVA_OPTS $SPEC_OPTS" >> settings.txt
  uname -a >> settings.txt 2>&1
  getconf PAGE_SIZE >> settings.txt
  thp_state=`cat /sys/kernel/mm/transparent_hugepage/enabled`
  echo "THP: $thp_state" >> settings.txt
  numa_state=`cat /proc/sys/kernel/numa_balancing`
  echo "NUMA BALANCING: $numa_state" >> settings.txt
  lscpu >> settings.txt 2>&1
  tail /proc/cpuinfo >> settings.txt
  sudo sysctl -a >> settings.txt 2>&1
  cat /proc/meminfo >> settings.txt
  sudo dmidecode > demidecode.txt 2>&1
  cat /proc/vmstat | egrep "compact|thp" > thpstat.txt
popd

tar -cjf $WORKSPACE/specjbb2015-data.tar.bz2 data

