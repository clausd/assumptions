package ATest;
use Assumptions;
@ISA = qw(Assumptions);

sub configure {
	my $app = shift;
	$app->set_template({  INCLUDE_PATH=>'./test_files/templates',
		      		POST_CHOMP   => 1,               # cleanup whitespace 
				EVAL_PERL    => 1,               # evaluate Perl code blocks
		});
	$app->set_cache('/home/classydk/cache', 'assumption_test');
	$app->set_session('./test_files/sessions');
	$app->set_dbix('assumption_test', 'root', '');
	# prepare statements
	#~ $app->db_prepare;
}

#~ sub db_prepare {
    #~ my $app = shift;
    #~ $app->dbh->schema(
        #~ testtable=> {
            #~ id=>'primary key',
            #~ string_value=>'string', 
            #~ integer_value=>'integer', 
            #~ hash_value=>'text',
        #~ },
    #~ );
#~ }

