#!/usr/bin/perl

local $| = 1;

###############################################################################
# AutoGame - Version 0.1
###############################################################################

###############################################################################
package AutoGame::Class;

use strict;
use warnings;
use Carp;

use Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(AUTOLOAD DESTROY);

our $AUTOLOAD;

sub AUTOLOAD {
	my $self = shift;
	my $type = ref($self)
	  or croak "$self is not an object";
	my $name = $AUTOLOAD;
	$name =~ s/.*://;
	unless ( exists $self->{_permitted}->{$name} ) {
		croak "Can't access `$name' field in class $type";
	}
	if (@_) {
		return $self->{$name} = shift;
	}
	else {
		return $self->{$name};
	}
}

sub DESTROY { }

1;

###############################################################################
package AutoGame::Utilities;

use strict;
use warnings;

use Win32::GuiTest qw(SetActiveWindow SetForegroundWindow);

use Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(str_pad_right stat_inc bring_window_to_front);
our $AUTOLOAD;

sub str_pad_right {
	my ( $str, $size ) = @_;
	$size = 10 unless $size;
	my $len  = length $str;
	my $diff = $size - $len;
	if ( $diff > 0 ) {
		$str = $str . ' ' x $diff;
	}
	return $str;
}

sub stat_inc {
	my ( $global, $local, $key, $value ) = @_;
	die "Invalid stat key" unless defined $global->{$key};
	$global->{$key} = $global->{$key} + $value;
	$local->{$key}  = $local->{$key} + $value;
}

sub bring_window_to_front {
	my $win     = shift;
	my $success = 1;
	unless ( defined $win ) {
		print "No window id specified to be foregrounded\n";
		return 0;
	}
	if ( SetActiveWindow($win) ) {

		#print "* Successfully set the window id: $window active\n";
	}
	else {
		print "* Could not set the window id: $win active\n";
		$success = 0;
	}
	if ( SetForegroundWindow($win) ) {

		#print "* Window id: $window brought to foreground\n";
	}
	else {
		print "* Window id: $win could not be brought to foreground\n";
		$success = 0;
	}
	return $success;
}

1;

###############################################################################
package AutoGame::Stats;

use strict;
use warnings;
use Carp;

import AutoGame::Class qw(AUTOLOAD DESTROY);
import AutoGame::Utilities qw(str_pad_right);

use Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(error);
our $AUTOLOAD;

our %fields = (
	_name       => undef,
	clicks      => undef,
	screenshots => undef,
	started_on  => undef,
	last_click  => undef,
	_custom_keys => undef,
);

sub new {
	my ( $proto, $name ) = @_;
	$name = '_DEFAULT' unless $name;
	my $class = ref($proto) || $proto;
	my $s = {
		_permitted => \%fields,
		%fields,
	};
	bless( $s, $class );
	$s->_name($name);
	$s->init();
	return $s;
}

sub init {
	my $s = shift;
	for my $k ( keys %$s ) {
		next if $k =~ /^_/;
		$s->$k(0);
	}
	my @keys;
	$s->_custom_keys(\@keys);
}

sub add_custom_key {
	my ($s, $section, $p_key, $value) = @_;
	my $key = $s->get_key($section, $p_key);
	die "Custom key cannot begin with '_' ($key)" if $key =~ /^_/;
	$s->{_permitted}->{$key} = $value;
	$s->$key($value);
	my %custom = (	
		section => $section,
		key => $key,
		value => $value,
	);
	push @{$s->_custom_keys}, %custom;
}

sub get_custom_keys {
	my ($s) = @_;
	return $s->_custom_keys;
}

sub import_custom_keys {
	my ($s, $custom_keys) = @_;	
	for (@{$custom_keys}) {
		$s->add_custom_key ($_->section, $_->key, $_->value);
	}
}

sub get_key {
	my ($s, $section, $key) = @_;
	die "No key" unless $key;
	#print "Get key " . (defined $section? $section: "NoSection") . " / " . (defined $key? $key: "NoKey") . "\n";
	return $key unless $section;
	return "$section.$key";
}

sub inc {
	my ($s, $section, $p_key, $value) = @_;
	my $key = $s->get_key($section, $p_key);
	die "Unknown key '$key'" unless defined $s->{$key};
	my $v = $s->$key;
	$v+=$value;
	$s->$key($v);
	return $s;
}

sub dec {
	my ($s, $section, $p_key, $value) = @_;
	my $key = $s->get_key($section, $p_key);
	die "Unknown key '$key'" unless defined $s->{$key};
	my $v = $s->$key;
	$v-=$value;
	$s->$key($v);
	return $s;
}

sub set {
	my ($s, $section, $p_key, $value) = @_;
	my $key = $s->get_key($section, $p_key);
	die "Unknown key '$key'" unless defined $s->{$key};
	$s->$key($value);
	return $s;
}	


sub to_s {
	my $s   = shift;
	my $str = 'Stat: ' . $s->_name . "\n";
	for my $k ( sort keys %$s ) {
		next if $k =~ /^_/;
		$str .= ' - '
		  . str_pad_right($k) . ': '
		  . ( defined $s->$k ? $s->$k : 'undef' ) . "\n";
	}
	return $str;
}

1;

###############################################################################
package AutoGame::Screenshot;

use strict;
use warnings;
use Carp;

use Imager;
use Imager::Search::Screenshot;
use Win32::GuiTest qw(MouseMoveAbsPix GetWindowRect);
use Time::HiRes qw(usleep time);
use Data::Dumper;

import AutoGame::Class qw(AUTOLOAD DESTROY);
import AutoGame::Utilities qw(bring_window_to_front);

use Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(error);
our $AUTOLOAD;

our %fields = (
	id        => undef,
	parent    => undef,
	screen    => undef,
	num       => undef,
	monitor   => undef,
	auto_save => undef,
	dir       => undef,
);

sub new {
	my ( $proto, $parent, $id ) = @_;
	my $class = ref($proto) || $proto;
	my $s = {
		_permitted => \%fields,
		%fields,
	};
	bless( $s, $class );
	$s->id($id);
	$s->parent($parent);
	$s->init();
	return $s;
}

sub take {
	my $s = shift;
	bring_window_to_front( $s->id );
	$s->save if ( $s->auto_save and $s->screen );
	usleep(250);
	print("-> Taking Screnshot ()\n");
	$s->screen(
		Imager::Search::Screenshot->new(
			[ monitor => 0 ],
			driver => 'Imager::Search::Driver::BMP24'
		)
	);
	die "Cannot take screenshot" unless $s->screen;
	$s->num( $s->num + 1 );
	$s->parent->inc_stat(undef, 'screenshots', 1);
	return $s;
}

sub save {
	my ( $s, $num ) = @_;
	$num = $s->num unless $num;
	my $file = sprintf( $s->dir . "/%d-%d-%d.png", time, $s->parent->parent->stats->screenshots, $s->id );
	print "Writing screenshot '$file'\n";
	my ( $left, $top, $right, $bottom ) = GetWindowRect( $s->id );
	my $cropped = $s->screen->image->crop(
		left   => $left,
		right  => $right,
		top    => $top,
		bottom => $bottom
	);
	unless($cropped) {
		print "Error: Cannot save $file (cropped)\n";
		return 0;
	}
	$cropped->write( file => $file );
	return 1;
}

sub search {
	my ( $s, $pattern, $greedy ) = @_;
	my @zones;
	if ($greedy) {
		@zones = $s->screen->find($pattern);
	} else {
		my @m = $s->screen->find($pattern);
		if (@m > 0) {
			push @zones, $m[0];	
		}
	}
	my $blue = Imager::Color->new( 0, 0, 255);
	for (@zones) {
		$s->draw_zone( $_, $blue );
	}
	return @zones;
}

sub draw_zone {
	my ( $s, $zone, $color ) = @_;
	$s->screen->image->box(
		color  => $color,
		xmin   => $zone->left,
		ymin   => $zone->top,
		xmax   => $zone->right,
		ymax   => $zone->bottom,
		filled => 0
	);
}

sub draw_click {
	my ( $s, $zone, $color ) = @_;
	my $x = $zone->center_x
	  || ( $zone->left + ( ( $zone->right - $zone->left ) / 2 ) );
	my $y = $zone->center_y
	  || ( $zone->top + ( ( $zone->bottom - $zone->top ) / 2 ) );
	$s->screen->image->circle(
		color  => Imager::Color->new( 255, 0, 0 ),
		r      => 1,
		x      => $x,
		y      => $y,
		filled => 1,
	);
}

sub init {
	my $s = shift;
	$s->num(0);
	$s->monitor(-1);
	$s->auto_save(0);
	my $dir = $ENV{RC_SCREENSHOTS} || 'screenshots/';
	$s->dir($dir);
}

1;

###############################################################################
package AutoGame::Window;

use strict;
use warnings;
use Carp;

use Win32::GuiTest qw(MouseMoveAbsPix SendMouse GetCursorPos);
use Time::HiRes qw(usleep);

import AutoGame::Class qw(AUTOLOAD DESTROY);
import AutoGame::Utilities qw(str_pad_right bring_window_to_front);

use Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(error);
our $AUTOLOAD;

our %fields = (
	id         => undef,
	parent     => undef,
	stats      => undef,
	screenshot => undef,
	mouse_x    => undef,
	mouse_y    => undef,
	greedy_search => undef,
);

sub new {
	my ( $proto, $parent, $id ) = @_;
	my $class = ref($proto) || $proto;
	my $s = {
		_permitted => \%fields,
		%fields,
	};
	bless( $s, $class );
	$s->id($id);
	$s->parent($parent);
	$s->init();
	return $s;
}

sub init {
	my $s = shift;
	$s->stats( new AutoGame::Stats( $s->id ) );
	$s->stats->import_custom_keys($s->stats->get_custom_keys);
	my $time = time;
	$s->stats->set(undef, 'last_click', $time); # Prevent stale function to restart game when program is just started
	$s->stats->set(undef, 'started_on', $time);
	$s->screenshot( new AutoGame::Screenshot( $s, $s->id ) );
	$s->set_greedy_search(1);
}

sub set_greedy_search {
	my ($s, $b) = @_;
	if ($b) {
		$s->greedy_search(1);
		return 1;
	}
	$s->greedy_search(0);
}

sub click {
	my ( $s, $zone, $bcode, $acode ) = @_;
	bring_window_to_front( $s->id );
	my $x = $zone->center_x
	  || ( $zone->left + ( ( $zone->right - $zone->left ) / 2 ) );
	my $y = $zone->center_y
	  || ( $zone->top + ( ( $zone->bottom - $zone->top ) / 2 ) );
	$s->inc_stat(undef, 'clicks', 1);
	$s->set_stat(undef, 'last_click', time);
	$s->screenshot->draw_click($zone);
	$s->save_mouse();
	&$bcode( $s, $zone ) if $bcode;
	$s->move_mouse( $x, $y );
	SendMouse("{LeftClick}");
	$s->move_mouse( 0, 0 );
	&$acode( $s, $zone ) if $acode;
	$s->restore_mouse();
	usleep(250);
	return ( $x, $y );
}

sub search {
	my ( $s, $key, $pattern) = @_;
	my @zones = $s->screenshot->search( $pattern, $s->greedy_search);
	$s->inc_stat('pattern', $key, scalar @zones);
	return \@zones;
}

sub search_and_click {
	my ( $s, $patterns, $bcode, $acode, $cbcode, $cacode ) = @_;
	my $total = 0;
	for my $pattern ( keys %$patterns ) {
		my $zones = $s->search( $pattern, $patterns->{$pattern} );
		&$bcode( $s, $pattern, $zones ) if $bcode;
		for my $zone (@{$zones}) {
			$total++;
			$s->click( $zone, $cbcode, $cacode );
		}
		&$acode( $s, $pattern, $zones ) if $acode;
	}
	return $total;
}

sub wait_and_click {
	my ( $s, $patterns, $duration, $bcode, $acode, $cbcode, $cacode ) = @_;
	print "WaitAndSearch $duration\n";
	if ($duration < 0) {
		return 0;
	}
	my $start = time;
	my $total;
	if ($total = $s->search_and_click( $patterns, $bcode, $acode, $cbcode, $cacode )) {
		return $total;
	}
	my $elapsed_time = time - $start;
	if ($elapsed_time < 1) {
		sleep(1);
	}
	$elapsed_time = time - $start;
	$s->screenshot->take;
	return $s->wait_and_click($patterns, ($duration - $elapsed_time), $bcode, $acode, $cbcode, $cacode);
}

sub move_mouse {
	my ( $s, $x, $y ) = @_;
	MouseMoveAbsPix( $x, $y );
}

sub save_mouse {
	my ($s) = @_;
	my ( $x, $y ) = GetCursorPos();
	$s->mouse_x($x);
	$s->mouse_y($y);
	return ( $x, $y );
}

sub restore_mouse {
	my ($s) = @_;
	$s->move_mouse( $s->mouse_x, $s->mouse_y );
	return ( $s->mouse_x, $s->mouse_y );
}

sub to_s {
	my $s   = shift;
	my $str = "Window id: " . $s->id . "\n";
	$str .= $s->stats->to_s;
}

sub inc_stat {
	my ($s, $section, $key, $value) = @_;
	$s->stats->inc($section, $key, $value);
	$s->parent->stats->inc($section, $key, $value);	
}

sub set_stat {
	my ($s, $section, $key, $value) = @_;
	$s->stats->set($section, $key, $value);
	$s->parent->stats->set($section, $key, $value);	
}

1;

###############################################################################
package AutoGame::Game;
use strict;
use warnings;
use Carp;

use Win32::GuiTest qw(FindWindowLike ShowWindow SW_SHOW SW_HIDE SW_RESTORE SW_MAXIMIZE);
use Time::HiRes qw(usleep);

import AutoGame::Class qw(AUTOLOAD DESTROY);
import AutoGame::Utilities qw(stat_inc);

use Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(error);
our $AUTOLOAD;

our %fields = (
	windows      => undef,
	stats        => undef,
	bmp_patterns => undef,
	is_running   => undef,
	is_paused    => undef,
);

sub new {
	my ($proto) = @_;
	my $class = ref($proto) || $proto;
	my $s = {
		_permitted => \%fields,
		%fields,
	};
	bless( $s, $class );
	$s->init();
	return $s;
}

sub init {
	my $s = shift;
	$s->windows( [] );
	$s->stats( new AutoGame::Stats('global') );
	$s->stats->started_on(time);
	$s->bmp_patterns( {} );
	$s->is_running(1);
	$s->is_paused(0);
}

sub toggle_pause {
	my ($s) = @_;
	if ($s->is_paused) {
		$s->is_paused(0);
	} else {
		$s->is_paused(1);
	}
	print "Toggle pause: " . $s->is_paused . "\n";
}
sub load_bmp_patterns {
	my ( $s, $dir ) = @_;
	$s->bmp_patterns( () );
	my $dh;
	opendir( $dh, $dir ) or die "Could not open pattern directory $dir";
	my $msg = "Loading patterns: ";
	while ( my $file = readdir($dh) ) {
		next if $file =~ /^\.\.?$/;
		next unless $file =~ /^(.*)\.bmp$/;
		$s->stats->add_custom_key('pattern', $1, 0);
		$msg .= "$1 ";
		$s->bmp_patterns->{$1} = Imager::Search::Pattern->new(
			driver => 'Imager::Search::Driver::BMP24',
			file   => "$dir/$file",
		);
	}
	$msg .= "\n";
	print $msg;
}

sub get_patterns {
	my ( $s, $like ) = @_;
	my $reg = qr/$like/;
	my %list;
	for my $k ( keys %{ $s->bmp_patterns } ) {
		next unless $k =~ /$reg/;
		$list{$k} = $s->bmp_patterns->{$k};
	}
	return \%list;
}

sub add_window {
	my ( $s, $name, $class, $depth ) = @_;
	for ( FindWindowLike( 0, $name, $class, undef, $depth ) ) {
		print "-> Adding window $_ ($name, $class, $depth)\n";
		my $win = new AutoGame::Window( $s, $_ );
		push @{ $s->windows }, $win;
	}
}

sub run {
	my ($s) = shift;
	die "No window to play with!" unless scalar  @{ $s->windows };
	while ( $s->is_running ) {
		if ($s->is_paused) {
			sleep(1);
			next;
		}
		for my $win ( @{ $s->windows } ) {
			ShowWindow( $win->id, SW_SHOW );
			ShowWindow( $win->id, SW_MAXIMIZE );
			usleep(500);
			$s->process_window($win);
			ShowWindow( $win->id, SW_HIDE );
		}
	}
}

sub process_window {
	my ( $s, $win ) = @_;
	print "You must provide your own process_window\n";
	sleep(1);
}

sub to_s {
	my $s = shift;
	my $str .= "########\n";
	$str    .= "# Game #\n";
	$str    .= "#------#\n";
	$str    .= $s->stats->to_s;
	$str    .= "###########\n";
	$str    .= "# Windows #\n";
	$str    .= "#---------#\n";
	for ( @{ $s->windows } ) {
		$str .= $_->to_s;
	}
	return $str;
}
1;

###############################################################################
package AutoGame::App::RC;

use strict;
use Time::HiRes qw(usleep);

use base qw(AutoGame::Game);

#########
# HELPER
#########
sub sleep_screen {
	my ( $win, $msec ) = @_;
	usleep($msec);
	return;
	while ( $msec >= 500 ) {
		usleep(500);
		$msec -= 500;
	}
	usleep($msec);
}

my $cb_sleep_screen = sub {
	my ( $s, $pattern, $matches ) = @_;
	if ( @$matches > 0 ) {
		usleep(250);
		$s->screenshot->take;
	}
};
my $cb_plate_a = sub {
	my ( $s, $pattern, $matches ) = @_;
	if ( @$matches > 0 ) {
		print "Sleeping for plate!!!\n";
		sleep( @$matches * 3 );
		$s->screenshot->take;
	}
};

my $cb_repair_a = sub {
	my ( $s, $pattern, $matches ) = @_;
	if ( @$matches > 0 ) {
		print "Sleeping while repairing!!!\n";
		sleep( @$matches * 5 );
		$s->screenshot->take;
	}
};
my $cb_sleep5s = sub { sleep(3) };

############
# Functions
############
sub is_started {
	my ($game, $win) = @_;
	my $patterns = $game->get_patterns('save');
	my @key = keys %{$patterns};
	my $search = $win->search( $key[0], $patterns->{$key[0]});
	if ( @{$search} > 0 ) {
		return 1;
	}
	return 0;
}

sub is_stale {
	my ($game, $win) = @_;
	my $last_action = time - $win->stats->last_click;
	print "Last action: $last_action\n";
	if ($last_action > 300) {
		return 1;
	}
	return 0;
}

sub time_to_restart {
	my($game, $win) = @_;
	my $elapsed_time = time - $win->stats->started_on;
	if ($elapsed_time > 1800) {
		return 1;
	}	
	return 0;
}

sub accept_gift {
	my ($game, $win) = @_;
	$win->set_greedy_search(0);
	if ($win->search_and_click( $game->get_patterns('gift_accept'), undef, undef, undef, undef )) {
		usleep(250);
		$win->screenshot->take;
		return accept_gift($game, $win);
	}
	$win->set_greedy_search(1);
}

sub close_popup {
	my ($game, $win) = @_;
	print "-> Closing popup\n";
	$win->search_and_click( $game->get_patterns('popup'),
		undef, $cb_sleep_screen, undef, $cb_sleep5s ) and $win->screenshot->take;
}

sub helpout {
	my($game, $win) = @_;
	$win->set_greedy_search(0);
	if ($win->search_and_click( $game->get_patterns('help_helpout'), undef, undef, undef, undef )) {
		sleep(3);
		$win->screenshot->take;
		$win->set_greedy_search(1);
		if($win->search_and_click( $game->get_patterns('fb_share'), undef, undef, undef, undef )){
			sleep(1);
			$win->screenshot->take;
		}
		return helpout($game, $win);
	}
	$win->set_greedy_search(1);
}

sub daily_ingredient {
	my($game, $win) = @_;
	if($win->search_and_click( $game->get_patterns('dailyingredient'), undef, undef, undef, undef )) {
		sleep(3);
		$win->screenshot->take;
		close_popup($game, $win);
	}
}

sub help_friends {
	my($game, $win) = @_;
	if($win->search_and_click( $game->get_patterns('help_truck'), undef, undef, undef, undef )) {
		sleep(1);
		$win->screenshot->take;
		helpout($game, $win);
		close_popup($game, $win);
	}
}

sub rc_restart {
	my ($game, $win) = @_;
	$win->stats->set(undef, 'started_on', time);
	close_popup($game, $win);
	$win->search_and_click( $game->get_patterns('save'),
		undef, undef, undef, undef ) and sleep(3);
	$win->search_and_click( $game->get_patterns('bookmark_rc'),
		undef, undef, undef, undef );
	$win->wait_and_click( $game->get_patterns('popup_skip'), 40,
		undef, $cb_sleep_screen, undef, sub { sleep(15) } );
	accept_gift($game, $win, undef, $cb_sleep_screen);
	close_popup($game, $win, undef, $cb_sleep_screen);
	#sleep(1);
}

sub rc_open {
	my ( $game, $win ) = @_;
	$win->search_and_click( $game->get_patterns('rc_gpbonus'),
		undef, $cb_sleep_screen, undef, undef );
	if (
		$win->search_and_click(
			$game->get_patterns('rc_closed'),
			undef, undef, undef, undef
		)
	  )
	{
		sleep(3);
		$win->screenshot->take;
		$win->search_and_click( $game->get_patterns('rc_open30mn'),
			undef, undef, undef, undef )
		  and sleep(3);
	}
}

sub process_window {
	my ( $s, $win ) = @_;
	print "---- Game stats -----\n";
	print $s->stats->to_s;
	print "\n";
	if (time_to_restart($s, $win)) {
		print "Need restart (Time)\n";
		rc_restart($s, $win);
		return;	
	}
	$win->screenshot->take();
	accept_gift($s, $win);
	close_popup($s, $win);
	unless (is_started($s, $win)) {
		print "Need restart (Not in rc)\n";
		rc_restart($s, $win);
		return;
	}
	if (is_stale($s, $win)) {
		print "Need restart (Stale)\n";
		rc_restart($s, $win);
		return;
	}
	$win->search_and_click(
		$s->get_patterns('unzoom'),
		undef,
		sub {
			my ( $s, $pattern, $matches ) = @_;
			if ( @$matches > 0 ) {
				sleep(2);
				$s->screenshot->take;

			}
		},
		undef,
		undef
	);
	rc_open( $s, $win );
	daily_ingredient($s, $win);
	help_friends($s, $win);
	$win->search_and_click( $s->get_patterns('collect'),
		undef, $cb_sleep_screen );
	$win->search_and_click( $s->get_patterns('watering'),
		undef, $cb_sleep_screen );
	$win->search_and_click( $s->get_patterns('plate'),
		undef, $cb_plate_a, undef, undef );
	$win->search_and_click( $s->get_patterns('repair'),
		undef, $cb_repair_a, undef, undef );
	$win->search_and_click( $s->get_patterns('trash'), undef, undef );
	$win->search_and_click( $s->get_patterns('clean'), undef, undef );
	sleep($ARGV[0]) if $ARGV[0];
}

1;

###############################################################################
package main;
use strict;

use Time::HiRes qw(usleep);

use Win32::GuiTest qw(:ALL);

use Data::Dumper;
use Imager::Search;
use Imager::Search::Screenshot ();
use Imager::Search::Driver::BMP24;

import AutoGame::Utilities qw(stat_inc);

$SIG{SIGTSTP}=\&sig_pause;


#######
# MAIN
#######
my $Game = new AutoGame::App::RC;
sub sig_pause {
	$Game->toggle_pause;
}
$Game->load_bmp_patterns("rc/patterns/");
$Game->add_window( '.*Google Chrome.*', undef, 2 );
$Game->run();
exit(0);
1;

__DATA__