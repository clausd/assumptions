package Assumptions;
use strict;
# make these dependend on goings on in import
use CGI;
use Cache::FileCache;
use Template;
use DBI;
use CGI::Session;
use Cwd;
use Data::Dumper;
our $AUTOLOAD;
our $debug = 0;

#use vars qw($cgi $template $dbh $sent_headers $sent_body);

sub new {
	my $class = shift;
	bless {
		has_setup => undef,
		sent_headers=> undef,
		sent_body=> undef,
		caller=> caller,
		server_errors=>[],
        client_errors=>[],
	} , $class;
}

sub  setup {
#	print @_;
	print "SETTING UP\n" if $debug;
	my $app = shift;
    eval {
	    $app->configure if not $app->{has_setup};
    };
    eval {
        &{shift()};
    };
	$app->{has_setup} = 1;
	$app->set_cgi;
	$app->set_template;
	$app->parse_url;
	#$app->caller(caller);
}

#~ sub configure {
    
#~ }

sub log_server_error {
	my $app = shift;
	push @{$app->{server_errors}}, @_;
}

sub log_client_error {
	my $app = shift;
	push @{$app->{client_errors}}, @_;
}

sub dump {
	my $app = shift;
	if (scalar(@_)) {
		return Dumper(@_);
	} else {
		return Dumper($app);
	}
}

sub parse_url {
	my $app = shift;
	if (!$app->has_parsed_url) {
		my $url = $app->cgi->url(-path_info=>1);
		my $path_info = $app->cgi->path_info;
		$url =~ s/$path_info$//i;
		$app->{url} = $url;
		my @facts = split m|/|, $path_info;
		shift @facts; # remove empty leading element
		$app->{action} = shift @facts;
		$app->{ident} = shift @facts;
		$app->{path_params} = \@facts;
		$app->{has_parsed_url} = 1;
	}
	# $app->{script} = $ENV
	return ($app->action, $app->ident, $app->object_type);
}
# TODO implementable url manipulation

sub route {

}

# Simplyfy to plain concat (much.easier.to.use)
# If needs be I can homegrow other ones that do "smarts"
sub url_for {
	my $app = shift;
    my $url = $app->url . '/' . join('/', @_);
    $url =~ s|([^:])/+|$1/|g; # all double slashes without a leading : to singles
    return $url;
}


sub set_cache {
	my $app = shift;
	return $app->cache if $app->cache;
	my $root = shift;
	my $namespace = shift;
	my $expiration = shift || '10 days'; # arbitrary
	$app->cache(new Cache::FileCache( {cache_root=> $root, namespace => $namespace, 'default_expires_in' => $expiration }));
}

sub set_dbh {
	my ($app, $dbname, $user, $password) = @_;
	return $app->dbh if $app->dbh;
 	$app->dbh(DBI->connect("dbi:mysql:$dbname", $user, $password));
}

sub set_dbix {
    my ($app, $dbname, $user, $password) = @_;
    use DBIx::Abstract;
    $app->set_dbh($dbname, $user, $password);
    $app->dbix(DBIx::Abstract->connect($app->dbh));
}

sub db {
    my $app = shift;
    return $app->{db} if $app->{db};
    $app->{db} = bless {app=>$app} , 'Assumptions::DB';
    return $app->{db};
}

sub check_db_err {
    my $app = shift;
    if ($app->dbh && $app->dbh->err) {
        $app->log_server_error($app->dbh->err);
    }
}

sub set_template {
	my ($app, $settings) = @_;
	print "Template dir : $settings\n" if $debug;
	return $app->template if $app->template;
	$app->use_data_templates(1) if not defined($settings);
	if (ref($settings)) {
		$app->template(Template->new($settings));
	} else {
		$app->template(Template->new({  INCLUDE_PATH=>$settings,
				INTERPOLATE  => 1,               # expand "$var" in plain text
		      		POST_CHOMP   => 1,               # cleanup whitespace 
      				# PRE_PROCESS  => 'header',        # prefix each template
				EVAL_PERL    => 1,               # evaluate Perl code blocks
		}));
	}
}

sub set_cgi {
	my $app = shift;
	return $app->cgi if $app->cgi;
	$app->cgi(new CGI) if not $app->cgi;
	# TODO various translation and url computation data prebaked
}

sub set_session {
	my $app = shift;
	my $config = shift;
	$app->set_cgi;
    if (ref($config) eq 'DBI::db') {
        $app->{session} = CGI::Session->new("driver:mysql", $app->cgi, { Handle => $config } );
    } else {
	    $app->{session} = CGI::Session->new(undef, $app->cgi, {Directory=>$config});
    }
}

sub handle_errors {
    my $app = shift;
    print $app->cgi->header('text/plain');
    print join "\n---\n" , @{$app->server_errors};
    $app->sent_headers(1);
    $app->sent_body(1);
}

sub headers {
	my $app = shift;
	return 1 if $app->sent_headers;
	if ($app->session) {
        $app->session->flush();
		print $app->session->header(@_);
	} else {
		print $app->cgi->header(@_);
	}
	$app->sent_headers(1);
}

sub redirect {
    my $app = shift;
    if (!$app->sent_headers) {
        my $url = shift;
        print $app->cgi->redirect($url);
        $app->sent_headers(1);
        $app->sent_body(1);
    }
}

sub render {
	my $app = shift;
    if ($app->use_data_templates) { # use inline templates
        print "no templates" if $debug;
        my $export = {app=>$app};
        $app->template->process(\*main::DATA, $export);
    } else {
        my $templatename = shift;
        if ($templatename !~ /\./) {
            $templatename .= '.html';
        }
        $app->{templatename} = $templatename;
        print "template '$templatename'\n" if $debug;
        my $export = {app=>$app};
        if (!$app->sent_body) {
            $app->template->process($templatename, $export) || $app->log_server_error($app->template->error);
        }
    }
	$app->sent_body(1);
}

sub handle {
	my $app = shift;
    if (scalar(@{$app->server_errors})) {
        $app->handle_errors;
    } else {
    	$app->headers;
	    $app->render(@_);
    }
    if (scalar(@{$app->server_errors})) {
        $app->handle_errors;
    }    
}

sub dispatch {
	print "DISPATCHING\n" if $debug;
	my $app = shift;
    $app->setup if not $app->{has_setup};
	$app->{in_dispatch} = 'true';
	my $action = $app->action || 'index' ; 
    $action =~ s/\.html$//i; # this is a hack - for when my htaccess rule stupidly thinks i'm looking for the action index.html
	my $namespace = $app->object_type || $app->caller;
	#TODO  - parse out package for data instead
	my $data = undef;
	eval {
		no strict 'refs';
		$app->{trying_to_call} = $app->caller . '::' . $action;
		$data = &{$namespace . '::' . $action}($app);
		$app->{got_data} = Dumper($data);
		# print "Data = $data\n";
		use strict 'refs';
	};
	$app->log_server_error($@) if $@; # $app->{controller_error} = $@;
    $app->check_db_err;
	$app->data($data);
	$app->handle($action);
}

# TODO - avoid using autoload - or think about it and think about lvalues at least
sub AUTOLOAD  {
	my $app = shift;
	my $value = shift;
	my $key = $AUTOLOAD;
	$key =~ s/^.*::([^:]+)$/$1/;
	if (defined $value)  {
		$app->{$key} = $value;
	}
	return $app->{$key};
}

sub DESTROY {
}

# World's smallest DB framework, write your own SQL - except when it is tediously obvious

# utility package, DB live object with a save method, knows which table it belongs to 
package Assumptions::DB;
our $AUTOLOAD;

sub _exists {
}

#~ sub _conversions {
    #~ my $self = shift;
    #~ if (scalar(@_)) {
        #~ %conversions = @_;
        #~ $self->{conversions} = \%conversions;
    #~ }
    #~ return $self->{conversions};
#~ }

# build a table object and return it
sub AUTOLOAD {
    #~ print "WHAT??";
    #~ my $package = shift;
    my $self = shift;
	my $key = $AUTOLOAD;
    print "\n\nTABLE :: $key\n\n" if $debug;
	$key =~ s/^.*::([^:]+)$/$1/;
    #~ print "\n\nTABLE :: $key\n\n";
    bless {app=>$self->{app}, name=>$key}, 'Assumptions::Table';
}

sub DESTROY {
}

package Assumptions::Table;

sub get {
    my $self = shift;
    
    # call DBIx::Abstract::select
    #~ die ref($self->{app}->dbix;
    my $parms = $self->{app}->dbix->select('*', $self->{name}, @_)->fetchrow_hashref;
    $self->{app}->check_db_err;
    if ($parms) {
        return new Assumptions::Record $self, $parms;
    } else {
        return undef
    }
}

sub add {
    my $self = shift;
    my $parms = shift || {};
    return new Assumptions::Record $self, $parms;
}

# return existing or new record
sub addmod {
    my $self = shift;
    my $record = $self->get(@_);
    if ($record) {
        return $record;
    }
    else {
        return $self->add;
    }
}

# support cursors
sub get_all {
    my $self = shift;
    my $sql = shift;
    my @records;
    my $finder = $self->{app}->dbh->prepare($sql);
    $finder->execute(@_);
    $self->{app}->check_db_err;
    while (my $parms = $finder->fetchrow_hashref) {
        push @records , new Assumptions::Record $self, $parms;
    }
    $finder->finish;
    return @records;
}

package Assumptions::Record;
our $AUTOLOAD;

sub new {
	my $class = shift;
    my $table = shift;
    my $parms = shift;
    # maybe statement handle for cursor
	bless {
        table =>$table,
        fields => $parms
	} , $class;
}

# for now just use get_all on the table class
sub new_cursor {
    die 'TODO';
	my $class = shift;
    my $table = shift;
    my $sth = shift;
    # maybe statement handle for cursor
    my $parms = $sth->fetchrow_hashref;
	bless {
        table =>$table,
        sth => $sth,
        fields => $parms,
	} , $class;
}

sub set {
    my $self = shift;
    my %data = @_;
    foreach my $key (keys %data) {
        #~ print "setting $key = $data{$key}\n";
        $self->fields->{$key} = $data{$key};
    }
}

# optionally restrict by fieldnames
sub save {
    my $self = shift;
    my @fieldnames = @_;
    my $fields = {id=>$self->{fields}->{id}};
    if (scalar(@fieldnames)) {
        foreach my $name (@fieldnames) {
            #~ print "$name = $self->fields->{$name};";
            $fields->{$name} = $self->fields->{$name};
        }
    } else {
        $fields = $self->{fields};
    }
    if ($fields->{id}) {
        #~ print "updating @fieldnames";
        $self->{table}->{app}->dbix->update($self->{table}->{name}, $fields, {id=>$fields->{id}});
        $self->{table}->{app}->check_db_err;
    } else {
        $self->{table}->{app}->dbix->insert($self->{table}->{name}, $fields);
        $self->{table}->{app}->check_db_err;
        $self->{fields}->{id} = $self->{table}->{app}->dbix->select_one_to_arrayref(' last_insert_id();')->[0];
        $self->{table}->{app}->check_db_err;
    } 
}

# ? do cursors
# for now I just use get_all
sub next {
    die 'TODO';
    my $self = shift;
    return undef if not $self->{sth};
    if (my ($parms) = $self->{sth}->fetchrow_hashref) {
        $self->{parms} = $parms;
        return 1;
    } else {
        $self->{table}->{app}->check_db_err;
        return undef;
    }
}


# TODO - avoid using autoload
sub AUTOLOAD : lvalue { # yes, AUTOLOAD also supports the lvalue attribute
	my $rec = shift;
	my $value = shift;
	my $key = $AUTOLOAD;
	$key =~ s/^.*::([^:]+)$/$1/;
    #~ return undef if not defined $rec->{fields}->{$key};
	$rec->{fields}->{$key};
}

sub fields {
    my $self = shift;
    return $self->{fields};
}

sub DESTROY {
}

1;

__END__

Documentation


use Assumptions

# no structure behind. Directly in callme.cgi


sub index {
    my $app = shift # get Assumptions
}

$app = new Assumptions;
$app->setup;
$app->dispatch;
(should be : Assumptions->dispatch)
(OR nothing at all because of an END clause in Assumptions - but then it's CGI only)

__END__
templates


or with a little more setup

callme.cgi
use MyApp;

sub index {

}

sub other {
    return {stuff => "for template output"};
}

$app = new MyApp;
$app->setup;
$app->dispatch;


in MyApp.pm

use base Assumptions;

sub configure {
    my $app = shift;
    $app->set_template(dirname);
    or
    $app->set_template($app->scriptdir + '/templates');
    or
    $app->set_template({template toolkit options hash});
    
    $app->set_cache
    or
    $app->set_cache($cachedir, $namespace)
    
    $app->set_session
    or
    $app->set_session($session_cache_dir);
    
    $app->set_dbix(mysqldbname, user, password)
    
}

sub use_utilities {
    my $app = shift;
    $my_row = $app->db->table_name->get({column=>value});
    $other_row = $abb->db->table_name->new;
    $my_row->property(set);
    $other_row->property(define);
    $other_row->save;
    $my_row->save;
*   cursors    
    
?    $value = $app->getcache("name");
    if ($value) {
        go on
    } else {
        create $value;
?        $app->cache->setcache("name", $value, $expiration);
    }
     

?    $app->session->get("sessionvar", $user_specific_value);
?    $app->session->set("sessionvar", $user_specific_value);
    
    $app->header(CGI headers);
    $app->render(Specific template);
    $app->redirect;
*    $app->mail(to=>someone, from=>someone, subject=>something, body=> something indeeed, anythingelse=>a header);
    
    return {hash=> \%fortemplates, value=>1}
}


in templates

[% app.data.hash.key %] [% app.data.value %]

[% app.url_for(partialurl) %]

