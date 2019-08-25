#!/bin/bash -e

# Usage: ./test.sh --checkpoint <checkpoint.tar>
#                  [--max_jobs M] [--job_ids 0,1,2]
#                  [--logdir /log/dir]
#                  [--test_runs_per_job N]

CUR_DIR=$(dirname "$(realpath -s "$0")")
ROOT_DIR="$CUR_DIR"/..

# ArgumentParser
CHECKPOINT=""
MAX_JOBS=0
JOB_IDS=""
TEST_RUNS_PER_JOB=3
BASE_LOG_DIR="$CUR_DIR/logs"
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --checkpoint )
      CHECKPOINT="$2"
      shift 2;;
    --max_jobs )
      MAX_JOBS="$2"
      shift 2;;
    --job_ids )
      JOB_IDS="$2"
      shift 2;;
    --logdir )
      BASE_LOG_DIR="$2"
      shift 2;;
    --test_runs_per_job )
      TEST_RUNS_PER_JOB="$2"
      shift 2;;
    * )    # Unknown option
      POSITIONAL+=("$1") # Save it in an array for later
      shift;;
  esac
done
set -- "${POSITIONAL[@]}" # Restore positional parameters

echo "CHECKPOINT: $CHECKPOINT"
echo "MAX_JOBS: $MAX_JOBS"
echo "JOB_IDS: $JOB_IDS"
echo "BASE_LOG_DIR: $BASE_LOG_DIR"
echo "TEST_RUNS_PER_JOB: $TEST_RUNS_PER_JOB"

if [ -z "$CHECKPOINT" ]; then
  echo "--checkpoint must be specified"
  exit 1
fi

LOG_DIR="$BASE_LOG_DIR/test"
mkdir -p $LOG_DIR

TORCHBEAST_DIR="$ROOT_DIR"/third-party/torchbeast
PYTHONPATH=$PYTHONPATH:"$TORCHBEAST_DIR"

# Unix domain socket path for RL server address
SOCKET_PATH="/tmp/rl_server_path"
rm -f $SOCKET_PATH

POLYBEAST_LOG="$LOG_DIR/polybeast.log"
PANTHEON_LOG="$LOG_DIR/pantheon.log"
PANTHEON_LOG_DIR="$LOG_DIR/pantheon"
mkdir -p $PANTHEON_LOG_DIR

# For testing, pantheon_env.py decides termination, so launch polybeast.py first
# in the background and kill it once pantheon_env.py returns.
# TODO (viswanath): More params
PYTHONPATH=$PYTHONPATH OMP_NUM_THREADS=1 python3 $ROOT_DIR/train/polybeast.py \
  --mode=test \
  --address "unix:$SOCKET_PATH" \
  --checkpoint "$CHECKPOINT" \
  --disable_cuda \
  > "$POLYBEAST_LOG" 2>&1 &
BG_PID=$!
echo "Polybeast running in background (pid: $BG_PID), logfile: $POLYBEAST_LOG."

# Now start pantheon_env.py
echo "Starting pantheon, logfile: $PANTHEON_LOG."
python3 $ROOT_DIR/train/pantheon_env.py \
  --mode=test \
  --max_jobs "$MAX_JOBS" \
  --job_ids "$JOB_IDS" \
  --test_runs_per_job "$TEST_RUNS_PER_JOB" \
  -v 1 \
  --logdir "$PANTHEON_LOG_DIR" \
  > "$PANTHEON_LOG" 2>&1

# Interrupt the background polybeast process.
echo "Done testing, terminating polybeast."
kill -INT "$BG_PID"
