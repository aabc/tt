## Simple tty work time tracker (tt)

Simple per-minute *tty* activity tracker.

### Methodology

It works like this:

1. periodically check all _ttys_ for activity;
2. scan process list for what process is run on each active _tty_;
3. log into `~/tt/tt.log` timestamp (with _minute_ resolution) and process command line.

Then you can view statistics of how much you are worked at *time interval* (day, hour, marked interval) and what you did. This is intentionally is not very precise, as precision is not always best thing, but it is *good enough* for understanding and sometimes billing. Smallest time unit is *minute*. If many commands was recorded at the same minute they will be accounted just as one minute of work time.

### Installation

You will need *ruby* as prerequisite.

    workbox:~/$ git clone http://github.com/aabc/tt.git

This will clone tracker code into your `~/tt/` directory. Note that `~/tt/` name is built-in. Add autostart of tracker into *crontab*, example:

    * * * * * ~/tt/timetrack.rb --daemon 2>/dev/null

To start every minute is *normal*, because tracker will let itself run only once and in case of some fault it ill restart quickly.

Check that you have `~/bin/` in your PATH env variable, if it's there: `ln -s ~/tt/timetrack.rb ~/bin/tt`. Alternatively you can create bash alias into your .bashrc: `alias tt=~/tt/timetrack.rb`. Done.

Now to view statistics just run `tt`. To get some command line help run `tt --help`.

### Usage details

Example output of `tt`:

    Total 19 minutes (0.32 hours). From 2014-10-06 04:25 to 2014-10-06 05:29. --today
        1    0.25  -bash
       21   16.75  bash
        2    2.00  vim README.md

* *Total minutes* is how much minutes you was active for specified interval (which is `--today` in this case, it's also default and could be changed with command line options).
* *From ... to ...* first and last registered activity time for your interval, so you can check that all your work time (ex. for today) is accounted. Timestamp is in localtime.
* Then goes per-command statistics:
 * First column is *total active minutes* accounted for this command.
 * Second column is minutes without *shared* time. For example, if you are used two command in same minute they may have time 0.5. Or, if processes are scanned each 10 seconds (changeable default) and you used command *A* once per minute and command *B* is registered 4 times per same minute, then they will have share 0.2 and 0.8 accounted in second column. Smaller you set scan interval, more precise is calculation is. (But, I think 5-10 sec is enough in any case.)
 * Third column is detected process command line.

Note, that *sum* of the first column should **not** give *total* work time, because some commands usually have shared minutes (i.e. many commands is run in same minute). But, *sum* of the second column **should** approximate to *total* time, with some imprecision. In general you should rely on *totals* as more precise time estimation.

### Markers

You may mark some point in time with `tt --mark=markname`, then subtotals will be shown like this (here mark is 'test'):

      subtotal 2014-10-06 04:25 -- 'test'  20 (0.33)
      subtotal 'test' -- 2014-10-06 05:43   1 (0.02)

* *First row* is work time between beginning of time interval and your mark in minutes and hours.
* If multiple marks are used they will be accounted too, each interval per row.
* *Last row* is work time accounted from the last mark to current time.

