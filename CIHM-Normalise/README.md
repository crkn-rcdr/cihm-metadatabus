# CIHM-Normalise

String normalization and metadata crosswalks.



The Dockerfile in this directory is used by the "runtest" script, which will buld a docker image and put you in a shell.


```
russell@russell-XPS-13-7390:~/git/cihm-metadatabus/CIHM-Normalise$ ./runtest 
[+] Building 0.0s (10/10) FINISHED                                                                      
 => [internal] load build definition from Dockerfile                                               0.0s
 => => transferring dockerfile: 291B                                                               0.0s
 => [internal] load .dockerignore                                                                  0.0s
 => => transferring context: 2B                                                                    0.0s
 => [internal] load metadata for docker.io/library/perl:5.36.0-bullseye                            0.0s
 => [1/5] FROM docker.io/library/perl:5.36.0-bullseye                                              0.0s
 => [internal] load build context                                                                  0.0s
 => => transferring context: 1.15kB                                                                0.0s
 => CACHED [2/5] RUN groupadd -g 1117 tdr && useradd -u 1117 -g tdr -m tdr                         0.0s
 => CACHED [3/5] WORKDIR /home/tdr                                                                 0.0s
 => CACHED [4/5] COPY --chown=tdr:tdr . /home/tdr                                                  0.0s
 => CACHED [5/5] RUN cpanm -n --installdeps . && perl Makefile.PL                                  0.0s
 => exporting to image                                                                             0.0s
 => => exporting layers                                                                            0.0s
 => => writing image sha256:1ed0630b704decae8246ff230a825a6fb59631eaca7604013eddbb5594b060ae       0.0s
 => => naming to docker.io/library/dmd-test                                                        0.0s
tdr@419fc76ec83b:~$ 
```


A "make test" will run all the tests in t/

```
tdr@419fc76ec83b:~$ make test
cp lib/CIHM/Normalise/dc.pm blib/lib/CIHM/Normalise/dc.pm
cp lib/CIHM/Normalise/flatten.pm blib/lib/CIHM/Normalise/flatten.pm
cp lib/CIHM/Normalise/issueinfo.pm blib/lib/CIHM/Normalise/issueinfo.pm
cp lib/CIHM/Normalise.pm blib/lib/CIHM/Normalise.pm
cp lib/CIHM/Normalise/marc.pm blib/lib/CIHM/Normalise/marc.pm
PERL_DL_NONLAZY=1 "/usr/local/bin/perl" "-MExtUtils::Command::MM" "-MTest::Harness" "-e" "undef *Test::Harness::Switches; test_harness(0, 'blib/lib', 'blib/arch')" t/*.t
t/00-load-flatten.t .................. ok   
t/00-load-normalise.t ................ ok   
t/dc.t ............................... ok   
t/iso8601.t .......................... ok   
t/issueinfo.t ........................ ok   
t/marc.t ............................. ok   
t/oocihm.8_00002_1-DC.t .............. ok   
t/oocihm.8_06510-MARC.t .............. ok   
t/oocihm.lac_reel_t1649-issueinfo.t .. ok   
All tests successful.
Files=9, Tests=14,  2 wallclock secs ( 0.03 usr  0.00 sys +  2.04 cusr  0.16 csys =  2.23 CPU)
Result: PASS
tdr@419fc76ec83b:~$ 
```


t/ and lib/ are volume mounted to put the source directly into the container, so changes can be made and immediately tested.
