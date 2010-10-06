---
title: Sequential write performance
layout: post
---

Sequential write performance
============================

In one of the projects I have a pretty big in-memory data structure.
The problem raised when I needed to restart a box or when program
crashes - as recreation of this data structure is pretty complex.

To save time on restarts I need to find a way to save the state of
this data. The most straightforward idea is to just dump it onto the
disk. Other approach would be to create append-only log.

That raises a question: how much better is append log than just
dumping a full state?

Appen log is more complex than dumping the data, but you can balance
out the cost of disk writes evenly - instead of a huge disk write
I would have a big number of tiny writes.

I decided I need a benchmark of how bad is sequentially writing
few gigs of data. The benchmark I did is indeed simple - it just
sequentially writes a lot of data. How can you do it quickly?
Well, use `write(2)` or if you feel modern try out `mmap(2)`.

The tests have two phases:
 1. First, how long it takes to get rid of the responsibility
    for the data. In the `write` test it means how long writes
    take. For `mmap` - how long it takes to write into memory.
 2. Time it takes kernel to flush the data to disk. `fdatasync`
    and `msync` accordingly.

Why to distinct those cases? The first phase I can't parallelize,
it's basically creating a snapshot of the data.
The second phase is pure synchronizing, which can be done in
the background.


One thing I've learned - `posix_fallocate(2)` on the SSD drive,
it has the same cost as writing data.

Let's answer the first question - what's faster `write` appending data
to a file or `memset` setting values inside mmaped memory region.

Here, we actually don't test anything interesting - purely `write` performance,
which in most cases is just raw memory speed.

{% gnuplot {'height'=>300}  %}
set bars 4
set border linewidth 1.5
set key off

set title "write(2) throughput (spinning disk)"
set ylabel "MB/s"
#set yrange [0:]
set xrange [0.5:6.5]
set xtics 1
set xtics ("128" 1, "256" 2, "512" 3, "1024" 4, "2048" 5, "4096" 6)

set style fill solid 0.50 border

set boxwidth 0.5 absolute

plot "<%= data_file %>" using 1:5:6 with boxerrorbars\
        linecolor rgbcolor "red" fill solid 0.50 border

---
# write(2)
1 128     0.112   0.024   1196.060049     237.424611  #write-128-f-spin.log write
2 256     0.187   0.016   1378.215555     102.374409  #write-256-f-spin.log write
3 512     0.387   0.030   1331.056715     95.372259  #write-512-f-spin.log write
4 1024    0.906   0.532   1305.866291     301.911383  #write-1024-f-spin.log write
5 2048    5.941   1.575   369.393165      95.675409  #write-2048-f-spin.log write
6 4096    22.347  1.777   184.477904      14.941767  #write-4096-f-spin.log write
{% endgnuplot %}


{% gnuplot {'height'=>300}  %}
set bars 4
set border linewidth 1.5
set key off

set title "memset(2) throughput (spinning disk)"
set ylabel "MB/s"
#set yrange [0:]
set xrange [0.5:6.5]
set xtics 1
set xtics ("128" 1, "256" 2, "512" 3, "1024" 4, "2048" 5, "4096" 6)

set style fill solid 0.50 border

set boxwidth 0.5 absolute

plot "<%= data_file %>" using 1:5:6 with boxerrorbars \
        linecolor rgbcolor "red" fill solid 0.50 border

---
# memset(2)
1 128     0.231   0.178   855.642108      400.539157  #write-128-m-spin.log memset
2 256     0.239   0.133   1183.758947     213.049507  #write-256-m-spin.log memset
3 512     0.463   0.095   1144.429752     188.862278  #write-512-m-spin.log memset
4 1024    1.944   0.749   665.296723      367.282021  #write-1024-m-spin.log memset
5 2048    7.295   0.831   284.763635      35.547922  #write-2048-m-spin.log memset
6 4096    24.021  3.734   174.738771      27.244621  #write-4096-m-spin.log memset
{% endgnuplot %}


Not surprisingly at some point near 1GB we hit a wall and kernel refuses to
accept more data in and blocks our `write` call. Still, if you wanted to just
append 4GB to a file - that will take you about 22 seconds.

As a sanity check, let's see the average time of both `write` and `fsync`. That
should be more or less constant, and not dependent on data chunk:

{% gnuplot {'height'=>300}  %}
set bars 4
set border linewidth 1.5
set key off

set title "write(2) + fdatasync(2) throughput (spinning disk)"
set ylabel "MB/s"
set yrange [0:]
set xrange [0.5:6.5]
set xtics 1
set xtics ("128" 1, "256" 2, "512" 3, "1024" 4, "2048" 5, "4096" 6)

set style fill solid 0.50 border

set boxwidth 0.5 absolute

plot "<%= data_file %>" using 1:5:6 with boxerrorbars \
        linecolor rgbcolor "red" fill solid 0.50 border

---
# write + fsync
1 128     1.247   0.049   102.795495      4.141677  #write-128-f-spin.log write + fdatasync
2 256     2.348   0.112   109.264601      5.337929  #write-256-f-spin.log write + fdatasync
3 512     4.757   0.359   108.251728      8.388862  #write-512-f-spin.log write + fdatasync
4 1024    9.297   0.493   110.460893      6.031970  #write-1024-f-spin.log write + fdatasync
5 2048    18.670  0.874   109.937905      5.236857  #write-2048-f-spin.log write + fdatasync
6 4096    36.390  2.674   113.187019      8.556186  #write-4096-f-spin.log write + fdatasync
{% endgnuplot %}


{% gnuplot {'height'=>300}  %}
set bars 4
set border linewidth 1.5
set key off

set title "memset(2) + msync(2) throughput (spinning disk)"
set ylabel "MB/s"
set yrange [0:]
set xrange [0.5:6.5]
set xtics 1
set xtics ("128" 1, "256" 2, "512" 3, "1024" 4, "2048" 5, "4096" 6)

set style fill solid 0.50 border

set boxwidth 0.5 absolute

plot "<%= data_file %>" using 1:5:6 with boxerrorbars \
        linecolor rgbcolor "red" fill solid 0.50 border

---
# memset msync
1 128     1.332   0.089   96.543561       6.631789  #write-128-m-spin.log memset + msync
2 256     2.542   0.164   101.156289      7.139098  #write-256-m-spin.log memset + msync
3 512     5.039   0.313   102.014740      6.659878  #write-512-m-spin.log memset + msync
4 1024    9.931   0.766   103.746471      8.198219  #write-1024-m-spin.log memset + msync
5 2048    19.443  1.846   106.291871      10.128701  #write-2048-m-spin.log memset + msync
6 4096    38.694  5.178   107.804159      14.596805  #write-4096-m-spin.log memset + msync
{% endgnuplot %}



{% gnuplot {'height'=>300}  %}
set bars 4
set border linewidth 1.5
set key off

set title "write(2) + fdatasync(2) throughput (ssd)"
set ylabel "MB/s"
set yrange [0:]
set xrange [0.5:6.5]
set xtics 1
set xtics ("128" 1, "256" 2, "512" 3, "1024" 4, "2048" 5, "4096" 6)

set style fill solid 0.50 border

set boxwidth 0.5 absolute

plot "<%= data_file %>" using 1:5:6 with boxerrorbars \
        linecolor rgbcolor "dark-green" fill solid 0.50 border

---
# write + fsync ssd
1 128     2.264   0.520   59.652185       13.844530  #write-128-f-ssd.log write + fdatasync
2 256     4.173   0.631   62.831446       9.909910  #write-256-f-ssd.log write + fdatasync
3 512     7.663   0.500   67.100107       4.333676  #write-512-f-ssd.log write + fdatasync
4 1024    16.159  1.625   63.981381       6.084900  #write-1024-f-ssd.log write + fdatasync
5 2048    31.113  3.090   66.442715       6.234642  #write-2048-f-ssd.log write + fdatasync
6 4096    60.278  4.306   68.278676       4.588681  #write-4096-f-ssd.log write + fdatasync
{% endgnuplot %}


{% gnuplot {'height'=>300}  %}
set bars 4
set border linewidth 1.5
set key off

set title "write(2) throughput (ssd)"
set ylabel "MB/s"
set yrange [0:]
set xrange [0.5:6.5]
set xtics 1
set xtics ("128" 1, "256" 2, "512" 3, "1024" 4, "2048" 5, "4096" 6)

set style fill solid 0.50 border

set boxwidth 0.5 absolute

plot "<%= data_file %>" using 1:5:6 with boxerrorbars \
        linecolor rgbcolor "dark-green" fill solid 0.50 border

---
# write
1 128     0.087   0.002   1467.402486     41.885088  #write-128-f-ssd.log write
2 256     0.172   0.003   1488.911904     28.128357  #write-256-f-ssd.log write
3 512     0.348   0.008   1473.322091     34.055191  #write-512-f-ssd.log write
4 1024    3.393   2.314   583.532377      513.320323  #write-1024-f-ssd.log write
5 2048    12.191  6.516   261.325687      213.628762  #write-2048-f-ssd.log write
6 4096    36.494  8.731   118.583811      26.793447  #write-4096-f-ssd.log write
{% endgnuplot %}


{% gnuplot {'height'=>300}  %}
set bars 4
set border linewidth 1.5
set key off

set title "memset(2) throughput (ssd)"
set ylabel "MB/s"
set yrange [0:]
set xrange [0.5:6.5]
set xtics 1
set xtics ("128" 1, "256" 2, "512" 3, "1024" 4, "2048" 5, "4096" 6)

set style fill solid 0.50 border

set boxwidth 0.5 absolute

plot "<%= data_file %>" using 1:5:6 with boxerrorbars \
        linecolor rgbcolor "dark-green" fill solid 0.50 border

---
# memset
1 128     0.072   0.006   1781.775485     127.381717  #write-128-m-ssd.log memset
2 256     0.140   0.005   1833.813661     67.042610  #write-256-m-ssd.log memset
3 512     0.280   0.010   1829.114359     62.007101  #write-512-m-ssd.log memset
4 1024    1.516   1.902   1482.833783     696.807414  #write-1024-m-ssd.log memset
5 2048    6.925   6.629   1014.371043     832.711940  #write-2048-m-ssd.log memset
6 4096    36.674  11.841  122.612936      34.560624  #write-4096-m-ssd.log memset
{% endgnuplot %}


{% gnuplot {'height'=>300}  %}
set bars 4
set border linewidth 1.5
set key off

set title "memset(2) + msync(2) throughput (ssd)"
set ylabel "MB/s"
set yrange [0:]
set xrange [0.5:6.5]
set xtics 1
set xtics ("128" 1, "256" 2, "512" 3, "1024" 4, "2048" 5, "4096" 6)

set style fill solid 0.50 border

set boxwidth 0.5 absolute

plot "<%= data_file %>" using 1:5:6 with boxerrorbars \
        linecolor rgbcolor "dark-green" fill solid 0.50 border

---
# memset + msync ssd
1 128     2.488   0.812   56.992817       17.536695  #write-128-m-ssd.log memset + msync
2 256     4.566   1.355   60.124751       14.472466  #write-256-m-ssd.log memset + msync
3 512     8.314   1.515   63.475930       10.569176  #write-512-m-ssd.log memset + msync
4 1024    16.713  2.471   62.529965       8.622401  #write-1024-m-ssd.log memset + msync
5 2048    31.173  3.194   66.326801       6.165061  #write-2048-m-ssd.log memset + msync
6 4096    61.921  7.549   67.031262       7.267082  #write-4096-m-ssd.log memset + msync
{% endgnuplot %}


{% gnuplot {'height'=>300}  %}
set bars 4
set border linewidth 1.5
set key off

set title "Average disk throughput"
set ylabel "MB/s"
set yrange [0:]
set xrange [0.5:2.5]
set xtics 1
set xtics ("spinning" 1, "ssd" 2)

set style fill solid 0.50 border

set boxwidth 0.5 absolute

plot "<%= data_file %>" every 2::0 using 1:2:3:4 with boxerrorbars \
        linecolor rgbcolor "red" fill solid 0.50 border,  \
     "<%= data_file %>" every 2::1 using 1:2:3:4 with boxerrorbars \
         linecolor rgbcolor "dark-green" fill solid 0.50 border

---
1 102.92618166666666 0 0.5
2 62.746919333333345 0 0.5
{% endgnuplot %}

I was
thinking which approach is faster - appen 
to check i
I wanted to check how quickly it's possible to write data to disk. It sounds
pretty trivial, but often it's the trivial experiments give the most interesting
results. This time it wasn't without the surprise: SSD's are slow.

The test I run was very simple, it wrote few gigs of zeroes to disk and
finished with an `fsync(2)` call. The intention is to test a sequential write
bandwidth.

The test comes in few configurations:

 * Write data using `write(2)`, synchronize with `fsync(2)`. Flavours:
   - start with empty file, `write` will append data to the file
   - pre-allocate disk space using `posix_fallocate(3)`
 * Set data in file using `mmap(2)`, synchronize with `msync(2)`. Flavours:
   - set initial size using `ftruncate(2)`
   - pre-allocate disk space using `posix_fallocate(3)`


I'm interested in two metrics:

 * time of writing (impractical for `mmap`)
 * time of writing and flushing to disk

{% gnuplot {'height'=>300}  %}
set bars 4
set border linewidth 1.5
set key off

set title "Disk throughput"
set ylabel "MB/s"
set yrange [0:]
set xrange [0.5:2.5]
set xtics 1
set xtics ("ssd" 1, "spinning" 2)

set style fill solid 0.50 border

set boxwidth 0.5 absolute

plot "<%= data_file %>" every 3::0 using 1:2:3:4 with boxerrorbars,\
     "<%= data_file %>" every 3::1 using 1:2:3:4 with boxerrorbars

---

1 10 2 0.5
2 12 3 0.5

{% endgnuplot %}


