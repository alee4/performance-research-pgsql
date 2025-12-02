setup

1. Clone PostgreSQL source (i use this to collect release metadata)
 git clone https://github.com/postgres/postgres.git

2. Get list of releases to test. this is just a text file of whatever releases they had
 git tag | grep "^REL_13_" | grep -v "BETA\|RC" | sort -V > ../pg13-releases.txt
 git tag | grep "^REL_14_" | grep -v "BETA\|RC" | sort -V > ../pg14-releases.txt

3. build releases
   ./build-all-releases.sh ../pg13-releases.txt
  verify with docker images | grep postgres-git | wc -l

4. run sysbench tests
 ./test-pg13-commits-rigorous.sh 60 10 3
  60 = how long you want to run each test for
  10 = db warmup
  3 = number of runs per release


some context-
 the ./test-pg13-commits-rigorous.sh script executes docker exec postgres-test sysbench oltp_write_only run
 inside a container, this runs random write operations for 60 seconds. oltp is a sysbench thing, other ones are oltp_read_write, oltp_read_only, oltp_write_only, oltp_point_select, oltp_update_index

output gives TPS (transactions per sec) and latency percentiles
