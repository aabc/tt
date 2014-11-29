#!/usr/bin/env ruby
# Working minutes Time Tracker
# (c) 2012-2014, ABC.
# LICENSE: GPL.

require "pathname"
require 'getoptlong'
require 'time'

@tt_log = File.expand_path "~/tt/tt.log" # main worktime log
@flock  = File.expand_path "~/tt/.lock"  # also contains pid
@delay  = 10.0 # scan every n seconds
@pts_times = {}
@now = Time.now

def scan_proc_linux
  @proc = {}
  pdir = Dir['/proc/*']
  pdir.each do |fd|
    next if fd[6..-1].to_i == 0
    stat = IO.read("#{fd}/stat").split(' ', 7) rescue []
    pid  = stat[0].to_i
    comm = stat[1]
    ppid = stat[3].to_i
    pgrp = stat[4].to_i
    tty  = stat[6].to_i
    link = "pts/#{tty & 0xff}" if (tty & 0xff00) == 0x8800
    next unless link
    if @proc[link]
      next if pid != pgrp		# not process group leader
      next if @proc[link][2] == pid	# not parent
    end
    cmdline = IO.read("#{fd}/cmdline").tr("\000", ' ').strip rescue nil
    @proc[link] ||= []
    @proc[link] = [cmdline, pid, ppid, pgrp]
  end
  @proc.delete_if {|k,v| v[0] =~ /^screen\b/}
end

def write_mark(mark)
  now = Time.now
  ts = now.strftime("%Y-%m-%d %H:%M")
  File.open(@tt_log, 'a') {|f| f.puts "#{ts} mark #{mark}"}
end

def monitor(debug = false)
  loop do
    now = Time.now
    pts = Dir['/dev/pts/*']
    pts.delete("/dev/pts/ptmx")
    pts.map! {|e| [e, File.atime(e)]}
    pts.delete_if {|e, mt| (now - mt) > 60 }
    if !pts.empty?
      scan_proc_linux
      pts.each do |fn, mt|
	tty = fn[5..-1]
	ts = mt.strftime("%Y-%m-%d %H:%M")
	next unless @proc[tty]
	prog = @proc[tty][0]
	pid  = @proc[tty][1]
	hash = [ts, prog, pid]
	if hash != @pts_times[tty]
	  puts [ts, tty, pid, prog, now - mt].join(' ') if debug
	  File.open(@tt_log, 'a') {|f| f.puts "#{ts} #{tty} #{prog}"}
	end
	@pts_times[tty] = hash
      end
    end
    # aggregate will filter out dups
    sleep @delay
  end
  exit 0
end

def col(str, color = "0;33")
  if $stdout.tty?
    "\033[#{color}m#{str}\033[m"
  else
    str
  end
end

class File
  # yield on each block in reverse order
  # yield's value is appended to the next block
  # returns last uprocessed slack
  def each_block_reverse(blocksize = 4096)
    block = size / blocksize
    b = ''
    while block >= 0 do
      seek(blocksize * block)
      break unless a = read(blocksize)
      b = yield(a + b)
      block -= 1
    end
    b
  end
  def each_line_reverse
    last = each_block_reverse do |bl|
      splits = bl.split("\n", -1)
      splits.delete_at(-1) if splits[-1] == ''
      splits[1..-1].reverse.each do |li|
        yield li
      end
      splits[0]
    end
    yield last
  end
end

def fmt(s, len)
  "%-*s" % [len, s]
end

def aggregate(f, matches = [])
  re = //
  re = Regexp.union(matches.map {|e| Regexp.new(e)}) unless matches.empty?
  time_dups = {} # duplicated timestamps
  cmd_count  = Hash.new(0) # total minutes cmd is used
  cmd_shared = Hash.new(0.0) # approximated w/o shared time
  cmd_dups = {} # same command in same minute
  count = 0 # total minutes
  mk = nil # curent mark
  marks = Hash.new(0) # marks raw stat
  marklist = [] # marks output stat
  time_cmds = [] # to track cmds with shared time

  f.each_line_reverse do |li|
    li.strip!
    next unless re.match(li)
    day, time, pts, cmd = li.split(' ', 4)
    ts = "#{day} #{time}"
    break if @limit && (@now - Time.parse(ts)) > @limit
    mk = ts unless mk

    if pts == 'mark'
      marklist << ["'#{cmd}' -- #{mk}", marks[mk], marks[mk] / 60.0]
      mk = "'#{cmd}'"
      @havemarks = true
      next
    end

    cmd = "#{pts} #{cmd}" unless @nopts
    if !time_dups.key?(ts)
      puts col('  ' + li) if @list >= 1
      time_dups[ts] = true
      count += 1
      marks[mk] += 1
      time_cmds.each { |c| cmd_shared[c] += 1.0 / time_cmds.size }
      time_cmds = []
    else
      puts '  ' + li if @list >= 2
    end

    time_cmds << cmd
    unless cmd_dups[li]
      cmd_count[cmd] += 1
      cmd_dups[li] = true
    end
  end
  time_cmds.each { |c| cmd_shared[c] += 1.0 / time_cmds.size }
  times = time_dups.keys.sort
  start = times[0]
  stop = times[-1]
  if @havemarks
    marklist << ["#{start} -- #{mk}", marks[mk], marks[mk] / 60.0]
    maxlen = marklist.map{|e| e[0].size}.max
    marklist.reverse.each do |tx, t1, t2|
      puts col("  subtotal %s %3d (%4.2f)" % [fmt(tx, maxlen), t1, t2], '0;36')
    end
  end
  print col("Total %d minutes (%.2f hours)." % [count, count / 60.0], '1;36')
  puts " From %s to %s. %s" % [col(start), col(stop), @lim_opt]
  cmd_count.to_a.reject {|a| !a[0]}.sort.each do |cmd, cnt|
    puts "  %3d %7.2f  %.*s" % [cnt, cmd_shared[cmd], @cols - 10, cmd]
  end
end

def today
  @now.to_i - Time.parse(@now.strftime('%Y-%m-%d 00:00')).to_i
end
def thismonth
  @now.to_i - Time.parse(@now.strftime('%Y-%m-1 00:00')).to_i
end
def multiply_time_limit(arg, limit = @limit)
  if arg.to_i > 1
    @limit = limit * (arg.to_i - 1)
    @lim_opt << "=#{arg}"
  end
end

@list = 0
@lim_opt = '--today'
@limit = today
@nopts = true
GetoptLong.new(
  ["--pts",   "-p", GetoptLong::NO_ARGUMENT],
  ["--list",  "-l", GetoptLong::NO_ARGUMENT],
  ["--hour",  '-H', GetoptLong::OPTIONAL_ARGUMENT],
  ["--day",   '-D', GetoptLong::OPTIONAL_ARGUMENT],
  ["--week",  '-W', GetoptLong::OPTIONAL_ARGUMENT],
  ["--month", '-M', GetoptLong::OPTIONAL_ARGUMENT],
  ["--year",  '-Y', GetoptLong::OPTIONAL_ARGUMENT],
  ["--full",  '-f', GetoptLong::NO_ARGUMENT],
  ["--today",       GetoptLong::OPTIONAL_ARGUMENT],
  ["--thismonth",   GetoptLong::OPTIONAL_ARGUMENT],
  ["--mark",  '-m', GetoptLong::OPTIONAL_ARGUMENT],
  ["--daemon",'-d', GetoptLong::OPTIONAL_ARGUMENT],
  ["--help",  '-h', GetoptLong::NO_ARGUMENT]
).each do |opt, arg|
  case opt
  when '--pts'
    @nopts = false
  when '--list'
    @list += 1
  when '--hour'
    @limit = 60 * 60
    @lim_opt = opt
    multiply_time_limit(arg)
  when '--day'
    @limit = 24 * 60 * 60
    @lim_opt = opt
    multiply_time_limit(arg)
  when '--week'
    @limit = 7 * 24 * 60 * 60
    @lim_opt = opt
    multiply_time_limit(arg)
  when '--month'
    @limit = 31 * 24 * 60 * 60
    @lim_opt = opt
    multiply_time_limit(arg)
  when '--year'
    @limit = 366 * 24 * 60 * 60
    @lim_opt = opt
    multiply_time_limit(arg)
  when '--today' # default
    @limit = today
    @lim_opt = opt
    multiply_time_limit(arg, 24 * 60 * 60)
  when '--thismonth'
    @limit = thismonth
    @lim_opt = opt
  when '--full'
    @limit = nil
    @lim_opt = opt
  when '--mark'
    write_mark arg
    exit 0
  when '--daemon'
    @daemon = true
    @delay = arg.to_i if arg.to_i > 0
  when '--help'
    puts "Help: #{__FILE__} [--options...] [regexps...]"
    puts "  --list    list all matched entries"
    puts "  --pts     show pts for commands"
    puts "  Accounting limiters:"
    puts "  in astronimical time:"
    puts "    --hour    last hour"
    puts "    --day     last day (i.e. 24 hours)"
    puts "    --week    last week"
    puts "    --month   last month"
    puts "    --year    last year"
    puts "    --full    everything"
    puts "  in calendar time (i.e. separated by 00:00):"
    puts "    --today   today only (default)"
    puts "  time limiters also accept args: number of such units."
    puts "  Regexps are to match command lines, like: bash irb"
    puts "    will account only matched as /bash/ OR /irb/"
    exit 0
  end
end

if @daemon
  f = File.open(@flock, File::RDWR|File::CREAT, 0644)
  raise "already started? pid #{f.read}" unless f.flock(File::LOCK_EX|File::LOCK_NB)
  pid = fork do
    Signal.trap('HUP', 'IGNORE')
    f.puts Process.pid
    monitor
  end
  Process.detach(pid)
  f.close
  exit 0
end

@cols = `tput cols`.to_i
if ARGV[0] == '-'
  aggregate $stdin
else
  aggregate File.open(@tt_log, 'r:binary'), ARGV
end

