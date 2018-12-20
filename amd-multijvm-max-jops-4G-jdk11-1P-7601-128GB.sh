#!/bin/bash

###############################################################################
# Sample script for running SPECjbb2015 in MultiJVM mode.
# 
# This sample script demonstrates running the Controller, TxInjector(s) and 
# Backend(s) in separate JVMs on the same server.
###############################################################################

pkill java
#tuned-adm profile throughput-performance

#Kernel Tuning
1P()
{
sudo sh -c "echo 990000 > /proc/sys/kernel/sched_rt_runtime_us"
sudo sh -c "echo 24000000 > /proc/sys/kernel/sched_latency_ns"
sudo sh -c "echo 10000 > /proc/sys/vm/dirty_expire_centisecs"
sudo sh -c "echo 1500 > /proc/sys/vm/dirty_writeback_centisecs"

sudo sh -c "echo 1000 > /proc/sys/kernel/sched_migration_cost_ns"
sudo sh -c "echo 10000000 > /proc/sys/kernel/sched_min_granularity_ns"
sudo sh -c "echo 15000000 > /proc/sys/kernel/sched_wakeup_granularity_ns"
sudo sh -c "echo 40 > /proc/sys/vm/dirty_ratio"
sudo sh -c "echo 10 > /proc/sys/vm/dirty_background_ratio"
sudo sh -c "echo 10 > /proc/sys/vm/swappiness"

sudo sh -c "echo always > /sys/kernel/mm/transparent_hugepage/defrag"
sudo sh -c "echo 0 > /proc/sys/kernel/numa_balancing"
}

1P_nosudo()
{
echo 990000 > /proc/sys/kernel/sched_rt_runtime_us
echo 24000000 > /proc/sys/kernel/sched_latency_ns
echo 10000 > /proc/sys/vm/dirty_expire_centisecs
echo 1500 > /proc/sys/vm/dirty_writeback_centisecs

echo 1000 > /proc/sys/kernel/sched_migration_cost_ns
echo 10000000 > /proc/sys/kernel/sched_min_granularity_ns
echo 15000000 > /proc/sys/kernel/sched_wakeup_granularity_ns
echo 40 > /proc/sys/vm/dirty_ratio
echo 10 > /proc/sys/vm/dirty_background_ratio
echo 10 > /proc/sys/vm/swappiness

echo always > /sys/kernel/mm/transparent_hugepage/defrag
echo 0 > /proc/sys/kernel/numa_balancing
}
# Launch command: java [options] -jar specjbb2015.jar [argument] [value] ...

# Number of Groups (TxInjectors mapped to Backend) to expect
GROUP_COUNT=$(lscpu|grep 'NUMA node(s)'|sed -e 's/.* //')

# Number of TxInjector JVMs to expect in each Group
TI_JVM_COUNT=1

# Benchmark options for Controller / TxInjector JVM / Backend
# Please use -Dproperty=value to override the default and property file value
# Please add -Dspecjbb.controller.host=$CTRL_IP (this host IP) to the benchmark options for the all components
# and -Dspecjbb.time.server=true to the benchmark options for Controller 
# when launching MultiJVM mode in virtual environment with Time Server located on the native host.

SPEC_OPTS_C=" -Dspecjbb.group.count=$GROUP_COUNT -Dspecjbb.txi.pergroup.count=$TI_JVM_COUNT -Dspecjbb.heartbeat.period=2000 -Dspecjbb.heartbeat.threshold=600000 -Dspecjbb.controller.handshake.timeout=800000 -Dspecjbb.forkjoin.workers.Tier1=180 -Dspecjbb.forkjoin.workers.Tier2=1 -Dspecjbb.forkjoin.workers.Tier3=22 -Dspecjbb.comm.connect.timeouts.connect=700000 -Dspecjbb.comm.connect.timeouts.read=700000 -Dspecjbb.comm.connect.timeouts.write=700000 -Dspecjbb.comm.connect.selector.runner.count=0 -Dspecjbb.mapreducer.pool.size=4"
SPEC_OPTS_TI="-Dspecjbb.comm.connect.client.pool.size=64 -Dspecjbb.comm.connect.worker.pool.max=64 -Dspecjbb.comm.connect.timeouts.connect=600000 -Dspecjbb.comm.connect.timeouts.read=600000 -Dspecjbb.comm.connect.timeouts.write=600000 -Dspecjbb.comm.connect.selector.runner.count=1 -Dspecjbb.mapreducer.pool.size=5"
SPEC_OPTS_BE="-Dspecjbb.comm.connect.client.pool.size=64 -Dspecjbb.comm.connect.worker.pool.max=64 -Dspecjbb.comm.connect.timeouts.connect=600000 -Dspecjbb.comm.connect.timeouts.read=600000 -Dspecjbb.comm.connect.timeouts.write=600000 -Dspecjbb.comm.connect.selector.runner.count=1 -Dspecjbb.mapreducer.pool.size=5"

# Java options for Controller / TxInjector / Backend JVM
JAVA_OPTS_C="-Xms2g -Xmx2g -Xmn1536m -XX:+UseParallelOldGC "
JAVA_OPTS_TI="-Xms2g -Xmx2g -Xmn1536m -XX:+UseParallelOldGC "
JAVA_OPTS_BE="-showversion -server -XX:AllocatePrefetchInstr=2 -XX:LargePageSizeInBytes=2m -XX:-UsePerfData -XX:+AggressiveOpts -XX:-UseAdaptiveSizePolicy -XX:+AlwaysPreTouch -XX:-UseBiasedLocking -XX:+UseLargePages -XX:+UseParallelOldGC -Xms27g -Xmx27g -Xmn25g -XX:SurvivorRatio=23 -XX:TargetSurvivorRatio=98 -XX:ParallelGCThreads=16 -XX:MaxTenuringThreshold=15 -Xnoclassgc -XX:InlineSmallCode=10k -XX:MaxGCPauseMillis=300 -XX:ThreadStackSize=1m -XX:+PrintFlagsFinal "

# Optional arguments for multiController / TxInjector / Backend mode 
# For more info please use: java -jar specjbb2015.jar -m <mode> -h
MODE_ARGS_C=""
MODE_ARGS_TI=""
MODE_ARGS_BE=""

# Number of successive runs
NUM_OF_RUNS=1

###############################################################################
# This benchmark requires a JDK7 compliant Java VM.  If such a JVM is not on
# your path already you must set the JAVA environment variable to point to
# where the 'java' executable can be found.
###############################################################################

#Openjdk Java Path
JAVA=`which java`	#/home/amd/openjdk11/jdk-11.0.1/bin/java

which java > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Could not find a 'java' executable. Please set the JAVA environment variable or update the PATH."
    exit 1
fi

for ((n=1; $n<=$NUM_OF_RUNS; n=$n+1)); do

  # Create result directory                
  timestamp=$(date '+%y-%m-%d_%H%M%S')
  result=./$timestamp
  mkdir $result
  cp $0 $result

  # Copy current config to the result directory
  cp -r config $result

  cd $result

  echo "Run $n: $timestamp"
  echo "Launching SPECjbb2015 in MultiJVM mode..."
  echo

  echo "Start Controller JVM"
  numactl --interleave=0-3 $JAVA $JAVA_OPTS_C $SPEC_OPTS_C -jar ../specjbb2015.jar -m MULTICONTROLLER $MODE_ARGS_C 2>controller.log > controller.out &

  CTRL_PID=$!
  echo "Controller PID = $CTRL_PID"

  for ((gnum=1; $gnum<$GROUP_COUNT+1; gnum=$gnum+1)); do

    GROUPID=Group$gnum
    echo -e "\nStarting JVMs from $GROUPID:"

    nodeid=$((gnum%GROUP_COUNT))
    echo Placing $GROUPID on to NODE: $nodeid / $GROUP_COUNT

    for ((jnum=1; $jnum<$TI_JVM_COUNT+1; jnum=$jnum+1)); do

        JVMID=txiJVM$jnum
        TI_NAME=$GROUPID.TxInjector.$JVMID

        echo "    Start $TI_NAME"
        numactl -N $nodeid -m $nodeid $JAVA $JAVA_OPTS_TI $SPEC_OPTS_TI -jar ../specjbb2015.jar -m TXINJECTOR -G=$GROUPID -J=$JVMID $MODE_ARGS_TI > $TI_NAME.log 2>&1 &
        echo -e "\t$TI_NAME PID = $!"
    done

    JVMID=beJVM
    BE_NAME=$GROUPID.Backend.$JVMID

    echo "    Start $BE_NAME"
    #GC_LOG=" -Xlog:gc*=info,gc+heap=debug:file=be_${gnum}.log "
    numactl -N $nodeid -m $nodeid $JAVA $GC_LOG  $JAVA_OPTS_BE $SPEC_OPTS_BE -jar ../specjbb2015.jar -m BACKEND -G=$GROUPID -J=$JVMID $MODE_ARGS_BE > $BE_NAME.log 2>&1 &
    echo -e "\t$BE_NAME PID = $!"

  done

  echo
  echo "SPECjbb2015 is running..."
  echo "Please monitor $result/controller.out for progress"

  wait $CTRL_PID
  echo
  echo "Controller has stopped"

  echo "SPECjbb2015 has finished"
  echo
  
  cd ..

done

exit 0

