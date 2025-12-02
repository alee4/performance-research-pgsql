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
