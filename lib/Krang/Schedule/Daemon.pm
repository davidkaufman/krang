package Krang::Schedule::Daemon;

use strict;
use warnings;

use IO::File;
use Proc::Daemon;
use POSIX ":sys_wait_h";

use Carp qw(croak);
use Time::Piece;
use Time::Seconds;

use Krang::Conf qw(KrangRoot instance instances);
use Krang::Log qw/critical debug info reopen_log/;
use Krang::Schedule;
use Krang::DB qw(dbh forget_dbh);

use Krang::Cache;

our $pidfile = File::Spec->catfile(KrangRoot, 'tmp', 'schedule_daemon.pid');

use constant MAX_CHILDREN => 3;
use constant CHUNK_SIZE   => 5;
use constant SLEEP_INTERVAL => 5;

my $CHILD_COUNT   = 0;
my %child_pids    = ();
my %assigned_jobs = ();


# handle SIGTERM
$SIG{'TERM'} = sub {
    _reap_dead_children();

    info(__PACKAGE__ . " caught SIGTERM.  Exiting.");

    # remove pidfile if it exists
    unlink $pidfile if -e $pidfile;

    # get out of here
    exit(0);
};




=head1 NAME

Krang::Schedule::Daemon - Module to handle scheduled tasks in Krang.

=head1 SYNOPSIS

  use Krang::Schedule::Daemon;

  Krang::Schedule::Daemon->run();

=head1 DESCRIPTION

This module is responsible for creating a daemon whose task is to run all scheduled tasks in Krang.

When started (using the C<run()> method), Krang::Schedule::Daemon creates a persistant daemon (whose PID file can be found at KRANG_ROOT/tmp/schedule_daemon.pid).  Once started, the daemon will poll L<Krang::Scheduler> at a set interval (defaults to 5 seconds --- Is this something we want settable in KrangConf??), looking for jobs that need to be executed.  If none are found, the daemon will sleep for another interval, wake up, and repeat the process.

If jobs are found, Krang::Schedule::Daemon will sort and group them based on priority, next_run time, and resource usage.  Once sorted and grouped, jobs will be handed off to child processes that will actually handle execution.

When a child process exits (all tasks have been completed, or a fatal error occurred), the parent daemon will make a note of the child exiting and clear its entry from the internal table tracking all work being done.

There is a limit to the number of children that can run simultaneously, determined by the L<Krang::Conf> config file directive B<ScheduleParallel>.



=head2 Job Execution

When a group of jobs is ready to be executed, a child process is spawned to handle the work.  The workload assigned to the child process is determined by the parent daemon, and the work is completed in order of priority.

Once spawned, the parent daemon makes entries in the C<%active_children> and C<%assigned_jobs> hashes.  C<%active_children> is keyed by child PID, and each entry contains a list of L<Krang::Schedule> IDs currently being processed by that child.  C<%assigned_jobs> is the opposite hash, keyed by Krang::Schedule IDs, where each key points to the child PID of the child process handling the job.  These two hashes exist to keep Krang::Schedule::Daemon from assigning work-in-progress to new children.


=head2 Priority

The Priority of a job entry determines when it will get executed in relation to all other pending jobs.  Priority is stored in the L<Krang::Schedule> object as an integer value.

Priority will be adjusted by Krang::Schedule::Daemon, based on whether or not the next scheduled execution (next_run) of a job was met (e.g. if the value of job->next_run() < now(), the execution was missed).

If scheduled execution was missed, the priority of the job will be bumped up by 1, unless it is more than 1 hour late, when it is bumped by 2.  This will not necessarily put the job at the front of the line, but it will get it executed sooner than it would have been.


=head2 Cleanup

When a child finishes an individual task, C<< Krang::Schedule->mark_as_completed($task_id) >> will be called, updating the entry in the database.  L<Krang::Schedule> will determine what the new entry in the database will look like, based on whether or not the job is a re-occuring one.

Once a child has completed all tasks assigned to it, the child will exit.  The parent daemon will trap the SIG_CHLD signal sent by the exiting child, and remove that child PID and all L<Krang::Schedule> entries from the C<%active_children> and C<%assigned_jobs> hashes.


=head1 INTERFACE

=over

=item C<< run() >>

Starts the L<Krang::Schedule::Daemon> daemon.  Once started, it periodically (5 seconds) polls the databases fore each instance, looking for 



Creates a pid file at KRANG_ROOT/tmp/schedule_daemon.pid with the process ID of the daemon itself.

The daemon can be killed by sending a SIG_TERM (e.g. kill) signal.

=cut

sub run {

    my $self = shift;

    # create the daemon.
    Proc::Daemon::Init;

    # reopen the logfile
    reopen_log();

    # forget old dbh from parent process
    forget_dbh();

    # drop off pidfile
    my $pidfile = IO::File->new(">$pidfile");
    unless (defined($pidfile)) {
        my $msg = __PACKAGE__ . "->run() unable to write '$pidfile'.  Exiting.";
        critical($msg);
        exit();
    }
    $pidfile->print($$);
    $pidfile->close();

    # print kickoff message
    my $now = localtime;
    info(__PACKAGE__ . " started.");

    while (1) {

        info(__PACKAGE__ . "->run(): heartbeat. $CHILD_COUNT child processes active");

        # make sure there's nothing dead left out there.
        _reap_dead_children() if ($CHILD_COUNT);

        foreach my $instance (Krang::Conf->instances) {
            Krang::Conf->instance($instance);

            my @jobs = _query_for_jobs();

            if (@jobs) {
                scheduler_pass(@jobs);
            }
        }

        sleep SLEEP_INTERVAL;
    }

}




=item C<< scheduler_pass() >>

Polls the schedule database for a given L<Krang::Conf> instance, looking for jobs where next_run <= now.

If work to be done is found, child processes are allocated to take care of the tasks at hand.

When a child process is spawned, it will C<execute()> all work in the order assigned.  When a task is completed, it is marked as complete, and updated if necessary.  Any jobs that fail will be trapped and skipped, and the work continnues.  When a child is finished, it will exit.

When a child exits, C<scheduler_pass()> will clean up, removing its entry from the tables tracking work being done.

If there is more work to be done than available child processes, C<scheduler_pass()> will block until a child returns, complete cleanup, and then spawn new children to handle the pending work.

Returns when all work has been assigned.  The first task on the next run will be to reap newly-dead (e.g. finished) children.

=cut

sub scheduler_pass {

    my @jobs = @_;

    our $CHILD_COUNT;

    my $instance = Krang::Conf->instance();

    # cleanup - make sure there's nothing dead left out there.
    _reap_dead_children() if ($CHILD_COUNT);

    info(sprintf("%s->scheduler_pass('%s'): %i jobs found.  Working..", __PACKAGE__, $instance, ($#jobs+1)));
    while (@jobs) {

        # allocate first CHUNK_SIZE jobs to be done.
        my @tasks = ();
        my $pid;

        while ((@tasks < CHUNK_SIZE) && @jobs) {
            push @tasks, shift @jobs;
        }

        # wait for a child to return.
        if ($CHILD_COUNT >= MAX_CHILDREN) {
            _reap_dead_children(1);
        }

        # fork a child to take care of the work.
        if ($pid = fork) {
            _parent_work($pid, \@tasks);

        } elsif (defined($pid)) {
            _child_work(\@tasks);

        } else {
            critical(__PACKAGE__ . "->run($instance): Cannot fork children: $!");
        }

        debug(sprintf("%s STATUS: %i children running, %i jobs left to do.", __PACKAGE__, $CHILD_COUNT, ($#jobs+1)));
    }

    # all jobs assigned.  Reap dead children.
    if ($CHILD_COUNT) {
        _reap_dead_children();
    }

    if ($CHILD_COUNT) {
        debug(sprintf("%s STATUS: Waiting on %i children to return.", __PACKAGE__, $CHILD_COUNT));
    } else {
        debug(sprintf("%s STATUS: no work pending.", __PACKAGE__));
    }

}


#
# same functionality as if the daemon was killed.
#
sub stop {

    # remove pidfile if it exists
    unlink $pidfile if -e $pidfile;

    info(__PACKAGE__ . "->stop(): Exiting.");

    # get out of here
    exit(0);

}


#
# _child_work(\@tasks);
#
# Handles the work assigned the newly-spawned child.  Runs through @tasks, executing all of them.
#
sub _child_work {

    my $tasks = shift;

    my $instance = Krang::Conf->instance();

    # reopen the log file
    reopen_log();

    # lose the parent's DB handle.
    forget_dbh();

    # start the cache
    Krang::Cache::start();

    # child
    debug(sprintf("%s: Child PID=%i spawned with %i tasks.",
                 __PACKAGE__, $$, ($#$tasks+1)));

    foreach my $t (@$tasks) {
        debug(sprintf("%s->_child_work('%s'): Child PID=%i running schedule_id=%i",
                      __PACKAGE__, $instance, $$, $t->schedule_id()));
        eval { $t->execute(); };
        if (my $err = $@) {
            critical(sprintf("%s->_child_work('%s'): Child PID=%i encountered fatal error with Schedule ID=%i",
                             __PACKAGE__, $instance, $$, $t->schedule_id()));
        }
    }

    # turn cache off
    Krang::Cache::stop();

    exit(0);

}

#
# _parent_work($pid, \@tasks)
#
# Handles the bookkeeping done by the parent after the fork().
#
# This means making PID and scheduleID entries in global hashes, 
# incrementing the child counter.
#

sub _parent_work {

    my ($pid, $tasks) = @_;
    our $CHILD_COUNT;

    my $instance = Krang::Conf->instance();

    # parent
    foreach my $t (@$tasks) {
        $assigned_jobs{$instance}{$t->schedule_id} = $pid;
        push @{$child_pids{$pid}{jobs}}, $t->schedule_id;
    }
    $child_pids{$pid}{instance} = $instance;

    $CHILD_COUNT++;

}

#
# _reap_dead_children($block)
#
# Polls waitpid() for dead children.  If none are found, it returns immediately.
# If $block is set to 1, and children exist, it will block until children return.
# If a dead child is found, it cleans the entries out of the %child_pids and %assigned_jobs tables.
#

sub _reap_dead_children {

    my $block = shift || 0;
    our $CHILD_COUNT;

    debug(__PACKAGE__ . "->_reap_dead_children(): $CHILD_COUNT children out there.");

    my $child_pid;

    if ($block) {
        # blocking, waiting for one to return.
        $child_pid = waitpid(-1, 0);

        if ($child_pid == -1 && $CHILD_COUNT) {
            info(__PACKAGE__ . " ERROR: $CHILD_COUNT processes are supposed to be working, 0 found.");
        } elsif ($child_pid > 0) {
            # reap it.
            _cleanup_tables($child_pid);
            $CHILD_COUNT--;
        }
    } else {

        # cleanup - reap everything that returns.
        while (($child_pid = waitpid(-1, &WNOHANG)) != -1) {
            last if ($child_pid == 0 || $child_pid == 1);
            _cleanup_tables($child_pid);
            # decrement counter.
            $CHILD_COUNT--;
        }
    }

    debug(__PACKAGE__ . "->_reap_dead_children(): $CHILD_COUNT children remaining.");

}



sub _cleanup_tables {

    my $child_pid = shift;

    my @sched_ids;
    my $instance = $child_pids{$child_pid}{instance};

    foreach my $sched_id (@{$child_pids{$child_pid}{jobs}}) {
        push @sched_ids, $sched_id;
        delete $assigned_jobs{$instance}{$sched_id};
    }
    delete $child_pids{$child_pid};

    debug(sprintf("%s: child PID=%i reaped.  Completed schedule IDs ('%s'): %s", __PACKAGE__, $child_pid, $instance, (join ',', @sched_ids)));

}


#
# _query_for_jobs
#
# Searches the Schedule database for jobs that need to be run now.
#

sub _query_for_jobs {

    my $now = localtime();

    my @schedules;

    @schedules = Krang::Schedule->find(
                                       next_run_less_than_or_equal => $now->mysql_datetime,
                                       order_by => 'priority'
                                      );

    if (@schedules) {
        debug(sprintf("%s: %i Pending jobs found.", __PACKAGE__, ($#schedules+1)));
    }

    return @schedules;

}

=back

=head1 TODO


=head1 SEE ALSO

L<Krang::Schedule>, L<Krang::Alert>, L<Krang::Publisher>


=cut


1;






